#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Trigger a GitHub Actions firmware build, wait for completion, and fetch artifacts.

Usage:
  scripts/gh-build-and-fetch.sh [options]

Options:
  -r, --repo <owner/name>    GitHub repo (default: inferred from origin remote)
  -b, --ref <branch>         Git ref/branch to build (default: current branch)
  -w, --workflow <name>      Workflow file or name (default: build.yml)
  -o, --out <dir>            Artifact output directory (default: ./artifacts)
  -h, --help                 Show this help
EOF
}

repo=""
ref=""
workflow="build.yml"
out_dir="artifacts"

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

echo "Repo: $repo"
echo "Ref: $ref"
echo "Workflow: $workflow"

before_id="$(
  gh run list \
    --repo "$repo" \
    --workflow "$workflow" \
    --branch "$ref" \
    --event workflow_dispatch \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId // 0'
)"

echo "Triggering workflow..."
gh workflow run "$workflow" --repo "$repo" --ref "$ref"

echo "Waiting for new run to appear..."
run_id=""
for _ in $(seq 1 120); do
  run_id="$(
    gh run list \
      --repo "$repo" \
      --workflow "$workflow" \
      --branch "$ref" \
      --event workflow_dispatch \
      --limit 1 \
      --json databaseId \
      --jq '.[0].databaseId // 0'
  )"
  if [[ "$run_id" != "0" && "$run_id" != "$before_id" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$run_id" || "$run_id" == "0" || "$run_id" == "$before_id" ]]; then
  echo "Could not find the new run ID." >&2
  exit 1
fi

run_url="$(gh run view "$run_id" --repo "$repo" --json url --jq '.url')"
echo "Run: $run_url"
echo "Watching run..."

if gh run watch "$run_id" --repo "$repo" --interval 10 --exit-status; then
  mkdir -p "$out_dir"
  if gh run download "$run_id" --repo "$repo" --name glove80.uf2 --dir "$out_dir"; then
    echo "Downloaded artifact 'glove80.uf2' into: $out_dir"
  else
    echo "Named artifact not found, downloading all artifacts..."
    gh run download "$run_id" --repo "$repo" --dir "$out_dir"
    echo "Downloaded artifacts into: $out_dir"
  fi
else
  echo "Build failed. Printing failed log output..."
  gh run view "$run_id" --repo "$repo" --log-failed || gh run view "$run_id" --repo "$repo" --log
  exit 1
fi
