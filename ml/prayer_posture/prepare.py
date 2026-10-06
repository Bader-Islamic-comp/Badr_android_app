"""Builds the prayer-posture training set from the two source datasets.

Each sample is one person in one of four postures, or a picture with nobody
in it (`CLASSES`), saved as a 256×256 JPEG:

- Kaggle "Salat Postures" (CC BY-NC 4.0): every labelled box, cropped square
  with a margin. Its two spellings of sitting and of sujud are merged. From
  half of the photos with a single person, a square well clear of them is
  "none".
- Mendeley IMCSPD (CC BY 4.0): the standing-prayer folders only, the whole
  photo padded to a square. The seated and lying modalities are left out: they
  are other ways of praying, not the movements a child learns first.
- Generated (source `synthetic`): 300 flat colours, gradients, blocks and
  noise, all "none". Without a "none" class the model names a posture for an
  empty room, and the practice would move on with nobody there.

Near-duplicates must not straddle the splits, or the test set measures memory.
Samples are grouped before splitting, by:

- the photo: boxes from one photo, and byte-identical copies;
- the session: photos one camera took less than 15 minutes apart (EXIF, or a
  `20251117_153358` file name), and `IMG_1255`-style numbers less than 30
  apart. In IMCSPD a session is close to a participant;
- the sequence: other numbered names (`ruku97`, `qiam(105)`) in runs of 20;
- the picture: whole photos whose 256-bit difference hashes nearly match.

A file filed under two postures is dropped. Each source is then split by group
into train, val and test (5 : 1 : 1), stratified by posture, with the seed
whose split comes closest to those shares.

    python prepare.py --kaggle <dir> --imcspd <dir> --out <dir>

writes `<out>/images/<source>/<id>.jpg`, `<out>/manifest.csv`, and the test
split again as `<out>/check/<posture>/<id>.jpg` for the on-device check
(`integration_test/posture_model_test.dart`). No image leaves the dataset
folder; nothing here belongs in the repository.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
import xml.etree.ElementTree as ET
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
from sklearn.model_selection import StratifiedGroupKFold

CLASSES = ("qiyam", "ruku", "sujud", "julus", "none")
NONE = "none"

KAGGLE_NAMES = {
    "qiyam": "qiyam",
    "ruku": "ruku",
    "sujud": "sujud",
    "Sujud": "sujud",
    "julus": "julus",
    "sitting": "julus",
}

# IMCSPD's standing modality, folder by folder. Takbir and recitation are
# standing; jalsa and the two salams are sitting. Dua (9) is sitting with the
# hands raised, as its photos show.
IMCSPD_FOLDERS = {
    "1": "qiyam",
    "2": "qiyam",
    "3": "qiyam",
    "4": "ruku",
    "5": "sujud",
    "6": "julus",
    "7": "julus",
    "8": "julus",
    "9": "julus",
}

SIZE = 256
MARGIN = 0.15
MIN_BOX = 48
GRAY = (114, 114, 114)
SPLITS = 7  # one fold test, one val, five train
TIME_GAP = 15 * 60  # seconds between photos of one session
NUMBER_GAP = 30  # IMG_#### numbers between photos of one session
SEQUENCE = 20  # other numbered names per sequence group
BACKGROUND_SHARE = 0.5  # of single-person photos that give a "none" square
BACKGROUND_OVERLAP = 0.05  # most of a "none" square a person (with margin) may cover
SYNTHETIC = 300
HASH_SIDE = 16
HASH_DISTANCE = 16  # of 256 bits


@dataclass
class Sample:
    id: str
    source: str
    label: str
    origin: str
    image: Image.Image
    hash: np.ndarray
    keys: list[str] = field(default_factory=list)
    group: int = -1
    split: str = ""


def square(image: Image.Image, box: tuple[float, float, float, float] | None) -> Image.Image:
    """The box (or the whole image) as a square with a margin, padded gray."""
    if box is None:
        x0, y0, x1, y1 = 0.0, 0.0, float(image.width), float(image.height)
        margin = 0.0
    else:
        x0, y0, x1, y1 = box
        margin = MARGIN
    side = max(x1 - x0, y1 - y0) * (1 + 2 * margin)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    left, top = round(cx - side / 2), round(cy - side / 2)
    side = round(side)
    canvas = Image.new("RGB", (side, side), GRAY)
    crop = image.crop((max(left, 0), max(top, 0), min(left + side, image.width), min(top + side, image.height)))
    canvas.paste(crop, (max(-left, 0), max(-top, 0)))
    return canvas.resize((SIZE, SIZE), Image.Resampling.BILINEAR)


def dhash(image: Image.Image) -> np.ndarray:
    """256 bits: whether each pixel of a 17×16 thumbnail is darker than the next."""
    pixels = np.asarray(image.convert("L").resize((HASH_SIDE + 1, HASH_SIDE), Image.Resampling.BILINEAR), dtype=np.int16)
    return (pixels[:, 1:] > pixels[:, :-1]).flatten()


_ORIENT = {3: Image.Transpose.ROTATE_180, 6: Image.Transpose.ROTATE_270, 8: Image.Transpose.ROTATE_90}


def _bytes(path: Path) -> str:
    return "bytes:" + hashlib.md5(path.read_bytes()).hexdigest()


def _session(image: Image.Image, source: str, stem: str) -> str | None:
    """`run:<series>:<value>` for the photo's place in a capture session."""
    exif = image.getexif()
    stamp = exif.get_ifd(0x8769).get(36867) or exif.get(306)
    if stamp:
        try:
            when = datetime.strptime(str(stamp).strip("\x00 "), "%Y:%m:%d %H:%M:%S")
            return f"run:time:{source}:{exif.get(272) or '?'}:{when.timestamp()}"
        except ValueError:
            pass
    if match := re.match(r"(\d{8})_(\d{6})", stem):
        when = datetime.strptime(match.group(1) + match.group(2), "%Y%m%d%H%M%S")
        return f"run:time:{source}:name:{when.timestamp()}"
    if match := re.fullmatch(r"(IMG|DSC|PXL)_(\d+)", stem, re.IGNORECASE):
        return f"run:number:{source}:{match.group(1).upper()}:{int(match.group(2))}"
    return None


