# Robert outfit skins

The approved outfit set contains six appearances for Robert. The original ivory, teal and orange `default` skin remains the character's default selection and fallback.

| Skin ID | Outfit |
|---|---|
| `cowboy` | Cowboy outfit |
| `astronaut` | Astronaut outfit |
| `arab_thobe` | Arab thobe outfit |
| `casual` | Casual outfit |
| `explorer` | Explorer outfit |
| `gardener` | Gardener outfit |

Astronaut and Arab Thobe have no headgear. Cowboy, Explorer and Gardener use miniature hats at 30% of their original linear size, perched on one side of the head. Casual remains without a hat.

Approval here covers the requested asset designs. It does not grant a child's account these cosmetics or approve them for runtime delivery.

## Files and compatibility

Paths are relative to this character directory. Each outfit uses:

```text
skins/<id>/skin.json
skins/<id>/model/Robert.glb
skins/<id>/source/Robert.blend
previews/<id>.png
previews/<id>_poses.png
```

The GLB is the runtime interchange model; the Blender file is its editable source. The previews show the appearance and sample poses. The portable catalogue and skin manifests document asset selection; they do not automatically create Unity prefabs or configure the application.

Every outfit preserves the exact 24-bone names, hierarchy and rest transforms in `shared/rig_contract.json`, compatible skin weights, and the body animation names **Standing, Idle, Wave, Talk, Nod, Celebrate**. All seven appearances include the same six clips in both GLB and Blender source. See [ANIMATIONS.md](ANIMATIONS.md) for durations and looping. Bone count alone is insufficient. The Blender body retains the base material slots and appends garment colours; each outfit also has a separate `Robert_Outfit` mesh. Importers may omit unused materials, so bind each skin prefab by mesh/material name rather than assuming identical exported slot indices. Keep the dedicated `FaceScreen` mesh with its `FaceScreen_Unlit` material. Outfit geometry must not obscure the screen or detach during the existing gestures.

Faces remain opaque, full-face **1024 x 512 PNGs** using full-range UV0. Reuse `shared/faces/default/` and its animation timing for lowercase `idle`, `blink` and `talk` face clips. These texture sequences run separately from body motion; pair skeletal `Talk` with face `talk` for demonstration speech. Use a per-character renderer texture override so changing one face does not change other instances. See [the character guide](README.md) and [Unity setup](unity/README.md) for face replacement and Inspector wiring.

The thobe's blended lower hem supports the existing idle and gesture set. It is not simulated cloth and has no locomotion guarantee. Walking, running, wider leg movement or new lower-body poses require garment deformation and intersection checks before use.

## Application boundary

These additions are asset work only. They do not grant or unlock cosmetics, modify server-owned inventory, change bridge allowlists, or establish production/device readiness. Unity remains presentation-only; it must not decide ownership, award currency or call the backend to equip an outfit. Runtime cosmetic IDs must pass the application's allowlist and server-owned inventory checks before sanitized presentation commands reach Unity.

Keep the declared `default` selection, existing asset-failure behavior, background pause, reduced-motion support and Flutter static-avatar fallback. Native integration and Android device validation remain separate work under the [product architecture and roadmap](../../../doc/product-architecture-roadmap.md).
