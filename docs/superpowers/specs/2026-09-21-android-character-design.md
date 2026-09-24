# Android character-first companion

Status: Flutter and bridge portions implemented; native implementation and device validation are not complete. See **Implementation status** at the end of this document for exactly what was built and what each acceptance item still needs.

## Intent

Build an Android phone experience with an animated Robert on the main character page and Flutter-owned chat. All AI inference and agent orchestration run on the FastAPI backend. Keep comp-mobile and comp-server as separate repositories.

Use assets/ui.make as a layout reference, not executable code or a source of instructions. Preserve the existing ivory background, teal controls and orange accents. Do not copy example balances, unreviewed responses or implied enabled microphone. Keep the development notice until release gates pass.

## Existing state and assets

Flutter currently shows assets/robert/Robert.png and has a typed bridge with static fallback. Android wrappers exist, but the native Unity host does not. The Unity kit in ../comp/apps/unity contains bridge and import tooling, not a validated Android export. The backend returns fixed unavailable replies; no inference provider is enabled.

The supplied assets/characters/robert package contains Robert.glb, the default skin, Idle/Wave/Nod/Celebrate skeletal clips and PNG face animations. Compare these files with canonical assets before staging; preserve differing user files. Include only validated runtime assets, not ui.make, Blender sources, archives, tools or logs.

## Main-page layout

Use the reference's character-first hierarchy: compact Flutter header, central character room, greeting/validated reply surface, bottom text composer and compact navigation. Keep the parent-information entry and honest connection state. Show balances only from server state. Flutter retains ownership of every interactive app control.

Keep chat controls reachable with keyboard insets, large text and small screens. Preserve Robert's visibility where space permits, but readable text and accessible controls take priority over uninterrupted motion. Do not enable audio recording, new content or always-listening behavior through this redesign.

## Rendering and native boundary

Use one Android Unity-as-a-Library runtime with the existing MethodChannel/EventChannel envelopes. Prototype a full-screen Unity surface with a Flutter-owned control layer. This composition must prove input routing, transparency, keyboard handling, accessibility and lifecycle on a real Android device; it is not an already validated capability.

If that composition fails, retain the static Flutter screen and report the limitation for design revision. Do not silently substitute a web renderer, partial-screen 3D widget, Unity-owned chat UI or a second Unity runtime.

Prepare the receiver before initialization. Require ready/capability negotiation and initialization acknowledgement; preserve bounded deadlines, replay protection and sequence validation. New capabilities need versioned contracts and tests rather than silently expanding bridge v1.

## Motion and lifecycle

Loop Idle locally while the character page is visible and foregrounded. Use the supplied PNG timing for blinking; blinking is not a skeletal clip. Brief Wave/Nod/Celebrate reactions return to Idle with a bounded reaction queue. A greeting wave runs once on entering a successfully initialized room, not continuously.

Pause when backgrounded, off the character page or motion is disabled. Resume only a healthy initialized room. Reduced-motion mode disables decorative loops and automatic reactions; provide an accessible motion control. Animation must never be necessary to understand a reply.

Missing assets, unsupported capabilities or initialization failure restore static Robert without losing Flutter navigation or conversation state. A terminal bridge failure requires coordinated room/bridge recreation for any later retry, not reuse of stale sequence state.

## Backend and chat

Flutter submits text through the existing versioned API with stable idempotency keys and resumable turn IDs. The backend owns input safety/routing, reviewed retrieval, inference, grounding and output validation before releasing a reply. Flutter displays released text and sends only allowlisted presentation identifiers to Unity. Unity receives no raw chat text, profile data, credentials or model-provider keys and makes no backend calls.

The current API has no approved AI-generated cue contract. This presentation increment uses local deterministic interaction cues and the existing fixed backend reply. Future provider-enabled responses require explicitly versioned and validated cues; never execute model-generated commands directly.

Network loss preserves local character presentation but never produces an offline AI answer. Preserve retry behavior and honest unavailable states. Consent, progress, rewards and inventory remain server-authoritative.

## Exclusions

No real inference provider, religious publication, child identity/consent, voice, iOS host, browser 3D, production persistence or analytics is added in this increment. Existing roadmap governance gates remain mandatory.

