# Robert presentation integration kit

A real Unity project. `Assets/`, `Packages/` and `ProjectSettings/` are tracked;
`Library/`, `Temp/` and the `export/` build output are not.

`Assets/Companion/Generated/` is produced by the room builder and can be deleted
and rebuilt at any time. The canonical character package under
`../assets/robert/` stays authoritative: the builder never edits it.

Verified with Unity 6000.3.24f1 (Android Build Support, bundled OpenJDK/SDK/NDK)
and the Android toolchain (SDK 36, build-tools 36.0.0, JetBrains Runtime 25).
The model imports, the scene builds, the Android export is produced and the room
renders on an x86_64 emulator — see *What the device run proved* below for what
that run did and did not settle. No physical device has been used, so startup
time, memory, frame time, ARM64, TalkBack and rotation remain unmeasured.

## What is and is not verified

| Source | State |
|---|---|
| `Assets/Companion/Runtime/BridgeCommand.cs` | Compiles; **executed** by 93 engine-free checks and the EditMode suite, including the six animations and eleven emotions, exact-case matching and parity with the shared schema |
| `Assets/Companion/Runtime/BridgeSession.cs` | Compiles; **executed** by 93 engine-free checks and the EditMode suite |
| `Assets/Companion/Runtime/AvatarPerformance.cs` | Compiles; **executed** by 22 EditMode tests (face pairing, Talk start and stop, blink resumption, pause/resume, skin-swap reapplication) and its pairing table by the engine-free checks |
| `Assets/Companion/Runtime/CompanionBridgeReceiver.cs` | Compiles; **executed** by 12 EditMode tests |
| `Assets/Companion/Runtime/RobertAvatarPresentation.cs` | Compiles; its scene renders on an emulator, an equipped colour look recolours the character there, and an equipped outfit swaps in its model (thobe → cowboy → Sunset Copper verified). Since the six-clip update the emulator has shown Standing moving at rest, the greeting Wave, the `giggle` and `wink` faces the right way up, Talk with its mouth cycle and arm gestures, and the `starry` face (see *What the device run proved*). Nod, Celebrate, the other faces, reduced motion, pause and resume on a device and a skin swap during Talk have **not** been seen yet, and the crossfades and blink resumption were not checked on their own; those rest on their rules (above) and the generated assets (below) |
| `Assets/Companion/Editor/CompanionRoomBuilder.cs` | Compiles; produces the room (`ROOM_OK`) and the export (`EXPORT_OK`). What it generates — the Animator, the models' clip import settings, every skin's face player, the face textures' import settings and the face lengths in the scene — is checked by 7 EditMode tests |
| `Assets/Companion/Runtime/RoomBackdrop.cs` | Compiles; its quad renders on an emulator. No aspect other than the emulator's has been seen |
| `Assets/Companion/Runtime/AndroidUnityEventTransport.cs` | Compiles; **executed** on an emulator — its events reach Flutter and the handshake completes |
| `../android/.../UnityRoomPlugin.kt`, `UnityRuntime.kt`, `MainActivity.kt` | Compiles into debug and release APKs; runs on an emulator |

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
transport, readiness waiting for a presentation that can actually perform, and
outgoing sequences increasing with unique message IDs.

It also runs the performance rules in `AvatarPerformance` against a recording
rig (see *Animation and face cues*), and reads the room's generated assets as
the throwaway project imports them: the shared Animator rests in Standing, binds
the real clips with the right lengths and Loop Time, and returns each one-shot
to Standing with a 0.2 s fixed transition at its end; all seven models import
the six clips with the right loop flags; every skin's face player carries every
manifest clip with its frames, timings and loop flag; every face frame is a
clamped sRGB texture; the spine's resting sway survives import; and the scene
holds each face clip's length. Those checks
describe the room as last built, so rebuild it before running them.

Neither suite is a substitute for importer verification, scene inspection,
rendering checks or Android device tests. The kit intentionally leaves those
gates open.

## Building the room

**Companion > Create Robert Development Room** generates everything from the
staged assets: the unlit face material, an Animator that rests in Standing and
whose one-shot states return to it, the model prefab with its face player wired
from the approved timing manifest, the skin definition, and the room scene with
the bridge GameObject. It validates every model, rig and clip and the manifest
first, and refuses rather than fabricating a substitute: all seven models must
carry the six clips with the right Loop Time, the bridge's animation allowlist
must be exactly those six clips, and the manifest must have a one-shot face for
every allowlisted emotion plus the `idle`, `talk` and `joy` clips the body cues
pair with.

