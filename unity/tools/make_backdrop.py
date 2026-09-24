"""Generates the room backdrop PNG from the project palette.

The room used to clear to transparent black, which read as a pitch-black void
behind the character wherever the Flutter page was not painting. A backdrop
image is the cheapest honest fix: it is decorative only, and carries no text,
no symbol and no real place, so it needs no content review.

Run it from anywhere:

    python unity/tools/make_backdrop.py

It writes Assets/Companion/Room/backdrop_desert.png. The room builder pins the
import settings and the quad geometry, so regenerating this file is the only
step needed to change how the room looks.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

# 2:1, which is what the room builder's backdrop quad is shaped for: wide
# enough to cover a landscape frustum without the texture being stretched.
WIDTH, HEIGHT = 2048, 1024

# The supplied Robert palette, so the room and the page read as one product.
TEAL = (0x23, 0x6C, 0x67)
ORANGE = (0xB7, 0x4D, 0x25)
SAND = (0xF3, 0xE6, 0xD1)
SKY_HIGH = (0x7F, 0xA8, 0xB4)
SKY_LOW = (0xF6, 0xDF, 0xBE)
SUN = (0xFF, 0xF6, 0xE2)

# The horizon sits just above the middle. The room builder frames the character
# centred with its feet below this line, so the horizon has to be high enough
# for it to read as standing on the ground rather than hovering over it.
HORIZON = 0.55


def rgb(colour, shape):
    """Broadcasts a colour tuple to an (h, w, 3) field."""
    return np.broadcast_to(np.asarray(colour, dtype=np.float32), shape + (3,)).copy()


def mix(a, b, t):
    """Blends two colour fields (or tuples) by `t`, which may be an array."""
    t = np.clip(np.asarray(t, dtype=np.float32), 0.0, 1.0)
    if t.ndim == 2:
        t = t[..., None]
    a = np.asarray(a, dtype=np.float32)
    b = np.asarray(b, dtype=np.float32)
    return a + (b - a) * t


def ridge(x, seed, amplitude, frequency):
    """A smooth dune silhouette: summed sines, never noise with hard steps."""
    weights = [1.0, 0.55, 0.28, 0.14]
    total = sum(weights)
    value = np.zeros_like(x)
    for index, weight in enumerate(weights):
        harmonic = frequency * (index + 1) * 0.5
        value = value + weight * np.sin(2 * np.pi * harmonic * x + seed + index * 1.7)
    return value / total * amplitude


def main() -> int:
    shape = (HEIGHT, WIDTH)
    x = np.broadcast_to(np.linspace(0.0, 1.0, WIDTH, dtype=np.float32), shape)
    y = np.broadcast_to(np.linspace(0.0, 1.0, HEIGHT, dtype=np.float32)[:, None], shape)

    # Sky: deep at the top, warming down towards the horizon.
    canvas = mix(rgb(SKY_HIGH, shape), rgb(SKY_LOW, shape), (y / HORIZON) ** 1.6)

    # The sun sits high and only slightly off centre. A portrait phone sees a
    # narrow centre crop of this wide image, so anything placed near an edge is
    # simply not on screen; anything at dead centre hides behind the character.
    aspect = WIDTH / HEIGHT
    distance = np.sqrt(((x - 0.44) * aspect) ** 2 + (y - 0.20) ** 2)
    canvas = mix(canvas, rgb((0xFF, 0xE7, 0xC4), shape),
                 np.clip(1.0 - distance / 0.62, 0.0, 1.0) ** 2.4 * 0.55)
    canvas = mix(canvas, rgb(SUN, shape),
                 np.clip(1.0 - distance / 0.055, 0.0, 1.0) ** 0.35)

    # Three dune bands: each nearer one is warmer, less hazed and lower.
    haze = mix(rgb(SAND, shape), rgb(SKY_LOW, shape), 0.55)
    for index, (base, amplitude, frequency, solidity) in enumerate(
            [(0.020, 0.035, 1.5, 0.30), (0.110, 0.060, 0.9, 0.55), (0.260, 0.090, 0.6, 0.85)]):
        near = mix(rgb(SAND, shape), rgb(ORANGE, shape), 0.18 + 0.12 * index)
        line = HORIZON + base + ridge(x, index * 2.3, amplitude, frequency)
        canvas = np.where((y >= line)[..., None], mix(haze, near, solidity), canvas)

    # Foreground sand, warming towards the bottom edge.
    floor = HORIZON + 0.260
    depth = np.clip((y - floor) / (1.0 - floor), 0.0, 1.0)
    ground = mix(mix(rgb(SAND, shape), rgb(ORANGE, shape), 0.30),
                 mix(rgb(SAND, shape), rgb(ORANGE, shape), 0.46), depth)
    canvas = np.where((y >= floor + ridge(x, 6.1, 0.090, 0.6))[..., None], ground, canvas)

    # A broad vignette settles the corners so the eye stays on the character.
    edge = np.clip(1.0 - (((x - 0.5) * 1.7) ** 2 + ((y - 0.45) * 1.25) ** 2), 0.0, 1.0)
    canvas = mix(mix(canvas, rgb(TEAL, shape), 0.42), canvas, 0.30 + 0.70 * edge)

    image = Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8), "RGB")
    # Soften the band edges so the flat shapes do not alias on a phone.
    image = image.filter(ImageFilter.GaussianBlur(radius=1.2))

    unity = Path(__file__).resolve().parent.parent
    # The Flutter pages that are not the character page show the same picture
    # without the character in it, so both read as one place. One generator,
    # one image, two consumers.
    targets = [unity / "Assets" / "Companion" / "Room",
               unity.parent / "assets" / "room"]
    for target in targets:
        target.mkdir(parents=True, exist_ok=True)
        out = target / "backdrop_desert.png"
        image.save(out, "PNG", optimize=True)
        print("BACKDROP_OK", out, out.stat().st_size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
