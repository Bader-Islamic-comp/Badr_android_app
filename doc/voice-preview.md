# Voice preview

The app can now hear and speak, in a development preview. Robert can read his
replies aloud. A child can ask him a question out loud. Learn has four short
adhkar and the duas of the day to listen to and practise saying. Quests has a
dhikr game that gives a star for each round practised.

All of it is a **development preview for adult operators**. It is not for
children until the DPIA, a retention owner and the release gate's voice items
are green.

## Decision

On 2026-10-06 the product owner decided how the preview works, within the
backend's development boundary. Their decisions are the review this document
records:

- **Robert's computer voice says four short adhkar only**: takbeer, tasbeeh,
  tahmeed and istighfar, from a reviewed allowlist. Longer duas and Quranic
  duas get a slot for a recorded human voice, which stays empty until
  recordings exist. Quran, hadith and duas are never spoken by a computer
  voice.
- **Questions can be asked out loud**, hold-to-talk only. The service writes
  down what it heard. The app shows it in the composer, and the child checks it
  and sends it like a typed question. The transcript is never logged or kept.
- **Robert's replies get a Listen button.** The service adds tashkeel to
  Robert's own sentences (quotes are skipped), checks that no letter changed,
  and renders them. The app plays the parts as they are ready.
- **Saying a dhikr or dua is pronunciation practice, never a verdict.** The
  outcomes are `clear`, `try_again` and `unsure`.
- **Stars reward practice**, not correctness or religious merit. A game round
  ends when the service hears the dhikr clearly, or after three counted tries.
  A finished round earns one star from the server's ledger.
- **The release gate's switch stays off.** The bootstrap's `features.voice`
  is still `false`, and the app still refuses a service where it is not. The
  preview is a separate object, `features.speech`, which the backend can only
  turn on in development mode.

`AGENTS.md` names this preview as approved. Any other microphone or audio
feature still needs its own approval.

## What reaches what

```text
microphone, only while the button is held
  → 16-bit PCM, mono, 16 kHz, streamed into memory (record plugin, no file)
  → a WAV header added in Dart (lib/speech/wav.dart)
  → POST to the backend as the raw body, Content-Type: audio/wav
  → the backend forwards it to the team's speech service on a private address
  → JSON back: what was heard, or a practice outcome and a feedback line
  → the app's copy of the audio is cleared
```

```text
Robert's voice, a dhikr, a feedback line or a recorded dua
  → GET from the backend, audio/wav bytes into memory
  → played from memory (Android MediaDataSource, audioplayers plugin)
  → Robert's Talk loop runs while his voice plays; nothing else reaches Unity
```

- The app talks only to the backend. It never calls the speech service and
  holds no speech credential.
- Robert's room gets the same decorative `Talk` loop as before, and nothing
  else: no audio, no text and no new bridge message.

## Never kept

- No audio is written to a file, a cache or a log. The recorder streams into
  memory; the plugin's file recording is never used.
- The audio buffer is cleared once the request has its answer. A recording
  that is cancelled, or cut off by leaving the page or the app, is dropped
  unsent.
- A transcript lives only in the composer, until it is sent or cleared, like
  typed text. It is not saved.
- Robert's voice and the other audio are read into memory, played and cleared.
  On iOS, macOS and Linux the player plugin would write bytes to a temporary
  file first, so there the app does not play them at all.
- Practice results are shown and not kept. The game's stars are the server's.

## Controls