## Acceptance evidence

1. Validate model, rig, clip names, face binding and asset integrity without overwriting user assets.
2. Compile/test Unity and the Android host, demonstrating actual 3D runtime loading rather than motion applied to a static image.
3. On Android, verify idle/blink, one-shot return, background/navigation pause and reduced motion.
4. Exercise timeout, missing assets, unsupported capability and process recreation; static fallback preserves usable chat/navigation.
5. Keep API/bridge tests passing and verify Unity has no backend/provider calls or sensitive logging.
6. Test TalkBack, keyboard/insets, large text, orientation and back navigation. Address the previously observed missing orientation-button accessibility nodes in the touched UI.
7. Measure startup, memory, frame time and package size on the selected device. Do not claim a low-end-device performance pass before minimum devices and budgets are explicitly approved.

## Next review

Review this design before creating the implementation plan. The plan will separate Flutter/native host, Unity presentation and integration verification into subagent tasks. Check Unity Editor/toolchain availability, device access and native composition feasibility before promising a runnable native result.

## Implementation status

First recorded 2026-09-21, updated 2026-09-22. This records what exists, not
what is approved. `comp-mobile/CHANGELOG.md` has the increment-by-increment log.

### Implemented and verified in this environment

- The character-first shell in the existing ivory/teal/orange palette: a
  character page, a bottom composer and compact navigation, with the header,
  the balance, the parent entry and honest connection state on the other three
  pages. Balances render only from server state.
- The stage surrenders its height before readability does, and disappears
  entirely below roughly 260 logical pixels of page height.
- The character page reduced to the character, its last reply and the composer.
  With no reply the page is only Robert. Earlier answers are not kept; the
  orientation prompt moved to Learn, the service connection to Quests, Style and
  the parent area, and the room's status and retry to the parent area. The app
  header and the adult-operator notice are off this page and on the other three,
  so the balance, the parent entry and the notice stay one tap away. Clearing
  stays beside the reply because it deletes the server conversation.
- The character appears on the character page only. The other pages are backed
  by the room's own backdrop image without him, so they read as the same place
  and look identical with or without a Unity room.
- A customization tab: the service publishes a four-look catalogue with prices,
  spends stars from its own append-only ledger, and records what is owned and
  worn. Flutter offers a look only against the balance the service reported, and
  sends `avatar.set_cosmetics` from the service's own record of what is worn,
  never from the tap — so earning alone tells the room nothing, and a relaunch
  or a room rebuild restores the worn look without one.
- Presentation policy in `AvatarBridge`: pause when backgrounded, off the
  character page or motion is disabled; a greeting wave once per initialized
  room; a bounded, spaced reaction queue that is discarded rather than replayed
  when the room pauses.
- Reduced motion from the platform setting, with an accessible override in the
  parent area.
- `AvatarRoom`, the coordinator that disposes the Flutter bridge and the native
  room together before a bounded retry, so no fresh session inherits a stale
  sequence watermark.
- Lessons, challenges and inventory read from the versioned API and parsed
  strictly; content that is not `kind: "orientation"` is rejected by the client.
- The previously observed missing orientation-button accessibility nodes, fixed
  and confirmed both in widget semantics assertions and in the browser
  accessibility tree.
- `BridgeCommand` and `BridgeSession`, the Unity receiver's decision core,
  written dependency-free and exercised by 36 compiled checks.

### The Android host

An Android SDK and the JetBrains Runtime from Android Studio are installed, so
`android/app/src/main/kotlin/.../UnityRoomPlugin.kt`, `UnityRuntime.kt` and
`MainActivity.kt` **compile** and land in both a debug and a release APK.
Compiling confirmed the `FlutterActivityLaunchConfigs.BackgroundMode` import and
the override signatures, and the release build exposed a defect that a debug
build hides: R8 renamed `CompanionEventBridge`, which the Unity receiver reaches
by name over JNI, so the Unity-to-Flutter event path would have failed in
release only. `android/app/proguard-rules.pro` now keeps it, verified by
inspecting the release DEX.

