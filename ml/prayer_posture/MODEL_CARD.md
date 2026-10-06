# Model card: prayer posture classifier (`prayer-posture-v1`)

The model behind the app's prayer-movement helper
(`../../doc/prayer-movement-helper.md`). From one camera frame it says which of
four prayer postures a person is in, or that nobody is in view.

| | |
| --- | --- |
| File | `assets/models/prayer_posture.tflite`, 1,107,960 bytes, SHA-256 `ebff7d294fb3ee117754350d2b28c8372995394e9f165b693ff598df51de5fe9` |
| Network | MobileNetV3-Small (ImageNet weights) with a five-way softmax head |
| Input | `[1, 224, 224, 3]` float32 RGB in 0–255: the whole frame upright, letterboxed on gray 114 |
| Output | `[1, 5]` probabilities in the order of `assets/models/prayer_posture_labels.txt`: qiyam, ruku, sujud, julus, none |
| Quantization | Dynamic range: int8 weights, float activations. A full int8 export of the same size failed to prepare under XNNPACK (TensorFlow 2.19), the default CPU delegate. |
| Runtime | TensorFlow Lite / LiteRT 1.4.0 through `tflite_flutter` 0.12.1, two threads, in a background isolate |
| Trained | 2026-10-06, TensorFlow 2.19.1 and Keras 3.12.4, on the CPU, seed 7 (`train.py`) |
| Licence | **CC BY-NC 4.0, non-commercial use only**, because of the Kaggle training set |

## Intended use

- Practice feedback for a child learning the movements of the prayer in this
  app, on the phone, with an adult nearby.
- The app takes a posture as seen only when it is the confident top choice
  (at least 0.6) in three of the last five frames, and a step counts once that
  is held for 1.2 s.
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
| [Salat Postures](https://www.kaggle.com/datasets/riotulab/salat-postures), Robotics and Internet-of-Things Lab (Koubâa et al., CDMA 2020) | CC BY-NC 4.0 | Every labelled person box, cropped square with a 15% margin. From half of the single-person photos, one square well clear of the person, as "none". | 1,931 people and 248 "none" from 1,904 images |
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
crowd photos have people nobody boxed. A few squares still contain someone,
such as a presenter in a TV frame.

**Left out:**
- Boxes under 48 px (85).
- Objects without a box (65).
- Files filed under two postures (79).
- Images whose size differs from their annotation (4).

**The people:**
- IMCSPD: adults, and boys who by their look are older children and teenagers,
  praying at home in 8 capture sessions.
- Kaggle: students and lab members photographed from many angles, with web
  images, cartoons and TV frames of prayer tutorials. Some lab photos are
  stored sideways. The rights in the web images are unclear, which is one more
  reason the model stays non-commercial.
- Few women or girls appear, and no young children.

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
- Totals: 2,359 train, 343 val, 484 test.

## Training

- Inputs are resized from 256 to 224.
- Augmentation: horizontal flip, zoom of −15% to +45% (mostly out, because a
  child fills less of a phone's frame than a box does), ±12% shift, ±11°
  rotation, and brightness and contrast ±25%.
- Classes are weighted by inverse frequency.
- Training runs in two stages, and the best validation loss is kept:
  - the head for 8 epochs at 1e-3;
  - then the whole network at a cosine-decayed 2e-4 with batch statistics
    frozen. It stopped after 19 epochs.

## Results

### Held-out test

The shipped TFLite file, on 484 samples:

| | Accuracy | Macro-F1 |
| --- | --- | --- |
| **Shipped TFLite file** | **89.7%** | **0.896** |
| Keras, before export | 88.4% | 0.885 |
| The IMCSPD session it never saw (108) | 100% | |
| Kaggle test groups (333) | 85.0% | |
| Generated "none" (43) | 100% | |

| True ↓ / seen → | qiyam | ruku | sujud | julus | none | Recall |
| --- | --- | --- | --- | --- | --- | --- |
| qiyam (69) | 68 | 0 | 0 | 0 | 1 | 98.6% |
| ruku (113) | 6 | 92 | 11 | 0 | 4 | 81.4% |
| sujud (70) | 0 | 2 | 68 | 0 | 0 | 97.1% |
| julus (163) | 0 | 4 | 15 | 140 | 4 | 85.9% |
| none (69) | 1 | 0 | 1 | 1 | 66 | 95.7% |
| Precision | 90.7% | 93.9% | 71.6% | 99.3% | 88.0% | |

**Mistakes that matter to the practice,** at the 0.6 confidence the app acts on:
- **False sightings:** an empty picture taken for a posture, 4.3% (3 of 69).
- **Missed people:** a person taken for nobody, 1.7% (7 of 415).

**The 50 errors,** listed in `results/main.json`, looked at one by one:
- About two in five are Kaggle photos stored sideways. The app always turns
  frames upright, so a phone never sees these.
- Most of the rest:
  - people sitting, seen from behind and read as sujud;
  - crowds bowing, seen from behind;
  - cartoons;
  - "none" squares that contain someone.

This test set is larger and harder than the one the first four-class version
scored 93.5% on: it holds out whole numbered sequences of the Kaggle set.

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

- **Children:** it has not been evaluated on young children, whose
  proportions differ. No child's picture may be collected to check it. Any
  test with children must be designed with the safeguarding review.
- **Sujud is over-called,** at 72% precision: people sitting seen from behind,
  and some bowing, read as sujud. A child sitting at the "Prostrate" step could
  be moved on. The app needs a steady reading held for 1.2 s, the child can
  always tap Next or Start again, and nothing rides on a step.
- **Empty rooms:** they are learnt from squares of the dataset photos. A room
  unlike those can still be taken for a posture now and then (4.3% of empty
  test pictures).
- **Viewpoint:** the training data is mostly side, front and back views at
  about waist height. Looking down from above or from far away is less
  reliable.
- **One person:** it assumes one person fills a fair part of the frame.
  Several people in view, or a child far away, read unreliably.
- **Single frames:** it looks at one frame at a time, so a movement in progress
  can read as either posture. The app's steadying handles that.
- **Label noise:** sideways photos, a few likely mislabels, and "none" squares
  with someone in them remain in the data.

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
