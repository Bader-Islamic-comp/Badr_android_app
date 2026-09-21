# Flutter development preview

## Android-first product direction

The intended product is a phone app, with Android first. Flutter owns
navigation, chat, networking and fallback; Unity owns Robert's 3D presentation.
All AI inference and agent orchestration run on the backend, never on the phone.
The web target remains a developer preview only.

This is a portable Flutter application source package, intended for adult
operators using synthetic data only. Warm ivory, teal and orange echo the
supplied Robert character. No child accounts, consent collection, audio,
providers, analytics, religious curriculum or production security are
implemented.

## Repository layout

| Path | Contents |
|---|---|
| `lib/` | Application source: `bridge/`, `data/`, `domain/`, `ui/` |
| `assets/` | Runtime assets only — the static preview and the Robert character package |
| `design/` | `ui-reference.png` layout reference (`ui.make`, its 6 MB Figma source, is untracked) |
| `unity/` | The Unity character-room project, its room builder and its test scripts |
| `archive/` | Untracked: superseded character revisions and the packaged distributable |
| `contracts/` | Versioned API and bridge schemas shared with `comp-server` |
| `doc/`, `docs/` | Roadmap, development boundary, and the character-page design |

## Character-first main page

The main page follows [`design/ui-reference.png`](design/ui-reference.png) —
compact header, central character room, greeting or validated reply surface,
bottom composer, compact navigation — while keeping the ivory, teal and orange
palette rather than the reference's dark violet. Its example balance, example
content and implied microphone are deliberately not copied.

Four destinations: **Talk** (the character page and composer), **Learn**
(orientation), **Quests** (challenges and the server-owned balance) and
**Style** (cosmetics). The star chip renders nothing at all until the service
reports a balance. Lesson, challenge and inventory content now comes from the
service and is parsed strictly: anything that is not `kind: "orientation"` is
rejected rather than displayed, so unreviewed content cannot reach the screen by
loosening a client check.

Below roughly 240 logical pixels of page height the character room yields its
space entirely — readable text and a reachable composer take priority over
keeping Robert visible.

## Character boundary

`AvatarBridge` uses `companion/unity_commands` (`sendMessage`, `openRoom`,
`disposeRoom`) and `companion/unity_events` with bridge v1 envelopes.
Initialization negotiates supported capabilities and requires an acknowledgement
plus `unity.ready`. Equipment acknowledgements have a deadline. Unknown
capability cues are not sent; malformed events are ignored; missing hosts, asset
failures and failed commands fall back to the static avatar.

Presentation policy lives in the bridge:

- The room animates only while initialized, on the character page, in the
  foreground and allowed to move. Any of those going false sends `app.pause`.
- A greeting wave runs once per successfully initialized room, not on every
  return to the page.
- Reactions (`Wave`, `Nod`, `Celebrate`) go through a bounded queue with
  spacing, so a burst of taps cannot become an animation backlog. Pausing
  discards the backlog rather than replaying it later. The room returns to Idle
  on its own; bridge v1 has no `animation.completed` and was not extended to add
  one.
- Reduced motion follows the platform setting and can be overridden from the
  parent area. Animation is never required to understand a reply.

Fallback is terminal for a bridge instance: a failed transport does not reset
the native receiver's sequence or initialization state. `AvatarRoom` is the
coordinator that makes a retry safe — it disposes the Flutter bridge, calls
`disposeRoom` so the native room and receiver are recreated with it, starts a
fresh session and re-applies page and motion state. Retries are bounded so an
unrecoverable host is not retried in a loop. Ordinary offline learning remains
available throughout.

The source does **not** embed or claim a live Unity renderer. The character
stage renders the supplied static preview and applies no motion to it: animating
a PNG would misrepresent an unimplemented 3D runtime. See
[`unity/README.md`](unity/README.md) for what is and is not verified there, and
[the integration design](docs/superpowers/specs/2026-09-21-android-character-design.md).
Flutter never sends credentials, child identifiers, questions or audio into
Unity.

## Prepare and run

Validated with Flutter 3.47.5 / Dart 3.13.4: analysis is clean and 28 tests
pass. Dependency versions are recorded in `pubspec.lock`.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Run `dart format lib test`, `flutter analyze` and `flutter test` after changes.

