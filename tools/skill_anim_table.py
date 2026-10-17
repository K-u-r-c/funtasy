#!/usr/bin/env python3
"""Prints the #19 skill -> animation table (Markdown) from data/skills/*.json and the weapon bases,
for docs/DECISIONS.md. "attack" / "cast" resolve through the main-hand weapon (attack_anim /
cast_anim), so they are listed per weapon.
usage: tools/skill_anim_table.py"""
import json, glob, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bases = {}
for f in glob.glob(os.path.join(ROOT, "data/items/bases/*.json")):
    b = json.load(open(f))
    if "attack_anim" in b:
        bases[b["id"]] = b
print("| Class | Skill | Animation |")
print("| --- | --- | --- |")
for cls in ["warrior", "ranger", "mage", "priest"]:
    weapons = sorted({k for k, b in bases.items() if cls in b.get("classes", [])})
    for s in json.load(open(os.path.join(ROOT, f"data/skills/{cls}.json"))):
        if s.get("passive"):
            continue
        a = s.get("anim", "attack")
        if a in ("attack", "cast"):
            key = "attack_anim" if a == "attack" else "cast_anim"
            per = sorted({f"{bases[w][key]}" for w in weapons})
            a = "weapon %s: %s" % (a, " / ".join(per))
        print(f"| {cls} | {s['name']} | {a} |")
