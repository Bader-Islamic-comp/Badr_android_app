# Changelog

Development increments, newest first. Nothing here is a release: the gates in
[`doc/development-boundary.md`](doc/development-boundary.md) are still open.

Paired server changes are in `comp-server/CHANGELOG.md`; the shared files under
`contracts/` must stay byte-identical between the two repositories.

## Unreleased — 2026-09-27 (animations)

Commits `7705441` (the package), `8576283` (the Unity room) and `91ed49d` (the app) on
branch `feature/rag-system-and-data-pipeline`. The product owner's request of
2026-09-27, verbatim:

> "I have added a bunch of new animations and updated some of the assets in
> the android app, can you update the codebase and implement these changes?
> use subagents."

The owner's updated character package replaces the old one. From it Robert
gets a resting loop that keeps moving, a Talk loop and eight new one-shot
faces. The Unity room plays them, and the app decides when: Robert talks while
a reply appears and then reacts to its answer type, and he reacts to taps, to
looks and to finishing the orientation. Only allowlisted cue names cross the
bridge; no question or reply text does. The bridge stays v1 with the same
capabilities; only its animation and emotion allowlists grew. Three existing
room bugs were fixed on the way, one of which froze Robert after startup. The
paired server entry is in `comp-server/CHANGELOG.md` (the schema copy only).

### Package (`assets/robert/`)

- The owner supplied the updated package at `assets/robert/`: `README.md`,
  `ANIMATIONS.md`, `SKINS.md`, `character.json`, the seven skins
  (`skins/<folder>/` with `skin.json`, `model/Robert.glb` and
  `source/Robert.blend`), the shared faces, `shared/animations.json`,
  `shared/rig_contract.json`, `tools/`, the `unity/` helpers, `validation/` and
  `previews/`. It supersedes `assets/characters/robert/`, which is removed.
  `tools/render_skin_preview.py`, written for the outfits and not part of the
  supplied package, is carried over unchanged.
- Only `assets/robert/Robert.png`, the static-avatar preview already in that
  folder, ships in the app; `pubspec.yaml` is unchanged and the package itself
  is not bundled.
- Every skin's GLB and Blender source carries six body clips, 30 fps with no
  root motion (`ANIMATIONS.md`, `shared/animations.json`):

  | Body clip | Length | Playback |
  |---|---:|---|
  | `Standing` | 6.0 s | Loop, new; the resting state |
  | `Idle` | 6.0 s | Loop; the same motion, kept as an alias |
  | `Wave` | 3.2 s | One-shot, re-timed |
  | `Talk` | 4.8 s | Loop, new |
  | `Nod` | 1.6 s | One-shot |
  | `Celebrate` | 2.4 s | One-shot |

- Faces (`shared/faces/default/`): the `idle` loop blinks now and then, and the
  `talk` loop is now a 4.8 s mouth cycle (it was 0.7 s). Eight new one-shot
  expressions, `joy`, `giggle`, `wink`, `curious`, `wow`, `sleepy`, `bashful`
  and `starry`, use the new `cute_*.png` frames.
- Current references to the old path are repointed: `.gitignore`,
  `assets/README.md`, `unity/README.md`, `unity/validation/Test-EditMode.ps1`,
  `lib/theme.dart` and the Android design spec's acceptance evidence. Older
  changelog entries, and the spec's record of what was supplied on
  2026-09-21, keep the path they had.
- The Style tab's six outfit thumbnails in `assets/looks/` are regenerated from
  the new `previews/<folder>.png`, still 256 px.

### Unity room

- All seven FBX files are re-exported with six clips each, and the faces are
  staged again from the package into `Assets/Companion/Character/Robert/Faces/`,
  with the nine new `cute_*.png` frames.