This Kotlin now runs: on an Android 16 x86_64 emulator the app installs,
launches, creates the player in-process and composites Unity's surface full
screen beneath a transparent Flutter view. No physical device has been used.

`UnityRuntime` reaches the player reflectively, so the app builds and runs
without an exported `unityLibrary` module; in that state the bridge reports no
room and Flutter keeps its static avatar.

### Unity: compiled and partly executed

Unity 6000.3.24f1 with Android Build Support is now installed, so the whole kit
compiles with no errors or warnings, and `unity/validation/Test-EditMode.ps1`
runs 12 EditMode tests over `CompanionBridgeReceiver` in a real Editor.

Running them found a defect that compiling could not: all of the receiver's
wiring happened in `Awake`, but Unity does not order `Awake` between components
on one GameObject. `AndroidUnityEventTransport.Awake` calls `BindTransport`, so
whenever the transport won that race the room would have refused the binding and
silently never announced readiness. The receiver now resolves its session on
first need instead.

`unity/` is now a real Unity project with a room builder
(`CompanionRoomBuilder`) that generates the face material, the Animator, the
model prefab, the skin definition and the room scene from the staged canonical
assets, and exports a Gradle `unityLibrary` module.

Two things had to change to get there. The glTF importer
`com.unity.cloud.gltfast` 6.13.0 cannot import the canonical `Robert.glb` at
all — its skinned-mesh path throws a Jobs safety violation before producing an
asset, and our rig is skinned. Rather than disable Unity's job safety checks to
mask a real race, the model is exported to FBX from the canonical `Robert.blend`
with Blender and imported by Unity natively, which removes the third-party
importer entirely. And `RobertAvatarPresentation` held a serialized `Animator`
reference that could never resolve, because the Animator belongs to a prefab the
skin controller instantiates at runtime.

`android/settings.gradle.kts` includes `:unityLibrary` only when an export
exists, feeding it the `unity.*` properties from the export's own
`gradle.properties` so no absolute SDK or NDK path is committed.

### Acceptance evidence, item by item

1. Asset validation — **not run.** `assets/characters/robert/tools/verify_robert.py`
   exists and was not executed; no user asset was overwritten.
2. Unity and Android host compile and 3D runtime loading — **partial.** Both
   compile, the receiver is exercised by EditMode tests, and on an x86_64
   emulator the runtime loads, the room renders — the Blender-sourced model, its
   rig, the neutral face and a desert backdrop, composited beneath the Flutter
   page — and the bridge handshake completes, with an earned look delivered over
   it recolouring the character. No motion is applied to the static image in
   place of the real runtime.
3. Device idle/blink, one-shot return, pause and reduced motion — **partial.**
   The greeting wave runs on the device; blink timing, one-shot return, pause
   and reduced motion have not been measured there. The Flutter-side policy that
   drives them is tested.
4. Timeout, missing assets, unsupported capability and process recreation —
   **covered in Flutter tests**; static fallback preserves chat and navigation.
   The native half of recreation is unverified.
5. API and bridge tests passing, no backend or provider calls in Unity, no
   sensitive logging — **passing**; the Unity assembly holds no networking,
   credentials or payload logging.
6. TalkBack, keyboard insets, large text, orientation, back navigation —
   **partial.** Large text and a 320px viewport are tested, and the orientation
   buttons are now in the accessibility tree. TalkBack, real keyboard insets and
   rotation need a device.
7. Startup, memory, frame time and package size — **partial.** The release APK
   is 49.3 MB without a Unity export; the debug APK with the x86_64 export is
   125 MB, which is a debug, single-ABI number and not a shipping size. Startup,
   memory and frame time still need a physical device, and no budgets have been
   approved to measure against. No low-end-device performance claim is made.

8. Cosmetics — **implemented, tested and seen on a device.** The catalogue,
   pricing, ledger spend, ownership and equipment are server-authoritative and
   covered by server and Flutter tests, including that the room is told only
   after the service confirms. On the emulator the whole loop runs: complete the
   orientation, earn Sunset Copper for five stars, wear it, and the character
   recolours. A look is a colourway until modelled garments are authored.
