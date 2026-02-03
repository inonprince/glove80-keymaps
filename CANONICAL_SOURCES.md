# Canonical Sources and Regeneration Notes

## Source of truth (edit here first)

- `keymap.json`
  - Canonical source for layer key assignments/positions from Glove80 Layout Editor exports.
  - If you are changing which key is at which position on a layer, this is the primary source.
- `keymap.dtsi.erb`
  - Canonical template source for generated custom DTS snippet logic (macros, combos, defaults, etc.).
- `world.yaml` and `emoji.yaml`
  - Canonical data sources for generated World/Emoji macro content.

## Generated/derived files

- `keymap.dtsi`
  - Generated from `keymap.dtsi.erb` + `keymap.json` (+ YAML inputs) via `rake` (phase 1).
  - Intended to be copied into the Layout Editor's "Custom Defined Behaviors" area.
- `config/glove80.keymap`
  - Build-time keymap used for local firmware builds in this repo.
  - Treated as downstream output in this workflow; should be kept in sync with canonical sources.
- `keymap.zmk`
  - Symlink to `config/glove80.keymap`.

## Symbol-layer change recorded here (2026-02-03)

Goal: on Symbol layer, swap:
1. Backspace and Tab
2. Delete and Shift+Tab

Canonical source edit was made in `keymap.json` on layer `Symbol`:
- Swapped indices `29` and `30` (`DEL` <-> `LS(TAB)`).
- Swapped indices `41` and `42` (`BSPC` <-> `TAB`).

## Commit source audit

- `ddba918eb35b84ebd6de34fca702fab2e20a836a`
  - `config/glove80.keymap` and `keymap.zmk` operating-system toggle were output-level edits (not canonical-source edits).
  - `scripts/gh-build-and-fetch.sh` is a direct source addition (canonical script source).
- `22e685c040c684d41531f881f973df6c96191940`
  - Cursor arrow swap was made only in `config/glove80.keymap` (output-level edit, not canonical-source edit).

### Canonical backports applied

- `ddba918...` backported to canonical sources by setting top-level default OS to macOS in:
  - `keymap.dtsi.erb`
  - `keymap.json` (`custom_defined_behaviors`)
- `22e685c...` backported to canonical source by swapping Cursor layer arrows to `LEFT, DOWN, UP, RIGHT` in:
  - `keymap.json` (layer `Cursor`)

## Regeneration (phase 1)

From `glove80-keymaps/`:

```bash
rake dtsi
```

Or full regeneration:

```bash
rake
```
