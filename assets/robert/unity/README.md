# Unity handoff helpers

These are uncompiled C# helpers, not an integrated Unity project. Unity Editor, Play Mode and device testing were unavailable. Copy the three `.cs` files into your project's `Assets` folder and let Unity generate metadata. Use your project's glTF importer for `Robert.glb`; these scripts do not install an importer or parse the JSON manifests.

## Inspector setup

1. Import the skin model and shared face PNGs. Set the PNGs to Texture Type **Default**, sRGB on, Wrap **Clamp**, and preserve their 1024 x 512 aspect ratio. They are opaque full-face images including the dark background. Read/Write is unnecessary. Choose filtering, compression and mipmaps for your intended screen size, then check the result on device.
2. Make an editable model prefab. Keep the `FaceScreen` mesh as its dedicated renderer with material slot 0. Its asset material is named `FaceScreen_Unlit`. Assign a Unity **Unlit** material suitable for your render pipeline, white tint, opaque surface, texture scale (1, 1), offset (0, 0). Set the neutral PNG as the initial texture and verify orientation. No facial morphs are used.
3. Add exactly one `RobertFacePlayer` to the prefab. Assign the dedicated screen Renderer and neutral Default Face. Add named clips in its Clips array, with ordered Texture2D frames and either FPS or one positive duration in **seconds** per frame. Use the manifest's lowercase names, including `idle`, `blink` and `talk`; lookup is case-sensitive. Convert timing JSON milliseconds to seconds; timings are not imported automatically. Set `idle` and `talk` to loop, and `blink` to one-shot playback. Keep the player and its child hierarchy enabled while presenting the character.
4. Create **Assets > Create > Robert > Skin Definition**. Set Stable Id to `default`, assign the model prefab and neutral Default Face. Future definitions need unique IDs and prefabs with the same 24-bone rig, rest pose, hierarchy and material-slot contract. Bone count alone does not prove compatibility. Author palette/material changes in prefab variants; the helpers never mutate shared material assets.
5. Add `RobertSkinController` to the persistent character object. Assign an empty Visual Root beneath it and the default definition. Put desired character scale on Visual Root: installed prefabs use local position zero, identity rotation and scale one. Do not place the controller on the replaceable model prefab.
6. Configure the model's compatible **Generic** rig and an Animator Controller with states named `Standing`, `Idle`, `Wave`, `Talk`, `Nod` and `Celebrate`, each using its matching imported clip. Disable Apply Root Motion. Set Standing, Idle and Talk to loop; keep the other clips one-shot. Use Standing as the default state. Configure approximately **0.2-second** crossfades; use fixed-duration transitions when specifying seconds. Give Wave, Nod and Celebrate exit transitions back to Standing. Drive entry to Talk and its return to Standing from the host's speech-active presentation cue.

`SelectSkin(definition)` installs the requested skin, or tries Default Skin if it is missing/invalid. The old visual remains when both fail. Null selects the default. `CurrentSkin` reports the actual installed definition; only persist its Stable Id after success. Your app owns ID lookup, unlocking and save data. Every skin prefab owns its face-player binding. A skin swap restarts that prefab's Animator; animation state is not transferred automatically.

## Playback

```csharp
skinController.FacePlayer.SetFace(happyPng);
skinController.FacePlayer.Play("blink");
skinController.FacePlayer.Play("talk");
```

Check `FacePlayer` for null before use and check the Boolean return values. Invalid clips, missing names and null textures leave valid playback running. A valid new face or clip interrupts the previous one. Completed one-shot clips return to Default Face; loops continue until interrupted. Disabling a player stops playback and leaves its last image visible; re-enabling does not automatically resume. Default playback uses unscaled time; disable Use Unscaled Time to respect game pause/time scale. Do not modify clip arrays during playback.

These calls are independent examples; calling them consecutively leaves only the final request playing. The six skeletal clips are **Standing (6 s), Idle (6 s), Wave (3.2 s), Talk (4.8 s), Nod (1.6 s), Celebrate (2.4 s)**, authored at 30 fps. Standing and Idle contain the same standing motion, preserving the existing Idle name. They use planted feet and no root motion. See [the animation guide](../ANIMATIONS.md) and `shared/animations.json` for the complete reference; manifests do not configure Unity automatically.

Pair the **skeletal `Talk`** state with **PNG `talk`** playback while speech is active. On speech end, crossfade the body back to Standing and call `SetFace(neutralPng)` or `Play("idle")` on the face player. The face and body loops have separate timing. Whole-face playback supports one sequence at a time: the supplied `talk` includes a combined mouth-and-blink frame, while a separate `blink` call interrupts talking. The mouth cycle is a visual demonstration, not audio lip-sync. Runtime sanitized timing or viseme cues can drive `SetFace`; these helpers do not capture audio or call the backend.

Textures are applied using one cached MaterialPropertyBlock per player at material index 0. The player detects `_BaseMap`, `_MainTex` and `_BaseColorTexture` and updates supported properties. An optional emission texture property may be configured; its shader keyword and colour must already be set on the authored material. Prefer Unlit to avoid pipeline-specific emission setup. There is no per-frame managed allocation in the playback loop; starting a coroutine and swapping a skin allocate. Use this player as the sole writer of the face texture properties. Two characters can share immutable PNG assets and material assets while displaying different faces; do not modify those shared textures or materials at runtime.

## Visibility, pause and reduced motion

The host application must pause presentation when the character view is hidden or the app is backgrounded. Stop or disable the Animator and call `StopPlayback()` on the face player; setting `Time.timeScale = 0` alone does not stop its default unscaled playback. Stopping leaves the last PNG visible. On return, explicitly restore the appropriate body state and face clip; the face helper does not resume itself.

For reduced motion, sample a neutral body pose once, keep skeletal playback stopped, and show the neutral PNG with `SetFace`. Standing is still an animated loop. Reapply visibility, speech and reduced-motion state after a skin swap because the replacement prefab starts a new Animator and face player. Keep Flutter's static-avatar fallback available if Unity fails. The supplied helpers do not implement these host lifecycle decisions or transfer animation state between skins.

## Validate in your project

Compile in Unity, then verify neutral display, all six body clips, seamless loop boundaries, 0.2-second crossfades, one-shot return, planted feet, PNG orientation, face looping/interruption and two instances playing different faces. Check speech end, background pause/resume and static reduced-motion behavior. Request an invalid face clip during a valid loop and confirm playback continues. Swap a valid skin and then a malformed definition; confirm fallback, the current visual and reapplication of presentation state. Check disabled/re-enabled behavior, Console errors, rig deformation, rendering and performance on the intended mobile device. No humanoid retargeting, automatic manifest loading, skin persistence or production-readiness claim is included.

API references: [Unity MaterialPropertyBlock](https://docs.unity.com/en-us/engine/6000.7/script-reference/unityengine/materialpropertyblock), [Renderer overrides](https://docs.unity.com/en-us/engine/6000.7/script-reference/unityengine/renderer), [Texture import settings](https://docs.unity.com/en-us/engine/6000.3/script-reference/unityeditor/textureimporter).
