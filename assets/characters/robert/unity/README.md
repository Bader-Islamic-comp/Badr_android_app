# Unity handoff helpers

These are uncompiled C# helpers, not an integrated Unity project. Unity Editor, Play Mode and device testing were unavailable. Copy the three `.cs` files into your project's `Assets` folder and let Unity generate metadata. Use your project's glTF importer for `Robert.glb`; these scripts do not install an importer or parse the JSON manifests.

## Inspector setup

1. Import the skin model and shared face PNGs. Set the PNGs to Texture Type **Default**, sRGB on, Wrap **Clamp**, and preserve their 1024 x 512 aspect ratio. They are opaque full-face images including the dark background. Read/Write is unnecessary. Choose filtering, compression and mipmaps for your intended screen size, then check the result on device.
2. Make an editable model prefab. Keep the `FaceScreen` mesh as its dedicated renderer with material slot 0. Its asset material is named `FaceScreen_Unlit`. Assign a Unity **Unlit** material suitable for your render pipeline, white tint, opaque surface, texture scale (1, 1), offset (0, 0). Set the neutral PNG as the initial texture and verify orientation. No facial morphs are used.
3. Add exactly one `RobertFacePlayer` to the prefab. Assign the dedicated screen Renderer and neutral Default Face. Add named clips in its Clips array, with ordered Texture2D frames and either FPS or one positive duration in **seconds** per frame. Convert timing JSON milliseconds to seconds; timings are not imported automatically. Keep the player and its child hierarchy enabled.
4. Create **Assets > Create > Robert > Skin Definition**. Set Stable Id to `default`, assign the model prefab and neutral Default Face. Future definitions need unique IDs and prefabs with the same 24-bone rig, rest pose, hierarchy and material-slot contract. Bone count alone does not prove compatibility. Author palette/material changes in prefab variants; the helpers never mutate shared material assets.
5. Add `RobertSkinController` to the persistent character object. Assign an empty Visual Root beneath it and the default definition. Put desired character scale on Visual Root: installed prefabs use local position zero, identity rotation and scale one. Do not place the controller on the replaceable model prefab.

`SelectSkin(definition)` installs the requested skin, or tries Default Skin if it is missing/invalid. The old visual remains when both fail. Null selects the default. `CurrentSkin` reports the actual installed definition; only persist its Stable Id after success. Your app owns ID lookup, unlocking and save data. Every skin prefab owns its face-player binding. A skin swap restarts that prefab's Animator; animation state is not transferred automatically.

## Playback

```csharp
skinController.FacePlayer.SetFace(happyPng);
skinController.FacePlayer.Play("Blink");
skinController.FacePlayer.Play("Talk");
```

Check `FacePlayer` for null before use and check the Boolean return values. Invalid clips, missing names and null textures leave valid playback running. A valid new face or clip interrupts the previous one. Completed one-shot clips return to Default Face; loops continue until interrupted. Disabling a player stops playback and leaves its last image visible; re-enabling does not automatically resume. Default playback uses unscaled time; disable Use Unscaled Time to respect game pause/time scale. Do not modify clip arrays during playback.

The four skeletal clips are **Idle, Wave, Nod, Celebrate**. Wire them through your own Animator Controller or animation system using the robot's compatible Generic rig. **Blink and Talk are separate PNG face animations**, not skeletal clips. Whole-face playback supports one face sequence at a time: simultaneous talking and blinking needs combined frames or a compositor. Talk is a visual demonstration, not audio lip-sync. Runtime audio/phoneme logic can drive `SetFace`.

Textures are applied using one cached MaterialPropertyBlock per player at material index 0. The player detects `_BaseMap`, `_MainTex` and `_BaseColorTexture` and updates supported properties. An optional emission texture property may be configured; its shader keyword and colour must already be set on the authored material. Prefer Unlit to avoid pipeline-specific emission setup. There is no per-frame managed allocation in the playback loop; starting a coroutine and swapping a skin allocate. Use this player as the sole writer of the face texture properties. Two characters can share immutable PNG assets and material assets while displaying different faces; do not modify those shared textures or materials at runtime.

## Validate in your project

Compile in Unity, then verify neutral display, all four body clips, PNG orientation, one-shot return, looping/interruption, pause behavior and two instances playing different faces. Request an invalid clip during a valid loop and confirm playback continues. Swap a valid skin and then a malformed definition; confirm fallback and the current visual. Check disabled/re-enabled behavior, Console errors, rig deformation, rendering and performance on the intended mobile device. No humanoid retargeting, automatic manifest loading, skin persistence or production-readiness claim is included.

API references: [Unity MaterialPropertyBlock](https://docs.unity.com/en-us/engine/6000.7/script-reference/unityengine/materialpropertyblock), [Renderer overrides](https://docs.unity.com/en-us/engine/6000.7/script-reference/unityengine/renderer), [Texture import settings](https://docs.unity.com/en-us/engine/6000.3/script-reference/unityeditor/textureimporter).