- `CompanionRoomBuilder`:
  - requires the six clips on every model, outfits included, and refuses to
    build if the bridge's animation allowlist differs from them or the face
    manifest lacks a clip a cue needs;
  - sets Loop Time on for Standing, Idle and Talk and off for Wave, Nod and
    Celebrate, and checks that it took;
  - keeps keyframe reduction but holds the rotation error to 0.05° (the default
    0.5° had flattened Standing's sway);
  - makes Standing the Animator's default state, and returns each one-shot to
    it with a 0.2 s fixed transition at its end;
  - pins every face frame to Default, sRGB, bilinear and Clamp;
  - writes each face clip's length from the manifest into the presentation's
    `faceCues`.
- **Three existing bugs fixed:**
  - Every clip imported with Loop Time off, so the old `Idle` played once and
    froze, after startup and after every one-shot.
  - The Animator states were bound to Unity's editor-only `__preview__` copies
    of the clips rather than the configured ones.
  - Face PNGs imported with Repeat wrap, which can bleed the opposite border
    into the face.
- New `AvatarPerformance.cs` holds the body and face rules with no Unity
  types, and `RobertAvatarPresentation.cs` is rewritten to carry them out on
  whichever model is installed:
  - `avatar.play` crossfades the body over 0.2 s and starts its paired face:
    Standing and Idle → `idle`, Talk → `talk`, Wave and Celebrate → `joy`,
    Nod → `idle`. Re-sending the loop that is already playing restarts nothing.
  - `avatar.set_emotion` plays the face once (`neutral` shows the neutral
    face), and blinking resumes once the body is resting.
  - `app.pause` freezes body and face; `app.resume` crossfades to Standing and
    restarts blinking. A skin swap re-applies the current state: resting, Talk,
    or frozen if paused.
- The allowlists in `BridgeCommand` and in
  `contracts/avatar-bridge-v1.schema.json` (byte-identical with comp-server),
  matched exactly and case-sensitively:
  - animations: `Standing`, `Idle`, `Wave`, `Talk`, `Nod`, `Celebrate`
  - emotions: `neutral`, `happy`, `surprised`, `joy`, `giggle`, `wink`,
    `curious`, `wow`, `sleepy`, `bashful`, `starry`

  The bridge stays v1 and the negotiated capabilities are unchanged.
- `unity/README.md` documents the clips, the cue rules and the import fixes
  (*Why FBX and not the GLB*, *Animation and face cues*).

### App

- `lib/ui/robert_cues.dart` (new) picks every cue from something the app
  already knows. It sees a reply only as its answer type and its length in
  runes, so no question or reply text reaches Unity.
- **Talking.** A reply released on Talk starts the `Talk` loop for 55 ms per
  character, kept between 1.5 s and 7 s, then `Standing`. This replaces the
  `Nod` that used to follow every released reply. The talk stops at once on
  clear, a new question, leaving Talk, turning motion off or backgrounding, and
  the bridge sends `Standing` before `app.pause`, so a paused room never
  resumes mid-talk.
- **After talking**, by answer type: `grounded` and `reviewed_answer` get a
  `Nod`, and `abstained` the `curious` face. `chat`, `safety`, `redirected` and
  `unavailable` get no face. An occasional `joy` face after chat was planned
  and removed: the service's reply to a sad feeling is also `chat`, and the app
  must not read the text to tell them apart. A non-text tone signal from the
  service would be needed first.
- **Tapping Robert** cycles `Wave`, the `giggle` face and the `wink` face,
  through the bounded queue (at most three, 1.2 s apart). Taps and faces are
  declined while he talks. The tap hint now reads "Robert waves, giggles or
  winks".
- **Looks and the orientation.** Earning a look gives the `starry` face,
  wearing one a `Celebrate`, and finishing the orientation a `Celebrate`, then
  `starry` 1.2 s later.
- **Bug fixed:** the room is paused on every page but Talk, so those
  celebrations used to be declined silently. They are now held until Robert is
  next shown on Talk (or, if he is talking, until the talk ends). Only the
  latest is kept, and backgrounding forgets it.
- **Reduced motion** sends nothing: no talk, no reaction and no face, because
  every face is itself animated.
- `AvatarBridge` gains `animations` and `emotions` allowlists equal to the
  schema's, `startTalking`, `stopTalking` and `talking`, and `express`, which
  queues a face in the same bounded queue as `react`. `setEmotion` is removed.
  `AvatarRoom` forwards the new calls.
- No trigger yet: `sleepy`, `wow`, `bashful`, and the older `happy` and
  `surprised`.
- `README.md` gains *Robert's talk and reactions*.

### Verification

- Flutter: 88 → **127 tests**, including a parity test that the app's
  animation and emotion allowlists match the bridge schema.
- Unity: bridge core checks 38 → **93** (the allowlists, exact case, schema
  parity, face pairing and which clips loop). EditMode 12 → **41**: 22 new
  tests of the presentation rules in `AvatarPerformance` and 7 of the
  generated assets. The room builds (`ROOM_OK`) and the x86_64 Android export
  succeeds (`EXPORT_OK`).
- Server: the schema copy is identical in both repositories, and `pytest` is
  539 passed.
- On the Android 16 x86_64 emulator, against the development harness:
  - Standing moves at rest: the mean pixel change between frames 0.8 s apart
    was 1.9–4.7.
  - The greeting Wave plays (`design/robert-greeting-wave.png`).
  - Taps show the giggle and wink faces, the right way up
    (`design/face-giggle.png`, `design/face-wink.png`).
  - Talk shows the mouth cycle and arm gestures while a reply appears
    (`design/robert-talking.png`, an `unavailable` reply).
  - Earning Casual on Style, then returning to Talk, plays the starry face
    after about 0.5 s (`design/face-starry.png`).
- Docs: `README.md`, `unity/README.md`, `assets/README.md`, the design spec's
  asset path and this entry.

### Known gaps

- Not seen on the emulator yet: the `curious` face after an abstention, the
  `Nod` after a grounded answer (the harness had grounded answers off),
  reduced motion, a skin swap during Talk, and pause and resume on a device.
  `Celebrate` and the faces with no trigger were not looked at either; they
  rest on the EditMode rules and asset checks.
- The mouth cycle is decorative, not lip-sync, and talk time is estimated from
  the reply's length.
- No physical device, ARM64 export, frame-time or memory measurement. Each
  re-exported FBX is about 0.3 MB larger, and the effect on the room's load
  time is unmeasured.

## Unreleased — 2026-09-25 (outfits)

Commit `b12fa70` ("Add six modelled outfits Robert can earn and wear") on
branch `feature/rag-system-and-data-pipeline`. Six modelled outfits for Robert, from the skins added to the character
package: **Casual, Cowboy, Astronaut, Arab Thobe, Explorer and Gardener**. They
join the three colourways in one catalogue, are earned with learning stars like
any look, and are worn in the Unity room by swapping in the outfit's own model.
The paired server entry is in `comp-server/CHANGELOG.md`.

### Character package (`assets/characters/robert/`)

- The six skins (`skins/<folder>/` with `skin.json`, `model/Robert.glb` and
  `source/Robert.blend`) are committed as supplied and registered in
  `character.json`. Each has a reshaped `Robert_Body`, a separate
  `Robert_Outfit` garment mesh and the shared `FaceScreen`; all six carry the
  default 24-bone rig exactly and the same Idle, Wave, Nod and Celebrate clips
  (checked in background Blender before anything was built).
- `previews/<folder>.png`, which each `skin.json` already referenced, are now
  rendered: `tools/render_skin_preview.py` renders a skin from its own scene
  camera and lights with the same Cycles settings as `build_robert.py`, and
  writes a 256 px thumbnail for the app.

(Superseded 2026-09-27: the package now lives at `assets/robert/`, every skin
carries six clips, and the thumbnails are regenerated from the package's new
previews; see the entry above.)

### Unity room

- `tools/export_robert_fbx.py` keeps `Robert_Outfit`; each outfit is exported
  to `Assets/Companion/Character/Skins/<id>/Robert.fbx`. The cosmetic id is the
  folder name with `_` written `-` (`arab_thobe` → `arab-thobe`), because
  cosmetic ids are letters, digits and hyphens everywhere they travel (the
  app's identifier check refuses `_`).
- `CompanionRoomBuilder` builds a prefab and skin definition per outfit
  (`Generated/RobertSkin_<id>.*`) with the shared face material and Animator,
  refuses an outfit whose rig differs from the default's transform for
  transform, frames the camera around every look so a hat is never cropped,
  and wires the outfits into the presentation.
- `RobertAvatarPresentation`: an outfit id swaps in that skin through
  `RobertSkinController`, and success is judged by what is actually worn
  afterwards, since the controller falls back to the default skin. A
  colourway puts the original model back first, then tints it. Outfits are
  never tinted. A swapped-in model starts neutral and idle and stays frozen
  while paused. Initialization re-resolves the Animator after re-applying the
  look, because an outfit replaces it.
- `BridgeCommand.Cosmetics` and the shared `contracts/avatar-bridge-v1.schema.json`
  (byte-identical in both repositories) list all ten looks.

### App

- `AvatarBridge.cosmetics` lists all ten looks. A new test reads the bridge
  schema and fails if the allowlist and the schema ever differ.
- **Style** shows outfits with their rendered thumbnail (`assets/looks/`,
  declared in `pubspec.yaml`) where colourways show a colour dot; the slot is
  56 px for both. The explanation card now reads "What a look changes: Colour
  looks recolour Robert in the character room. Outfits give him new clothes,
  like a hat, a vest or boots. Either way his face stays as it is, and every
  look is earned the same way: with learning stars."

### Verification

- Docs: `README.md`, `unity/README.md` (new *Outfits* section),
  `assets/characters/robert/README.md`, the Android design spec and the shared
  roadmap (§9 status note, byte-identical with comp-server) describe the ten looks.
- Flutter: 86 → **88 tests**, analysis clean. Bridge core checks: 36 → **38**
  (an outfit is a catalogue look; the folder name `arab_thobe` is not). Unity
  EditMode: **12/12**. The room builds in batch mode with all six outfits and
  the x86_64 Android export succeeds.
- On the Android 16 emulator, against a development harness seeded with 200
  learning stars (only the orientation lesson grants stars in the demo): the
  Style tab lists all ten looks with thumbnails; Arab Thobe, then Cowboy, were
  earned and worn and the room swapped models each time; wearing Sunset Copper
  afterwards restored the original model in copper. See
  `design/style-outfits.png`, `design/outfit-thobe.png` and
  `design/outfit-cowboy.png`.

### Known gaps

- Only three of the six outfits (thobe, cowboy, and astronaut's thumbnail)
  were looked at on the emulator; the other outfits are verified by the
  build's rig check and the previews, not by eye in the room.
- The cowboy hat is small and sits on the head's top edge, as authored; the
  art is reproduced faithfully rather than adjusted.
- No physical device, ARM64 export, frame-time or memory measurement: six
  more models add to the room's download and load time, unmeasured.
- The demo still grants only 5 stars, so outfits cannot be earned in the
  normal demo flow without more lessons.

## Unreleased — 2026-09-25 (casual chat)

Commit `c6419b6` ("Show Robert's casual chat replies") on branch
`feature/rag-system-and-data-pipeline`. The service now gives casual messages
such as "Hi, how are you?" a short reply in Robert's own voice, and answers
faith questions only from its corpus, otherwise saying warmly that it has no
checked lesson about that. All of that is decided on the service (`comp-server`
commit `54ff6b0`): the policy is `comp-server/doc/conversation-policy.md`, the
character sheet is `comp-server/doc/robert-persona.md`, and the boundary is
ADR 0004 (`comp-server/doc/adr-0004-casual-conversation.md`). The app only
learns to show the new `chat` answer type, and its own few words get a little
of Robert's character. It is development only and off by default, the corpus
is synthetic app help, and nothing here is reviewed for children.

The product owner's request of 2026-09-25 is quoted in full in the paired
`comp-server/CHANGELOG.md` entry: faith only from the corpus, and otherwise say
so; friendly casual chat; a loving, charming character that encourages children
to learn more about their faith; and log everything.

### Parsing a reply

- **`ReplyType.chat` (`"chat"`) is accepted.** It is not a library type
  (`cited` is false), so it must carry no citations and no sources. A chat
  reply that carries any is refused whole, like every other non-library reply,
  so casual chat cannot borrow the library's authority. Every other contract
  rule applies unchanged.

### The Talk page

- **Chat has no label.** The bubble holds Robert's words, with the × beside
  them. A label says where a reply came from, and chat claims to come from
  nowhere; left bare, it cannot be mistaken for a library reply, which is
  always named and sourced. The reply is still a live region.
- **One thinking line for every reply:** "Robert is thinking… his antennae are
  wiggling", next to a spinner, or a still robot icon under reduced motion. It
  replaces "Robert is looking in his library…" and "Robert is thinking…", and
  the book icon. Which kind of reply is coming is the service's decision and is
  not known yet, and a hello is not a trip to the library. The antennae are
  Robert's own: two, orange-tipped, on the model.
- **Composer hint** when connected: "Say hi or ask (test text only)", replacing
  "Type a synthetic test question". It invites a hello as well as a question
  and still says the text is only for testing. It is also shorter: at 320×380
  with text at 2×, it wraps to three lines instead of four and leaves the reply
  about 107 px instead of 56 (measured in the widget tester with Roboto
  loaded).

### The parent area

- The "Grounded answers: on · development corpus" subtitle now reads
  "Questions are answered only from the service’s development library, with
  their sources. Casual chat, like a hello, gets a friendly reply without
  sources. The model runs on the service, never on this phone." Chat is not
  from the library, so the provenance a parent reads has to say so. The "off"
  row is unchanged.

### Contracts and shared docs

- `contracts/openapi-v1.json` was regenerated from the server and is
  byte-identical to `comp-server/contracts/openapi-v1.json`: `answerType`
  gains `chat`, and the `Turn` description says citations and sources are empty
  except for `grounded` and `reviewed_answer`.
- Recorded afterwards with this entry (documentation only), and byte-identical
  to the server's copies: `AGENTS.md` now scopes the grounding rule to answers
  to questions, says casual chat replies (ADR 0004) pass the conversation-policy
  checks and never carry generated faith content, and points to the policy, the
  character sheet and ADR 0004; `doc/product-architecture-roadmap.md` gains a
  §5.1 status note on casual chat and the faith-only rule.
- `README.md`: the `chat` row in the label table, the new thinking line and
  hint, and the new screenshots (below).

### Verification

- Flutter: 81 → **86 tests**. The new tests cover:
  - a chat reply parsing with no sources, and not counting as a library reply
  - a chat reply that carries sources being refused
  - on the page: the new hint, the thinking line with a still robot icon under
    reduced motion, and a chat reply with no label, no sources and the × still
    usable
  - the parent area saying that chat replies carry no sources
  - a chat reply at 320×380 with text at 2× staying in reach
- **On the Android emulator**, against the live API with Qwen3.5-9B
  generating, four messages behaved as intended:
  - "Hi, how are you?" → `chat` in 2.1 s, with no label
    (`design/chat-reply.png`). `design/thinking-bubble.png` is replaced: it now
    shows the new thinking line while that reply was on its way.
  - "Who is Prophet Muhammad?" → `abstained` with the faith abstention
    (service outcome `faith_abstain:weak_evidence`, 1 ms, no model call),
    labelled "Robert isn’t sure" (`design/faith-abstain.png`).
  - "Can you tell me a joke?" → `chat` with a reviewed invitation to the Learn
    tab (`design/chat-invitation.png`).
  - "I am sad today" → `chat` pointing to a grown-up they trust, with no
    invitation (`design/chat-feeling.png`).
- The service's own verification, including five runs against the real
  Qwen3.5-9B (47/47 cases each, 65/65 chat replies passing its checks, 25/25
  faith questions abstaining), is in `comp-server/CHANGELOG.md`.

Still not done: no physical device has run chat replies. The invitations point
to faith lessons in the Learn tab, which this development app does not have
yet. All of Robert's new wording, on the service and in this app, awaits
safeguarding and scholarly review.

Known issues:
- At 320×380 with text at 2×, the composer's hint still wraps (three lines),
  leaving the reply about 107 px.

## Unreleased — 2026-09-25

Branch `feature/rag-system-and-data-pipeline`. The service can now answer a
question from a corpus release. This is development only and off by default.
The Talk page shows those answers and says where they came from. Retrieval,
generation (a self-hosted Qwen3.5-9B) and verification all stay on the service.
The app gains no model, no provider and no credential; all it learns is whether
the switch is on. The paired server entry is in `comp-server/CHANGELOG.md`. The
design is `comp-server/doc/rag-system.md`, and its §7 is the contract this
client parses against.

### Connecting

- **`DemoApi.bootstrap()` now accepts a service with
  `features.generativeAnswers` on, and returns the flag.** It used to refuse
  such a service. The flag must be a real boolean: a string `"true"` or a missing flag describes a service this build
  was not made for. Every other check is as strict as before. Voice on, another
  mode, character or profile, or published content still refuses the service.
- `CompanionController.groundedAnswers` records the flag. It is false whenever
  nothing is connected. The app never turns it on, because whether a model
  answers is the service's decision.

### Waiting for a reply

- **`ask()` handles a `pending` turn.** A turn the service is still working on
  is read again with `GET /v1/turns/{id}` every second, for at most 90 seconds
  per attempt. Fixed replies, and every reply while grounded answers are off,
  are already complete when the turn is created, so they are read once with no
  waiting.
- **Past the deadline the question is paused, not lost.** The notice says
  "Robert is taking longer than usual. Try again." The question, its idempotency
  key and its turn id are all kept, so a retry resumes polling the same turn
  with no second `POST`. The service answers one question at a time and queues
  the rest, so a slow reply does not mean the question failed.
- **Clearing works mid-wait.** `clearConversation` stops the wait immediately
  rather than at the next read, then deletes the conversation. A reply that
  lands in between is dropped, not shown after the child asked for it to go. If
  the delete fails, the question is held for retry, as after any other failure.
- Disposing the controller mid-wait also stops polling, and it sends no
  notifications after dispose.
- The poll interval, the deadline, the wait and the clock are injectable, so
  tests can poll without real timers. A real delay under the widget tester's
  fake clock never finishes.

### Parsing a reply

`Reply.fromTurn` replaces the bare `answer` string. It enforces every rule of
§7 and refuses the whole payload if any rule is broken, rather than showing
part of it. This is the text a child reads and the provenance a parent relies
on. A library reply without sources, or a fixed reply with some, should never
be rendered in the hope that it is right.

- `answerType` must be one of `unavailable`, `grounded`, `reviewed_answer`,
  `abstained`, `redirected` or `safety`. (Superseded 2026-09-25: `chat` is
  also accepted, with no sources; see the entry above.)
- The library types, `grounded` and `reviewed_answer`, carry 1–4 sources whose
  ids match the citations one for one, in order. Every other type carries none,
  so no other reply can borrow the library's authority.
- Chunk ids must match `^[a-z0-9][a-z0-9-]{1,63}#[1-9][0-9]{0,3}$`, and no id
  may appear twice.
- Text is 1–1,200 characters and not blank. It is counted in runes, as the
  service counts it, so a reply at the limit that uses characters outside the
  basic plane is not refused as too long on this side.
- A leftover `[n]` marker is refused. The service strips the markers once it
  has checked them, so one that survives means the text is not the verified
  release.
- Source titles are at most 120 characters and references at most 160.
- A pending turn must have a null `answerType`, and the `turnId` must be the one
  asked for. An unknown status is refused, whether it arrives when the turn is
  created or on a later read.
- Errors are generic ("The service returned an unexpected reply.") and never
  echo what the service sent.

### The Talk page

- **Each reply is labelled by the service's answer type**, in 13 px bold
  sentence case. This replaces the old upper-case "SERVICE RESPONSE" that
  appeared on every reply.

  | Answer type | Label | Colour |
  |---|---|---|
  | `grounded`, `reviewed_answer` | "From Robert’s library" | teal |
  | `abstained` | "Robert isn’t sure" | muted |
  | `redirected` | "Let’s ask a grown-up" | orange |
  | `safety` | "You can talk to a grown-up you trust" | ink |
  | `unavailable` | "Service response" | teal |

  (Superseded 2026-09-25: `chat` was added later and has no label; see the
  entry above.)

  The wording stays calm for every type, because not being sure, or being
  pointed to a grown-up, is not a mistake the child made. The safety label uses
  the steady ink colour, not an alert colour, so it does not alarm.
- **Library replies list their sources** under the text: a "Sources" heading,
  then each source's title with its reference beneath it in muted text. They
  are plain text, not links, because there is nothing on the phone to open.
- **A thinking bubble** replaces the reply while Robert is working. It says
  "Robert is looking in his library…", or "Robert is thinking…" when grounded
  answers are off, next to a spinner, or a book icon under reduced motion.
  (Superseded 2026-09-25: one line for every reply, "Robert is thinking… his
  antennae are wiggling", with a robot icon under reduced motion; see the entry
  above.) It is a live region. The × stays usable, so a child does not have to wait out a
  slow answer to take the question back.
- **A long reply now scrolls from its beginning.** It used to open at its end.
  A reply can be 1,200 characters with four sources underneath, and a child
  should land on the first sentence, not on the sources.
- The progress bar at the top of the page is hidden on Talk while Robert is
  thinking, because the bubble already says so.

### The parent area

- A new row reports the service's switch but offers no way to change it:
  - on: "Grounded answers: on · development corpus", with the subtitle "Answers
    come only from the service’s development library and show their sources.
    The model runs on the service, never on this phone." (Superseded
    2026-09-25: the subtitle now also says that casual chat gets a friendly
    reply without sources; see the entry above.)
  - off: "Grounded answers: off", with the subtitle "No AI model answers
    questions."
- "Content awaits review" no longer says that no AI provider is enabled. The
  new row now covers that.

### Contracts

- `contracts/openapi-v1.json` was regenerated from the server and is
  byte-identical to `comp-server/contracts/openapi-v1.json`. The changes:
  - `Turn` gains `answerType` and `sources`, using a new `Source` schema.
  - `status` on `Turn` and `TurnCreated` may now be `pending`.
  - Citations and sources are capped at four, and text at 1,200 characters.
  - `Features.generativeAnswers` is no longer `const: false`.

### Verification

- Flutter: 33 → **81 tests**, analysis clean. The new tests cover:
  - the bootstrap flag and each way it is refused
  - a turn completed at creation being read once
  - polling a pending turn every interval, the deadline, and resuming the same
    turn with no second `POST`
  - each contract rule above, one test per rule, plus rune counting
  - clearing and disposing mid-wait, including a reply that lands after the
    clear
  - on the page: the thinking bubble followed by a library reply with its
    sources
  - clearing from the bubble while Robert is thinking
  - each non-library reply type's label, with no sources shown
  - a long library reply on a small screen starting at its beginning
- **Live run across both repositories.** The real `CompanionController` and
  `DemoApi` ran against the real server with grounded answers on, a release
  built with the offline hashing embedder, and a local stand-in for the Qwen
  server, with no model downloaded. All five answer types that such a server
  returns (`grounded`, `reviewed_answer`, `abstained`, `redirected`, `safety`)
  parsed correctly, and clearing worked.
- **Live run against the real Qwen3.5-9B.** The same client code, against the
  live API with Qwen3.5-9B generating through Ollama, parsed grounded replies
  with their sources in about 2 s (including the 1 s poll), a reviewed answer
  in 1 s, a ruling redirect in 4 ms, and an abstention for a question the
  corpus cannot answer. See the paired `comp-server/CHANGELOG.md` entry.

- **On the Android 16 x86_64 emulator**, against the live API with Qwen3.5-9B
  generating (once Steam and Chrome were closed to free memory for both): the
  thinking bubble, a grounded reply with its "Sources" list, and a ruling
  redirect labelled "Let’s ask a grown-up" all rendered as designed. See
  `design/thinking-bubble.png`, `design/grounded-answer.png` and
  `design/redirect-reply.png`. (Superseded 2026-09-25:
  `design/thinking-bubble.png` has been replaced and now shows the new thinking
  line; see the entry above.) The first try surfaced a verifier issue on the
  server (Qwen sometimes cites once after two sentences), now fixed as
  `grounding-v2`; see `comp-server/CHANGELOG.md`.

Still not done: no physical device has run the new bubble. The corpus is synthetic help
text about using the app, not religious teaching, and it has not been reviewed
for children.

Known issues:
- **Pre-existing:** at 320×380 with text at 2×, the composer's hint wraps and
  leaves the reply about 64 px. (Superseded 2026-09-25: measured again in the
  widget tester with Roboto loaded, the old hint left about 56 px; the new,
  shorter hint leaves about 107 px. See the entry above.)
- **Source limits now match** (resolved before commit). The server's schema
  caps a source's title at 120 characters and its reference at 160, the same as
  this app, and its pipeline refuses any document that could exceed them, so a
  long title can no longer make the app refuse a whole reply.

## Unreleased — 2026-09-22

Three asks: declutter the character page, give the room a background instead of
a black void, and add a customization tab. Fixing the third so it could be seen
on a device turned out to require fixing the bridge handshake, which had never
completed.

### The character page

- **Reduced to the character, the last reply and the composer.** With no reply
  yet the page is only Robert.
- **Removed** the greeting card, the room status chip, the "character room
  stopped" notice, the app header and the adult-operator banner — all from this
  page only.
- **Moved, not dropped:**
  - header and banner → every other page, so the star balance, the parent entry
    and the operator notice stay one tap away. The notice still appears until
    the release gates pass; what changed is where.
  - room status and restart → the parent area, where an adult would act on them.
    How the renderer is doing is developer state, not something to put over a
    character's face.
  - orientation prompt → Learn. Service connection → Quests, Style and the
    parent area.
- **Kept beside the reply:** clearing the conversation, because it deletes the
  server-side conversation as well as the answer, and it stays reachable
  whenever a conversation exists even with no answer showing.
- The "Open character room" button now appears only when the room is *not*
  already the page's background, where it would have opened what is open.
- The stage yields its space below 260 logical pixels of page height, was 240.

### The room's backdrop

- **Added** `unity/tools/make_backdrop.py`, which draws a plain desert horizon
  from the project palette. Decoration only: no text, no symbol, no real place,
  so it needs no content review. One generator writes both copies —
  `unity/Assets/Companion/Room/backdrop_desert.png` for Unity and
  `assets/room/backdrop_desert.png` for Flutter.
- **Added** `unity/Assets/Companion/Runtime/RoomBackdrop.cs`: an unlit quad
  parked behind the character. It sizes itself to the frustum at runtime and
  centre-crops the texture to the screen ("cover", not stretch), because how big
  it must be depends on a viewport the builder cannot know. The quad carries
  both windings — an invisible backdrop from one wrong 180° is a silent failure
  not worth risking for four triangles.
- **Changed** the room camera to clear to an opaque sky colour. It used to clear
  to transparent black, which is what read as a pitch-black void wherever the
  full-bleed page was not painting.
- **Changed** the camera framing: margin 3.4 → 2.6, pitch 10° → 2°, and no
  vertical lift. Pitching down pushes the subject *up* the frame, which is what
  stranded the character above the horizon.
- **Added** the same image, veiled, as the background of every page that is not
  the character page. Robert exists only on Talk; the others read as the same
  place without him, and look identical whether or not a Unity room is running.

### Customization

- **Rewrote** `lib/ui/style_page.dart` as the customization tab: the catalogue
  with prices, swatches, what is earned, what is worn, and how many more stars a
  locked look needs.
- **Added** to the model and controller: `Cosmetic.description` and
  `Cosmetic.cost` (strictly validated — a price the app cannot parse is a
  rejected payload, not a free look), `claimCosmetic`, `equipCosmetic`,
  `equippedCosmeticId`, `canAfford`, and per-look idempotency keys so a retry
  reuses its own key and no look is answered with another's recorded result.
- **Replaced** `DemoApi.equipDefault` with `equipCosmetic(id, key)`, and added
  `claimCosmetic(id, key)`.
- **Replaced** `AvatarBridge.applyServerConfirmedDefault` with
  `applyServerConfirmedCosmetic(id)`, gated on a four-id allowlist that mirrors
  the room's own. A look this build does not ship is refused without touching
  the room.
- **Added** to Unity: the four-look allowlist in `BridgeCommand`, and per-look
  body recolouring in `RobertAvatarPresentation`, re-applied on initialize so a
  rebuilt room does not come back in its default colours. The face screen is
  never tinted — it is approved art, and recolouring it would change what the
  face reads as.
- **The shell decides what the room wears**, from what the service reports as
  worn rather than from the tap that changed it. Earning is not wearing, and the
  worn look comes back by itself after a relaunch or a room rebuild.

A look recolours the character; it is not modelled clothing, because no garment
art exists. The skin system already swaps whole model prefabs, so garments drop
in later as new catalogue entries without changing the bridge contract or how
they are earned. The Style page says this rather than implying otherwise.

### The bridge handshake — it had never completed

The status chip read "Character room · not connected" over a visibly working
room. Two causes, both about waiting for the wrong thing:

- **The handshake deadline was the ordinary 3-second bridge timeout**, but
  initialization waits on the host *starting an engine* — about six seconds on
  the development emulator. `AvatarBridge.surfaceTimeout` is now
  `startupTimeout` (30 s) and covers both the surface probe and the handshake,
  since both wait for an engine rather than for a room that is already
  answering.
- **The receiver announced readiness from `Awake`.** The host releases every
  held command the moment it hears any event from Unity, so the queued
  `avatar.initialize` arrived before `RobertSkinController.Start` had installed
  the visual. `IsAvailable` was false, the session answered `asset_unavailable`,
  and Flutter fell back for good — on every launch.
  `CompanionBridgeReceiver` now announces readiness from `Update`, once the
  presentation reports it can perform. A room whose assets never arrive simply
  never claims readiness, and Flutter's own deadline falls back, which is the
  outcome that was wanted anyway.

What settled it was a lifecycle trace of the Kotlin host — `attach`,
`onPlayerReady`, `onListen`, then Unity's events arriving with a live sink and
lengths matching `asset.failed` rather than an acknowledgement. That tracing was
removed once it had done its job.

### Contracts

- `contracts/openapi-v1.json` **regenerated from the app** rather than
  hand-edited, adding `POST /v1/cosmetics/claim` and the `Cosmetic`
  `description`/`cost` fields. `comp-server/tools/export_contracts.py` writes
  both repositories' copies and a server test fails when the checked-in copy
  drifts from the routes the app serves.
- `contracts/avatar-bridge-v1.schema.json`: `cosmeticId` widened from
  `const: "default"` to the four-id enum.

### Housekeeping

- Untracked `hs_err_pid20448.log`, a JVM crash dump committed by accident, and
  ignored `hs_err_pid*.log`, `replay_pid*.log` and `android/.kotlin/`.
- Removed `sandScrim` and `DevelopmentBanner.overRoom`, dead once the banner
  stopped appearing over the live room.
- `design/room-on-device.png` refreshed and `design/customization-tab.png`
  added, both from the emulator.

### Verification

- Flutter: 29 → **33 tests**, analysis clean. The new ones cover a look being
  earned from the service rather than granted on the device, the balance being
  re-read rather than adjusted, a refused claim spending and wearing nothing, a
  claim naming a different look being a failure rather than an unlock, and — end
  to end through a fake Unity host — the room being told only what the service
  reports as worn.
- Unity: 34 → **36 engine-free checks**, 11 → **12 EditMode tests** (the new one
  covers readiness waiting for a room that can perform).
- Emulator (Android 16, x86_64): the room renders with its backdrop, the
  handshake completes, and the full loop runs — finish the orientation, earn
  Sunset Copper for five stars, wear it, and the character recolours. A fresh
  launch plus connect restores the worn look with no tap.

Still unmeasured: any physical device, ARM64, startup time, memory, frame time,
TalkBack and rotation. A cold first launch after install can still come up
opaque; the host should push a "room attached" event rather than have Flutter
wait on a reply.
