# Prayer posture classifier

Trains the model behind the prayer-movement helper
(`../../doc/prayer-movement-helper.md`). The model is a MobileNetV3-Small
classifier for four postures (qiyam, ruku, sujud, julus) and "none" (nobody in
view) that runs on the phone.
What it is and how well it does is in [`MODEL_CARD.md`](MODEL_CARD.md).

The datasets are not in this repository, and nothing here copies an image into
it. Only the scripts, the metrics and the exported model are committed.

## Reproduce

1. Download the two datasets outside the repository, for example into
   `../datasets` beside `comp-mobile`:
   - Kaggle "Salat Postures" (CC BY-NC 4.0):
     `https://www.kaggle.com/api/v1/datasets/download/riotulab/salat-postures`
     (662 MB). Unzip it; the folder you need is `Salat-All-img-xml`.
   - Mendeley IMCSPD v2 (CC BY 4.0):
     `https://data.mendeley.com/public-api/zip/xwrgj6c7wr/download/2` (4.5 GB). It
     holds `IMCSPD-Dataset.zip`. Only the folders `1_Qiyam` to `9_Dua` are used.
2. Make a Python 3.10 environment and install `requirements.txt`. TensorFlow
   2.19 on Windows runs on the CPU. The main run takes about 15 minutes on a
   6-core desktop. Leave about 6 GB of memory free: with the emulator and a
   Gradle daemon running, fine-tuning ran out of memory.
3. Prepare the samples. This writes 256-pixel crops, `manifest.csv` with
   leakage-aware splits, and the test split again under `check/` for the
   on-device check:

   ```bash
   python prepare.py --kaggle <dir>/Salat-All-img-xml --imcspd <dir>/IMCSPD-Dataset --out <dir>/prepared
   ```

4. Train, export and score:

   ```bash
   python train.py --data <dir>/prepared --out <dir>/runs/main
   python train.py --data <dir>/prepared --out <dir>/runs/kaggle-to-imcspd --train kaggle,synthetic --test imcspd --no-export
   python train.py --data <dir>/prepared --out <dir>/runs/imcspd-to-kaggle --train imcspd,synthetic --test kaggle --no-export
   ```

5. Copy `runs/main/prayer_posture.tflite` to `../../assets/models/`, and each
   run's `metrics.json` to `results/<run>.json`. Then update the model card.
   `test/posture_test.dart` checks that the labels file matches the app's
   `Posture` order and that the model is bundled.
6. Check the model on a device. Its header says how to copy `check/` into the
   app. On the Android 16 x86_64 emulator it read 435 of the 484 test pictures
   correctly (89.9%), at 180 ms per inference:

   ```bash
   flutter test integration_test/posture_model_test.dart -d emulator-5554
   ```

## Files

| File | What it does |
| --- | --- |
| `prepare.py` | Maps both datasets to the four postures and crops each person square. It adds "none" samples: squares clear of the person in single-person photos, and generated flat colours, gradients, blocks and noise. It groups near-duplicates by photo, session, numbered sequence and picture hash, then splits each source by group into train, val and test. |
| `train.py` | Trains MobileNetV3-Small with ImageNet weights in two stages. It exports a TensorFlow Lite model with int8 weights and scores the Keras model and the exported file on the held-out test set. |
| `results/` | `metrics.json` from the runs behind the bundled model. |
| `MODEL_CARD.md` | What the model is for, what it is not for, its data, licences, results and limits. |
