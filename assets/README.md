# Runtime character assets

Only files under this directory are eligible for bundling into the app, and only
those listed under `flutter: assets:` in `pubspec.yaml` actually ship. Archives,
Blender sources, build tooling output and design files are deliberately kept out
of here.

- `robert/` — the portable character package. Its guides are `README.md` (the
  model, the face screen and the layout), `ANIMATIONS.md` (the six body clips:
  lengths, looping, face pairing and playback guidance) and `SKINS.md` (the six
  outfits: ids, files and compatibility). Beside them: the `character.json`
  catalogue, seven skins under `skins/` (each a GLB model and editable Blender
  source with the six body clips), `shared/faces/default/` (face PNGs, including
  the eight `cute_*` expressions, and their timing), `shared/animations.json`
  (body clips and face pairing), `shared/rig_contract.json`, `unity/` helper
  scripts, `tools/` reproducible build, animation and verification scripts,
  `previews/` and `validation/`. Only `robert/Robert.png` ships in the app: it
  is the static-avatar preview used by the Flutter fallback.
- `looks/` — the Style tab's outfit thumbnails, downscaled from
  `robert/previews/<skin>.png`.
- `models/` — the on-device prayer-posture classifier
  (`prayer_posture.tflite`, 1.1 MB) and its label order. It is trained by
  `../ml/prayer_posture/` and described in its `MODEL_CARD.md`; it inherits the
  CC BY-NC 4.0 licence of one of its training sets.

The Unity room imports from `robert/`; see
[`../unity/README.md`](../unity/README.md). Copy only the selected runtime
assets and helper scripts into a Unity project — exclude archives, Blender
sources, logs and verification scripts from runtime asset folders.

Not in this directory:

- `../design/` — the `ui.make` Figma layout source and `ui-reference.png`.
- `../archive/` — superseded character revisions and the packaged
  `Robert_character.zip`. Untracked; reproducible with
  `robert/tools/package_asset.py`.

Add future Robert skins beneath `robert/skins`. The package moved here from
`characters/robert/` on 2026-09-27, when the animation update replaced it.
