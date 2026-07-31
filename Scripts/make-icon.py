#!/usr/bin/env python3
"""Draws the app icon and builds Resources/Icon/ideai.icns.

Rendered rather than checked in as a binary blob so the artwork stays
reviewable and editable: the icon is a handful of shapes, and a diff of the
numbers that describe them says more than a diff of a PNG.

Run: python3 Scripts/make-icon.py
"""
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

# The window's own palette, so the icon and the app agree.
BACKGROUND_TOP = (43, 45, 48)
BACKGROUND_BOTTOM = (26, 27, 30)
CHEVRON = (110, 170, 240)
CARET = (219, 160, 74)


def squircle_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw() -> Image.Image:
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # Vertical gradient, one row at a time.
    gradient = Image.new("RGB", (1, SIZE))
    for y in range(SIZE):
        t = y / (SIZE - 1)
        gradient.putpixel((0, y), tuple(
            round(BACKGROUND_TOP[i] + (BACKGROUND_BOTTOM[i] - BACKGROUND_TOP[i]) * t)
            for i in range(3)
        ))
    background = gradient.resize((SIZE, SIZE)).convert("RGBA")
    image.paste(background, (0, 0), squircle_mask(SIZE, int(SIZE * 0.225)))

    draw = ImageDraw.Draw(image)

    # A prompt chevron and a caret: the two marks every editor and terminal
    # shares, and the only shapes that stay legible at 16 points.
    unit = SIZE / 1024
    # Heavier than looks right at full size: at 16 points the whole icon is
    # sixteen pixels across, and thin strokes there turn to grey mush.
    stroke = int(104 * unit)

    left = int(276 * unit)
    middle = int(494 * unit)
    top = int(306 * unit)
    bottom = int(718 * unit)
    draw.line([(left, top), (middle, SIZE // 2), (left, bottom)],
              fill=CHEVRON, width=stroke, joint="curve")
    # Rounded ends, which the line joint does not give the tips.
    for point in [(left, top), (left, bottom), (middle, SIZE // 2)]:
        radius = stroke // 2
        draw.ellipse([point[0] - radius, point[1] - radius,
                      point[0] + radius, point[1] + radius], fill=CHEVRON)

    caret_left = int(608 * unit)
    draw.rounded_rectangle(
        [caret_left, top, caret_left + int(160 * unit), bottom],
        radius=int(34 * unit),
        fill=CARET,
    )

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

    subprocess.run(
        ["iconutil", "-c", "icns", iconset,
         "-o", os.path.join(destination, "ideai.icns")],
        check=True,
    )
    print("==> Resources/Icon/ideai.icns")


if __name__ == "__main__":
    main()