def _sequence(stem: str, folder: str) -> str | None:
    """Other numbered names (`ruku97`, `qiam(105)`) group in runs of 20."""
    match = re.fullmatch(r"(.*?)\(?(\d+)\)?", stem)
    if not match or re.fullmatch(r"c[a-z0-9]{20,}", stem):
        return None
    return f"seq:{folder}:{match.group(1).lower()}:{int(match.group(2)) // SEQUENCE}"


def background(image: Image.Image, boxes: list[tuple[float, float, float, float]],
               rng: np.random.Generator) -> Image.Image | None:
    """A square of the photo well clear of every person in it, or None."""
    short = min(image.width, image.height)
    for _ in range(30):
        side = int(short * rng.uniform(0.35, 0.7))
        if side < MIN_BOX:
            return None
        x = int(rng.integers(0, image.width - side + 1))
        y = int(rng.integers(0, image.height - side + 1))
        covered = 0.0
        for x0, y0, x1, y1 in boxes:
            pad = MARGIN * max(x1 - x0, y1 - y0)
            w = min(x + side, x1 + pad) - max(x, x0 - pad)
            h = min(y + side, y1 + pad) - max(y, y0 - pad)
            if w > 0 and h > 0:
                covered += w * h
        if covered <= BACKGROUND_OVERLAP * side * side:
            return image.crop((x, y, x + side, y + side)).resize((SIZE, SIZE), Image.Resampling.BILINEAR)
    return None


