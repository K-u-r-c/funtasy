#!/usr/bin/env python3
"""Hero art pipeline v2 (#18 / #19, DECISIONS "#16 / #18 / #19"): the 75-frame animation set from a
PixelLab character download, outfits by transfer_outfit in 15-frame batches.

usage: build_hero_v2.py SOURCES_JSON WORK_DIR STEP
  frames  download the base character zip, write the picked frames of every clip and drawn
          direction (64 px, centred like the game cell) to WORK_DIR/base/
  upload  upload each batch's frames per drawn direction (needs PIXELLAB_UPLOAD_URL, the URL
          from the MCP tool get_upload_url) -> WORK_DIR/uploads.json {batch: {dir: [upload refs]}}
          The transfers are then started with the MCP tool transfer_outfit(frame_urls=refs,
          reference_image_url=<outfit state rotation of that direction>), and their job ids
          written to SOURCES "outfits" -> <name> -> "jobs" -> "<batch>" -> {dir: job}.
  sheets  download the transfers, write the body, ghost and outfit sheets (mirrored rows for the
          3 undrawn directions), then run tools/gear_cut.gd and tools/bake_gear.gd.

SOURCES_JSON (tools/hero_<gender>_v2.json):
  {"config": "tools/hero_male.json", "character": "<base character id>", "cell": 64,
   "drawn": ["south", "south-east", "east", "north-east", "north"],
   "mirror": {"west": "east", "north-west": "north-east", "south-west": "south-east"},
   "clips": {"<game anim>": {"from": "<zip animation folder>", "pick": [frame indices],
                              "pick_dir": {"<direction>": [same count, other frames]},
                              "from_dir": {"<direction>": "<other zip animation folder>"}}, ...},
   "batches": [["walk", "idle", "hit"], ...],           # 15 frames each
   "strip_glow": ["cast"],                              # clips whose frames may show spell glow
   "ghost": {"from": "ghost", "state": "Ghost", "pick": [...]},
   "outfits": {"plate": {"state": "Plate", "src_dir": "res://assets/sprites/pixellab/gear_src/male_plate",
                         "jobs": {"0": {"south": "<job id>", ...}, ...}}}}
"""
import json
import os
import subprocess
import sys
import zipfile

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]


def run(*args):
    subprocess.run(list(args), check=True)


def curl(url, path):
    if not os.path.exists(path):
        run("curl", "-sfL", "--retry", "6", "--retry-all-errors", "--retry-delay", "2", "-o", path, url)


def godot(*args):
    r = subprocess.run(["godot", "--headless", "--path", PROJ, *args], cwd=PROJ, capture_output=True, text=True)
    out = [l for l in r.stdout.splitlines() + r.stderr.splitlines()
           if l.startswith(("pixellab_import", "gear_cut", "bake_gear")) or "ERROR" in l]
    print("\n".join(out))


def base_path(work, anim, d, k):
    return os.path.join(work, "base", f"{anim}_{d}_{k}.png")


