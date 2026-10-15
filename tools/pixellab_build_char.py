#!/usr/bin/env python3
"""Build game sheets from a PixelLab character archive (dev tool, see docs/DECISIONS.md "Final art").

usage: build_char.py CHAR_ID OUT_RES_DIR WORK_DIR MAPPING_JSON
MAPPING_JSON: {"idle": {"src": "idle"}, "dash": {"src": "walk", "fps": 14},
               "ghost": {"ghost_of": "idle"}, "downed": {"src": "death", "tail": 2}, ...}
Prints the assets.json entry (frame_size, feet_offset, anims overrides) as JSON.
"""
import json, os, subprocess, sys, urllib.request, zipfile

PROJ = "/home/kurc/Projects/GodotProjects/funtasy"
DIRS = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
BASE = {"idle": (4, 5), "walk": (6, 10), "attack": (4, 14), "cast": (4, 10), "dash": (3, 14),
        "hit": (2, 10), "downed": (2, 2), "death": (4, 8), "ghost": (4, 5)}

cid, out_dir, work, mapping_path = sys.argv[1:5]
mapping = json.load(open(mapping_path))
os.makedirs(work, exist_ok=True)
zpath = os.path.join(work, "char.zip")
urllib.request.urlretrieve(f"https://api.pixellab.ai/mcp/characters/{cid}/download", zpath)
x = os.path.join(work, "x")
with zipfile.ZipFile(zpath) as z:
    for n in z.namelist():
        if ".." in n or n.startswith("/"):
            raise SystemExit("unsafe path in archive: " + n)
    z.extractall(x)
meta = json.load(open(os.path.join(x, "metadata.json")))
state = meta["states"][0]
size = state["character"]["size"]["width"]
anims = state["frames"]["animations"]
# animation display names may differ in case; index lower-case
by_name = {k.lower(): v for k, v in anims.items()}
rot = state["frames"]["rotations"]

ops = []
entry_anims = {}
missing = []
for game_anim, spec in mapping.items():
    if "ghost_of" in spec:
        continue
    src = by_name.get(spec["src"].lower())
    if src is None:
        print(f"missing animation {spec['src']} (have {list(by_name)})", file=sys.stderr)
        sys.exit(2)
    rows = []
    for d in DIRS:
        frames = [os.path.join(x, p) for p in src.get(d, [])]
        if not frames:
            missing.append(f"{spec['src']}:{d}")
            frames = [os.path.join(x, rot[d])]
        if "tail" in spec:
            frames = frames[-spec["tail"]:]
        rows.append(frames)
    n = len(rows[2])
    base_frames, base_fps = BASE[game_anim]
    duration = base_frames / base_fps
    fps = spec.get("fps", round(n / duration, 1))
    ops.append({"op": "sheet", "rows": rows, "frames": n, "cell": size, "dst": f"{out_dir}/{game_anim}.png"})
    entry_anims[game_anim] = {"frames": n, "fps": fps}
for game_anim, spec in mapping.items():
    if "ghost_of" in spec:
        src_anim = spec["ghost_of"]
        ops.append({"op": "ghost", "src": f"{out_dir}/{src_anim}.png", "dst": f"{out_dir}/{game_anim}.png"})
        entry_anims[game_anim] = dict(entry_anims[src_anim])
man = os.path.join(work, "manifest.json")
json.dump(ops, open(man, "w"))
r = subprocess.run(["godot", "--headless", "--path", PROJ, "-s", "tools/pixellab_import.gd", "--", man],
                   cwd=PROJ, capture_output=True, text=True)
summary = [l for l in r.stdout.splitlines() if "pixellab_import" in l]
print("\n".join(summary), file=sys.stderr)
# feet offset from the south rotation: distance from the canvas bottom to the lowest pixel row
r2 = subprocess.run(["godot", "--headless", "-s", os.path.join(PROJ, "tools", "pixellab_used_rect.gd"), "--",
                     os.path.join(x, rot["south"])], capture_output=True, text=True)
line = [l for l in r2.stdout.splitlines() if "used" in l][0]
# "south.png (92, 92) used [P: (33, 13), S: (27, 66)]"
import re
m = re.search(r"P: \((\d+), (\d+)\), S: \((\d+), (\d+)\)", line)
py, sy = int(m.group(2)), int(m.group(4))
feet = size - (py + sy)
if missing:
    print("MISSING " + " ".join(missing), file=sys.stderr)
print(json.dumps({"missing": missing, "frame_size": size, "feet_offset": feet, "anims": entry_anims, "body_box": [int(m.group(1)), py, int(m.group(3)), sy]}))
