#!/usr/bin/env python3
"""Rebuild monster / boss sheets from PixelLab animations (dev tool, see docs/DECISIONS.md
"Character art pipeline").

usage: build_monster.py SOURCES_JSON WORK_DIR
SOURCES_JSON (e.g. tools/monsters_sources.json):
  {"anim_base": "https://.../file/pixellab-characters/<user>/",
   "monsters": {"ghoul": {"character": "<id>", "cell": 64, "out": "res://.../monsters/ghoul",
                          "mirror": {"west": "east", ...},
                          "anims": {"idle": {"src": "<animation id per direction>", "pick": [..], "fps": 5}, ...},
                          "groups": {"idle": {"south": "<animation id>", ...}, ...},
                          "derive": {"dash": "walk", "downed": ["death", -1]}}}}
Each game animation takes the picked frames of a PixelLab animation group ("src" names the
group), centred on the cell; mirrored directions are flipped copies. Prints the assets.json
entries (frame_size, feet_offset, height, anims).
"""
import json, os, subprocess, sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]


def curl(url, path):
    if not os.path.exists(path):
        subprocess.run(["curl", "-sf", "--retry", "6", "--retry-all-errors", "--retry-delay", "2", "-o", path, url], check=True)


def used_rect(path):
    r = subprocess.run(["godot", "--headless", "--path", PROJ, "-s", "tools/pixellab_used_rect.gd", "--", path],
                       capture_output=True, text=True)
    import re
    m = re.search(r"P: \((\d+), (\d+)\), S: \((\d+), (\d+)\)", r.stdout)
    return [int(g) for g in m.groups()]


def main():
    src = json.load(open(sys.argv[1]))
    work = sys.argv[2]
    os.makedirs(work, exist_ok=True)
    only = sys.argv[3:]
    entries = {}
    for name, mon in src["monsters"].items():
        if only and name not in only:
            continue
        cell = int(mon["cell"])
        mirror = {DIRS.index(d): DIRS.index(s) for d, s in mon.get("mirror", {}).items()}
        ops = []
        anims = {}
        bottoms = []
        tops = []
        for game_anim, spec in mon["anims"].items():
            group = mon["groups"][spec["src"]]
            rows = []
            n = 0
            for d in DIRS:
                if DIRS.index(d) in mirror or d not in group:
                    rows.append([])
                    continue
                frames = []
                for i in spec["pick"]:
                    p = os.path.join(work, f"{name}_{spec['src']}_{d}_{i}.png")
                    curl(f'{src["anim_base"]}{mon["character"]}/animations/{group[d]}/{d}/{i}.png', p)
                    frames.append(p)
                    if game_anim == "idle":
                        x, y, w, h = used_rect(p)
                        tops.append(y)
                        bottoms.append(y + h)
                rows.append(frames)
                n = len(frames)
            dst = f'{mon["out"]}/{game_anim}.png'
            ops.append({"op": "sheet", "rows": rows, "frames": n, "cell": cell, "dst": dst})
            if mirror:
                ops.append({"op": "mirror_rows", "src": dst, "cell": cell, "rows": {str(k): v for k, v in mirror.items()}})
            anims[game_anim] = {"frames": n, "fps": spec.get("fps", 10)}
        # Standing clips keep the idle feet row (v3 clips can sit a few px higher or lower).
        for game_anim in mon.get("align_to_idle", ["walk", "attack", "cast", "dash", "hit"]):
            if game_anim in mon["anims"] and game_anim != "idle":
                ops.append({"op": "align_feet", "src": f'{mon["out"]}/{game_anim}.png', "ref": f'{mon["out"]}/idle.png', "cell": cell})
        man = os.path.join(work, f"{name}_manifest.json")
        json.dump(ops, open(man, "w"))
        r = subprocess.run(["godot", "--headless", "--path", PROJ, "-s", "tools/pixellab_import.gd", "--", man],
                           cwd=PROJ, capture_output=True, text=True)
        print(name, [l for l in r.stdout.splitlines() if "pixellab_import" in l])
        canvas = int(mon.get("canvas", 48))
        pad = (cell - canvas) // 2
        bottom = max(bottoms)
        top = min(tops)
        entries[name] = {"path": mon["out"] + "/", "frame_size": cell, "feet_offset": cell - (pad + bottom),
                         "height": bottom - top, "anims": anims}
    print(json.dumps(entries))


main()