| Control | Default | Where |
| --- | --- | --- |
| Build kill switch | on | `--dart-define=VOICE=false` builds the app with no speech screen, no microphone button, no parent switch for it, and no microphone request. |
| Service switches | off | `features.speech` in the bootstrap: `preview`, then `recitation`, `voiceQuestions` and `robertVoice`. A feature shows only while `preview` is on. |
| Parent switch, "Microphone (hold to talk)" | **off** at every app start | Parent area. Shown only when the build has the preview and the service has it on. It is not saved. Every recording needs it; listening does not. |
| Recording | off | Hold the microphone button. A red dot and "Listening… 3 s" show while it is held. It stops on release, at `maxRecordingSeconds` (15 from the service, never over 30), at 1 MB, when the page closes and when the app leaves the screen. |
| Microphone permission | not asked | Asked by Android the first time the button is held with the parent switch on. A refusal records nothing, says so, and typing still works. |
| Listen | — | Needs no switch. Stop ends it, as do a new question, clearing the reply, leaving Talk and leaving the app. |

## On each page

- **Talk.** Under a reply Robert can read aloud (chat, library, "not sure" and
  "ask a grown-up" replies, never a safeguarding reply) there is **Listen**.
  The app asks the service for his voice, reads its state every 2 s for up to
  5 minutes, and plays each part as soon as it is ready, in order. While it
  waits it says "Robert's voice is getting ready…".
- **Talk, out loud.** With the parent switch on and nothing typed, the send
  button becomes a microphone. Hold it, speak, let go. What was heard goes into
  the composer to check and send. If the service was not sure, the app says
  "I didn't catch that. Try again or type it." A small button beside the line
  chooses Arabic (ع, the default) or English (EN).
- **Learn → Adhkar.** The four adhkar, each with Listen and Practise.
  Practice shows the service's feedback line, and, on the first tries, each
  word gently marked: soft green for "sounded clear", soft sand for "practise
  this one". There are no stars here.
- **Learn → Duas.** The duas of the day, with their child notes. Listen plays
  a recorded human voice when there is one. Otherwise the slot says "A
  recorded voice is coming". Duas the service has split into parts can be
  practised part by part. Quranic duas show no text here.
- **Quests → Dhikr game.** Pick a dhikr, hear Robert say it, hold the
  microphone and say it. The round shows "Try 1 of 3". A finished round shows
  "+1 star", and the balance is read again from the server. "See looks in
  Style" opens the Style tab. When the day's game stars are all given, the
  game says "The game's stars for today are all collected. You can keep
  playing just for practice."

## Wording

- The app never says a recitation is correct, valid or accepted, and never
  uses the banned words (غلط، خطأ، فشلت، ما قُبل، باطل، لا يصح، ما بتنحسب،
  مرفوض, wrong, failed, invalid, rejected, incorrect, mistake).
  `test/voice_copy_test.dart` scans every string in the preview's files.
- Feedback lines are the service's reviewed copy. The app adds none of its
  own.
- Every practice page ends: "This is practice for saying the words clearly. It
  is not a test, and Robert does not judge anyone's worship."
- No timers, streaks or rankings. The daily cap is said warmly, with no loss.
- Speech-service outages read gently: "Voice practice is resting right now"
  and "Lots of voices at once right now".

## The routes the app calls

All are the backend's, with `X-Demo-Token`, in development mode. Writes carry
an `Idempotency-Key`, one request at a time. A transcription carries none: it
is not a write, and the backend keeps nothing to replay. Asking for Robert's
voice gets a fresh key each time; the backend is idempotent by turn.

| Route | Use |
| --- | --- |
| `GET /v1/bootstrap` | `features.speech`; `features.voice` must stay `false` |
| `GET /v1/adhkar`, `GET /v1/duas` | Learn content |
| `GET /v1/audio/adhkar/{id}`, `/duas/{id}`, `/feedback/{copyId}` | audio/wav |
| `POST /v1/recitations/attempts?itemId=&segment=&attempt=` | practice, raw WAV |
| `GET /v1/games/dhikr`, `POST /v1/games/dhikr/rounds` | the game |
| `POST /v1/games/dhikr/rounds/{roundId}/attempts` | a try, raw WAV |
| `POST /v1/speech/transcriptions?language=ar\|en` | a spoken question, raw WAV |
| `POST` and `GET /v1/turns/{turnId}/speech` | Robert's voice: ask, then read its state |
| `GET /v1/turns/{turnId}/speech/parts/{index}` | one part, audio/wav |

