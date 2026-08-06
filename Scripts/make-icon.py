#!/usr/bin/env python3
"""Draws the app icon and builds Resources/Icon/ideai.icns.

Rendered rather than checked in as a binary blob so the artwork stays
reviewable and editable: the icon is a handful of shapes, and a diff of the
numbers that describe them says more than a diff of a PNG.

The icon is a desert horizon: a sun bisected by the line it is setting behind.

Run: python3 Scripts/make-icon.py
"""
import math
import os
import subprocess
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Pillow is required: python3 -m pip install pillow")

# Drawn large and downsampled, which is cheaper than antialiasing by hand.
SCALE = 4
SIZE = 1024 * SCALE

# Amber on a near-black sky. The sky is kept dark deliberately: macOS derives
# a tinted, single-hue variant of every icon, and that transform keeps
# luminance and discards colour. A bright disc on a dark field survives it; a
# sunset gradient, whose whole effect lives in its hue, turns to grey mush.
SKY_TOP = (16, 13, 11)
SKY_HORIZON = (46, 27, 14)
SUN_TOP = (255, 221, 155)
SUN_BOTTOM = (238, 149, 32)
GROUND = (14, 11, 9)
GLOW = (255, 179, 71)
HORIZON_LINE = (255, 192, 105)

# In 1024-point units, measured from the top-left.
#
# The horizon sits at exactly the sun's centre, so the disc is halved: a
# half-circle on a flat line is geometry that survives to 16 points, where a
# landscape would not. 640 is not an arbitrary height either — it is 5/8 of
# the icon, so the line lands on a whole pixel at every size macOS asks for
# rather than smearing across two.
SUN_CENTRE_X = 512
HORIZON_Y = 640
SUN_RADIUS = 288
GLOW_RADIUS = 384
HORIZON_WEIGHT = 6
GLOW_PEAK_ALPHA = 108
HORIZON_LINE_ALPHA = 107


def squircle_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def vertical_gradient(width, height, top, bottom):
    """One column, interpolated, then stretched — Pillow has no gradient fill."""
    column = Image.new("RGB", (1, height))
    for y in range(height):
        t = y / max(height - 1, 1)
        column.putpixel((0, y), tuple(
            round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
        ))
    return column.resize((width, height))


def glow(size, centre, radius, colour, peak_alpha):
    """A radial falloff, computed small and scaled up.

    The falloff is smooth enough that the interpolation costs nothing visible,
    and a per-pixel loop over 4096 squared in Python is not worth the wait.
    """
    small = 512
    layer = Image.new("RGBA", (small, small), colour + (0,))
    pixels = layer.load()
    cx = centre[0] / size * small
    cy = centre[1] / size * small
    r = radius / size * small
    for y in range(small):
        dy = y - cy
        for x in range(small):
            distance = math.hypot(x - cx, dy)
            if distance >= r:
                continue
            falloff = 1.0 - distance / r
            pixels[x, y] = colour + (int(peak_alpha * falloff * falloff),)
    return layer.resize((size, size), Image.LANCZOS)


def draw() -> Image.Image:
    unit = SIZE / 1024
    centre_x = SUN_CENTRE_X * unit
    centre_y = HORIZON_Y * unit
    radius = SUN_RADIUS * unit

    canvas = vertical_gradient(SIZE, SIZE, SKY_TOP, SKY_HORIZON).convert("RGBA")

    canvas.alpha_composite(
        glow(SIZE, (centre_x, centre_y), GLOW_RADIUS * unit, GLOW, GLOW_PEAK_ALPHA))

    # The disc, its gradient spanning only the half that is above the horizon.
    # Running it across the whole circle wastes the amber end below the ground
    # line, where nothing can see it, and leaves the visible half washed pale.
    disc_top = int(round(centre_y - radius))
    disc = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    disc.paste(vertical_gradient(SIZE, int(round(radius)), SUN_TOP, SUN_BOTTOM),
               (0, disc_top))
    disc_mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(disc_mask).ellipse(
        [centre_x - radius, centre_y - radius, centre_x + radius, centre_y + radius],
        fill=255)
    canvas.paste(disc, (0, 0), disc_mask)

    # The ground cuts the disc in half.
    ImageDraw.Draw(canvas).rectangle([0, centre_y, SIZE, SIZE], fill=GROUND)

    # A lit edge where the two meet, so the cut reads as a horizon and not as
    # a shape that happens to stop.
    weight = HORIZON_WEIGHT * unit
    edge = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rectangle(
        [0, centre_y - weight / 2, SIZE, centre_y + weight / 2],
        fill=HORIZON_LINE + (HORIZON_LINE_ALPHA,))
    canvas.alpha_composite(edge)

    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    image.paste(canvas, (0, 0), squircle_mask(SIZE, int(SIZE * 0.225)))
    return image


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    destination = os.path.join(root, "Resources", "Icon")
    os.makedirs(destination, exist_ok=True)

    master = draw().resize((1024, 1024), Image.LANCZOS)
    master.save(os.path.join(destination, "icon-1024.png"))

    iconset = os.path.join(destination, "ideai.iconset")
    os.makedirs(iconset, exist_ok=True)
    # The sizes macOS asks for; anything missing is scaled badly at runtime.
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        master.resize((size, size), Image.LANCZOS).save(
            os.path.join(iconset, f"icon_{size}x{size}.png"))
        if size <= 512:
            master.resize((size * 2, size * 2), Image.LANCZOS).save(
                os.path.join(iconset, f"icon_{size}x{size}@2x.png"))
    os.remove(os.path.join(iconset, "icon_1024x1024.png"))
    os.remove(os.path.join(iconset, "icon_64x64.png"))

    # The same renderings again for the asset catalog. Xcode builds read these
    # and Scripts/bundle.sh reads the .icns, so leaving one of them stale means
    # the two ways of building the app disagree about what it looks like.
    catalog = os.path.join(root, "Resources", "Assets.xcassets", "AppIcon.appiconset")
    if os.path.isdir(catalog):
        for size in [16, 32, 128, 256, 512]:
            master.resize((size, size), Image.LANCZOS).save(
                os.path.join(catalog, f"icon_{size}x{size}.png"))
            master.resize((size * 2, size * 2), Image.LANCZOS).save(
                os.path.join(catalog, f"icon_{size}x{size}@2x.png"))
        print("==> Resources/Assets.xcassets/AppIcon.appiconset")

    subprocess.run(
        ["iconutil", "-c", "icns", iconset,
         "-o", os.path.join(destination, "ideai.icns")],
        check=True,
    )
    print("==> Resources/Icon/ideai.icns")


if __name__ == "__main__":
    main()
