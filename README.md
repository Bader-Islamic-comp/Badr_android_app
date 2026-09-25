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
| `assets/` | Runtime assets only — the static preview, the shared room backdrop and the Robert character package |
| `design/` | `ui-reference.png` layout reference (`ui.make`, its 6 MB Figma source, is untracked), plus from the emulator `room-on-device.png`, `customization-tab.png`, `thinking-bubble.png`, `grounded-answer.png`, `redirect-reply.png`, and the casual-chat set `chat-reply.png`, `chat-invitation.png`, `chat-feeling.png` and `faith-abstain.png`, and the outfit set `style-outfits.png`, `outfit-thobe.png` and `outfit-cowboy.png` |
| `unity/` | The Unity character-room project, its room builder and its test scripts |
| `archive/` | Untracked: superseded character revisions and the packaged distributable |
| `contracts/` | Versioned API and bridge schemas shared with `comp-server` |
| `doc/`, `docs/` | Roadmap, development boundary, and the character-page design |
| `CHANGELOG.md` | What each development increment changed, and what it verified |

## Character-first main page

The layout started from [`design/ui-reference.png`](design/ui-reference.png) —
character-first hierarchy, a reply surface, a bottom composer and compact
navigation — keeping the ivory, teal and orange palette rather than the
reference's dark violet, and not copying its example balance, example content or
implied microphone. It has since been cut back further than the reference: the
character page now carries no header and no greeting card, only the character,
the last reply and the composer.

Four destinations: **Talk** (the character and the composer), **Learn**
(orientation), **Quests** (challenges and the server-owned balance) and
**Style** (the customization tab). The star chip renders nothing at all until
the service reports a balance. Lesson, challenge and inventory content comes
from the service and is parsed strictly: anything that is not
`kind: "orientation"`, and any look without a price the app can make sense of,
is rejected rather than displayed, so unreviewed content cannot reach the screen
by loosening a client check.

