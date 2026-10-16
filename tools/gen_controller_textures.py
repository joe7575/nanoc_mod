#!/usr/bin/env python3
"""Generate the NanoC controller textures (Siemens-SPS-like look).

Writes:
  textures/nanoc_mod_controller.png            front panel overlay (128x128)
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
sampled per face from these regions: top/bottom/left/right strips + central
square (the back).

Run:  python3 tools/gen_controller_textures.py
"""

import os
from PIL import Image, ImageDraw, ImageFont

# Siemens-like palette (no readable brand name)
BODY = (17, 74, 112, 255)
BODY_HI = (42, 118, 164, 255)
BODY_LO = (9, 47, 74, 255)
LABEL = (206, 208, 212, 255)
LABEL_LO = (150, 154, 160, 255)
BLACK = (22, 22, 26, 255)
TEAL = (0, 168, 168, 255)
GREEN = (36, 146, 68, 255)
GREEN_LO = (16, 82, 40, 255)
TERM_HI = (60, 176, 96, 255)
AMBER = (222, 158, 40, 255)
RED = (196, 34, 48, 255)
DISPLAY = (8, 26, 40, 255)
SCREW = (206, 208, 204, 255)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "textures")

# central-square window of the nodebox front face, in normalized UV
UV_LO = 0.3125
UV_SIZE = 0.375


def front(path, n=128):
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

    # grey nameplate with teal brand mark (no readable brand)
    d.rectangle([4, 4, 28, 15], fill=LABEL, outline=LABEL_LO)
    d.rectangle([6, 6, 10, 10], fill=TEAL)
    f = ImageFont.load_default()
    d.text((12, 7), "nc", fill=BLACK, font=f)
    d.line([6, 13, 26, 13], fill=(176, 180, 186, 255))

    # display window
    d.rectangle([31, 4, 44, 15], fill=DISPLAY, outline=(120, 126, 134, 255))
    for yy in (7, 10, 13):
        d.line([33, yy, 42, yy], fill=(0, 170, 170, 190))

    # status LEDs
    for x, col in ((4, GREEN), (9, GREEN), (14, AMBER), (19, RED)):
        d.rectangle([x, 19, x + 2, 21], fill=col)

    # vents
    for yy in (26, 29, 32):
        d.rectangle([4, yy, 26, yy + 1], fill=(8, 40, 64, 255))

    # terminal strip
    d.rectangle([0, 38, s - 1, s - 1], fill=GREEN, outline=GREEN_LO)
    d.line([0, 38, s - 1, 38], fill=TERM_HI)
    step = s // 6
    for x in range(0, s, step):
        d.line([x, 39, x, s - 1], fill=GREEN_LO)
        d.ellipse([x + 1, 41, x + 3, 43], fill=SCREW)
        d.ellipse([x + 1, 44, x + 3, 46], fill=(178, 180, 176, 255))

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
    d.rectangle([fx0 + 3, fy0 + 3, fx0 + 22, fy0 + 12], fill=LABEL, outline=LABEL_LO)
    d.rectangle([fx0 + 5, fy0 + 5, fx0 + 8, fy0 + 8], fill=TEAL)
    f = ImageFont.load_default()
    d.text((fx0 + 10, fy0 + 5), "nc", fill=BLACK, font=f)
    d.rectangle([fx0 + 25, fy0 + 3, fx0 + 29, fy0 + 12], fill=DISPLAY)
    for x, col in ((fx0 + 4, GREEN), (fx0 + 8, GREEN), (fx0 + 12, AMBER)):
        d.rectangle([x, fy0 + 16, x + 2, fy0 + 18], fill=col)
    d.rectangle([fx0, fy1 - 8, fx1, fy1], fill=GREEN, outline=GREEN_LO)
    for x in range(fx0, fx1, 6):
        d.line([x, fy1 - 7, x, fy1], fill=GREEN_LO)
        d.ellipse([x + 1, fy1 - 5, x + 3, fy1 - 3], fill=SCREW)
    img.save(path)


front(os.path.join(OUT, "nanoc_mod_controller.png"))
side(os.path.join(OUT, "nanoc_mod_controller_side.png"))
inventory(os.path.join(OUT, "nanoc_mod_controller_inventory.png"))
print("wrote textures to", os.path.normpath(OUT))
