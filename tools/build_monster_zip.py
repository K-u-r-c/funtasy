#!/usr/bin/env python3
"""Builds monster / boss sheets from a PixelLab character download (the zip of its rotations and
named animations). The cheap pipeline for the biome monsters: three template animations (walk,
attack, death) on 5 drawn directions, the other 3 mirrored; idle and hit are taken from those
clips. Prints the data/assets.json entry.

usage: build_monster_zip.py CHARACTER_ID OUT_DIR WORK_DIR [CELL] [--attack=NAME]
  CHARACTER_ID  PixelLab character id (its animations named walk / attack / death)
  OUT_DIR       e.g. res://assets/sprites/pixellab/monsters/plague_ratman
  CELL          frame size (default 64)
"""
import glob
import json
import os
import subprocess
import sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
MIRROR = {"west": "east", "north-west": "north-east", "south-west": "south-east"}
# game animation -> (zip animation, picked frames or None for all, fps)
ANIMS = {
    "idle": ("walk", [0, 0, 4, 4], 3),
    "walk": ("walk", None, 12),
    "attack": ("attack", None, 14),
    "cast": ("attack", None, 12),
    "dash": ("walk", None, 16),
    "hit": ("death", [0, 1], 10),
    "downed": ("death", [-1, -1], 2),
    "death": ("death", None, 10),
}


def used_rect(path):
    r = subprocess.run(["godot", "--headless", "--path", PROJ, "-s", "tools/pixellab_used_rect.gd", "--", path],
                       capture_output=True, text=True)
    import re
    m = re.search(r"P: \((\d+), (\d+)\), S: \((\d+), (\d+)\)", r.stdout)
    return [int(g) for g in m.groups()]


def main():
    char, out, work = sys.argv[1], sys.argv[2], sys.argv[3]
    cell = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4].isdigit() else 64
    attack = next((a.split("=")[1] for a in sys.argv if a.startswith("--attack=")), "attack")
    name = out.rstrip("/").split("/")[-1]
    zdir = os.path.join(work, name + "_zip")
    zp = os.path.join(work, name + ".zip")
    subprocess.run(["curl", "-sfL", "--retry", "6", "-o", zp, "https://api.pixellab.ai/mcp/characters/%s/download" % char], check=True)
    subprocess.run(["rm", "-rf", zdir], check=True)
    subprocess.run(["unzip", "-q", "-o", zp, "-d", zdir], check=True)
    root = glob.glob(os.path.join(zdir, "*", "animations"))[0]
    ops = []
    anims = {}
    tops, bottoms = [], []
    for game_anim, (src, pick, fps) in ANIMS.items():
        src = attack if src == "attack" else src
        rows = []
        n = 0
        for d in DIRS:
            folder = os.path.join(root, src, d)
            if d in MIRROR or not os.path.isdir(folder):
                rows.append([])
                continue
            files = sorted(glob.glob(os.path.join(folder, "frame_*.png")))
            idx = pick if pick is not None else list(range(len(files)))
            frames = [files[i] for i in idx]
            if game_anim == "walk":
                x, y, w, h = used_rect(frames[0])
                tops.append(y)
                bottoms.append(y + h)
            rows.append(frames)
            n = len(frames)
        dst = "%s/%s.png" % (out.rstrip("/"), game_anim)
        ops.append({"op": "sheet", "rows": rows, "frames": n, "cell": cell, "dst": dst})
        ops.append({"op": "mirror_rows", "src": dst, "cell": cell, "rows": {str(DIRS.index(k)): DIRS.index(v) for k, v in MIRROR.items()}})
        anims[game_anim] = {"frames": n, "fps": fps}
    for game_anim in ["idle", "attack", "cast", "dash", "hit"]:
        ops.append({"op": "align_feet", "src": "%s/%s.png" % (out.rstrip("/"), game_anim), "ref": "%s/walk.png" % out.rstrip("/"), "cell": cell})
    man = os.path.join(work, name + "_manifest.json")
    json.dump(ops, open(man, "w"))
    r = subprocess.run(["godot", "--headless", "--path", PROJ, "-s", "tools/pixellab_import.gd", "--", man],
                       cwd=PROJ, capture_output=True, text=True)
    errs = [l for l in r.stdout.splitlines() + r.stderr.splitlines() if "ERROR" in l]
    if errs:
        print("\n".join(errs[:5]), file=sys.stderr)
    canvas = int(subprocess.run(["magick", "identify", "-format", "%w", glob.glob(os.path.join(root, "walk", "south", "frame_000.png"))[0]],
                                capture_output=True, text=True).stdout)
    pad = (cell - canvas) // 2
    entry = {"path": out.rstrip("/") + "/", "frame_size": cell, "feet_offset": cell - (pad + max(bottoms)),
             "height": max(bottoms) - min(tops), "anims": anims}
    print(json.dumps(entry))


main()
