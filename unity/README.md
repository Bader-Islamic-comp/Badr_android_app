# Robert presentation integration kit

A real Unity project. `Assets/`, `Packages/` and `ProjectSettings/` are tracked;
`Library/`, `Temp/` and the `export/` build output are not.

`Assets/Companion/Generated/` is produced by the room builder and can be deleted
and rebuilt at any time. The canonical character package under
`../assets/characters/robert/` stays authoritative: the builder never edits it.

Verified with Unity 6000.3.24f1 (Android Build Support, bundled OpenJDK/SDK/NDK)
and the Android toolchain (SDK 36, build-tools 36.0.0, JetBrains Runtime 25).
**No glTF model is imported, no scene is built and no Android export is
produced**, so rendering, the Unity-as-a-Library composition and every device
measurement remain unverified. No device or emulator is available.

## What is and is not verified

| Source | State |
|---|---|
| `Assets/Companion/Runtime/BridgeCommand.cs` | Compiles; **executed** by 34 engine-free checks and the EditMode suite |
| `Assets/Companion/Runtime/BridgeSession.cs` | Compiles; **executed** by 34 engine-free checks and the EditMode suite |
| `Assets/Companion/Runtime/CompanionBridgeReceiver.cs` | Compiles; **executed** by 11 EditMode tests |
| `Assets/Companion/Runtime/RobertAvatarPresentation.cs` | Compiles; never executed — needs an imported model and scene |
| `Assets/Companion/Runtime/AndroidUnityEventTransport.cs` | Compiles; never executed — needs an Android export and a device |
| `../android/.../UnityRoomPlugin.kt`, `UnityRuntime.kt`, `MainActivity.kt` | Compiles into debug and release APKs; never executed |

`BridgeCommand` and `BridgeSession` are deliberately free of engine and
third-party dependencies, including the JSON reader, so the part of the contract
that decides what may touch presentation can be compiled and run without Unity
at all:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File validation/Test-BridgeCore.ps1
```

The receiver needs the engine. This builds a throwaway project, stages the kit
and the canonical character helpers, and runs the EditMode suite in batch mode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File validation/Test-EditMode.ps1
```

Pass `-Fresh` to discard the throwaway project first, or `-UnityPath` to pick an
Editor. The first run takes several minutes while Unity creates and imports the
project.

The EditMode suite covers what only the engine can: component wiring, transport
binding and the exact envelopes Flutter has to validate — readiness reporting
installed and then negotiated capabilities, acknowledgements naming the message
they answer, malformed envelopes producing no reply at all, best-effort cues
going unacknowledged, refused equipment answering with its reason, missing
assets reporting `asset.failed`, nothing being accepted without a connected
transport, and outgoing sequences increasing with unique message IDs.

Neither suite is a substitute for importer verification, scene inspection,
rendering checks or Android device tests. The kit intentionally leaves those
gates open.

## Building the room

**Companion > Create Robert Development Room** generates everything from the
staged assets: the unlit face material, an Animator whose one-shot states return
to Idle, the model prefab with its face player wired from the approved timing
manifest, the skin definition, and the room scene with the bridge GameObject.
It validates the model, the four rig clips and the manifest first, and refuses
rather than fabricating a substitute.

**Companion > Export Android Character Room** does that and then exports the
Gradle `unityLibrary` module into `export/`, which
`../android/settings.gradle.kts` includes when it is present. Both have batch
entry points (`CompanionRoomBuilder.BuildRoomBatch` and `ExportAndroidBatch`),
which is how they are actually run here, via `-batchmode -executeMethod`.

The export targets **x86_64 only**, which is what the development emulator runs.
A physical phone needs an ARM64 export, and a store build needs both plus its own
signing; neither is configured.

### Why the classic Activity entry point

Unity 6 defaults its Android **Application Entry Point** to GameActivity. That
export ships only `com.unity3d.player.UnityPlayerGameActivity` — an Activity you
launch — and **no `UnityPlayer` class at all**. Unity-as-a-Library composition
needs `UnityPlayer`, the embeddable player the host adds to its own view
hierarchy, so a GameActivity export cannot be composited beneath Flutter no
matter how the host is written.

The exporter therefore sets
`PlayerSettings.Android.applicationEntry = AndroidApplicationEntry.Activity`,
which restores `UnityPlayer` and `UnityPlayerActivity`. If that setting is ever
changed back, the host will find no player, report no room, and Flutter will
fall back to the static avatar — silently, because that is also what a machine
with no export at all looks like.