def synthetic(count: int = SYNTHETIC, seed: int = 11) -> list[Sample]:
    """Pictures with nobody in them: flat colours, gradients, blocks and noise."""
    rng = np.random.default_rng(seed)
    samples = []
    for i in range(count):
        kind = ("flat", "gradient", "blocks", "noise")[i % 4]
        a, b = rng.integers(0, 256, 3), rng.integers(0, 256, 3)
        if kind == "flat":
            pixels = np.broadcast_to(a, (SIZE, SIZE, 3))
        elif kind == "gradient":
            t = np.linspace(0, 1, SIZE)[:, None, None]
            pixels = np.broadcast_to(a * (1 - t) + b * t, (SIZE, SIZE, 3))
            if rng.random() < 0.5:
                pixels = pixels.transpose(1, 0, 2)
        elif kind == "blocks":
            pixels = np.broadcast_to(a, (SIZE, SIZE, 3)).copy()
            for _ in range(int(rng.integers(3, 13))):
                x0, y0 = rng.integers(0, SIZE, 2)
                x1, y1 = x0 + rng.integers(16, SIZE // 2), y0 + rng.integers(16, SIZE // 2)
                pixels[y0:y1, x0:x1] = rng.integers(0, 256, 3)
        else:
            cells = int(rng.choice([4, 8, 16, 32]))
            small = rng.integers(0, 256, (SIZE // cells, SIZE // cells, 3))
            pixels = small.repeat(cells, 0).repeat(cells, 1)
        image = Image.fromarray(np.ascontiguousarray(pixels, dtype=np.uint8))
        samples.append(Sample(f"synthetic-{kind}-{i:03d}", "synthetic", NONE, f"generated {kind}",
                              image, dhash(image), [f"photo:synthetic:{i}"]))
    return samples


def kaggle(root: Path, seed: int = 7) -> tuple[list[Sample], Counter]:
    samples, skipped = [], Counter()
    rng = np.random.default_rng(seed)
    for xml in sorted(root.glob("*.xml")):
        tree = ET.parse(xml).getroot()
        path = next((p for p in root.glob(xml.stem + ".*") if p.suffix.lower() != ".xml"), None)
        if path is None:
            skipped["no image"] += 1
            continue
        try:
            raw = Image.open(path)
            raw.load()
        except OSError:
            skipped["unreadable"] += 1
            continue
        width, height = int(tree.findtext("size/width") or 0), int(tree.findtext("size/height") or 0)
        if (width, height) != raw.size:
            skipped["size differs from annotation"] += 1
            continue
        orientation = raw.getexif().get(274, 1)
        image = raw.convert("RGB")
        upright = image.transpose(_ORIENT[orientation]) if orientation in _ORIENT else image
        folder = tree.findtext("folder") or ""
        keys = [f"photo:kaggle:{xml.stem}", _bytes(path)]
        keys += [k for k in (_session(raw, "kaggle", xml.stem) or _sequence(xml.stem, folder),) if k]
        picture = dhash(upright)
        objects = list(tree.iter("object"))
        # Only a photo with exactly one person, and that one boxed, gives a
        # "none" square: crowds often have people nobody boxed.
        if len(objects) == 1 and rng.random() < BACKGROUND_SHARE:
            corners = [objects[0].findtext(f"bndbox/{k}") for k in ("xmin", "ymin", "xmax", "ymax")]
            empty = None if None in corners else background(image, [tuple(float(v) for v in corners)], rng)
            if empty is not None:
                if orientation in _ORIENT:
                    empty = empty.transpose(_ORIENT[orientation])
                samples.append(Sample(f"kaggle-{xml.stem}-none", "kaggle", NONE, path.name, empty, picture, list(keys)))
        for index, obj in enumerate(objects):
            label = KAGGLE_NAMES.get((obj.findtext("name") or "").strip())
            if label is None:
                skipped["unknown class"] += 1
                continue
            corners = [obj.findtext(f"bndbox/{k}") for k in ("xmin", "ymin", "xmax", "ymax")]
            if None in corners:
                skipped["no box"] += 1
                continue
            box = tuple(float(v) for v in corners)
            if min(box[2] - box[0], box[3] - box[1]) < MIN_BOX:
                skipped["box under 48 px"] += 1
                continue
            crop = square(image, box)
            # The boxes are drawn on the stored pixels; a crop is turned upright
            # only after it is cut.
            if orientation in _ORIENT:
                crop = crop.transpose(_ORIENT[orientation])
            samples.append(Sample(f"kaggle-{xml.stem}-{index}", "kaggle", label, path.name, crop, picture, list(keys)))
    return samples, skipped


def imcspd(root: Path) -> tuple[list[Sample], Counter]:
    samples, skipped = [], Counter()
    for folder in sorted(p for p in root.iterdir() if p.is_dir()):
        number = folder.name.split("_", 1)[0]
        label = IMCSPD_FOLDERS.get(number)
        if label is None:
            skipped[f"modality left out ({folder.name})"] += sum(1 for _ in folder.iterdir())
            continue
        for path in sorted(folder.iterdir()):
            if path.suffix.lower() not in (".jpg", ".jpeg", ".png"):
                continue
            raw = Image.open(path)
            keys = [f"photo:imcspd:{path.stem}", _bytes(path)]
            keys += [k for k in (_session(raw, "imcspd", path.stem),) if k]
            # The whole photo becomes 256 px: decode it at a fraction of its size.
            raw.draft("RGB", (SIZE * 2, SIZE * 2))
            image = ImageOps.exif_transpose(raw).convert("RGB")
            samples.append(Sample(f"imcspd-{folder.name}-{path.stem}", "imcspd", label,
                                  f"{folder.name}/{path.name}", square(image, None), dhash(image), keys))
    return samples, skipped


def drop_conflicts(samples: list[Sample]) -> list[Sample]:
    """The same file filed under two postures says nothing about either.

    A "none" square cut from a photo shares the photo's file with its person,
    so it is not a second posture."""
    labels: dict[str, set[str]] = {}
    for sample in samples:
        if sample.label == NONE:
            continue
        for key in sample.keys:
            if key.startswith("bytes:"):
                labels.setdefault(key, set()).add(sample.label)
    bad = {key for key, seen in labels.items() if len(seen) > 1}
    return [s for s in samples if not bad.intersection(s.keys)]


def group(samples: list[Sample]) -> None:
    """Union of samples that share a photo, a session, a sequence or a picture."""
    parent = list(range(len(samples)))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(i: int, j: int) -> None:
        parent[find(i)] = find(j)

    first: dict[str, int] = {}
    runs: list[tuple[str, float, int]] = []
    for i, sample in enumerate(samples):
        for key in sample.keys:
            if key.startswith("run:"):
                series, value = key.rsplit(":", 1)
                runs.append((series, float(value), i))
            elif key in first:
                union(i, first[key])
            else:
                first[key] = i
    runs.sort()
    for (series_a, a, i), (series_b, b, j) in zip(runs, runs[1:]):
        gap = TIME_GAP if series_a.startswith("run:time:") else NUMBER_GAP
        if series_a == series_b and b - a <= gap:
            union(i, j)
    # Generated pictures are independent by construction; their flat colours
    # and gradients would otherwise all hash alike.
    for source in {s.source for s in samples} - {"synthetic"}:
        index = [i for i, s in enumerate(samples) if s.source == source]
        bits = np.array([samples[i].hash for i in index])
        for n, i in enumerate(index[:-1]):
            distance = (bits[n + 1:] != bits[n]).sum(axis=1)
            for m in np.nonzero(distance <= HASH_DISTANCE)[0]:
                union(i, index[n + 1 + int(m)])
    roots: dict[int, int] = {}
    for i, sample in enumerate(samples):
        sample.group = roots.setdefault(find(i), len(roots))


def _folds(labels: list[int], groups: list[int], seed: int) -> list[str]:
    names = [""] * len(labels)
    folds = StratifiedGroupKFold(n_splits=SPLITS, shuffle=True, random_state=seed)
    for fold, (_, held) in enumerate(folds.split(np.zeros(len(labels)), labels, groups)):
        for i in held:
            names[i] = "test" if fold == 0 else "val" if fold == 1 else "train"
    return names


def _imbalance(labels: list[int], names: list[str]) -> float:
    """How far each posture's test and val shares are from one in seven."""
    total = 0.0
    for label in set(labels):
        held = [n for l, n in zip(labels, names) if l == label]
        for name in ("test", "val"):
            total += abs(held.count(name) / len(held) - 1 / SPLITS)
    return total


def split(samples: list[Sample], seeds: int = 50) -> None:
    """Each source by group, with the seed whose split is closest to 5 : 1 : 1
    for every posture: a few large groups (the video frames) can otherwise
    land in the test split and starve training."""
    for source in sorted({s.source for s in samples}):
        part = [s for s in samples if s.source == source]
        labels = [CLASSES.index(s.label) for s in part]
        groups = [s.group for s in part]
        best = min((_folds(labels, groups, seed) for seed in range(seeds)),
                   key=lambda names: _imbalance(labels, names))
        for sample, name in zip(part, best):
            sample.split = name


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--kaggle", type=Path, required=True, help="the Salat-All-img-xml folder")
    parser.add_argument("--imcspd", type=Path, required=True, help="the folder holding 1_Qiyam … 25_*")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    samples, skipped = kaggle(args.kaggle)
    more, skipped_imcspd = imcspd(args.imcspd)
    samples += more + synthetic()
    kept = drop_conflicts(samples)
    for sample in samples:
        if sample not in kept:
            (skipped if sample.source == "kaggle" else skipped_imcspd)["same file under two postures"] += 1
    samples = kept
    group(samples)
    split(samples)

    images = args.out / "images"
    rows = []
    for sample in samples:
        path = images / sample.source / f"{sample.id}.jpg"
        path.parent.mkdir(parents=True, exist_ok=True)
        sample.image.save(path, quality=92)
        if sample.split == "test":
            check = args.out / "check" / sample.label / f"{sample.id}.jpg"
            check.parent.mkdir(parents=True, exist_ok=True)
            sample.image.save(check, quality=92)
        rows.append({
            "id": sample.id,
            "source": sample.source,
            "label": sample.label,
            "split": sample.split,
            "group": f"{sample.source}-{sample.group}",
            "path": path.relative_to(args.out).as_posix(),
            "origin": sample.origin,
        })
    with open(args.out / "manifest.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    print(f"{len(rows)} samples")
    for source in ("kaggle", "imcspd", "synthetic"):
        sizes = Counter(r["group"] for r in rows if r["source"] == source)
        print(f"  {source}: {len(sizes)} groups, largest {sorted(sizes.values())[-5:]}")
        for name in ("train", "val", "test"):
            counts = Counter(r["label"] for r in rows if r["source"] == source and r["split"] == name)
            print(f"  {source:7} {name:5} " + "  ".join(f"{c} {counts[c]:4}" for c in CLASSES))
    for source, counter in (("kaggle", skipped), ("imcspd", skipped_imcspd)):
        for reason, count in sorted(counter.items()):
            print(f"  skipped {source}: {reason}: {count}")


if __name__ == "__main__":
    main()
