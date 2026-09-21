# Robert presentation integration kit

An importable kit, not an Editor-created Unity project: no `ProjectSettings/`,
scene YAML or platform export is fabricated here. The scripts are nonetheless
compiled and exercised in a real Editor by `validation/Test-EditMode.ps1`, which
builds a throwaway project outside the repository.

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

## Import and create the room

1. Create a project with a supported Unity Editor using the Built-in or
   Universal Render Pipeline, and copy `Assets/Companion` into its `Assets`
   directory. Let the Editor generate `.meta` files and commit them with that
   project.
2. Copy the three character helpers from
   `../assets/characters/robert/unity/` (`RobertFacePlayer.cs`,
   `RobertSkinController.cs`, `RobertSkinDefinition.cs`) into
   `Assets/Companion/Character/` so they compile into the same assembly that
   `RobertAvatarPresentation` references. Keep them byte-identical to the
   canonical package.
3. Install a glTF importer compatible with that Editor and pipeline. It must
   import `../assets/characters/robert/skins/default/model/Robert.glb` as a
   `GameObject` asset exposing four nonempty `AnimationClip` subassets named
   exactly **Idle**, **Wave**, **Nod** and **Celebrate**. The kit neither
   supplies nor silently installs one.
4. Follow `../assets/characters/robert/unity/README.md` for the Inspector setup
   of the face player, the unlit face material and the skin definition. Convert
   the millisecond timings in `shared/faces/default/animations.json` to seconds;
   they are not imported automatically.
5. Build a `CompanionBridge` GameObject carrying `CompanionBridgeReceiver`,
   `RobertAvatarPresentation` and `AndroidUnityEventTransport`. Assign the skin
   controller, the Animator and the neutral, happy and surprised PNGs. Set the
   receiver's presentation reference to the `RobertAvatarPresentation`.
6. Inspect in Play Mode: front-facing camera, scale, rig deformation, PNG
   orientation, every body clip, return to Idle, and pause/resume.

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