def step_frames(src, work):
    zp = os.path.join(work, "character.zip")
    if os.path.exists(zp):
        os.remove(zp)
    curl("https://api.pixellab.ai/mcp/characters/%s/download" % src["character"], zp)
    zdir = os.path.join(work, "zip")
    with zipfile.ZipFile(zp) as z:
        z.extractall(zdir)
    meta = json.load(open(os.path.join(zdir, "metadata.json")))
    states = {s["folder"]: s for s in meta["states"]}
    os.makedirs(os.path.join(work, "base"), exist_ok=True)
    os.makedirs(os.path.join(work, "full"), exist_ok=True)
    base = states[src.get("state", "Idle")]
    jobs = []
    for anim, clip in src["clips"].items():
        for d in src["drawn"]:
            # "from_dir": another source clip for one direction (a re-roll).
            frames = base["frames"]["animations"][clip.get("from_dir", {}).get(d, clip["from"])]
            if d not in frames:
                sys.exit(f"missing {clip['from']} {d}")
            for k, i in enumerate(clip.get("pick_dir", {}).get(d, clip["pick"])):
                jobs.append((os.path.join(zdir, frames[d][i]), base_path(work, anim, d, k)))
            # The whole clip too: bake_gear follows the hands frame by frame on it (--track).
            for i, fp in enumerate(frames[d]):
                jobs.append((os.path.join(zdir, fp), os.path.join(work, "full", f"{anim}_{d}_{i}.png")))
            full_len = len(frames[d])
            src.setdefault("_full", {}).setdefault(anim, {})[d] = full_len
    gh = src.get("ghost")
    if gh:
        frames = states[gh["state"]]["frames"]["animations"][gh["from"]]
        for d in src["drawn"]:
            for k, i in enumerate(gh["pick"]):
                jobs.append((os.path.join(zdir, frames[d][i]), base_path(work, "ghost", d, k)))
    # Every frame centred on a 64 px canvas: 48 px template frames get an 8 px border, v3
    # frames are already 64 px with the character where the centred rotation is.
    for a, b in jobs:
        run("magick", a, "-background", "none", "-gravity", "center", "-extent", "%dx%d" % (src["cell"], src["cell"]), b)
    json.dump(src["_full"], open(os.path.join(work, "full_len.json"), "w"))
    # Spell glow / stray specks off the picked frames before they go to the outfit transfers.
    ops = []
    for anim in src.get("strip_glow", []):
        for d in src["drawn"]:
            for k in range(len(src["clips"][anim]["pick"])):
                ops.append({"op": "strip_glow", "src": base_path(work, anim, d, k), "cell": src["cell"], "specks": 30})
    man = os.path.join(work, "glow_manifest.json")
    json.dump(ops, open(man, "w"))
    godot("-s", "tools/pixellab_import.gd", "--", man)
    print("frames: %d written" % len(jobs))


def step_upload(src, work):
    url = os.environ["PIXELLAB_UPLOAD_URL"]
    path = os.path.join(work, "uploads.json")
    out = json.load(open(path)) if os.path.exists(path) else {}
    for bi, batch in enumerate(src["batches"]):
        for d in src["drawn"]:
            if out.get(str(bi), {}).get(d):
                continue
            refs = []
            for anim in batch:
                for k in range(len(src["clips"][anim]["pick"])):
                    r = subprocess.run(["curl", "-sS", "-F", "file=@" + base_path(work, anim, d, k), url], capture_output=True, text=True, check=True)
                    refs.append(json.loads(r.stdout)["ref"])
            out.setdefault(str(bi), {})[d] = refs
            json.dump(out, open(path, "w"), indent=1)
    print("uploads: %s" % path)