The staged faces are a copy of the package's `shared/faces/default/`: every PNG
and its `animations.json`, in `Assets/Companion/Character/Robert/Faces/`. The
builder pins every frame the manifest uses to Default, sRGB, bilinear and
**Clamp** (the screen's UVs span the whole image, so a repeating edge would
bleed the opposite border into the face), and copies each clip's length into the
presentation's `faceCues`, from which it knows when a one-shot face has ended.

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

Switching the entry point is necessary but not sufficient. In Unity 6
`UnityPlayer` itself is **abstract**: its only constructor is protected and
takes an obfuscated internal type, and `getView()` is abstract. The concrete
Activity-hosted player is `com.unity3d.player.UnityPlayerForActivityOrService`,
which does expose a public `(Context)` constructor and `getView()`.
`UnityRuntime` tries that first and falls back to `UnityPlayer` for older
exports, skipping any candidate that turns out to be abstract.

Unity's exported manifest declares its own activity with a LAUNCHER
intent-filter and sets `android:appCategory="game"`. Merged as-is that would give
the app a second launcher icon and categorise a children's learning app as a
game, so `../android/app/src/main/AndroidManifest.xml` strips both. Those rules
are inert when no export is present.

### The backdrop

The room has no skybox and used to clear to transparent black, which on a device
read as a pitch-black void wherever the full-bleed Flutter page was not
painting. `tools/make_backdrop.py` draws a plain desert horizon from the project
palette — decoration only, with no text, symbol or real place, so it needs no
content review — and the builder parks it on an unlit quad behind the character.

The generator writes the same image twice, because two things show it: this
project's `Assets/Companion/Room/backdrop_desert.png`, and the Flutter app's
`../assets/room/backdrop_desert.png`, which backs every page that is *not* the
character page so those pages read as the same place without Robert in them. One
generator, one picture, two consumers.

```powershell
python unity/tools/make_backdrop.py
```

Three details are worth keeping:

- **The quad carries both windings.** Which way a camera ends up facing a
  generated quad is easy to get wrong by one 180° rotation, and the symptom is
  an invisible backdrop with no error. Four extra triangles removes the
  question entirely.
- **`RoomBackdrop` sizes it at runtime, not at build time.** How large the quad
  must be depends on the viewport, which the builder does not know. The
  component fills the frustum and centre-crops the texture to the screen's
  shape — "cover", not "stretch" — and redoes that whenever the aspect or field
  of view changes. A portrait phone therefore sees a narrow centre slice of a
  2:1 image, which is why the generator keeps the composition centred.
- **The camera is nearly level.** It used to be pitched 10° down, and pitching
  down pushes the subject *up* the frame, which stranded the character against
  the sky above the backdrop's horizon. It is now 2°, with no vertical lift and
  a tighter margin, so Robert stands on the sand in the middle of the frame.

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
`Robert_Rig|Standing`, so the builder matches on the action name, exactly: `Talk`
is a body clip and `talk` a face clip. The sources keep each clip on its own
muted NLA track with no active action, so the export bakes every action on its
own, over its own frame range, without another track blending in.

Three import details used to be wrong, and are now pinned and checked:

- **Loop Time.** The importer left to its defaults imports every take with Loop
  Time off, and nothing set it: the old `Idle` (then a 2 s clip) played once and
  held its last frame, so the room's "idle motion" stopped two seconds after
  every cue. The builder now rebuilds each model's clip list from the file's
  takes on every build, with Loop Time on for Standing, Idle and Talk and off
  for Wave, Nod and Celebrate, and refuses a model whose clips did not take it.
  Rebuilding from the takes also picks up a re-export's new frame ranges.
- **Preview clips.** The importer also makes an Inspector preview copy of every
  take, named `__preview__Robert_Rig|…`, and the old builder's first match was
  that copy, so the Animator bound preview clips rather than the configured
  ones. It now skips them, and an EditMode test checks the bound clip names.
- **Keyframe reduction.** The resting sway is authored in fractions of a degree
  (the spine moves about 0.2–0.4°). At the importer's default 0.5° rotation
  error, Standing's spine imported as a flat two-key curve and the other
  resting channels as five keys over six seconds. The builder keeps keyframe
  reduction but holds rotations to 0.05°; the clips stay small, because only
  the default model's clips are referenced by the Animator.

### Outfits

Six modelled outfits come from the canonical package's `skins/` folders. Each
is a whole skin: a reshaped `Robert_Body`, a separate `Robert_Outfit` garment
mesh and the same `FaceScreen`, all skinned to the default 24-bone rig with the
same six clips. `tools/export_robert_fbx.py` keeps `Robert_Outfit`, and exports
each one to `Assets/Companion/Character/Skins/<id>/Robert.fbx` (the default
skin goes to `Assets/Companion/Character/Robert/Robert.fbx`):

