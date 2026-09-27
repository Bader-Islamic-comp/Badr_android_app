# Robert PNG faces

All faces are opaque 1024 × 512 PNGs and work on every skin's `FaceScreen`.
The existing neutral, blinking and talking frames remain available.
The `talk` sequence now spans 4.8 seconds, with varied mouth frames and one combined blink, matching the body Talk loop's duration. Body and face playback are still configured separately. See [the animation guide](../../../ANIMATIONS.md).

| New clip ID | PNG | Expression |
|---|---|---|
| `joy` | `cute_joy.png` | Happy curved eyes, warm cheeks and a broad smile |
| `giggle` | `cute_giggle_a.png`, `cute_giggle_b.png` | Alternates an open laugh with a smile |
| `wink` | `cute_wink.png` | One winking eye, a playful smile and a sparkle |
| `curious` | `cute_curious.png` | Raised eyebrow and a small questioning mouth |
| `wow` | `cute_wow.png` | Wide eyes and a round surprised mouth |
| `sleepy` | `cute_sleepy.png` | Resting eyes and little sleep marks |
| `bashful` | `cute_bashful.png` | A small smile with peach cheek marks |
| `starry` | `cute_starry.png` | Star-shaped eyes and an excited smile |

Timing is supplied in `animations.json` in milliseconds. All new clips are one-shot reactions and return to the neutral PNG through the existing player's completion behavior. Giggle, Wink and Wow include additional transition frames; use the manifest's ordered frames when configuring them.

In Unity, import each PNG as a Texture2D, assign it with `RobertFacePlayer.SetFace(texture)`, or add a named clip in the player's Inspector and call `Play("giggle")`. Convert manifest milliseconds to seconds for Inspector frame durations. The helper does not import JSON automatically. Keep the material opaque/unlit, white-tinted, and use per-instance texture overrides.

These are authored presentation expressions, not emotion detection or automatic app behavior. The original embedded neutral PNG in each GLB remains unchanged.

To regenerate everything, run `tools/create_face_assets.py` from the character root; it also runs `create_cute_faces.py`. To regenerate only this added set, run `tools/create_cute_faces.py`. Both are authoring tools and replace their generated PNG files. Pillow is required.
