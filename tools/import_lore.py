#!/usr/bin/env python3
"""Imports the lore books (.design/lore_books/book_*.md) into data/lore_books.json.

Usage: python3 tools/import_lore.py [source_dir] [output_json]
Defaults: .design/lore_books -> data/lore_books.json (run from the project root).

Reproducible: the output is sorted by book number and only depends on the markdown files.
Every book becomes:
  {"id": "lore_001", "number": 1, "title", "origin", "biome", "classification": "standard" |
   "tome" | "legendary", "effect": {"mods": [{"stat", "value"}]} | {"talent_points", "stat_points"} | {},
   "effect_text", "text"}
The script fails loudly when a field or an effect string can't be parsed.
"""
import json
import os
import re
import sys

ORIGINS = {
    "The Forgotten Crypt": "crypt",
    "Sewers of Heresy": "sewers",
    "Infernal Foundry": "foundry",
    "The Shrouded Archives": "archives",
    "The Blighted Kurgan": "kurgan",
    "Ancient Lore": "ancient",
    "Transcendent Mystery": "transcendent",
}
CLASSES = {
    "Standard Lore": "standard",
    "Tome of Enlightenment": "tome",
    "Legendary Tome": "legendary",
}
# effect phrase -> (stat key in Stats, multiplier applied to the number)
STATS = {
    "strength": ("strength", 1),
    "stamina": ("stamina", 1),
    "agility": ("agility", 1),
    "intellect": ("intellect", 1),
    "armor": ("armor", 1),
    "max health": ("max_hp", 1),
    "max mana": ("max_resource", 1),
    "movement speed": ("move_speed", 1),
    "critical strike chance": ("crit_chance", 0.01),
    "leech": ("leech", 0.01),
    "dodge": ("dodge", 0.01),
}


def field(text, name, path):
    m = re.search(r"\*\*%s:\*\*\s*(.+?)\s*$" % re.escape(name), text, re.M)
    if not m:
        raise SystemExit("%s: missing field %s" % (path, name))
    return m.group(1).strip().strip("`").strip()


def parse_effect(s, path):
    if s.startswith("None"):
        return {}
    m = re.match(r"\+(\d+) Skill Point & \+(\d+) Stat Points", s)
    if m:
        return {"talent_points": int(m.group(1)), "stat_points": int(m.group(2))}
    body = re.sub(r"\s*\(Permanent[^)]*\)\s*$", "", s)
    mods = []
    for part in body.split(","):
        part = part.strip()
        m = re.match(r"\+(\d+(?:\.\d+)?)(%?) (.+)$", part)
        if not m:
            raise SystemExit("%s: can't parse effect part '%s'" % (path, part))
        name = m.group(3).strip().lower()
        if name not in STATS:
            raise SystemExit("%s: unknown stat '%s'" % (path, name))
        key, mult = STATS[name]
        value = float(m.group(1)) * mult
        mods.append({"stat": key, "value": round(value, 4) if mult != 1 else int(value)})
    return {"mods": mods}


def story(text, path):
    m = re.search(r"### In-Game Lore & Story\s*\n(.*?)\n---", text, re.S)
    if not m:
        raise SystemExit("%s: no story section" % path)
    lines = []
    for line in m.group(1).strip().split("\n"):
        line = line.strip()
        if line.startswith(">"):
            line = line[1:].strip()
        lines.append(line)
    out = "\n".join(lines).strip()
    # The quote is wrapped as *"..."*: drop the italics markers, keep the quotes.
    out = re.sub(r"^\*|\*$", "", out).strip()
    out = re.sub(r"\n\*|\*\n", "\n", out)
    return out


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else ".design/lore_books"
    dst = sys.argv[2] if len(sys.argv) > 2 else "data/lore_books.json"
    books = []
    for name in sorted(os.listdir(src)):
        if not re.match(r"book_\d{3}_.*\.md$", name):
            continue
        path = os.path.join(src, name)
        text = open(path, encoding="utf-8").read()
        title = re.search(r"^# (.+)$", text, re.M).group(1).strip()
        bid = field(text, "Book ID", path)
        origin = field(text, "Origin", path)
        cls = field(text, "Classification", path)
        eff_text = field(text, "Permanent Effect", path)
        if origin not in ORIGINS or cls not in CLASSES:
            raise SystemExit("%s: unknown origin/classification '%s' / '%s'" % (path, origin, cls))
        books.append({
            "id": bid, "number": int(bid.split("_")[1]), "title": title, "origin": origin,
            "biome": ORIGINS[origin], "classification": CLASSES[cls],
            "effect": parse_effect(eff_text, path), "effect_text": eff_text, "text": story(text, path),
        })
    books.sort(key=lambda b: b["number"])
    counts = {}
    for b in books:
        counts[b["classification"]] = counts.get(b["classification"], 0) + 1
    with open(dst, "w", encoding="utf-8") as f:
        f.write("[\n")
        f.write(",\n".join("\t" + json.dumps(b, ensure_ascii=False) for b in books))
        f.write("\n]\n")
    print("wrote %d books to %s: %s" % (len(books), dst, counts))


if __name__ == "__main__":
    main()