```powershell
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b ..\assets\robert\skins\cowboy\source\Robert.blend `
  --python tools\export_robert_fbx.py -- "$PWD\Assets\Companion\Character\Skins\cowboy\Robert.fbx"
```

The cosmetic id is the folder name with `_` written `-` (`arab_thobe` →
`arab-thobe`), because cosmetic ids are letters, digits and hyphens everywhere
they travel. The builder lists the outfits in `CompanionRoomBuilder.Outfits`,
refuses any whose rig differs from the default's transform for transform,
makes `RobertSkin_<id>.prefab` and `.asset` for each with the shared face
material and Animator, wires them into the presentation's `outfits`, and frames
the camera around all of them so a hat is never cropped. Adding an outfit means
exporting its FBX, adding its id to that list, to `BridgeCommand.Cosmetics`, to
the bridge schema, to the Flutter allowlist and to the service's catalogue; the
catalogue and allowlist tests in both repositories fail when they disagree.

## Flutter/native boundary

`CompanionBridgeReceiver.ReceiveMessage(string)` is the entry point for Unity
native messaging. Commands use the shared v1 contract in
`../contracts/avatar-bridge-v1.schema.json`. Only Robert is accepted, and only
the looks the room was built with — the colourways `default`, `sunset`, `dune`
and `midnight`, and the outfits `casual`, `cowboy`, `astronaut`, `arab-thobe`,
`explorer` and `gardener` — allowlisted in `BridgeCommand.Cosmetics` and
matched exactly. Cues are allowlisted the same way, in `BridgeCommand.Animations`
(`Standing`, `Idle`, `Wave`, `Talk`, `Nod`, `Celebrate`) and
`BridgeCommand.Emotions` (`neutral`, `happy`, `surprised`, `joy`, `giggle`,
`wink`, `curious`, `wow`, `sleepy`, `bashful`, `starry`), matched exactly and
case-sensitively: `talk` is not an animation and `Joy` is not an emotion. The
schema in this repository and in `../comp-server/contracts/` carries the same
lists and must stay byte-identical; the engine-free checks compare it with the
receiver. Extending an allowlist is additive, so the bridge stays v1 and the
negotiated capabilities (`avatar.play`, `avatar.set_emotion`, …) are unchanged.
Input is bounded to 4096 characters and parsed with a strict
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

Initialization selects the current look, then rests: Standing with the blinking
`idle` face. Equipment cannot grant ownership — Flutter sends a look only after
the service has recorded that it was earned and worn. An outfit swaps in its own model through
the skin controller; a colourway puts the original model back if an outfit was
worn and recolours every renderer except the face screen, which keeps its
approved art. Outfits are never tinted. A swap re-applies the presentation state
to the new model (see *Animation and face cues*). A cue rejected while paused
answers `presentation_rejected`, never `asset_unavailable`, and leaves the
watermark untouched so the sender can reuse that sequence.

### Animation and face cues

Every model carries six body clips from the package, 30 fps with no root
motion, and every skin shares one Animator:

| Body clip | Length | Playback | Face it brings |
|---|---:|---|---|
| `Standing` | 6.0 s | Loop; the Animator's **default state** and the resting state | `idle` (blinks now and then) |
| `Idle` | 6.0 s | Loop; the same motion, kept as an alias | `idle` |
| `Talk` | 4.8 s | Loop until the next body cue | `talk` (looping mouth cycle) |
| `Wave` | 3.2 s | One-shot, back to Standing | `joy` |
| `Nod` | 1.6 s | One-shot, back to Standing | `idle`, left running |
| `Celebrate` | 2.4 s | One-shot, back to Standing | `joy` |

`AvatarPerformance` holds the rules, free of engine types so they can be tested
alone; `RobertAvatarPresentation` carries them out on whichever model is
installed:

- **`avatar.play`** crossfades the body over 0.2 s (`CrossFadeInFixedTime`) and
  starts the paired face. Re-sending the loop that is already playing restarts
  nothing. One-shots return to Standing through the Animator's own exit
  transition at their end, again 0.2 s, so bridge v1 needs no completion event.
- **Talk** starts with `avatar.play` `Talk` and runs, body and mouth, until the
  next `avatar.play`. Flutter ends it by sending `Standing`, which crossfades
  back and resumes blinking. The mouth cycle is decorative, not lip-sync.
- **`avatar.set_emotion`** plays that face clip once — `happy`, `surprised`,
  `joy`, `giggle`, `wink`, `curious`, `wow`, `sleepy`, `bashful`, `starry` are
  all one-shots that end on the neutral PNG. `neutral` shows the neutral face at
  once. An emotion during Talk interrupts the mouth cycle and the mouth stays
  still until the next body cue, so Flutter sends `Standing` first.
- **Blinking resumes by itself.** The shared face player reports neither a
  finished clip nor whether one is playing, and it is copied unchanged from the
  package, so the presentation keeps each clip's length (`faceCues`, written by
  the builder from the manifest) and checks once a frame: when a one-shot face
  has run its length and the body is in, or blending into, Standing or Idle, it
  starts `idle` again. Until the body rests the face stays neutral. A
  `Standing` cue lets an expression that is still showing finish first. The
  check allocates nothing, and returns at once while a loop is playing.
- **`app.pause`** freezes the Animator and stops the face where it is; cues are
  declined until **`app.resume`**, which crossfades to Standing and restarts
  the blinking face.
- **A skin swap** gives the new model a fresh Animator and face player, so the
  current state is applied again: the resting loop with `idle`, Talk with
  `talk` if Talk was playing, or Standing frozen on the neutral face if paused.
  A one-shot in progress does not carry over; the swap lands where it would
  have returned to.

Unity only ever receives these allowlisted names — never child text or audio.

No credentials, networking, conversation state, rewards, persistence, text or
audio belongs in this assembly.

### The host must drive Unity's lifecycle

`UnityPlayerActivity` in the export is the reference for what a host owes the
player, and it is more than constructing it:

- it adds **`getFrameLayout()`** to the hierarchy, not `getView()` — `getView()`
  returns the inner surface, which already sits inside that frame layout and so
  cannot be re-parented;
- it forwards `onStart`, `onResume`, `onPause`, `onStop`, `destroy`,
  `windowFocusChanged` and `configurationChanged`.

Without `onStart`/`onResume` the player never begins rendering, so the scene
never loads, the receiver's `Awake` never runs, and no handshake is possible —
with no error from either side.

### The surface query is answered late, not guessed

Dart starts running inside the activity's `onCreate`, so Flutter can ask
`roomSurface` before the room has been attached. Answering "no" then is wrong
and would leave the page opaque over a perfectly good room, so the host holds
that reply until the activity reports the player. Flutter applies its own
deadline, and its deadline helper had to learn that a startup probe is
legitimate before any bridge exists — it previously cancelled every call made
while the room was not ready, which is precisely when the probe runs.

The probe also needs its own, much longer deadline than an ordinary bridge
message: it waits on the host constructing the engine, which on a slow or
memory-pressured device takes many seconds. Reusing the 3-second bridge timeout
reports "no room" on exactly the devices least able to afford losing one.

### Preparing the room before the handshake

The receiver binds its transport in `Awake`, which only runs once Unity is
actually playing the scene. So the host creates the player, attaches its surface
and resumes it during preparation, **not** in `openRoom` — `openRoom` is only
offered after a successful handshake, so waiting for it would deadlock.

Commands are then held until the receiver proves it exists by emitting its first
event. Delivering earlier targets a GameObject the scene has not created yet,
and Unity drops that silently, with no error on either side.

### Generated assets must outlive the scene switch

Two wiring traps in the builder, both of which serialise as a plausible-looking
null rather than an error:

- `AssetDatabase.CreateAsset` makes the instance passed to it *become* the
  asset, but reloading it by path in the same pass can return null. The builder
  uses the created instance directly.
- Opening the generated scene with `EditorSceneManager.NewScene` invalidates
  references to assets created earlier in the same run. The skin definition is
  flushed with `SaveAssets`/`Refresh` and then re-resolved by path *after* the
  scene exists.

Missing either one leaves `defaultSkin: {fileID: 0}` in the scene, and the only
symptom is `RobertSkinController` logging "wire a valid default skin, visual
root and face player" on a device. The builder therefore asserts every
serialized reference it sets with `Require(...)`, so an unassigned field fails
the export instead.

### Generated prefabs must be unpacked

The room builder instantiates the imported model and then adds components to
it. Saved directly, that produces a **variant of the FBX**, and the added
components' references to base objects serialize as bare local file IDs which
do not exist in the saved asset. The YAML looks correct — `faceRenderer:
{fileID: ...}` is right there — but the reference resolves to null at runtime,
and the only symptom is `RobertSkinController` logging "wire a valid default
skin, visual root and face player" on device.

The builder therefore unpacks the instance completely before wiring, and then
calls `Rebind()` and `SetDefaultFace()` itself so a broken binding fails the
build rather than the device.

### Readiness must wait for a room that can perform

The receiver announced `unity.ready` from `BindTransport`, which the transport
calls in `Awake`. The host releases every command it was holding the moment it
hears any event from Unity, so the queued `avatar.initialize` was delivered
immediately — while `RobertSkinController.Start` had not yet installed the
visual. `IsAvailable` was therefore false, the session answered
`asset_unavailable`, and Flutter fell back to the static avatar **for good, on
every single launch**, with the room rendering perfectly behind it.

The symptom was a status chip reading "Character room · not connected" over a
visibly working room, which points at the transport and is nothing to do with
it. What settled it was a lifecycle trace of the host: `attach`, `onPlayerReady`
and `onListen` all arrived in order, Unity's events arrived with a live sink,
and their lengths matched `asset.failed` rather than an acknowledgement.

The receiver now announces readiness from `Update`, once — and only once — the
presentation reports it can perform. A room whose assets never arrive simply
never claims readiness and Flutter's own deadline falls back, which is the
outcome that was wanted anyway.

Two deadlines were wrong for the same underlying reason. Initialization used the
ordinary 3-second bridge timeout, but it waits on the engine starting: Unity
takes around six seconds on this emulator, and the handshake had already given
up. `AvatarBridge.startupTimeout` now covers both that and the surface probe,
because both wait for an engine rather than for a room that is already
answering.

## What the device run proved

On an Android 16 x86_64 emulator the app installs, launches without crashing and
Unity starts in-process:

```
Unity : Context Type: ActivityOrService
Unity : Built from '6000.3/staging' ... Scripting Backend 'il2cpp' ...
Unity : Product Name: Robert Room
```

The generated scene loads with no errors, so the skin, prefab, Animator and face
player all resolve at runtime. The composition is in place too — `dumpsys
activity top` shows Unity's surface full screen beneath a transparent Flutter
view:

```
com.unity3d.player.a.g{... 0,0-1080,2400 ... app:id/unitySurfaceView}
io.flutter.embedding.android.FlutterView{... 0,0-1080,2400 #1}
  io.flutter.embedding.android.FlutterTextureView{...}
```

The room renders. `design/room-on-device.png` is the character running full
bleed behind the Flutter layer on that emulator: the Blender model, its rig and
the neutral face texture, framed from the model's own measured bounds, standing
on the generated desert backdrop with only the composer and the navigation over
it.

**The bridge handshake completes.** The parent area's room line reads "Character
room · playing", the greeting wave runs, and an earned look sent as
`avatar.set_cosmetics` recolours the character in the room; since the outfits,
an earned outfit sent the same way swaps in its model (Arab Thobe, then Cowboy,
then back to Sunset Copper on the original model). That is the full
path — Flutter to the host, the host to Unity, Unity's events back to Flutter —
running on a device.

**Robert moves at rest, talks and reacts.** After the six-clip update, on the
same emulator against the development harness:

- Standing keeps moving: the mean pixel change between frames 0.8 s apart was
  1.9–4.7.
- The greeting Wave plays (`design/robert-greeting-wave.png`).
- Taps show the `giggle` and `wink` faces, the right way up
  (`design/face-giggle.png`, `design/face-wink.png`).
- Talk shows the mouth cycle and arm gestures while a reply appears
  (`design/robert-talking.png`).
- Earning Casual on Style, then returning to Talk, plays the `starry` face
  after about 0.5 s (`design/face-starry.png`).

Not seen yet: the `curious` face after an abstention, Nod after a grounded
answer (the harness had grounded answers off), reduced motion, a skin swap
during Talk, and pause and resume on a device.

One thing remains:

- **A cold first launch can still miss the room.** Immediately after an install
  the page came up opaque and a warm relaunch showed the room. The surface probe
  now shares the longer startup deadline, which helps, but a deadline is the
  wrong instrument: the host should push a "room attached" event rather than
  have Flutter wait on a reply.

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
- Whether the backdrop's runtime "cover" crop still frames well on aspects other
  than the emulator's 1080x2400, including a tablet and a landscape rotation.
- Whether `CompanionEventBridge` survives release shrinking in the final app.
  R8 renames it by default, which breaks the Unity-to-Flutter event path in
  release builds only; `android/app/proguard-rules.pro` keeps it, and that rule
  must be re-checked whenever the transport's class or method names change.

If the composition fails, keep the static Flutter screen and report the
limitation for design revision. Do not substitute a web renderer, a
partial-screen 3D widget, Unity-owned chat UI or a second Unity runtime.
