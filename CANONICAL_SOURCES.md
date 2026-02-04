# Canonical Sources and How to Make Changes

This document defines where to make edits first, depending on the kind of change.

## Source of truth by change type

### 1) Key assignments / key positions on layers

Edit:
- `keymap.json` (canonical for layer bindings and physical positions)

Typical examples:
- swapping keys on Symbol/Cursor/Number layers
- moving a key from one position to another
- changing a key behavior at a specific position

Notes:
- In `keymap.json`, these changes are in `layers` entries (indexed by `layer_names`).
- For this repo, treat `config/glove80.keymap` as downstream output for these edits.

### 2) DTS template logic (macros, combos, defaults, helper behaviors)

Edit:
- `keymap.dtsi.erb` (canonical template)

Typical examples:
- changing combo logic
- changing behavior definitions
- changing default preprocessor settings in the generated DTS

### 3) World/Emoji data content

Edit:
- `world.yaml`
- `emoji.yaml`

These feed generated sections used by `keymap.dtsi.erb`.

### 4) Build/runtime keymap output

Derived/downstream files:
- `config/glove80.keymap`
- `keymap.dtsi`
- `keymap.zmk` (symlink to `config/glove80.keymap`)

Do not treat these as canonical for key-placement edits unless you intentionally need an output-only hotfix.

## Diagram sources (separate from keymap generation)

Layer diagrams are maintained separately and are **not** auto-generated from `keymap.json`.

Edit:
- `README/*-layer-diagram.json` (KLE source for visual maps)

Render flow:
1. Upload `README/*-layer-diagram.json` to KLE.
2. Export/screenshot to `README/*-layer-diagram.png`.
3. Run `rake pdf` to generate per-layer PDFs and `README/all-layer-diagrams.pdf`.

Important:
- `rake` does not regenerate diagram JSON.
- `rake pdf` only converts existing PNGs to PDFs and combines them.

## Regeneration commands

From `glove80-keymaps/`:

```bash
/opt/homebrew/opt/ruby/bin/rake dtsi
```

Full pipeline:

```bash
/opt/homebrew/opt/ruby/bin/rake
```

## Key-change checklist (recommended)

When changing key assignments:
1. Edit `keymap.json` at the target layer/positions.
2. Regenerate outputs (`rake` or `rake dtsi`).
3. update matching `README/*-layer-diagram.json`.
4. Verify `config/glove80.keymap` matches intended behavior.

## Historical backport notes

These commits were originally output-level changes and were backported to canonical sources:
- `ddba918eb35b84ebd6de34fca702fab2e20a836a` (OS default and script changes)
- `22e685c040c684d41531f881f973df6c96191940` (cursor arrow order)
- `3e054fbedb575cc5eb8317f2d6f7b66d7587a490` (Symbol swaps)
- `e3106daaa3d59e4e7e3dc38f45f782cdd87f4f20` (C1 F16-F19 moved to Number layer)
