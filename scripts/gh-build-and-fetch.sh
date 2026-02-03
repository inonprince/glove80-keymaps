#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Smart firmware build helper for GitHub Actions.

Behavior:
  - If a run already exists for the same target commit SHA, it reuses it.
  - Otherwise it triggers a new workflow_dispatch run.
  - It waits for completion, downloads artifacts on success, or prints failed logs.

Usage:
  scripts/gh-build-and-fetch.sh [options]

Options:
  -r, --repo <owner/name>    GitHub repo (default: inferred from origin remote)
  -b, --ref <branch>         Git ref/branch to build (default: current branch)
  -w, --workflow <name>      Workflow file or name (default: build.yml)
  -o, --out <dir>            Artifact output directory (default: ./artifacts)
  -f, --force-trigger        Always trigger a new run (ignore reusable existing runs)
  -h, --help                 Show this help
EOF
}

repo=""
ref=""
workflow="build.yml"
out_dir="artifacts"
force_trigger=false

is_sha_ref() {
  [[ "$1" =~ ^[0-9a-fA-F]{7,40}$ ]]
}

download_artifacts() {
  local run_id="$1"
  mkdir -p "$out_dir"
  if gh run download "$run_id" --repo "$repo" --name glove80.uf2 --dir "$out_dir"; then
    echo "Downloaded artifact 'glove80.uf2' into: $out_dir"
  else
    echo "Named artifact not found, downloading all artifacts..."
    gh run download "$run_id" --repo "$repo" --dir "$out_dir"
    echo "Downloaded artifacts into: $out_dir"
  fi
}

print_failed_logs() {
  local run_id="$1"
  gh run view "$run_id" --repo "$repo" --log-failed || gh run view "$run_id" --repo "$repo" --log
}

process_run() {
  local run_id="$1"
  local status="" conclusion="" run_url=""

  run_url="$(gh run view "$run_id" --repo "$repo" --json url --jq '.url')"
  status="$(gh run view "$run_id" --repo "$repo" --json status --jq '.status')"

  echo "Run: $run_url"

  if [[ "$status" != "completed" ]]; then
    echo "Watching run..."
    if ! gh run watch "$run_id" --repo "$repo" --interval 10 --exit-status; then
      echo "Build failed. Printing failed log output..."
      print_failed_logs "$run_id"
      exit 1
    fi
  fi

  conclusion="$(gh run view "$run_id" --repo "$repo" --json conclusion --jq '.conclusion // ""')"
  if [[ "$conclusion" == "success" ]]; then
    download_artifacts "$run_id"
    return 0
  fi

  echo "Run conclusion: ${conclusion:-unknown}"
  echo "Printing failed log output..."
  print_failed_logs "$run_id"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--repo)
      repo="${2:-}"; shift 2 ;;
    -b|--ref)
      ref="${2:-}"; shift 2 ;;
    -w|--workflow)
      workflow="${2:-}"; shift 2 ;;
    -o|--out)
      out_dir="${2:-}"; shift 2 ;;
    -f|--force-trigger)
      force_trigger=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is not installed or not in PATH." >&2
  exit 1
fi

if ! gh auth status -h github.com >/dev/null 2>&1; then
  echo "gh is not authenticated. Run: gh auth login -h github.com" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$repo" ]]; then
  if [[ -z "$repo_root" ]]; then
    echo "Not in a git repo and --repo was not provided." >&2
    exit 1
  fi
  origin_url="$(git -C "$repo_root" remote get-url origin)"
  repo="${origin_url#git@github.com:}"
  repo="${repo#https://github.com/}"
  repo="${repo%.git}"
fi

if [[ -z "$ref" ]]; then
  if [[ -z "$repo_root" ]]; then
    echo "--ref is required when not running inside a git repo." >&2
    exit 1
  fi
  ref="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)"
  if [[ "$ref" == "HEAD" ]]; then
    echo "Detached HEAD detected. Pass --ref <branch>." >&2
    exit 1
  fi
fi

target_sha="$(gh api "repos/$repo/commits/$ref" --jq '.sha')"
if [[ -z "$target_sha" || "$target_sha" == "null" ]]; then
  echo "Could not resolve target commit SHA for ref '$ref' in '$repo'." >&2
  exit 1
fi

run_list_args=(--repo "$repo" --workflow "$workflow")
if ! is_sha_ref "$ref"; then
  run_list_args+=(--branch "$ref")
fi

echo "Repo: $repo"
echo "Ref: $ref"
echo "Workflow: $workflow"
echo "Target SHA: $target_sha"

if [[ "$force_trigger" != true ]]; then
  existing_running_id=""
  existing_running_updated=""
  existing_completed_id=""
  existing_completed_updated=""

  while IFS=$'\t' read -r id sha status _conclusion _url _event _created updated; do
    [[ "$sha" == "$target_sha" ]] || continue

    if [[ "$status" != "completed" ]]; then
      if [[ -z "$existing_running_id" || "$updated" > "$existing_running_updated" ]]; then
        existing_running_id="$id"
        existing_running_updated="$updated"
      fi
    else
      if [[ -z "$existing_completed_id" || "$updated" > "$existing_completed_updated" ]]; then
        existing_completed_id="$id"
        existing_completed_updated="$updated"
      fi
    fi
  done < <(
    gh run list "${run_list_args[@]}" --limit 200 \
      --json databaseId,headSha,status,conclusion,url,event,createdAt,updatedAt \
      --jq '.[] | [.databaseId, .headSha, .status, (.conclusion // ""), .url, .event, .createdAt, .updatedAt] | @tsv'
  )

  if [[ -n "$existing_running_id" ]]; then
    echo "Reusing existing in-progress run for this SHA: $existing_running_id"
    process_run "$existing_running_id"
    exit 0
  fi

  if [[ -n "$existing_completed_id" ]]; then
    echo "Reusing existing completed run for this SHA: $existing_completed_id"
    process_run "$existing_completed_id"
    exit 0
  fi
fi

echo "No reusable run found. Triggering workflow..."
gh workflow run "$workflow" --repo "$repo" --ref "$ref"

echo "Waiting for new workflow_dispatch run for SHA $target_sha..."
new_run_id=""
for _ in $(seq 1 120); do
  while IFS=$'\t' read -r id sha; do
    if [[ "$sha" == "$target_sha" ]]; then
      new_run_id="$id"
      break
    fi
  done < <(
    gh run list "${run_list_args[@]}" --event workflow_dispatch --limit 100 \
      --json databaseId,headSha \
      --jq '.[] | [.databaseId, .headSha] | @tsv'
  )

  if [[ -n "$new_run_id" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$new_run_id" ]]; then
  echo "Could not find the newly triggered run for SHA $target_sha." >&2
  exit 1
fi

process_run "$new_run_id"
exit 0
