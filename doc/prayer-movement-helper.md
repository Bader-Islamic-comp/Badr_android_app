# Prayer-movement helper

The Learn page has a practice of the prayer movements: one rak'ah, step by step.
The practice works by itself, with the child tapping Next after each movement.
The **movement helper** is optional. It uses the phone's front camera and a
small on-device model to recognise four postures (standing, bowing, prostrating
and sitting), and to tell when nobody is in view. It moves the practice on when
it sees the step held.

## Decision

On 2026-10-06 the product owner asked for this as a full app feature, with the
model running on the phone for the children's safety. Their decision is the
review this document records.

Two of the repository's earlier rules are changed by it, and only for this
feature:

- "No on-device inference." The posture classifier is the one model in the app.
  Running it on the phone is what keeps camera frames off the network: the
  alternative would send pictures of a child to a server. Chat, answers and
  every generative model stay on the backend.
- "No camera verification." The helper is practice feedback, not verification.
  It proves nothing, grants nothing, and the practice never needs it.

`AGENTS.md` and `product-architecture-roadmap.md` now name this exception, and
every other camera or body-motion feature still needs its own approval.

## What reaches what

```text
front camera (low resolution, no audio)
  → one frame in memory, at most one every 300 ms
  → turned upright and letterboxed to 224×224 (lib/posture/posture_input.dart)
  → the model, in a background isolate (assets/models/prayer_posture.tflite)
  → five probabilities: the four postures, and "none" for nobody in view
  → steadied over the last five frames (lib/posture/posture_smoother.dart)
  → "the helper sees: Standing", and the step moves on after 1.2 s held
```

- No frame is written to storage, logged, put in a crash report, sent to the
  service, or kept after its one inference. Only the five probabilities leave
  the classifier, and nothing is kept after the page closes.
- The camera records no audio. The plugin's `RECORD_AUDIO` and
  `WRITE_EXTERNAL_STORAGE` permissions are removed from the merged manifest;
  the app asks for `CAMERA` only. A phone without a camera can still install
  the app.
- The model is loaded the first time the helper is turned on, never at app
  start.
- Nobody in view never moves the practice on. The first four-class model, run
  on the emulator against an empty camera scene, said "Standing" and ticked off
  a step. A model that knows only postures has to name one, so the model now has
  a fifth output, "none", trained on empty squares of the dataset photos and on
  generated pictures. The app treats it as nothing seen.

## Controls

| Control | Default | Where |
| --- | --- | --- |
| Build kill switch | on | `--dart-define=POSTURE_HELPER=false` builds the app with no helper and no parent switch for it. |
| Parent switch, "Movement helper (camera)" | **off** at every app start | Parent area. Like the motion setting, it is not saved yet. |
| Camera | off | The practice page's "Turn on the camera". A "Camera on" badge shows while it runs. It stops on "Turn off the camera", when the page closes, and whenever the app leaves the screen. Coming back does not restart it. |
| The practice | — | Always works without the camera: Next and Start again. A refused camera permission explains itself and leaves the practice working. |

## Wording

- The helper names what it sees ("The helper sees: Sitting · الجلوس"). Another
  posture is never called a mistake, and an unsteady view shows "The helper is
  watching…".
- The page says the helper "checks the movement only. It cannot tell whether a
  prayer is correct or accepted. Ask a parent or teacher what to say in each
  movement."
- No stars, streaks or rewards come from the practice or the helper.
- The steps are movement names only (`lib/posture/movement_practice.dart`): القيام,
  الركوع, الرفع من الركوع, السجود, الجلوس بين السجدتين, السجدة الثانية, الجلوس. There
  is no recitation and no ruling. The four postures are the same in every
  madhhab, and the helper does not look at hand positions or other details
  where practice differs.

## The model

`ml/prayer_posture/MODEL_CARD.md` covers the data, licences, results and limits.
In short:

- MobileNetV3-Small, 1.1 MB, with int8 weights. It runs on TensorFlow Lite
  (LiteRT 1.4 through `tflite_flutter`).
- It was trained on two public datasets of adults and older children praying.
  **The Kaggle set is CC BY-NC 4.0, so the model is for non-commercial use**
  until it is retrained without that set.
- On 484 held-out pictures it is right 89.7% of the time. Of the empty
  pictures, 4.3% are taken for a posture, and 1.7% of people are taken for
  nobody. The model card has the detail.
- Its main weakness is over-calling prostration: some people sitting, seen from
  behind, and some bowing, read as sujud. A child sitting at the "Prostrate"
  step can be moved on. That costs nothing: they can tap Start again, and no
  step carries a reward.

## Testing

- `test/posture_test.dart` covers:
  - the model input: letterbox, rotation and colour conversion;
  - the steadying of readings;
  - the practice steps;
  - the label order against the bundled model.
- `test/prayer_practice_test.dart` covers the page with a scripted source in
  place of the camera:
  - the camera starts only when asked;
  - it stops on leaving;
  - a refused permission leaves the practice working;
  - the parent switch.
- `integration_test/posture_model_test.dart` runs the bundled model on a phone
  or emulator against held-out photos copied into the app's own storage. It
  checks that the Dart input and the Android runtime agree with the Python
  scores. On the emulator it read 435 of 484 correctly (89.9%), at 180 ms per
  inference.
- On the Android 16 x86_64 emulator, the whole path was checked in the real app:
  - the parent switch;
  - the system camera prompt;
  - the "Camera on" badge and the live preview;
  - the camera released when the page closes or the camera is turned off
    (`dumpsys media.camera` lists no active client).
  - With the emulator's empty generated scene in view for 20 s, the practice
    stayed on its first step ("The helper is watching…").
  - The APK asks for `CAMERA` and `INTERNET` only.
- Development testing is adult-operated, as the rest of this preview is. The
  helper has not been tried with children, and no child's picture may be
  collected to try it.

## Open

- The step names await the scholarly reviewer, like the rest of the religious
  content.
- If the team wants this decision under the signed governance of
  `comp-server/doc/decisions/`, it can be recorded there as a policy decision.
- The parent switch should be saved with the other guardian settings once those
  exist.
- A shipping phone build needs an ARM64 Unity export. The model and runtime
  already have ARM64 libraries.
- Retrain without the CC BY-NC data before any commercial release.
