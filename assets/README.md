# Runtime character assets

Only files under this directory are eligible for bundling into the app, and only
those listed under `flutter: assets:` in `pubspec.yaml` actually ship. Archives,
Blender sources, build tooling output and design files are deliberately kept out
of here.

- `robert/Robert.png` — the staged static-avatar preview used by the Flutter
  fallback. This is the supplied preview render, not newly generated art.
- `characters/robert/` — the portable character package: `character.json`
  catalogue, `skins/default/` (GLB model and editable Blender source),
  `shared/faces/default/` (face PNGs and timing), `shared/rig_contract.json`,
  `unity/` helper scripts, `tools/` reproducible build and verification scripts,
  `previews/` and `validation/`.

The Unity room imports from `characters/robert/`; see
[`../unity/README.md`](../unity/README.md). Copy only the selected runtime
assets and helper scripts into a Unity project — exclude archives, Blender
sources, logs and verification scripts from runtime asset folders.

Not in this directory:

- `../design/` — the `ui.make` Figma layout source and `ui-reference.png`.
- `../archive/` — superseded character revisions and the packaged
  `Robert_character.zip`. Untracked; reproducible with
  `characters/robert/tools/package_asset.py`.

Add future characters beside `robert`; add future Robert skins beneath
`characters/robert/skins`.
