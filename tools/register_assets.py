#!/usr/bin/env python3
"""Registers files in data/assets.json without reformatting the hand-kept file.

Usage (from the project root):
    python3 tools/register_assets.py <group> <dir> [name ...]
        Adds / updates "<group>": {"<name>": "res://<dir>/<name>.png"} for the given names, or for
        every .png in <dir> (except files starting with "_") when no names are given.

Existing keys are updated in place, new keys are inserted at the top of the group, one per line,
matching the file's layout. Real art registered here overrides the generated placeholders in
data/assets_placeholders.json.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "data", "assets.json")


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    group, rel_dir = sys.argv[1], sys.argv[2].rstrip("/")
    names = sys.argv[3:] or sorted(f[:-4] for f in os.listdir(os.path.join(ROOT, rel_dir)) if f.endswith(".png") and not f.startswith("_"))
    text = open(ASSETS).read()
    m = re.search(r'^(\t)"%s": \{\n' % re.escape(group), text, re.M)
    if not m:
        raise SystemExit("group %s not found (add it to data/assets.json first)" % group)
    added = updated = 0
    for name in names:
        path = "res://%s/%s.png" % (rel_dir, name)
        line_pat = re.compile(r'^\t\t"%s": "[^"]*"' % re.escape(name), re.M)
        # Only search inside this group: from its opening line to the next top-level key.
        start = m.end()
        end_m = re.compile(r'^\t\}', re.M).search(text, start)
        block = text[start:end_m.start()]
        if line_pat.search(block):
            block = line_pat.sub('\t\t"%s": "%s"' % (name, path), block, count=1)
            updated += 1
        else:
            block = '\t\t"%s": "%s",\n' % (name, path) + block
            added += 1
        text = text[:start] + block + text[end_m.start():]
        m = re.search(r'^(\t)"%s": \{\n' % re.escape(group), text, re.M)
    json.loads(text)
    open(ASSETS, "w").write(text)
    print("%s: %d added, %d updated" % (group, added, updated))


if __name__ == "__main__":
    main()
