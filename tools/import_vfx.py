#!/usr/bin/env python3
"""Imports a PixelLab vfx_workbench export (spritesheet PNG + JSON) as a one-row strip.

Usage (from the project root, needs Pillow):
    python3 tools/import_vfx.py <export_base_url_or_dir> <export_name> <asset_key> [--loop] [--skip N]

<export_base_url_or_dir> is the "download" URL the export printed (or a local directory holding
<export_name>.png and .json). Writes assets/sprites/pixellab/fx/<asset_key>.png (frames left to
right, as CombatFx._anim_sprite reads them) and registers "fx.<asset_key>" in data/assets.json
with frames, fps, the effect's anchor (pixel of the effect's origin inside a frame) and loop.
Blank trailing frames are dropped (one is kept as a clean end for one-shots).
"""
import io
import json
import os
import re
import sys
import urllib.request

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def fetch(base, name, ext):
    if base.startswith("http"):
        with urllib.request.urlopen(base.rstrip("/") + "/" + name + ext) as r:
            return r.read()
    with open(os.path.join(base, name + ext), "rb") as f:
        return f.read()


def main():
    argv = sys.argv[1:]
    skip = 0
    if "--skip" in argv:
        i = argv.index("--skip")
        skip = int(argv[i + 1])
        del argv[i:i + 2]
    args = [a for a in argv if not a.startswith("--")]
    loop = "--loop" in argv
    if len(args) != 3:
        raise SystemExit(__doc__)
    base, name, key = args
    meta = json.loads(fetch(base, name, ".json"))
    sheet = Image.open(io.BytesIO(fetch(base, name, ".png"))).convert("RGBA")
    frames = meta["frames"]
    w, h = frames[0]["frame"]["w"], frames[0]["frame"]["h"]
    cells = [sheet.crop((f["frame"]["x"], f["frame"]["y"], f["frame"]["x"] + w, f["frame"]["y"] + h)) for f in frames][skip:]
    if not loop:
        while len(cells) > 2 and cells[-1].getbbox() is None and cells[-2].getbbox() is None:
            cells.pop()
    strip = Image.new("RGBA", (w * len(cells), h))
    for i, c in enumerate(cells):
        strip.paste(c, (i * w, 0))
    out_dir = os.path.join(ROOT, "assets", "sprites", "pixellab", "fx")
    os.makedirs(out_dir, exist_ok=True)
    strip.save(os.path.join(out_dir, key + ".png"))
    fps = round(1000.0 / max(1, frames[0].get("duration", 83)))
    pv = frames[0].get("pivot", {"x": 0.5, "y": 0.5})
    entry = {"path": "res://assets/sprites/pixellab/fx/%s.png" % key, "frames": len(cells), "fps": fps,
             "anchor": [round(pv["x"] * w), round(pv["y"] * h)], "loop": loop}
    path = os.path.join(ROOT, "data", "assets.json")
    text = open(path, encoding="utf-8").read()
    line = '\t\t"%s": %s,' % (key, json.dumps(entry))
    pat = re.compile(r'^\t\t"%s": .*$' % re.escape(key), re.M)
    if pat.search(text):
        text = pat.sub(line, text)
    else:
        anchor = '\t"fx": {\n'
        if anchor not in text:
            raise SystemExit("no fx section in data/assets.json")
        text = text.replace(anchor, anchor + line + "\n", 1)
    json.loads(text)
    open(path, "w", encoding="utf-8").write(text)
    print("fx.%s: %d frames %dx%d @ %d fps, anchor %s%s" % (key, len(cells), w, h, fps, entry["anchor"], " loop" if loop else ""))


if __name__ == "__main__":
    main()