Android builds succeed: `flutter build apk --debug` and `--release` both
produce an APK (release 49.3 MB), and the Kotlin host in
`android/app/src/main/kotlin/` compiles into both. The APK requests `INTERNET`
only — no microphone, camera or location permission. **Nothing has been run on a
device or emulator**: none is available here, so startup, memory, frame time,
TalkBack, keyboard insets and rotation are all still unmeasured, and no
performance budget has been approved to measure against.

`android/settings.gradle.kts` includes the exported Unity room as
`:unityLibrary` **only when `unity/export/unityLibrary` exists**, so the app
still builds without an export and Flutter keeps its static avatar. The module
reads `unityStreamingAssets` and `unity.*` Gradle properties that live in the
export's own `gradle.properties`; settings reads them from there rather than
committing absolute SDK and NDK paths. An export forces `minSdk 25` and, for the
current x86_64-only export, restricts the app's ABIs to match so the APK cannot
ship a Flutter ABI with no Unity runtime beside it.

Release builds shrink with R8. `android/app/proguard-rules.pro` keeps
`CompanionEventBridge`, which the Unity receiver reaches by name over JNI;
without that rule R8 renames it and the Unity-to-Flutter event path fails in
release builds only. Re-check that rule if the transport's class or method names
change.

iOS platform builds require macOS and Xcode and have not been run. The included
web target provides an offline development preview
(`flutter build web --no-web-resources-cdn`); web API testing requires explicit
backend CORS configuration, which is currently disabled. A live character room is
still unavailable in every wrapper: no `unityLibrary` export has been produced,
so `UnityRuntime` finds no player to create and the app shows the static
avatar. Producing one needs a glTF importer, a room scene and a Unity Android
export, none of which exist yet.

The default run performs no backend requests. It supports a local orientation,
labels local completion accurately and never invents a reward balance. The parent
area is explicitly a prototype, not a secure gate or a consent flow.

## Optional development service

Start the repository's API in its explicit development mode with an
operator-supplied demo token, then configure matching values at build/run time:

```powershell
flutter run --dart-define=DEMO_API_URL=http://10.0.2.2:8000 --dart-define=DEMO_API_TOKEN=your-local-demo-token
```

Use `127.0.0.1` for desktop; Android emulator uses `10.0.2.2`. The Android debug
configuration allows HTTP only for those loopback/development hosts and
`localhost`; it does not change release transport settings. A physical device
needs a reachable HTTPS development host. Never commit a real token. Dart defines
are embedded in the binary and are **not** appropriate for production secrets or
authentication.

Connection is user initiated from any page's connection card. The bootstrap must
identify the synthetic development profile, disabled voice/generation and
awaiting-review content. Completion, balance, challenge state, lessons and
inventory come from the service. Equipment requires an ownership check and a
confirmed server write before the sanitized bridge cue. Write retries reuse their
idempotency key; question retries resume a known turn. The UI fetches a complete
validated turn with REST; it does not expose token streaming. The shared SSE
endpoint is reserved for later resume/stream UI work.

Question text stays only in memory during submission and retry. It is not logged
or saved to disk. Clearing the conversation deletes the server conversation
before clearing local handles, preserving retry capability on failure. The
service itself is an ephemeral synthetic demo; there is no real profile export
or deletion.

## Verification coverage and remaining work

The 28-test suite covers no-network default mode, server-owned rewards, ownership
rejection, idempotent completion headers, resuming known question turns,
sanitized failures, missing native host, malformed bridge events, cancellation of
native deadlines on disposal, asynchronous send/delete disposal, offline
orientation, 320px/large-text layout, the character-page visibility and
foreground policy, reduced motion, the bounded reaction queue, coordinated room
recreation and its bound, and activatable button semantics for the orientation
controls.

A browser check of the built web preview previously found the orientation
buttons missing from the accessibility tree. They are now exposed as buttons
with labels, hints and tap actions, asserted in the widget tests and confirmed
again in the browser accessibility tree.

The Unity kit is compiled and exercised separately in a real Editor: 34
engine-free checks over the bridge decision core plus 11 EditMode tests over the
receiver. See [`unity/README.md`](unity/README.md). No scene, imported model or
Android export exists yet, so the character room has never rendered and the
Unity-as-a-Library composition is still unproven.

Remaining gates include native host integration and device validation, real
guardian identity and consent, secure token storage, persisted server state,
published reviewed content, approved safeguarding, end-to-end deletion and
export, integration and device accessibility testing, and bridge/device
performance validation. Widget layout checks are not a complete device
accessibility audit. No religious or child-safety approval is implied by these
developer tests.
