#!/usr/bin/env python3
"""Generate the NanoC controller textures (Siemens-SPS-like look).

Writes:
  textures/nanoc_mod_controller.png            front panel overlay (256x256)
  textures/nanoc_mod_controller_side.png       housing sides / back (64x64)
  textures/nanoc_mod_controller_inventory.png  item icon (48x48)

IMPORTANT - nodebox UV window
-----------------------------
The controller node is a nodebox smaller than a full node:

    node_box = {{-6/32, -6/32, 12/32, 6/32, 6/32, 16/32}}

Luanti derives the texture coordinates from the box position within the node
(client/content_mapblock.cpp: generateCuboidTextureCoords). With the box above,
the front face samples only the *central* region of the texture:

    x, y in [0.3125 .. 0.6875]   (central 37.5% square)

So the front artwork must be drawn exactly into that central square, and the
rest of the canvas is unused padding (transparent here). The side texture is
sampled per face from: top/bottom/left/right strips + central square (the back).

Run:  python3 tools/gen_controller_textures.py
"""

import os
from PIL import Image, ImageDraw

# Siemens-like palette (no readable brand name)
BODY = (17, 74, 112, 255)
BODY_HI = (42, 118, 164, 255)
BODY_LO = (9, 47, 74, 255)
LABEL = (206, 208, 212, 255)
LABEL_LO = (150, 154, 160, 255)
BLACK = (22, 22, 26, 255)
WHITE = (238, 238, 240, 255)
TEAL = (0, 168, 168, 255)
GREEN = (36, 146, 68, 255)
GREEN_LO = (16, 82, 40, 255)
TERM_HI = (60, 176, 96, 255)
AMBER = (222, 158, 40, 255)
RED = (196, 34, 48, 255)
DISPLAY = (8, 26, 40, 255)
SCREW_HI = (196, 198, 194, 255)
SCREW_LO = (96, 98, 96, 255)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "textures")

# central-square window of the nodebox front face, in normalized UV
UV_LO = 0.3125
UV_SIZE = 0.375

# tiny 3x5 pixel font
GLYPHS = {
    "N": ["101", "111", "101", "101", "101"],
    "C": ["011", "100", "100", "100", "011"],
    "0": ["010", "101", "101", "101", "010"],
    "1": ["010", "110", "010", "010", "010"],
    "2": ["011", "001", "010", "100", "111"],
    "R": ["110", "101", "110", "101", "101"],
    "U": ["101", "101", "101", "101", "011"],
    "-": ["000", "000", "111", "000", "000"],
    "n": ["100", "110", "101", "101", "101"],
    "c": ["011", "100", "100", "100", "011"],
}


def text(d, x, y, s, color, spacing=1, scale=1):
    cx = x
    for ch in s:
        g = GLYPHS.get(ch)
        if g:
            for ry, row in enumerate(g):
                for rx, bit in enumerate(row):
                    if bit == "1":
                        px, py = cx + rx * scale, y + ry * scale
                        d.rectangle([px, py, px + scale - 1, py + scale - 1], fill=color)
        cx += (3 + spacing) * scale
    return cx


def screw(d, cx, cy, r):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=SCREW_HI)
    d.ellipse([cx - r + 1, cy - r + 1, cx + r - 1, cy + r - 1], fill=(150, 152, 150, 255))
    d.line([cx - r + 1, cy, cx + r - 1, cy], fill=SCREW_LO)


