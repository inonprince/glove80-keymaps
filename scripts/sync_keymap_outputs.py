#!/usr/bin/env python3
"""Sync build-facing keymap outputs from canonical keymap.json."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KEYMAP_JSON = ROOT / "keymap.json"
KEYMAP_DTSI = ROOT / "keymap.dtsi"
BUILD_KEYMAP = ROOT / "config" / "glove80.keymap"

# Physical layout row widths in Glove80 editor JSON ordering.
ROW_WIDTHS = (10, 12, 12, 12, 18, 16)


def regenerate_dtsi() -> None:
    candidates = [
        ["/opt/homebrew/opt/ruby/bin/rake", "keymap.dtsi"],
        ["rake", "keymap.dtsi"],
    ]
    for cmd in candidates:
        try:
            subprocess.run(cmd, cwd=ROOT, check=True, capture_output=True, text=True)
            return
        except FileNotFoundError:
            continue
        except subprocess.CalledProcessError as exc:
            raise RuntimeError(exc.stderr.strip() or exc.stdout.strip() or str(exc)) from exc
    raise RuntimeError("Unable to find rake executable to regenerate keymap.dtsi.")


def _resolve_nested(node: object) -> str | None:
    if node is None:
        return None
    if not isinstance(node, dict):
        return str(node)

    value = str(node.get("value", ""))
    params = node.get("params") or []
    child = _resolve_nested(params[0]) if params else None

    if value == "&kp":
        return child
    if child:
        return f"{value}({child})"
    return value


def key_to_token(key: dict[str, object]) -> str:
    behavior = str(key.get("value", ""))
    params = key.get("params") or []
    if not params:
        return behavior

    first = params[0]
    if behavior == "Custom":
        if isinstance(first, dict):
            return str(first.get("value", ""))
        return str(first)

    nested = _resolve_nested(first)
    if behavior == "&kp":
        return f"&kp {nested}" if nested else "&kp"
    return f"{behavior} {nested}" if nested else behavior


def render_bindings(keys: list[dict[str, object]]) -> str:
    tokens = [key_to_token(key) for key in keys]
    if len(tokens) != sum(ROW_WIDTHS):
        raise ValueError(f"Expected 80 keys, found {len(tokens)}.")

    out = []
    i = 0
    for width in ROW_WIDTHS:
        row = " ".join(tokens[i : i + width])
        out.append(f"            {row}")
        i += width
    return "\n".join(out)


def sync_custom_defined_behaviors(config_text: str, dtsi_text: str) -> tuple[str, int]:
    pattern = re.compile(
        r"/\* Custom Defined Behaviors \*/\n/ \{\n.*?\n/\* Generated input processors \*/",
        re.S,
    )
    # keymap.dtsi ends at `/*HACK*//{` and the generated keymap keeps a balancing
    # `};` immediately before "Generated input processors".
    replacement = (
        "/* Custom Defined Behaviors */\n"
        "/ {\n"
        f"{dtsi_text.rstrip()}\n\n"
        "};\n\n"
        "/* Generated input processors */"
    )
    return pattern.subn(replacement, config_text, count=1)


def sync_layer_bindings(config_text: str, layer_name: str, keys: list[dict[str, object]]) -> tuple[str, int, bool]:
    block = render_bindings(keys)
    pattern = re.compile(
        rf"(layer_{re.escape(layer_name)}\s*\{{\s*bindings\s*=\s*<\n)"
        r"(.*?)"
        r"(\n\s*>;\n\s*\};)",
        re.S,
    )
    match = pattern.search(config_text)
    if not match:
        return config_text, 0, False

    old_block = match.group(2)
    old_norm = " ".join(old_block.split())
    new_norm = " ".join(block.split())
    if old_norm == new_norm:
        return config_text, 1, False

    updated = f"{match.group(1)}{block}{match.group(3)}"
    return config_text[: match.start()] + updated + config_text[match.end() :], 1, True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--write",
        action="store_true",
        help="Write updates to config/glove80.keymap (default is dry-run).",
    )
    parser.add_argument(
        "--skip-rake",
        action="store_true",
        help="Skip regenerating keymap.dtsi before syncing.",
    )
    args = parser.parse_args()

    if not args.skip_rake:
        regenerate_dtsi()

    data = json.loads(KEYMAP_JSON.read_text())
    layer_names = data["layer_names"]
    layers = data["layers"]
    layer_map = dict(zip(layer_names, layers))

    config_text = BUILD_KEYMAP.read_text()
    dtsi_text = KEYMAP_DTSI.read_text()

    updated_text, replaced = sync_custom_defined_behaviors(config_text, dtsi_text)
    if replaced != 1:
        raise RuntimeError("Could not find Custom Defined Behaviors section in config/glove80.keymap.")

    changed_layers = []
    for layer_name, keys in layer_map.items():
        updated_text, count, changed_layer = sync_layer_bindings(updated_text, layer_name, keys)
        if count != 1:
            raise RuntimeError(f"Could not find layer block for '{layer_name}' in config/glove80.keymap.")
        if changed_layer:
            changed_layers.append(layer_name)

    changed = updated_text != config_text
    if args.write:
        BUILD_KEYMAP.write_text(updated_text)
        print("Updated config/glove80.keymap." if changed else "config/glove80.keymap already in sync.")
    else:
        print("Would update config/glove80.keymap." if changed else "config/glove80.keymap already in sync.")
        print("Run with --write to apply changes.")
    if changed_layers:
        print(f"Layer blocks changed: {', '.join(changed_layers)}")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"sync_keymap_outputs.py: {exc}", file=sys.stderr)
        raise SystemExit(1)
