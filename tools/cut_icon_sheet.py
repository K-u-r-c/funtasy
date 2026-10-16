#!/usr/bin/env python3
"""Cuts a PixelLab icon sheet (a grid of icons in one image) into single icon files.

Usage (from the project root, needs ImageMagick `magick`):
    python3 tools/cut_icon_sheet.py <sheet.png> <cols> <rows> <out_dir> <name1> <name2> ... [--size 32]

Cells are read left to right, top to bottom; a name of "-" skips that cell. Each cell is cut
exactly (cell = image size / grid), then scaled with nearest-neighbour to --size (default: the
cell size, i.e. no scaling). The sheet itself is kept next to the icons as <out_dir>/_sheet_<n>.png
so a cut can be redone. Register the files in data/assets.json (icons.<name>) to use them.
"""
import os
import shutil
import subprocess
import sys


def main():
    args = sys.argv[1:]
    size = None
    if "--size" in args:
        i = args.index("--size")
        size = int(args[i + 1])
        del args[i:i + 2]
    if len(args) < 5:
        raise SystemExit(__doc__)
    sheet, cols, rows, out_dir = args[0], int(args[1]), int(args[2]), args[3]
    names = args[4:]
    os.makedirs(out_dir, exist_ok=True)
    w, h = (int(v) for v in subprocess.check_output(["magick", "identify", "-format", "%w %h", sheet]).decode().split())
    cw, ch = w // cols, h // rows
    keep = os.path.join(out_dir, "_sheet_%s.png" % os.path.splitext(os.path.basename(sheet))[0])
    if os.path.abspath(keep) != os.path.abspath(sheet):
        shutil.copyfile(sheet, keep)
    n = 0
    for idx, name in enumerate(names):
        if name == "-" or idx >= cols * rows:
            continue
        x, y = (idx % cols) * cw, (idx // cols) * ch
        cmd = ["magick", sheet, "-crop", "%dx%d+%d+%d" % (cw, ch, x, y), "+repage"]
        if size and size != cw:
            cmd += ["-filter", "point", "-resize", "%dx%d!" % (size, size)]
        cmd.append(os.path.join(out_dir, name + ".png"))
        subprocess.run(cmd, check=True)
        n += 1
    print("cut %d icons (%dx%d cells) into %s" % (n, cw, ch, out_dir))


if __name__ == "__main__":
    main()