def front(path, n=256):
    s = int(round(UV_SIZE * n))
    c = int(round(UV_LO * n))
    art = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)
    d.rectangle([0, 0, s - 1, s - 1], fill=BODY)
    d.line([0, 0, s - 1, 0], fill=BODY_HI)
    d.line([0, 1, s - 1, 1], fill=BODY_HI)
    d.line([0, 0, 0, s - 1], fill=BODY_HI)
    d.line([0, s - 1, s - 1, s - 1], fill=BODY_LO)
    d.line([s - 1, 0, s - 1, s - 1], fill=BODY_LO)

    # grey nameplate with teal brand mark + model text (no readable brand)
    d.rectangle([6, 6, 62, 34], fill=LABEL, outline=LABEL_LO)
    d.rectangle([9, 9, 25, 27], fill=TEAL)
    text(d, 14, 16, "n", WHITE)
    text(d, 18, 16, "c", WHITE)
    text(d, 29, 13, "NC-1200", BLACK)
    d.line([9, 31, 59, 31], fill=(176, 180, 186, 255))

    # display window
    d.rectangle([66, 6, 90, 34], fill=DISPLAY, outline=(120, 126, 134, 255))
    for yy in (12, 18, 24, 30):
        d.line([69, yy, 87, yy], fill=(0, 170, 170, 190))

    # status LEDs + RUN label
    for x, col in ((8, GREEN), (16, GREEN), (24, AMBER), (32, RED)):
        d.rectangle([x, 44, x + 3, 47], fill=col)
    text(d, 42, 44, "RUN", (205, 208, 205, 255))

    # vents
    for yy in (56, 60, 64):
        d.rectangle([8, yy, 44, yy + 1], fill=(8, 40, 64, 255))

    # terminal strip
    d.rectangle([0, 74, s - 1, s - 1], fill=GREEN, outline=GREEN_LO)
    d.line([0, 74, s - 1, 74], fill=TERM_HI)
    step = s // 8
    for x in range(0, s, step):
        d.line([x, 75, x, s - 1], fill=GREEN_LO)
        screw(d, x + step // 2, 88, 4)

    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    img.paste(art, (c, c))
    img.save(path)


def side(path, n=64):
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, n - 1, n - 1], fill=BODY)
    d.line([0, 0, n - 1, 0], fill=BODY_HI)
    d.line([0, 1, n - 1, 1], fill=BODY_HI)
    d.line([0, n - 1, n - 1, n - 1], fill=BODY_LO)
    d.line([n - 1, 0, n - 1, n - 1], fill=BODY_LO)
    c = int(round(UV_LO * n))
    s = int(round(UV_SIZE * n))
    for yy in range(c + 4, c + s - 2, 4):          # back face: vents
        d.rectangle([c + 3, yy, c + s - 4, yy + 1], fill=(8, 40, 64, 255))
    img.save(path)


def inventory(path, n=48):
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    fx0, fy0, fx1, fy1 = 6, 8, 36, 42
    off = 5
    d.polygon([(fx0, fy0), (fx0 + off, fy0 - off),
               (fx1 + off, fy0 - off), (fx1, fy0)], fill=BODY_HI)
    d.polygon([(fx1, fy0), (fx1 + off, fy0 - off),
               (fx1 + off, fy1 - off), (fx1, fy1)], fill=BODY_LO)
    d.rectangle([fx0, fy0, fx1, fy1], fill=BODY, outline=BODY_LO)
    d.rectangle([fx0 + 3, fy0 + 3, fx0 + 23, fy0 + 13], fill=LABEL, outline=LABEL_LO)
    d.rectangle([fx0 + 5, fy0 + 5, fx0 + 16, fy0 + 11], fill=TEAL)
    text(d, fx0 + 7, fy0 + 6, "n", WHITE)
    text(d, fx0 + 11, fy0 + 6, "c", WHITE)
    d.rectangle([fx0 + 25, fy0 + 3, fx0 + 29, fy0 + 13], fill=DISPLAY)
    for x, col in ((fx0 + 4, GREEN), (fx0 + 8, GREEN), (fx0 + 12, AMBER)):
        d.rectangle([x, fy0 + 17, x + 2, fy0 + 19], fill=col)
    d.rectangle([fx0, fy1 - 8, fx1, fy1], fill=GREEN, outline=GREEN_LO)
    for x in range(fx0, fx1, 6):
        d.line([x, fy1 - 7, x, fy1], fill=GREEN_LO)
        screw(d, x + 3, fy1 - 4, 2)
    img.save(path)


front(os.path.join(OUT, "nanoc_mod_controller.png"))
side(os.path.join(OUT, "nanoc_mod_controller_side.png"))
inventory(os.path.join(OUT, "nanoc_mod_controller_inventory.png"))
print("wrote textures to", os.path.normpath(OUT))
