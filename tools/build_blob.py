#!/usr/bin/env python3
"""Builds monster sheets for shapeless creatures (slimes, leeches, ink pools, wisps, ticks, rat
critters, sludge mounds) from ONE PixelLab sprite: every animation is made of squash / stretch /
bob / fade transforms of that sprite, the same on all 8 direction rows (rows facing west are
mirrored). Needs ImageMagick (`magick`). Prints the data/assets.json entry.

usage: build_blob.py SOURCE.png OUT_DIR CELL [--mirror-west | --faces-left] [--fly] [--scale=N]
  SOURCE.png    transparent sprite, feet / underside at the bottom of its content
  OUT_DIR       e.g. assets/sprites/pixellab/monsters/acid_slime
  CELL          frame size in px (the sprite is centred horizontally, feet 12 px above the bottom)
  --mirror-west flip the sprite on the W, SW and NW rows (for sprites that face right)
  --faces-left  flip the sprite on the E, SE and NE rows (for sprites that face left)
  --scale=N     scale the source first (percent, e.g. 60 for a small variant)
  --fly         hover: the idle / walk bob is a float instead of a squash (wisps)
"""
import json
import os
import subprocess
import sys
import tempfile

ROWS = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
WEST = {"south-west", "west", "north-west"}
EAST = {"south-east", "east", "north-east"}
FEET = 12

# Per animation: list of (scale_x %, scale_y %, lift px, opacity %) and fps.
ANIMS = {
    "idle": ([(100, 100, 0, 100), (102, 97, 0, 100), (104, 95, 0, 100), (102, 97, 0, 100)], 5),
    "walk": ([(100, 100, 0, 100), (106, 92, 0, 100), (96, 106, 2, 100), (94, 108, 3, 100),
              (98, 103, 1, 100), (106, 92, 0, 100)], 10),
    "attack": ([(100, 100, 0, 100), (110, 88, 0, 100), (90, 118, 3, 100), (114, 96, 1, 100), (104, 98, 0, 100)], 14),
    "cast": ([(100, 100, 0, 100), (96, 106, 1, 100), (92, 112, 3, 100), (96, 106, 1, 100)], 10),
    "dash": ([(112, 88, 0, 100), (118, 84, 1, 100), (112, 88, 0, 100)], 14),
    "hit": ([(112, 86, 0, 100), (96, 104, 0, 100)], 10),
    "downed": ([(120, 50, 0, 100), (122, 48, 0, 100)], 2),
    "death": ([(108, 90, 0, 100), (118, 70, 0, 95), (126, 50, 0, 80), (132, 34, 0, 60), (136, 24, 0, 35)], 8),
}
FLY = {
    "idle": ([(100, 100, 2, 100), (100, 100, 4, 100), (100, 100, 5, 100), (100, 100, 3, 100)], 5),
    "walk": ([(100, 100, 2, 100), (98, 102, 4, 100), (100, 100, 6, 100), (102, 98, 4, 100)], 10),
}


def run(args):
    subprocess.run(args, check=True)


def main():
    src, out, cell = sys.argv[1], sys.argv[2], int(sys.argv[3])
    flip_rows = WEST if "--mirror-west" in sys.argv else (EAST if "--faces-left" in sys.argv else set())
    scale = next((int(a.split("=")[1]) for a in sys.argv if a.startswith("--scale=")), 100)
    fly = "--fly" in sys.argv
    os.makedirs(out, exist_ok=True)
    tmp = tempfile.mkdtemp()
    trimmed = os.path.join(tmp, "src.png")
    run(["magick", src, "-trim", "+repage", "-filter", "point", "-resize", "%d%%" % scale, trimmed])
    w, h = [int(v) for v in subprocess.run(["magick", "identify", "-format", "%w %h", trimmed],
                                           capture_output=True, text=True, check=True).stdout.split()]
    anims = dict(ANIMS)
    if fly:
        anims.update(FLY)
    entry = {"path": "res://" + os.path.relpath(os.path.abspath(out), os.path.dirname(os.path.dirname(os.path.abspath(__file__)))) + "/",
             "frame_size": cell, "feet_offset": FEET, "height": h, "anims": {}}
    for name, (frames, fps) in anims.items():
        cells = {False: [], True: []}
        for i, (sx, sy, lift, alpha) in enumerate(frames):
            nw, nh = max(1, round(w * sx / 100)), max(1, round(h * sy / 100))
            for flip in (False, True):
                f = os.path.join(tmp, "%s_%d_%d.png" % (name, i, flip))
                x = (cell - nw) // 2
                y = cell - FEET - nh - lift
                cmd = ["magick", "-size", "%dx%d" % (cell, cell), "xc:none", "(", trimmed]
                if flip:
                    cmd += ["-flop"]
                cmd += ["-filter", "point", "-resize", "%dx%d!" % (nw, nh), "-channel", "A", "-evaluate", "multiply", "%.2f" % (alpha / 100.0), "+channel", ")",
                        "-geometry", "%+d%+d" % (x, y), "-compose", "over", "-composite", f]
                run(cmd)
                cells[flip].append(f)
        rows = []
        for r in ROWS:
            row = os.path.join(tmp, "%s_row_%s.png" % (name, r))
            run(["magick"] + cells[r in flip_rows] + ["+append", row])
            rows.append(row)
        run(["magick"] + rows + ["-append", os.path.join(out, name + ".png")])
        entry["anims"][name] = {"frames": len(frames), "fps": fps}
    print(json.dumps(entry))


if __name__ == "__main__":
    main()
