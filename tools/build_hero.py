#!/usr/bin/env python3
"""Rebuild a hero body + worn/held gear sheets from PixelLab sources (dev tool, see
docs/DECISIONS.md "Character art pipeline").

usage: build_hero.py SOURCES_JSON WORK_DIR [--skip-download]
SOURCES_JSON (e.g. tools/hero_male_sources.json):
  {"config": "tools/hero_male.json",           # gear_cut / bake_gear config (paths, palette)
   "frame": 48, "cell": 64,                    # PixelLab canvas, game cell (frames centred)
   "clips": [["idle", 2], ...],                # frames per animation, in transfer order (batch 1)
   "clips2": [["cast", 5], ...],               # optional second batch (outfit "jobs2")
   "picks": {"idle": [0, 2], ...},             # which template frames make each clip
   "anim_base": "https://.../animations/",     # PixelLab animation frame URL prefix
   "anims": {"idle": {"south": "<animation id>", ...}, ...},
   "mirror": {"west": "east", ...},            # directions drawn as mirrors of others
   "strip_glow": ["cast"],                     # clips whose template draws a spell flame
   "ghost": {"anim_base": ".../<ghost state>/animations/", "anims": {dir: id}, "pick": [..],
             "fix_colors": ["#rrggbb"]},            # optional: stray template pixels to repaint
   "outfits": {"plate": {"src_dir": "res://...", "jobs": {"south": "<transfer job id>", ...},
                         "jobs2": {...}}}}
Steps: download frames -> body sheets (+ mirrored rows, ghost) -> outfit sheets -> gear_cut
(worn layers, hide masks, derived animations) -> bake_gear (held items).
"""
import json, os, subprocess, sys

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]


def curl(url, path):
    if not os.path.exists(path):
        subprocess.run(["curl", "-sf", "--retry", "6", "--retry-all-errors", "--retry-delay", "2", "-o", path, url], check=True)


def godot(*args):
    r = subprocess.run(["godot", "--headless", "--path", PROJ, *args], cwd=PROJ, capture_output=True, text=True)
    out = [l for l in r.stdout.splitlines() + r.stderr.splitlines()
           if l.startswith(("pixellab_import", "gear_cut", "bake_gear")) or "ERROR" in l]
    print("\n".join(out))


def main():
    src = json.load(open(sys.argv[1]))
    work = sys.argv[2]
    os.makedirs(work, exist_ok=True)
    cfg = json.load(open(os.path.join(PROJ, src["config"])))
    cell = int(src.get("cell", 64))
    mirror = {DIRS.index(d): DIRS.index(s) for d, s in src.get("mirror", {}).items()}
    drawn = [d for d in DIRS if d not in src.get("mirror", {})]
    ops = []
    batches = [("clips", "jobs")] + ([("clips2", "jobs2")] if src.get("clips2") else [])
    # Body: the picked template frames, centred on the game cell.
    for anim, n in [c for key, _ in batches for c in src[key]]:
        rows = []
        for d in DIRS:
            if d not in drawn:
                rows.append([])
                continue
            frames = []
            for i in src["picks"][anim]:
                p = os.path.join(work, f"base_{anim}_{d}_{i}.png")
                curl(f'{src["anim_base"]}{src["anims"][anim][d]}/{d}/{i}.png', p)
                frames.append(p)
            rows.append(frames)
        dst = f'{cfg["body_dir"]}/{anim}.png'
        ops.append({"op": "sheet", "rows": rows, "frames": n, "cell": cell, "dst": dst})
        if anim in src.get("strip_glow", []):
            ops.append({"op": "strip_glow", "src": dst})
        if mirror:
            ops.append({"op": "mirror_rows", "src": dst, "cell": cell, "rows": {str(k): v for k, v in mirror.items()}})
    # Outfits: one transfer per drawn direction, frames in clip order.
    # One transfer job per drawn direction and batch; its frames are the batch's clips in order.
    for name, outfit in src.get("outfits", {}).items():
        for clips_key, jobs_key in batches:
            local = {}
            for d, job in outfit.get(jobs_key, {}).items():
                total = sum(n for _, n in src[clips_key])
                local[d] = []
                for i in range(total):
                    p = os.path.join(work, f"{name}_{jobs_key}_{d}_{i}.png")
                    curl(f"https://api.pixellab.ai/mcp/images/{job}/download?index={i}", p)
                    local[d].append(p)
            start = 0
            for anim, n in src[clips_key]:
                rows = [local[d][start:start + n] if d in local else [] for d in DIRS]
                dst = f'{outfit["src_dir"]}/{anim}.png'
                ops.append({"op": "sheet", "rows": rows, "frames": n, "cell": cell, "dst": dst})
                if anim in src.get("strip_glow", []):
                    ops.append({"op": "strip_glow", "src": dst})
                if mirror:
                    ops.append({"op": "mirror_rows", "src": dst, "cell": cell, "rows": {str(k): v for k, v in mirror.items()}})
                start += n
    man = os.path.join(work, "hero_manifest.json")
    json.dump(ops, open(man, "w"))
    godot("-s", "tools/pixellab_import.gd", "--", man)
    godot("-s", "tools/gear_cut.gd", "--", src["config"])
    # Ghost: the drawn ghost state's idle when the sources list it, else a pale copy of the
    # body idle. No gear is drawn on ghosts.
    if src.get("ghost"):
        gh = src["ghost"]
        rows = []
        for d in DIRS:
            if DIRS.index(d) in mirror or d not in gh["anims"]:
                rows.append([])
                continue
            frames = []
            for i in gh["pick"]:
                p = os.path.join(work, f"ghost_{d}_{i}.png")
                curl(f'{gh["anim_base"]}{gh["anims"][d]}/{d}/{i}.png', p)
                frames.append(p)
            rows.append(frames)
        dst = f'{cfg["body_dir"]}/ghost.png'
        ghost = [{"op": "sheet", "rows": rows, "frames": len(gh["pick"]), "cell": cell, "dst": dst}]
        if mirror:
            ghost.append({"op": "mirror_rows", "src": dst, "cell": cell, "rows": {str(k): v for k, v in mirror.items()}})
        ghost.append({"op": "align_feet", "src": dst, "ref": f'{cfg["body_dir"]}/idle.png', "cell": cell})
        if gh.get("fix_colors"):
            ghost.append({"op": "replace_color", "src": dst, "colors": gh["fix_colors"]})
    else:
        ghost = [{"op": "ghost", "src": f'{cfg["body_dir"]}/idle.png', "dst": f'{cfg["body_dir"]}/ghost.png'}]
    json.dump(ghost, open(man, "w"))
    godot("-s", "tools/pixellab_import.gd", "--", man)
    godot("-s", "tools/bake_gear.gd", "--", src["config"])


main()
