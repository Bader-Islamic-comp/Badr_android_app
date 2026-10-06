# Model card: prayer posture classifier (`prayer-posture-v2`)

The model behind the app's prayer-movement helper
(`../../doc/prayer-movement-helper.md`). From one camera frame it says which of
four prayer postures a person is in, or that nobody is in view.

| | |
| --- | --- |
| File | `assets/models/prayer_posture.tflite`, 1,107,960 bytes, SHA-256 `4028e211e9c691470c1dc357920b5ef959c2334a6102e3e03f15d0da3c263abb` |
| Network | MobileNetV3-Small (ImageNet weights) with a five-way softmax head |
| Input | `[1, 224, 224, 3]` float32 RGB in 0–255: the whole frame upright, letterboxed on gray 114 |
| Output | `[1, 5]` probabilities in the order of `assets/models/prayer_posture_labels.txt`: qiyam, ruku, sujud, julus, none |
| Thresholds | One per posture, set on the validation split: `results/thresholds.json`, copied into `PostureSmoother.defaultThresholds`. For this model all four are 0.6. |
| Quantization | Dynamic range: int8 weights, float activations. A full int8 export of the same size failed to prepare under XNNPACK (TensorFlow 2.19), the default CPU delegate. |
| Runtime | TensorFlow Lite / LiteRT 1.4.0 through `tflite_flutter` 0.12.1, two threads, in a background isolate |
| Trained | 2026-10-06, TensorFlow 2.19.1 and Keras 3.12.4, on the CPU, seed 7 (`train.py`) |
| Licence | **CC BY-NC 4.0, non-commercial use only**, because of the Kaggle training set |

## Intended use

- Practice feedback for a child learning the movements of the prayer in this
  app, on the phone, with an adult nearby.
- The app takes a posture as seen only when, in three of the last five frames,
  it is the top choice and its probability reaches that posture's threshold.
  A step counts once that is held for 1.2 s.
- "None" is never a posture, so it never completes a step.

## Not for

- Judging whether a prayer is valid, correct or accepted. The page says it
  cannot.
- Judging details where practice differs, such as hand placement or the feet.
  It only tells four broad postures apart.
- Seated or lying prayer. Those modalities were left out of training.
- Identifying, counting or tracking people, or anything that keeps or sends
  images.
- Gating rewards or progress.

## Data