def step_sheets(src, work):
    cfg = json.load(open(os.path.join(PROJ, src["config"])))
    cell = src["cell"]
    mirror = {str(DIRS.index(d)): DIRS.index(s) for d, s in src["mirror"].items()}
    ops = []

    def sheet(rows, n, dst, anim):
        ops.append({"op": "sheet", "rows": rows, "frames": n, "cell": cell, "dst": dst})
        if anim in src.get("strip_glow", []):
            ops.append({"op": "strip_glow", "src": dst, "cell": cell})
        ops.append({"op": "mirror_rows", "src": dst, "cell": cell, "rows": mirror})

    anims = list(src["clips"].keys()) + (["ghost"] if src.get("ghost") else [])
    for anim in anims:
        n = len(src["ghost"]["pick"]) if anim == "ghost" else len(src["clips"][anim]["pick"])
        rows = [[base_path(work, anim, d, k) for k in range(n)] if d in src["drawn"] else [] for d in DIRS]
        sheet(rows, n, f'{cfg["body_dir"]}/{anim}.png', anim)
    for name, outfit in src.get("outfits", {}).items():
        local = {}
        for bi, batch in enumerate(src["batches"]):
            for d, job in outfit.get("jobs", {}).get(str(bi), {}).items():
                total = sum(len(src["clips"][a]["pick"]) for a in batch)
                files = []
                for i in range(total):
                    p = os.path.join(work, "outfit", f"{name}_{bi}_{d}_{i}.png")
                    os.makedirs(os.path.dirname(p), exist_ok=True)
                    curl(f"https://api.pixellab.ai/mcp/images/{job}/download?index={i}", p)
                    files.append(p)
                start = 0
                for anim in batch:
                    n = len(src["clips"][anim]["pick"])
                    local.setdefault(anim, {})[d] = files[start:start + n]
                    start += n
        for anim, per_dir in local.items():
            n = len(src["clips"][anim]["pick"])
            rows = [per_dir.get(d, []) for d in DIRS]
            sheet(rows, n, f'{outfit["src_dir"]}/{anim}.png', anim)
    # Full-clip body sheets + the picks, for bake_gear's hand tracking.
    full_len = json.load(open(os.path.join(work, "full_len.json")))
    track = {"dir": os.path.join(work, "track"), "picks": {}}
    for anim, clip in src["clips"].items():
        n = max(full_len[anim].values())
        rows = [[os.path.join(work, "full", f"{anim}_{d}_{i}.png") for i in range(full_len[anim][d])] if d in src["drawn"] else [] for d in DIRS]
        ops.append({"op": "sheet", "rows": rows, "frames": n, "cell": cell, "dst": os.path.join(track["dir"], anim + ".png")})
        ops.append({"op": "mirror_rows", "src": os.path.join(track["dir"], anim + ".png"), "cell": cell, "rows": mirror})
        picks = []
        for d in DIRS:
            sd = src["mirror"].get(d, d)
            picks.append(clip.get("pick_dir", {}).get(sd, clip["pick"]))
        track["picks"][anim] = picks
    os.makedirs(track["dir"], exist_ok=True)
    json.dump(track, open(os.path.join(work, "track.json"), "w"))
    man = os.path.join(work, "manifest.json")
    json.dump(ops, open(man, "w"))
    godot("-s", "tools/pixellab_import.gd", "--", man)
    ghost_fix = [{"op": "align_feet", "src": f'{cfg["body_dir"]}/ghost.png', "ref": f'{cfg["body_dir"]}/idle.png', "cell": cell}]
    if src.get("ghost", {}).get("fix_colors"):
        ghost_fix.append({"op": "replace_color", "src": f'{cfg["body_dir"]}/ghost.png', "colors": src["ghost"]["fix_colors"]})
    json.dump(ghost_fix, open(man, "w"))
    godot("-s", "tools/pixellab_import.gd", "--", man)
    done = [n for n, o in src.get("outfits", {}).items() if o.get("jobs")]
    if done:
        # Cut only the outfits that have their transfers (the others keep their layers).
        cut_cfg = dict(cfg)
        cut_cfg["outfits"] = {n: o for n, o in cfg["outfits"].items() if n in done}
        cut_path = os.path.join(work, "gear_cut_config.json")
        json.dump(cut_cfg, open(cut_path, "w"))
        godot("-s", "tools/gear_cut.gd", "--", cut_path)
    else:
        # Body-only preview (no transfers yet): align the feet like gear_cut would.
        json.dump([{"op": "align_feet", "src": f'{cfg["body_dir"]}/{a}.png', "ref": f'{cfg["body_dir"]}/{r}.png', "cell": cell, "max": 4}
                   for a, r in cfg.get("align", {}).items()], open(man, "w"))
        godot("-s", "tools/pixellab_import.gd", "--", man)
    godot("-s", "tools/bake_gear.gd", "--", src["config"], "--track=" + os.path.join(work, "track.json"))


def main():
    src = json.load(open(sys.argv[1]))
    work = sys.argv[2]
    os.makedirs(work, exist_ok=True)
    {"frames": step_frames, "upload": step_upload, "sheets": step_sheets}[sys.argv[3]](src, work)


main()
