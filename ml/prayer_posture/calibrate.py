"""Per-posture confidence thresholds for the app, set on the validation split.

The app counts a reading as a posture only when that posture is the top choice
and its probability reaches the posture's own threshold; "none" never counts
(`lib/posture/posture_smoother.dart`). A posture that is over-called, such as
sujud taken for people sitting, needs a higher bar than one that is not.

Each threshold is the lowest of 0.60, 0.61, … 0.99 at which the posture's
validation precision reaches `TARGET`. 0.60 is the single bar the app used
before. A posture that never reaches the target gets the threshold with its
best precision. Only the validation split is used; the test split is scored at
the thresholds afterwards and never chooses them.

    python calibrate.py --data <prepared dir> --run <run dir>

scores `<run>/prayer_posture.tflite` on the run's validation and test splits,
writes `<run>/thresholds.json` and adds the thresholds and the scores at them
to `<run>/metrics.json`. `train.py` does the same at the end of every run.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from prepare import CLASSES, NONE

TARGET = 0.90
FLOOR = 0.60
STEPS = np.round(np.arange(FLOOR, 1.0, 0.01), 2)
POSTURES = [c for c in CLASSES if c != NONE]


def _truth(part: list[dict]) -> np.ndarray:
    return np.array([CLASSES.index(r["label"]) for r in part])


def seen(probabilities: np.ndarray, thresholds: dict[str, float]) -> np.ndarray:
    """The posture each reading counts as, or -1 when it counts as nothing."""
    top = probabilities.argmax(1)
    bar = np.array([thresholds.get(c, np.inf) for c in CLASSES])
    return np.where(probabilities.max(1) >= bar[top], top, -1)


def calibrate(part: list[dict], probabilities: np.ndarray) -> dict[str, float]:
    truth, top, best = _truth(part), probabilities.argmax(1), probabilities.max(1)
    out = {}
    for posture in POSTURES:
        c = CLASSES.index(posture)
        precision = []
        for step in STEPS:
            called = (top == c) & (best >= step)
            precision.append((called & (truth == c)).sum() / called.sum() if called.any() else 0.0)
        reached = [step for step, p in zip(STEPS, precision) if p >= TARGET]
        out[posture] = float(reached[0] if reached else STEPS[int(np.argmax(precision))])
    return out


def at_thresholds(part: list[dict], probabilities: np.ndarray, thresholds: dict[str, float]) -> dict:
    """Scores as the app counts readings: below its bar, a reading is nothing."""
    truth, counted = _truth(part), seen(probabilities, thresholds)
    out = {"per_posture": {}}
    for posture in POSTURES:
        c = CLASSES.index(posture)
        called, right = counted == c, (counted == c) & (truth == c)
        out["per_posture"][posture] = {
            "threshold": thresholds[posture],
            "precision": round(float(right.sum() / max(1, called.sum())), 4),
            "recall": round(float(right.sum() / max(1, (truth == c).sum())), 4),
            "n": int((truth == c).sum()),
            "called": int(called.sum()),
        }
    nobody, people = truth == CLASSES.index(NONE), truth != CLASSES.index(NONE)
    out["false_sightings"] = round(float((nobody & (counted >= 0)).sum() / max(1, nobody.sum())), 4)
    out["people_unseen"] = round(float((people & (counted < 0)).sum() / max(1, people.sum())), 4)
    out["people_wrong_posture"] = round(float((people & (counted >= 0) & (counted != truth)).sum()
                                              / max(1, people.sum())), 4)
    out["n_nobody"], out["n_people"] = int(nobody.sum()), int(people.sum())
    return out


def summary(model: str, scored_with: str, part: list[dict], probabilities: np.ndarray,
            thresholds: dict[str, float]) -> dict:
    """`thresholds.json`: the values the app ships with, and what they did on val."""
    return {
        "model": model,
        "calibrated_on": "val",
        "scored_with": scored_with,
        "target_precision": TARGET,
        "floor": FLOOR,
        "thresholds": thresholds,
        "val": at_thresholds(part, probabilities, thresholds),
        "val_at_floor": at_thresholds(part, probabilities, dict.fromkeys(POSTURES, FLOOR)),
    }


def main() -> None:
    from train import held_out, pick, rows, run_tflite

    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--run", type=Path, required=True)
    args = parser.parse_args()

    metrics = json.loads((args.run / "metrics.json").read_text(encoding="utf-8"))
    manifest = rows(args.data)
    val_part = pick(manifest, metrics["train_sources"], "val")
    test_part = held_out(manifest, metrics["train_sources"], metrics["test_sources"])
    model = args.run / "prayer_posture.tflite"
    val = run_tflite(model, args.data, val_part)
    thresholds = calibrate(val_part, val)
    calibration = summary(metrics["model"], "tflite", val_part, val, thresholds)
    (args.run / "thresholds.json").write_text(json.dumps(calibration, indent=2) + "\n", encoding="utf-8")
    metrics["thresholds"] = {k: v for k, v in calibration.items() if k not in ("model", "floor")}
    metrics["tflite"]["at_thresholds"] = at_thresholds(test_part, run_tflite(model, args.data, test_part), thresholds)
    (args.run / "metrics.json").write_text(json.dumps(metrics, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"thresholds": thresholds, "test": metrics["tflite"]["at_thresholds"]}, indent=1))


if __name__ == "__main__":
    main()