| Source | Licence | Used | Samples |
| --- | --- | --- | --- |
| [Salat Postures](https://www.kaggle.com/datasets/riotulab/salat-postures), Robotics and Internet-of-Things Lab (Koubâa et al., CDMA 2020) | CC BY-NC 4.0 | Every labelled person box, cropped square with a 15% margin. From half of the single-person photos, one square well clear of the person, as "none". 222 photos stored sideways are turned upright. | 1,931 people and 217 "none" from 1,904 images |
| [IMCSPD v2](https://doi.org/10.17632/xwrgj6c7wr.2), Ashadzzaman, Kamruzzaman and Yaser, Mendeley Data 2026 | CC BY 4.0 | The standing-prayer folders `1_Qiyam` to `9_Dua`, each whole photo letterboxed | 707 |
| Generated (`prepare.synthetic`) | — | Flat colours, gradients, blocks and noise, as "none" | 300 |

**Postures:**
- Takbir and recitation count as qiyam.
- Jalsa, the two salams and dua (sitting with raised hands) count as julus.
- Kaggle's two spellings of sitting and of sujud are merged.

**Why "none":** the first version knew only the four postures. On the emulator
it named one ("Standing") for a camera scene with nobody in it, and the
practice moved on.

**"None" squares** come only from photos with a single boxed person, because
crowd photos have people nobody boxed. Even so, 31 of the 248 squares had
someone in them: TV presenters, the robe of a second worshipper, bowing
crowds, drawings. They are dropped (see below).

**Fixes made for v2,** each in a reviewed list beside `prepare.py` and
confirmed by eye on contact sheets:
- **Sideways photos** (`kaggle_rotations.csv`, 222 photos). Three lab sessions
  of the Kaggle set (a wood-floor lab and a mosque with a blue carpet) are
  stored turned a quarter anticlockwise, with no EXIF orientation to say so.
  A seated man on his side looks like sujud, so they taught the model wrong
  and made up about two in five of v1's test errors. The phone always turns
  frames upright. To find them:
  - A small self-supervised rotation classifier was trained: frozen
    MobileNetV3-Small features of every photo turned 0°, 90°, 180° and 270°,
    and a logistic regression on which turn it was. It was cross-fitted by
    photo group, so no photo was judged by a model that had seen it.
  - Each photo was scored in all four turns together. The classifier was a
    pointer, not a judge: it flagged 208 photos, of which only 83 were
    sideways. It learnt each sideways session as upright from the session's
    own photos and missed the other 139.
  - So the whole Kaggle set (1,901 photos) was looked at on contact sheets,
    and every photo of the sessions found sideways was checked again next to
    its upright turn.
  - A second round, trained with the confirmed photos' true turns, found
    nothing new. Its remaining flags were photos taken from straight above
    (where "upright" means little), drawings and photos that are upright.
  - All 222 need the same quarter turn clockwise. Only confirmed photos are
    listed.
- **"None" squares with a person** (`kaggle_none_excluded.csv`, 31 squares).
  All 248 squares were looked at on contact sheets, with v1's reading of
  each. v1 called only 6 of them a posture, so its score alone would have
  missed most. The square is still cut, so that every other photo keeps the
  same square.

**Left out:**
- Boxes under 48 px (85).
- Objects without a box (65).
- Files filed under two postures (79).
- Images whose size differs from their annotation (4).
- "None" squares with a person in them (31).

**The people:**
- IMCSPD: adults, and boys who by their look are older children and teenagers,
  praying at home in 8 capture sessions.
- Kaggle: students and lab members photographed from many angles, with web
  images, cartoons and TV frames of prayer tutorials. The rights in the web
  images are unclear, which is one more reason the model stays non-commercial.
  A few series show boys who look to be of primary-school age, praying at
  home or in a mosque.
- Few women or girls appear, and no children younger than those.

**Splits** (`prepare.py`):
- Samples are first grouped so that near-duplicates never straddle a split:
  - boxes and "none" squares from one photo, and identical files;
  - photos one camera took within 15 minutes, and `IMG_####` numbers within 30
    of each other;
  - other numbered names in runs of 20;
  - whole photos with nearly equal 256-bit difference hashes.
- Each source is then split by group, stratified by posture, into train, val and
  test (5 : 1 : 1). Of 50 seeds, the one whose shares come closest to that for
  every class is kept: a few large groups of video frames otherwise starved
  training.
- IMCSPD falls into exactly its 8 sessions, and one whole session is its test
  set.
- Totals: 2,243 train, 409 val, 503 test.
- Turning photos upright changed their picture hashes, and so the Kaggle
  groups and splits. The IMCSPD session and the generated pictures held out
  for test are the same as v1's; the Kaggle test groups are not.

## Training

- Inputs are resized from 256 to 224.
- Augmentation: horizontal flip, zoom of −15% to +45% (mostly out, because a
  child fills less of a phone's frame than a box does), ±12% shift, ±11°
  rotation, and brightness and contrast ±25%.
- Classes are weighted by inverse frequency.
- Training runs in two stages, and the best validation loss is kept:
  - the head for 8 epochs at 1e-3;
  - then the whole network at a cosine-decayed 2e-4 with batch statistics
    frozen. It ran all 30 epochs, and the last was the best.
- Then each posture's threshold is set on the validation split
  (`calibrate.py`): the lowest of 0.60, 0.61, … 0.99 at which the posture's
  validation precision reaches 90%. 0.6 is the single bar the app used before.
  The test split never chooses a threshold.

## Results

### Held-out test

The shipped TFLite file, on 503 samples. This is a new test split (see
Splits), so its numbers are not comparable with v1's 89.7% on 484 samples. The
comparison that is fair comes below.

| | Accuracy | Macro-F1 |
| --- | --- | --- |
| **Shipped TFLite file** | **97.0%** | **0.968** |
| Keras, before export | 97.2% | 0.972 |
| The IMCSPD session it never saw (108) | 100% | |
| Kaggle test groups (352) | 95.7% | |
| Generated "none" (43) | 100% | |

| True ↓ / seen → | qiyam | ruku | sujud | julus | none | Recall |
| --- | --- | --- | --- | --- | --- | --- |
| qiyam (65) | 64 | 1 | 0 | 0 | 0 | 98.5% |
| ruku (115) | 0 | 105 | 9 | 0 | 1 | 91.3% |
| sujud (76) | 0 | 1 | 74 | 1 | 0 | 97.4% |
| julus (170) | 0 | 0 | 1 | 169 | 0 | 99.4% |
| none (77) | 0 | 0 | 1 | 0 | 76 | 98.7% |
| Precision | 100% | 98.1% | 87.1% | 99.4% | 98.7% | |

**Thresholds.** Set on the validation split (409 samples), every posture
already reaches the 90% precision aim at 0.6, the bar the app used before, so
every threshold stays 0.6. A higher bar was not needed on validation and would
cost recall.
The per-posture thresholds are still in the app (`PostureSmoother`), so a
later model can ship its own.

| At the thresholds (all 0.6) | qiyam | ruku | sujud | julus |
| --- | --- | --- | --- | --- |
| Validation precision | 100% | 99.2% | 97.6% | 96.2% |
| Validation recall | 95.6% | 96.7% | 96.4% | 100% |
| Test precision | 100% | 98.1% | 88.1% | 99.4% |
| Test recall | 96.9% | 90.4% | 97.4% | 99.4% |

**Mistakes that matter to the practice,** as the app counts readings (a
reading below its posture's threshold counts as nothing seen):
- **False sightings:** an empty picture taken for a posture, 0% (0 of 77;
  v1: 4.3%, 3 of 69).
- **Missed people:** a person confidently taken for nobody, 0% (0 of 426;
  v1: 1.7%).
- **People not seen:** a person whose reading reaches no threshold, 0.7%
  (3 of 426). The practice waits; nothing is shown.
- **Wrong posture:** a person counted as another posture, 3.1% (13 of 426).

**The 15 errors,** listed in `results/main.json`, looked at one by one:
- 8 are the boxes of one photo of a packed mosque, where each worshipper in
  a bowing row is a few dozen pixels high. All 8 read as sujud. They hold
  sujud's precision at 87% (88% at the threshold); without them it would be
  96% (74 of 77).
- 3 are drawings: two bowing figures (read as sujud, and as nobody at 0.47),
  and a tutorial slide in a "none" square read as sujud at 0.56, below the
  bar.
- 1 is probably mislabelled: a man bowing, boxed as sujud, which the model
  calls ruku.
- 1 is a crouch photographed from straight above, boxed as sujud, read as
  julus.
- 1 is a man in a standing row read as bowing.
- 1 is a real miss of the kind v1 made often: a man sitting, seen from the
  side, read as sujud (0.85).

### Before and after

The fair comparison is on the 214 samples held out from both models: test in
v1's split and in v2's. They are mostly the shared IMCSPD session (108) and
generated pictures (43), with 63 Kaggle samples, 18 of them from photos now
turned upright. Each model's TFLite file:

| | Accuracy | Macro-F1 | False sightings | People not seen at 0.6 | Errors |
| --- | --- | --- | --- | --- | --- |
| v1, pictures as v1 had them | 89.7% | 0.860 | 2.0% (1 of 50) | 7.3% | 22 |
| v1, the same pictures upright | 93.9% | 0.906 | 2.0% (1 of 50) | 3.0% | 13 |
| **v2** | **94.4%** | **0.902** | **0%** | **1.2%** | **12** |

- Most of the gain is the pictures. Turned upright, 9 of v1's 22 errors go
  away; 6 of them were sideways sitting photos read as sujud.
- Retraining on the fixed data adds less here than the headline suggests. v2
  fixes four bowing photos v1 missed and its one false sighting, but reads all
  8 people in the packed-mosque photo as sujud, where v1 read 4 of them so.
- On the whole new test split, v1's file gets 96.6%, but it was trained on 244
  of those 503 samples, so that number flatters it.

### Across datasets

Training on one source (with the generated "none" pictures) and testing on all
of the other shows how far the model carries to people and rooms it has not
seen. These models were trained for the check and are not shipped. In both,
fine-tuning stopped early, after 7 epochs.

| Trained on → tested on | Accuracy | Per-posture recall | "None" |
| --- | --- | --- | --- |
| Kaggle → all of IMCSPD (707) | 81.3% | qiyam 98.7%, ruku 75.6%, sujud 75.8%, julus 71.5% (79 of 295 read as qiyam) | none in the test set |
| IMCSPD → all of Kaggle (2,179) | 54.7% | qiyam 94.9%, ruku 29.3%, sujud 78.7%, julus 25.1% | 28.6% of Kaggle's empty squares taken for a posture |

IMCSPD alone (8 home sessions) does not carry to Kaggle's mosques, TV frames,
cartoons and angles, or to real empty rooms. Kaggle carries to IMCSPD. That is
why the shipped model learns from both.

### On a device

`integration_test/posture_model_test.dart` runs the same 484 test pictures
through the app's Dart input code and the Android runtime (LiteRT 1.4.0). On the
Android 16 x86_64 emulator it gets **435 right (89.9%)**, against 89.7% for the
same file in Python, at 180 ms per inference on the emulated CPU. The page
classifies at most one frame every 300 ms, so even that leaves room.

| True ↓ / seen → | qiyam | ruku | sujud | julus | none |
| --- | --- | --- | --- | --- | --- |
| qiyam (69) | 68 | 0 | 0 | 0 | 1 |
| ruku (113) | 4 | 92 | 13 | 0 | 4 |
| sujud (70) | 0 | 2 | 68 | 0 | 0 |
| julus (163) | 0 | 4 | 15 | 143 | 1 |
| none (69) | 1 | 0 | 3 | 1 | 64 |

**In the app,** the emulator's camera shows a generated scene with nobody in it:

| Version | Over 20 s of that scene |
| --- | --- |
| Four-class | Said "Standing" and completed a step |
| This model | Stayed on "The helper is watching…" |

That scene looks like the generated block patterns, so the held-out false
sighting rate above is the fairer measure.

## Limits

- **Children:** it has not been evaluated on young children as a group,
  whose proportions differ. A few Kaggle series of older boys are all it has. No child's picture may be collected to check it. Any
  test with children must be designed with the safeguarding review.
- **Sujud is still the weakest call,** at 87% test precision (v1: 72% on its
  own test split). Most of what is left is small figures bowing in a packed
  crowd, which a phone held for one child should not see, but a man sitting
  seen from the side can still read as sujud. A child sitting at the
  "Prostrate" step could be moved on. The app needs a steady reading held for
  1.2 s, the child can always tap Next or Start again, and nothing rides on a
  step.
- **Small validation set:** the thresholds rest on 409 validation samples, 83
  of them sujud. At 0.6 every posture clears 90% precision there, but a
  posture's precision on a different crowd of photos can differ by several
  points, as sujud's 97.6% on validation and 87% on test show.
- **Empty rooms:** they are learnt from squares of the dataset photos and
  generated pictures. None of the 77 empty test pictures was taken for a
  posture, but they are few, and a room unlike them still can be. No extra
  "none" squares were added for v2: validation did not call for them (1 false
  sighting in 58).
- **Viewpoint:** the training data is mostly side, front and back views at
  about waist height. Looking down from above or from far away is less
  reliable.
- **One person:** it assumes one person fills a fair part of the frame.
  Several people in view, or a child far away, read unreliably.
- **Single frames:** it looks at one frame at a time, so a movement in progress
  can read as either posture. The app's steadying handles that.
- **Label noise:** the sideways photos and the "none" squares with people are
  fixed. A few likely mislabels remain, such as a man bowing boxed as sujud
  and a man sitting boxed as sujud; they were noted, not changed. Photos taken
  from straight above have no clear upright and were left as they are.

## Licence and attribution

- **Licences of the data:**
  - IMCSPD is CC BY 4.0.
  - Salat Postures is CC BY-NC 4.0.
  - The ImageNet weights come with Keras, under Apache 2.0.
- **The model** is an adaptation of both datasets, so it is used under CC BY-NC
  4.0: non-commercial use only. **Before any commercial release, retrain without
  the Kaggle set**, or with data cleared for commercial use. The IMCSPD-only
  result above shows that more varied data, including empty rooms, is then
  needed.
- **Attribution** for both datasets is in the app's licence list
  (`lib/main.dart`, opened from the parent area). Please cite:
  - Koubâa, A., Ammar, A., Benjdira, B., Al-Hadid, A., Kawaf, B., Al-Yahri,
    S.A., Babiker, A., Assaf, K. and Ras, M.B. (2020). Activity Monitoring of
    Islamic Prayer (Salat) Postures using Deep Learning. *6th Conference on Data
    Science and Machine Learning Applications (CDMA)*, 106–111. IEEE.
  - Ashadzzaman, B.M., Kamruzzaman, B. and Yaser, S. (2026). Islamic
    Multi-Category Salat Posture Dataset (IMCSPD), version 2. Mendeley Data.
    doi:10.17632/xwrgj6c7wr.2.
