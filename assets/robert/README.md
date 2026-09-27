# Robert — default character asset

Revision 3 uses a flat PNG display instead of 3D eyes, mouth or facial morphs. The compact proportions, seamless arms, flat soles and 24-bone skeleton remain. The torso has a nearly flush battery door; the back of the head retains its original raised enclosure, inset panel and five vents. The original ivory/teal/orange appearance is the `default` skin.

## Layout

```
robert/
  character.json                # catalogue; default_skin = default
  skins/
    default/
      skin.json                 # default appearance definition
      model/Robert.glb           # runtime interchange asset, embedded neutral PNG
      source/Robert.blend        # editable source with packed face image
    _template/skin.template.json # copy when adding a skin; not a selectable skin
  shared/
    rig_contract.json           # exact bone hierarchy, rest transforms and material slots
    animations.json             # body clip timing, loop intent and suggested face pairing
    faces/default/              # PNG artwork and animation timing
  unity/                        # Unity helper scripts and Inspector setup guide
  tools/                        # reproducible Blender/Pillow build and verification
  previews/                     # current rendered views
  validation/                   # measured stats and validation report
```

## Replace the face with a PNG

Eight additional cute reactions are included: **Joy, Giggle, Wink, Curious, Wow, Sleepy, Bashful and Starry-eyed**. See [the face guide](shared/faces/default/README.md) and [expression sheet](previews/cute_expressions.png). They use the same face binding across all seven appearances.

Create a **1024 × 512 PNG**, or another 2:1 image. Draw the complete face over the dark background in `shared/faces/default/blank_template.png`. Keep features a little inside the edges. Use opaque artwork: the display is intentionally opaque, and transparency is not composited over the backing. PNGs use ordinary top-left image orientation; do not flip them before importing. UV0 fills the image from 0 to 1. The screen has four vertices and two triangles, sits in front of the glass backing, and is fully weighted to `head`.

In Blender, select `FaceScreen`, open its `FaceScreen_Unlit` material in the Shader Editor, and replace the image in the **FACE_PNG_REPLACE_ME** Image Texture node. Pack the replacement if sharing the blend file. The exported GLB embeds the neutral PNG; changing a loose PNG does not change that embedded image automatically. Re-export or set the texture in your engine.

For Unity, follow [unity/README.md](unity/README.md). The helper can accept a Texture2D in `SetFace` and play PNG frame sequences. Give the screen a dedicated opaque Unlit material. Do not assign face textures to the full body renderer. The face uses a per-renderer texture override so multiple characters can display different expressions while sharing textures.

`shared/faces/default/animations.json` describes face frame durations in milliseconds, relative to its own directory. It is engine-independent reference data, not a glTF animation or an automatically imported Unity asset. The Unity helper clips are configured in the Inspector. Talking is a sample frame cycle, not audio lip-sync. Whole-face PNGs cannot independently layer blinking and speech; the supplied `talk_blink.png` demonstrates a combined frame.

## Add skins later

1. Copy `skins/default` to `skins/<unique_id>` and edit the new `skin.json`, or use the template.
2. For recolours, reuse the mesh and skeleton and change body materials in a Unity prefab variant. Keep `FaceScreen` on its own material. For different geometry, preserve the exact bone names, hierarchy and rest transforms in `shared/rig_contract.json`, weights and body clip names. Bone count alone is not enough.
3. Reuse the shared face set, or put a new face set under `shared/faces/<set_id>` and reference its timing file.
4. Add the skin ID and manifest path to `character.json`. Paths in character/skin manifests are relative to this character folder; face frame paths are relative to their timing JSON.
5. In Unity create a RobertSkinDefinition for the skin prefab and set the original definition as the controller's default. The JSON catalogue documents the portable asset layout; the supplied Unity components use Inspector references and do not automatically load this JSON.

The default model is supplied and declared in the asset catalogue. These asset-generation tools do not modify game scenes or player prefabs. Import and Inspector wiring remain required for the new outfits. Skin changes reset visual animation state; application-specific save selection and animation-state transfer are not included.

## Outfit collection

Six additional local art assets are included: **Cowboy, Astronaut, Arab Thobe, Casual, Explorer, and Gardener**. See [SKINS.md](SKINS.md) for their stable IDs, file paths, compatibility and integration notes, and [the collection preview](previews/skin_collection.png) for the lineup. The original `default` selection remains unchanged. Registering art files does not grant ownership, change backend inventory, or expand the runtime bridge allowlist.

## Animation and validation

Every skin's GLB and Blender source contains **Standing, Idle, Wave, Talk, Nod and Celebrate** skeletal clips. Standing and Idle share a gentle six-second standing loop; Idle keeps the existing clip name compatible. Wave is a brief greeting, and Talk adds subtle hand gestures and nods. Feet stay planted and the clips use no root motion. See [ANIMATIONS.md](ANIMATIONS.md) for durations, previews and playback guidance.

The lowercase face clips `idle`, `blink` and `talk` are separate PNG sequences. Pair skeletal `Talk` with face `talk` for demonstration speech; neither provides audio lip-sync. In Blender, NLA tracks start muted for a neutral pose; unmute one body track to preview it. Use Generic animation rather than assuming humanoid retargeting. `shared/animations.json` records body timing, loop intent and face pairing; it does not automatically configure Unity.

Source: Blender Z-up, front -Y, height approximately 2.31 m; glTF uses Y-up. Run `tools/create_face_assets.py` with Pillow, then `tools/build_robert.py` in background Blender, followed by `tools/verify_robert.py`. The build replaces current generated outputs and clears its Blender session. The character follows the user's original drawing; no third-party art was used.

The GLB is re-imported in Blender and checked for skin weights, UVs, embedded image, clip names, absence of morph faces, flat soles, the flat torso battery cover and restored rear head enclosure. Unity helpers are supplied as source and have not been compiled or tested in the target Unity project or on a device. See the reports in `validation/` for actual checks.