Uploads and audio reads wait up to 30 s; JSON reads 12 s, as before. Every
payload is parsed strictly (`lib/domain/speech_models.dart`), and a payload
that breaks a rule is refused whole.

How the backend's answers are read:

- `speech_unavailable` and `speech_busy` (503) get the gentle lines above. The
  bootstrap's switches come from the backend's settings, not from the speech
  service, so a route can still answer `speech_unavailable`.
- `speech_disabled` (404) means that part is switched off: "This part of the
  voice preview is switched off right now." For Listen it reads as no voice.
- `item_not_found` (404): "This one is not ready for practice yet."
- `request_in_progress` (409) can only follow a lost answer, since the app
  sends one request at a time. Each dhikr has its own key for starting a
  round, so another dhikr never reuses one.
- `round_complete` (409) and `round_not_found` (404) end the round on screen
  and offer a new one.
- For Robert's voice, a part the backend dropped leaves the list, so indices
  can have gaps: the app plays the listed parts in order and waits for the
  next listed one. A part that answers `audio_not_found` is skipped. An
  unknown turn (`not_found`) has no voice. The `reason` is never shown.
- `features.speech.robertVoice` is on only while grounded answers are on.
- A feedback line may come from the backend's own copy when the service's
  line did not pass its checks. The app always shows `feedback.text`, and
  fetches its voice only when `feedback.audio` is true.
- Everything else reads the generic "The service could not finish this
  request." The service's own text is never shown.

## Android

- `RECORD_AUDIO` comes from the `record` plugin's manifest. The app manifest
  no longer removes it. A build with `VOICE=false` still declares it, because
  a Dart define cannot change the manifest, but it never asks for it.
- The microphone is optional hardware, like the camera.
- `WRITE_EXTERNAL_STORAGE` is still removed.
- The packages are `record` 7.1.1 and `audioplayers` 6.8.1. `audioplayers`
  brings `path_provider`, whose Android side now uses `jni` and builds a small
  native library with CMake.

## Testing

- `test/speech_api_test.dart`: the WAV header (RIFF sizes, 16 kHz, mono,
  16-bit), every new response shape and its bounds, and the requests (raw
  bytes, headers, query, the 1 MB bound, error codes).
- `test/voice_preview_test.dart`: with a fake microphone, a fake player and a
  scripted service:
  - the build switch, the service switches and the parent switch;
  - a refused permission;
  - Listening with its seconds, the 15 s and 1 MB bounds, a tap, leaving the
    app;
  - a transcript into the composer, and an unsure one;
  - Listen polling every 2 s, parts in order with the Talk loop, the 5-minute
    limit, dropped and lost parts skipped, an unknown turn, no voice for a
    safeguarding reply;
  - Adhkar and Duas practice;
  - a game round to its star and the balance read again, the daily cap, and
    a round key kept per dhikr;
  - the composer at 320×380 with text at 2×.
- `test/voice_copy_test.dart`: the banned words and verdict words.
- Not yet run on a phone or the emulator, and no APK was built for this
  change. The merged manifest is still to be checked after a build.

## Open

- Try it on the emulator against the speech-enabled backend, then on a phone.
- Check the merged manifest and the APK's permissions after the first build.
- `contracts/openapi-v1.json` is to be synced from the backend's
  regenerated contract. The app was written against the agreed spec and
  checked against the backend's contract for the shapes above.
- An upload waits 30 s, and the backend's own speech timeout is also 30 s, with
  retries when the service is busy. A slow answer can reach the app as
  "Connection unavailable" rather than the gentle busy line.
- The parent switch should be saved with the other guardian settings once
  those exist.
- The DPIA (G04), a retention owner and the release gate's voice items, before
  any child uses it.