Unity's exported manifest declares its own activity with a LAUNCHER
intent-filter and sets `android:appCategory="game"`. Merged as-is that would give
the app a second launcher icon and categorise a children's learning app as a
game, so `../android/app/src/main/AndroidManifest.xml` strips both. Those rules
are inert when no export is present.

### Why FBX and not the GLB

The canonical runtime model is `Robert.glb`, but it is **not** what this project
imports. `com.unity.cloud.gltfast` 6.13.0 cannot import it at all: its
skinned-mesh path throws before producing an asset.

```
InvalidOperationException: The previously scheduled job SortAndNormalizeBoneWeightsJob
writes to NativeArray<VBones> ... You must call JobHandle.Complete() ...
  at GLTFast.MeshGenerator.GenerateMesh (MeshGenerator.cs:189)
```

That is an upstream defect in the importer, triggered by any skinned mesh — ours
has a 24-bone rig. Rather than disable Unity's job safety checks to paper over a
real race, `tools/export_robert_fbx.py` exports `Robert.fbx` from the canonical
`Robert.blend` with Blender, and Unity's own FBX importer handles it. That drops
the third-party importer entirely and keeps the same source of truth.

The export keeps only `FaceScreen`, `Robert_Body` and `Robert_Rig` — the
canonical scene's camera, lights and studio floor are for renders, and the room
builds its own. Blender writes one take per action, which Unity names
`Robert_Rig|Idle`, so the builder matches on the action name.

## Flutter/native boundary

`CompanionBridgeReceiver.ReceiveMessage(string)` is the entry point for Unity
native messaging. Commands use the shared v1 contract in
`../contracts/avatar-bridge-v1.schema.json`. Only Robert and the default skin are
accepted. Input is bounded to 4096 characters and parsed with a strict
allowlist: extra or duplicate fields, unsupported commands, malformed UUIDs,
unsupported versions, fractional or negative sequences, unknown cosmetics, and
any field carrying child text or audio all fail before presentation changes.

The host side is `companion/unity_commands` (`sendMessage`, `openRoom`,
`disposeRoom`) and `companion/unity_events`. `disposeRoom` is what makes a retry
safe: a reused receiver keeps its sequence watermark and initialization state,
so the Flutter bridge and the native room must be recreated together.
`AvatarRoom` on the Flutter side does exactly that.

The receiver emits `unity.ready` only with installed capabilities, `asset.failed`
when required presentation assets are missing, and `bridge.ack` for structurally
valid initialization and equipment requests. Malformed envelopes are dropped
without a reply and without logging the payload. Readiness is repeated after an
accepted initialization, so Flutter may subscribe and initialize in either
order. Only the intersection of requested and installed capabilities is enabled.
The 128-entry retry cache returns the same outcome without replaying a mutation;
evicted messages are still refused by the sequence watermark.

Initialization selects neutral face and Idle. Default equipment is already
installed and cannot grant ownership — Flutter sends equipment changes only
after the server has validated its own inventory. A cue rejected while paused
answers `presentation_rejected`, never `asset_unavailable`, and leaves the
watermark untouched so the sender can reuse that sequence.

No credentials, networking, conversation state, rewards, persistence, text or
audio belongs in this assembly.

## Open device questions

These are unresolved and must be answered on a real Android device before the
character room is treated as a capability rather than a prototype:

- Whether full-screen Unity beneath a transparent Flutter view routes input,
  keyboard insets and accessibility correctly. `MainActivity` requests
  `BackgroundMode.transparent` only when an exported runtime is present; that
  also needs a translucent window theme, which is not yet set.
- Startup time, memory, frame time and package size against budgets that have
  not been approved yet.
- Crash and lifecycle behaviour across background, rotation and process death.
- Whether the reflective names in `UnityRuntime.kt` match the actual export.
- Whether the glTF importer produces the four required clips on the imported
  root, and whether the face material renders correctly in the chosen pipeline.
- Whether `CompanionEventBridge` survives release shrinking in the final app.
  R8 renames it by default, which breaks the Unity-to-Flutter event path in
  release builds only; `android/app/proguard-rules.pro` keeps it, and that rule
  must be re-checked whenever the transport's class or method names change.

If the composition fails, keep the static Flutter screen and report the
limitation for design revision. Do not substitute a web renderer, a
partial-screen 3D widget, Unity-owned chat UI or a second Unity runtime.
