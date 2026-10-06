"""Trains the prayer-posture classifier and exports it for the phone.

MobileNetV3-Small with ImageNet weights and a five-way head (`prepare.CLASSES`:
four postures and "none"),
trained in two stages: the head alone, then the whole network at a low rate with
batch statistics frozen. Augmentation leans towards zooming out, because on the
phone the child fills less of the frame than a labelled box does.

    python train.py --data <prepared dir> --out <dir>
    python train.py --data <prepared dir> --out <dir> --train kaggle --test imcspd --no-export

A test source that is also a training source is scored on its test split; one
that is not is scored on all of it, which is the cross-dataset check.

Writes to <out>: `prayer_posture.tflite`, `labels.txt` and `metrics.json`. The
model takes a float RGB image in 0–255 and gives five probabilities. Its weights
are int8 and its activations float (dynamic-range quantization): a full int8
export of this network is the same size but fails to prepare under XNNPACK,
TensorFlow Lite's default CPU delegate, in TensorFlow 2.19.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import platform
from pathlib import Path

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import keras  # noqa: E402
import numpy as np  # noqa: E402
import tensorflow as tf  # noqa: E402
from keras import layers  # noqa: E402
from sklearn.metrics import confusion_matrix, f1_score, precision_recall_fscore_support  # noqa: E402

from prepare import CLASSES, NONE  # noqa: E402

MODEL_VERSION = "prayer-posture-v1"
INPUT = 224
GRAY = 114.0


def rows(data: Path) -> list[dict]:
    with open(data / "manifest.csv", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def pick(manifest: list[dict], sources: list[str], split: str) -> list[dict]:
    return [r for r in manifest if r["source"] in sources and r["split"] == split]


def held_out(manifest: list[dict], train: list[str], test: list[str]) -> list[dict]:
    return [r for r in manifest if r["source"] in test and (r["split"] == "test" or r["source"] not in train)]


def _load(path: tf.Tensor) -> tf.Tensor:
    image = tf.io.decode_jpeg(tf.io.read_file(path), channels=3)
    return tf.image.resize(tf.cast(image, tf.float32), (INPUT, INPUT))


def dataset(data: Path, part: list[dict], *, training: bool, batch: int = 32, seed: int = 7) -> tf.data.Dataset:
    paths = [str(data / r["path"]) for r in part]
    labels = [CLASSES.index(r["label"]) for r in part]
    ds = tf.data.Dataset.from_tensor_slices((paths, labels))
    if training:
        ds = ds.shuffle(len(part), seed=seed, reshuffle_each_iteration=True)
    ds = ds.map(lambda p, y: (_load(p), y), num_parallel_calls=tf.data.AUTOTUNE)
    if training:
        augment = keras.Sequential([
            layers.RandomFlip("horizontal"),
            # Positive zoom is out: the child is smaller in a phone's frame.
            layers.RandomZoom((-0.15, 0.45), fill_mode="constant", fill_value=GRAY),
            layers.RandomTranslation(0.12, 0.12, fill_mode="constant", fill_value=GRAY),
            layers.RandomRotation(0.03, fill_mode="constant", fill_value=GRAY),
            layers.RandomBrightness(0.25, value_range=(0, 255)),
            layers.RandomContrast(0.25),
        ], name="augment")
        ds = ds.batch(batch).map(lambda x, y: (tf.clip_by_value(augment(x, training=True), 0, 255), y),
                                 num_parallel_calls=tf.data.AUTOTUNE)
    else:
        ds = ds.batch(batch)
    return ds.prefetch(tf.data.AUTOTUNE)


def build() -> tuple[keras.Model, keras.Model]:
    base = keras.applications.MobileNetV3Small(
        input_shape=(INPUT, INPUT, 3), include_top=False, weights="imagenet",
        include_preprocessing=True, pooling="avg")
    inputs = keras.Input((INPUT, INPUT, 3), name="image")
    features = base(inputs, training=False)
    features = layers.Dropout(0.3)(features)
    outputs = layers.Dense(len(CLASSES), activation="softmax", name="posture")(features)
    return keras.Model(inputs, outputs, name="prayer_posture"), base


def class_weights(part: list[dict]) -> dict[int, float]:
    counts = np.bincount([CLASSES.index(r["label"]) for r in part], minlength=len(CLASSES))
    return {i: float(counts.sum() / (len(CLASSES) * c)) for i, c in enumerate(counts) if c}


def scores(truth: np.ndarray, guess: np.ndarray) -> dict:
    precision, recall, f1, support = precision_recall_fscore_support(
        truth, guess, labels=range(len(CLASSES)), zero_division=0)
    return {
        "n": int(len(truth)),
        "accuracy": round(float((truth == guess).mean()), 4),
        "macro_f1": round(float(f1_score(truth, guess, labels=range(len(CLASSES)), average="macro", zero_division=0)), 4),
        "per_class": {c: {"precision": round(float(p), 4), "recall": round(float(r), 4), "f1": round(float(f), 4), "n": int(s)}
                      for c, p, r, f, s in zip(CLASSES, precision, recall, f1, support)},
        "confusion": confusion_matrix(truth, guess, labels=range(len(CLASSES))).tolist(),
    }


def report(part: list[dict], probabilities: np.ndarray) -> dict:
    truth = np.array([CLASSES.index(r["label"]) for r in part])
    guess = probabilities.argmax(1)
    out = scores(truth, guess)
    out["by_source"] = {s: scores(truth[m], guess[m]) for s in sorted({r["source"] for r in part})
                        if (m := np.array([r["source"] == s for r in part])).any()}
    # What matters to the practice: a posture seen with nobody there, or a
    # child taken for nobody, at the confidence the app acts on.
    confident = probabilities.max(1) >= 0.6
    none = CLASSES.index(NONE)
    nobody, people = truth == none, truth != none
    out["nobody"] = {
        "false_sightings": round(float((nobody & (guess != none) & confident).sum() / max(1, nobody.sum())), 4),
        "missed_people": round(float((people & (guess == none) & confident).sum() / max(1, people.sum())), 4),
        "n_nobody": int(nobody.sum()),
    }
    out["wrong"] = [{"id": r["id"], "label": r["label"], "guess": CLASSES[g], "p": round(float(p.max()), 3)}
                    for r, g, p in zip(part, guess, probabilities) if CLASSES.index(r["label"]) != g]
    return out


def export(model: keras.Model, out: Path) -> Path:
    saved = out / "saved_model"
    model.export(str(saved), verbose=False)
    converter = tf.lite.TFLiteConverter.from_saved_model(str(saved))
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    path = out / "prayer_posture.tflite"
    path.write_bytes(converter.convert())
    return path


def run_tflite(path: Path, data: Path, part: list[dict]) -> np.ndarray:
    interpreter = tf.lite.Interpreter(model_path=str(path), num_threads=os.cpu_count())
    interpreter.allocate_tensors()
    source, = interpreter.get_input_details()
    target, = interpreter.get_output_details()
    out = []
    for r in part:
        interpreter.set_tensor(source["index"], tf.expand_dims(_load(tf.constant(str(data / r["path"]))), 0).numpy())
        interpreter.invoke()
        out.append(interpreter.get_tensor(target["index"])[0].copy())
    return np.array(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--train", default="kaggle,imcspd,synthetic")
    parser.add_argument("--test", default="kaggle,imcspd,synthetic")
    parser.add_argument("--head-epochs", type=int, default=8)
    parser.add_argument("--tune-epochs", type=int, default=30)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--no-export", action="store_true")
    args = parser.parse_args()

    keras.utils.set_random_seed(args.seed)
    args.out.mkdir(parents=True, exist_ok=True)
    train_sources, test_sources = args.train.split(","), args.test.split(",")
    manifest = rows(args.data)
    train_part = pick(manifest, train_sources, "train")
    val_part = pick(manifest, train_sources, "val")
    test_part = held_out(manifest, train_sources, test_sources)
    train_ds = dataset(args.data, train_part, training=True, seed=args.seed)
    val_ds = dataset(args.data, val_part, training=False)
    weights = class_weights(train_part)
    print(f"train {len(train_part)}  val {len(val_part)}  test {len(test_part)}  weights {weights}")

    model, base = build()
    base.trainable = False
    model.compile(optimizer=keras.optimizers.Adam(1e-3), loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    head = model.fit(train_ds, validation_data=val_ds, epochs=args.head_epochs, class_weight=weights, verbose=2)

    base.trainable = True
    steps = args.tune_epochs * int(np.ceil(len(train_part) / 32))
    model.compile(optimizer=keras.optimizers.Adam(keras.optimizers.schedules.CosineDecay(2e-4, steps)),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    tune = model.fit(train_ds, validation_data=val_ds, epochs=args.tune_epochs, class_weight=weights, verbose=2,
                     callbacks=[keras.callbacks.EarlyStopping("val_loss", patience=6, restore_best_weights=True)])

    metrics = {
        "model": MODEL_VERSION,
        "classes": list(CLASSES),
        "input": {"shape": [1, INPUT, INPUT, 3], "range": [0, 255], "layout": "RGB, letterboxed with gray 114"},
        "output": {"shape": [1, len(CLASSES)], "order": list(CLASSES)},
        "train_sources": train_sources,
        "test_sources": test_sources,
        "counts": {"train": len(train_part), "val": len(val_part), "test": len(test_part)},
        "epochs": {"head": len(head.history["loss"]), "tune": len(tune.history["loss"])},
        "val_accuracy": round(float(max(tune.history["val_accuracy"])), 4),
        "keras": report(test_part, model.predict(dataset(args.data, test_part, training=False), verbose=0)),
        "seed": args.seed,
        "tensorflow": tf.__version__,
        "keras_version": keras.__version__,
        "machine": platform.processor() or platform.machine(),
    }
    if not args.no_export:
        path = export(model, args.out)
        metrics["tflite"] = report(test_part, run_tflite(path, args.data, test_part))
        metrics["tflite"]["bytes"] = path.stat().st_size
        (args.out / "labels.txt").write_text("\n".join(CLASSES) + "\n", encoding="utf-8")
    (args.out / "metrics.json").write_text(json.dumps(metrics, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    summary = {k: metrics[k]["accuracy"] for k in ("keras", "tflite") if k in metrics}
    print(json.dumps({"test": summary, "macro_f1": metrics["keras"]["macro_f1"],
                      "nobody": metrics.get("tflite", metrics["keras"])["nobody"],
                      "by_source": {s: v["accuracy"] for s, v in metrics["keras"]["by_source"].items()}}))


if __name__ == "__main__":
    main()