**Talk carries the character, the composer and nothing else.** The last answer
sits in a single bubble just above the composer; with no answer yet the page is
just Robert. The bubble says where an answer came from; casual chat has no
label, because it is just Robert talking. While Robert is thinking, it says
that instead (see [Grounded answers](#grounded-answers)).
Earlier answers are not kept. Everything else moved to where it
belongs — the orientation prompt to Learn, the service connection to Quests,
Style and the parent area, and the room's own state and its retry to the parent
area, because how the renderer is doing is developer state and does not belong
over a character's face. Clearing stays beside the reply, because it deletes the
server conversation as well as the answer, and it remains reachable whenever a
conversation exists even if no answer is showing.

The app header and the adult-operator notice are also off this one page, and on
for the other three, so the balance, the parent entry and the notice are always
one tap away rather than gone. The notice stays until the release gates in
[`doc/development-boundary.md`](doc/development-boundary.md) pass; what changed
is where it appears, not whether it does.

**Robert exists only on Talk.** The other pages show the same desert from
`assets/room/backdrop_desert.png` — the very image the Unity room renders,
written by the same generator — veiled so a headline stays readable over it. So
they read as the same place with the character absent, rather than as a live
scene with text on top of him, and they look the same whether or not a Unity
room is running.

Below roughly 260 logical pixels of page height the character room yields its
space entirely — readable text and a reachable composer take priority over
keeping Robert visible.

The layout is **full bleed when, and only when, a room is composited behind
Flutter**. `AvatarRoom.surfaceAttached` asks the host whether a surface exists,
deliberately independent of the bridge handshake, and that alone decides whether
the page paints. With a room the scaffold and the character stage are
transparent so the live 3D shows through, and the few things that do carry text
there — a service notice, the reply bubble, the composer and the navigation —
keep their own surface, because a 3D scene cannot be relied on for contrast.
Without a room the page stays opaque ivory and the stage shows the static
preview on its card; painting transparently with nothing behind it would show an
empty window. Only the character page is ever transparent: the other three are
backed by the veiled backdrop image, so nothing there needs a scrim.

## Character boundary

`AvatarBridge` uses `companion/unity_commands` (`sendMessage`, `openRoom`,
`disposeRoom`) and `companion/unity_events` with bridge v1 envelopes.
Initialization negotiates supported capabilities and requires an acknowledgement
plus `unity.ready`. Equipment acknowledgements have a deadline.

Two of these waits are not like the others. Initialization and the surface probe
wait on the host **starting an engine**, which takes seconds, not on a room that
is already answering; both use `AvatarBridge.startupTimeout` rather than the
ordinary `timeout`. Using the 3-second bridge timeout for the handshake meant it
gave up before Unity had finished loading, on every launch — see
[`unity/README.md`](unity/README.md). A look outside
the four the room was built with is refused here without touching the room — the
room is not broken, it simply has nothing to install. Unknown
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

Validated with Flutter 3.47.5 / Dart 3.13.4: analysis is clean and 81 tests
pass. Dependency versions are recorded in `pubspec.lock`.

The SDK is **vendored, not installed**: it lives beside the repositories at
`../../comp/.tools/flutter` and is not on `PATH`, so `flutter` alone will not
resolve. Put it on `PATH` for the session first, or call it by full path.

```powershell
$env:Path = "$HOME\Desktop\comp\.tools\flutter\bin;$env:Path"
```

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

`adb` is on `PATH` from `C:\Android\platform-tools`. The Android SDK and its
emulator are under `$env:LOCALAPPDATA\Android\Sdk`, and the development AVD is
named `companion`.

Run `dart format lib test`, `flutter analyze` and `flutter test` after changes.

Android builds succeed: `flutter build apk --debug` and `--release` both
produce an APK (release 49.3 MB without a Unity export; 125 MB debug with the
x86_64 export, which is a debug, single-ABI number and not a shipping size), and
the Kotlin host in `android/app/src/main/kotlin/` compiles into both. The APK
requests `INTERNET` only — no microphone, camera or location permission.

The app has been run on an **Android 16 x86_64 emulator**: the character room
renders, the bridge handshake completes, and an earned look sent over the bridge
recolours the character. **No physical device has been used**, so startup, memory, frame
time, ARM64, TalkBack, keyboard insets and rotation are all still unmeasured,
and no performance budget has been approved to measure against.

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
backend CORS configuration, which is currently disabled. A live character room
exists only in the Android wrapper, and only once
`unity/CompanionRoomBuilder.ExportAndroidBatch` has produced an export; without
one `UnityRuntime` finds no player to create and the app shows the static
avatar everywhere.

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

Connection is user initiated from the connection card on Quests, Style or the
parent area. The bootstrap must identify the synthetic development profile,
disabled voice and awaiting-review content. `features.generativeAnswers` is the
one feature the service may report as on, and it must be a real boolean. The
app records it and never turns it on, and the parent area shows whether it is
on. Completion, balance, challenge state, lessons and inventory come from the
service.

Looks are earned and worn through the service, never on the device. **Style**
shows the catalogue with its price, what is earned, what is worn and how many
more stars a locked look needs. There are two kinds: colourways of the original
model (shown as a colour dot) and six modelled outfits — Casual, Gardener, Arab
Thobe, Explorer, Cowboy and Astronaut — shown with a rendered thumbnail from
`assets/looks/` (`design/style-outfits.png`). Wearing an outfit swaps Robert's
model in the room (`design/outfit-thobe.png`, `design/outfit-cowboy.png`). Earning posts to `/v1/cosmetics/claim` and then
re-reads the balance rather than subtracting locally; wearing re-checks
ownership and writes `/v1/equipped-cosmetics`. Claim and equip keys are per
look, so a retry reuses its own key and no look is answered with another's
recorded result.

The room is then told by the **shell**, watching what the service reports as
worn — not by the tap that changed it. Earning is not wearing, so a claim alone
tells the room nothing; and because the cue follows server state rather than a
gesture, the worn look comes back by itself after a relaunch or a room rebuild,
neither of which involves a tap. Write retries reuse their
idempotency key; question retries resume a known turn.

Questions are answered on the service, never on the phone. Fixed replies, and
every reply while grounded answers are off, are already complete when the turn
is created, and are read once. A turn the service is still working on comes
back `pending`. The app then reads it again with REST every second, for at most
90 seconds per attempt. Past that, the notice says "Robert is taking longer
than usual. Try again." Trying again resumes polling the same turn rather than
asking twice. The shared SSE endpoint is not used. A completed turn is parsed
strictly against
[`comp-server/doc/rag-system.md`](../comp-server/doc/rag-system.md) §7. If it
breaks any rule, the whole reply is refused with a generic error that never
echoes the service's text. Clearing works mid-wait: it stops polling, and a
reply that lands afterwards is dropped.

Question text stays only in memory during submission and retry. It is not logged
or saved to disk. Clearing the conversation deletes the server conversation
before clearing local handles, preserving retry capability on failure. The
service itself is an ephemeral synthetic demo; there is no real profile export
or deletion.

### Grounded answers

The service can answer from a corpus release. It retrieves passages, then does
one of two things. It may return a reviewed answer word for word. Otherwise, a
self-hosted Qwen3.5-9B writes a reply from the passages, and the service
releases it only if every sentence is supported by a passage it cites. This is
development only and **off by default**. All of it runs on the service. The app
has no model, no provider and no credential, and all it learns is whether the
switch is on.

To try it:

1. Start the server with grounded answers enabled, following
   [`../comp-server/README.md`](../comp-server/README.md). The settings are
   listed in
   [`comp-server/doc/rag-system.md`](../comp-server/doc/rag-system.md) §9.
2. Connect the app as usual: the same `DEMO_API_URL` and `DEMO_API_TOKEN` as
   above, then connect from Quests, Style or the parent area. The parent area
   should then read "Grounded answers: on · development corpus". If it reads
   "Grounded answers: off", the server was started without them.
3. Ask on Talk. The composer's hint reads "Say hi or ask (test text only)".
   While the service works, the bubble says "Robert is thinking… his antennae
   are wiggling" next to a spinner, or a still robot icon under reduced motion.
   The line is the same for every kind of reply, because which kind is coming
   is not known until the service answers.

**The corpus is synthetic app help only.** It is invented help text about using
the app, covering stars, looks, quests, the parent area and taking a break. It
contains no religious teaching and has not been reviewed for children. Ask
synthetic questions about the app. Questions outside the corpus should come
back as "Robert isn’t sure" or "Let’s ask a grown-up", not as an answer. A
hello such as "Hi, how are you?" gets a short chat reply instead. The
server refuses any model host that is not on the operator's machine or private
network, so no question goes to a third-party provider.

**Casual chat, and faith from the corpus only.** The service decides this, not
the app ([`comp-server/doc/conversation-policy.md`](../comp-server/doc/conversation-policy.md),
Robert's character sheet
[`comp-server/doc/robert-persona.md`](../comp-server/doc/robert-persona.md), and
the boundary in
[ADR 0004](../comp-server/doc/adr-0004-casual-conversation.md)). A faith
question is answered only from the corpus, never from the model's memory or by
casual chat. The development corpus has no faith lessons, so today every faith
question comes back as "Robert isn’t sure", saying warmly that he only answers
faith questions from lessons his teachers have checked. Small talk gets a short,
checked reply in Robert's voice as answer type `chat`, and now and then a
reviewed line inviting the child to explore a lesson in the Learn tab; a sad
feeling gets a kind reply that points to a grown-up they trust, and no
invitation. On the emulator, against the real model:

| Screenshot | Message | Reply |
|---|---|---|
| [`design/thinking-bubble.png`](design/thinking-bubble.png) | "Hi, how are you?" | the thinking line while the service works |
| [`design/chat-reply.png`](design/chat-reply.png) | "Hi, how are you?" | `chat`, no label, in 2.1 s |
| [`design/chat-invitation.png`](design/chat-invitation.png) | "Can you tell me a joke?" | `chat`, with a reviewed invitation to the Learn tab |
| [`design/chat-feeling.png`](design/chat-feeling.png) | "I am sad today" | `chat`, pointing to a grown-up they trust, no invitation |
| [`design/faith-abstain.png`](design/faith-abstain.png) | "Who is Prophet Muhammad?" | `abstained` with the faith abstention, in 1 ms with no model call |

All of this wording awaits safeguarding and scholarly review, and the Learn tab
does not have the faith lessons the invitations point to yet.

Each reply is labelled by the answer type the service sends. The app never
infers the label from the text:

| Answer type | Label | Colour |
|---|---|---|
| `grounded`, `reviewed_answer` | "From Robert’s library", with a Sources list | teal |
| `chat` | No label: just Robert's words, with the × beside them | — |
| `abstained` | "Robert isn’t sure" | muted |
| `redirected` | "Let’s ask a grown-up" | orange |
| `safety` | "You can talk to a grown-up you trust" | ink |
| `unavailable` (grounded answers off) | "Service response" | teal |

Only library replies carry sources. Each one appears under the text as a title
with its reference beneath, in plain text, because there is nothing on the
phone to open. A reply of any other type that carries sources is refused,
including chat. Chat has no label because a label says where a reply came
from, and chat claims to come from nowhere; left bare, it cannot be mistaken
for a library reply, which is always named and sourced. The labels stay calm,
because not being sure, or being pointed to a grown-up, is not a mistake the
child made. The safety label uses the steady ink colour
rather than an alert colour. A long reply opens at its first sentence, and the
sources are further down.

## Verification coverage and remaining work

The 86-test suite covers no-network default mode, server-owned rewards,
ownership rejection, idempotent completion headers, resuming known question
turns, the bootstrap's grounded-answers flag, polling a pending turn to its
deadline and resuming it, every turn-contract rule, clearing and disposal
mid-wait, the reply labels and sources, unlabelled chat replies and the parent
area's account of them, the thinking line and composer hint, sanitized failures,
missing native host, malformed bridge events, cancellation of native deadlines
on disposal, asynchronous send/delete disposal, offline orientation,
320px/large-text layout, the character-page visibility and foreground policy,
reduced motion, the bounded reaction queue, coordinated room recreation and its
bound, and activatable button semantics for the orientation controls.

Five of those tests cover the customization tab specifically: that a look is
earned from the service rather than granted on the device, that the balance is
re-read rather than adjusted locally, that a refused claim spends nothing and
wears nothing, that a claim whose response names a different look is a failure
rather than an unlock, and — end to end through a fake Unity host — that
`avatar.set_cosmetics` reaches the room only after the equipment write is
confirmed, and never on the claim alone.

Grounded replies have also been checked across both repositories. The real
`CompanionController` and `DemoApi` ran against the real server with grounded
answers on, a release built with the offline hashing embedder, and a local
stand-in for the Qwen server, with no model downloaded. The app parsed all five
answer types that such a server returns, and clearing worked. The same client
code then ran against the live API with the real Qwen3.5-9B generating, and
parsed grounded replies with sources in about 2 s. On the emulator, with Qwen
generating, the thinking bubble, a grounded reply with its sources and a ruling
redirect all rendered as designed (`design/thinking-bubble.png`,
`design/grounded-answer.png`, `design/redirect-reply.png`); the emulator and the
loaded model only fit in memory together once Steam and Chrome were closed.
Casual chat was then checked the same way: a hello, a joke with an invitation, a
sad feeling and a faith question (`design/chat-reply.png`,
`design/chat-invitation.png`, `design/chat-feeling.png`,
`design/faith-abstain.png`; `design/thinking-bubble.png` now shows the new
thinking line). No physical device has run it yet. At 320×380 with text
at 2×, the composer's hint still wraps. The shorter hint takes three lines
rather than four and leaves the reply about 107 px rather than 56 (measured in
the widget tester with Roboto loaded).

A browser check of the built web preview previously found the orientation
buttons missing from the accessibility tree. They are now exposed as buttons
with labels, hints and tap actions, asserted in the widget tests and confirmed
again in the browser accessibility tree.

The Unity kit is compiled and exercised separately in a real Editor: 36
engine-free checks over the bridge decision core plus 12 EditMode tests over the
receiver. See [`unity/README.md`](unity/README.md) for what the room builder,
the desert backdrop and the emulator run do and do not settle.

Remaining gates include native host integration and device validation, real
guardian identity and consent, secure token storage, persisted server state,
published reviewed content, approved safeguarding, end-to-end deletion and
export, integration and device accessibility testing, and bridge/device
performance validation. Widget layout checks are not a complete device
accessibility audit. No religious or child-safety approval is implied by these
developer tests.
