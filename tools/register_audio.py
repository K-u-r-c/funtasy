#!/usr/bin/env python3
"""Hooks your own audio files (Suno music, recorded SFX) into data/assets.json.

Usage (from the project root):
    python3 tools/register_audio.py

Drop files named after their registry key into
    assets/audio/music/<key>.ogg | .mp3 | .wav    (e.g. assets/audio/music/boss_morvath.ogg)
    assets/audio/sfx/<key>.ogg | .mp3 | .wav      (e.g. assets/audio/sfx/shriek.wav)
and run this script: every matching key in the "music" / "sfx" groups of data/assets.json is pointed
at your file (it overrides the generated placeholder). Keys and the prompts used to write them are
listed in docs/SUNO_PROMPTS.md. Files are never moved or deleted. Then open the project once in the
editor (or run `godot --headless --import`) so Godot imports them.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "data", "assets.json")
EXTS = (".ogg", ".mp3", ".wav")


def known_keys(group):
    keys = set()
    for path in (ASSETS, os.path.join(ROOT, "data", "assets_placeholders.json")):
        if os.path.exists(path):
            keys |= set(json.load(open(path)).get(group, {}).keys())
    spec = os.path.join(ROOT, "tools", "placeholder_icons.json")
    if os.path.exists(spec):
        keys |= {k.split(".", 1)[1] for k in json.load(open(spec)) if k.startswith(group + ".")}
    return keys


def main():
    text = open(ASSETS).read()
    done = 0
    for group in ("music", "sfx"):
        folder = os.path.join(ROOT, "assets", "audio", group)
        keys = known_keys(group)
        for f in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
            name, ext = os.path.splitext(f)
            if ext.lower() not in EXTS or name not in keys:
                continue
            res = "res://assets/audio/%s/%s" % (group, f)
            m = re.search(r'^\t"%s": \{\n' % group, text, re.M)
            start = m.end()
            end = re.compile(r"^\t\}", re.M).search(text, start).start()
            block = text[start:end]
            pat = re.compile(r'^\t\t"%s": "[^"]*"' % re.escape(name), re.M)
            if pat.search(block):
                block = pat.sub('\t\t"%s": "%s"' % (name, res), block, count=1)
            else:
                block = '\t\t"%s": "%s",\n' % (name, res) + block
            text = text[:start] + block + text[end:]
            print("%s.%s -> %s" % (group, name, res))
            done += 1
    json.loads(text)
    open(ASSETS, "w").write(text)
    print("%d audio keys registered" % done)


if __name__ == "__main__":
    main()
