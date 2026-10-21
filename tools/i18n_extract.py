#!/usr/bin/env python3
"""Collects every player-facing string into data/i18n/translations.csv (#32).

Keys are the English source text. The script finds them in two places:
  - code (scripts/, autoload/): string literals that read like text (filters below,
    exact exceptions in tools/i18n_ignore.txt),
  - data (data/**/*.json): the text fields (name, title, description, text, ...), the
    affix stat names, game setting options and composite interaction prompts.
Existing Polish translations are kept; keys no longer found are dropped; new keys get an
empty Polish entry (the i18n test fails until they are filled in).

  python3 tools/i18n_extract.py           # rewrite the CSV
  python3 tools/i18n_extract.py --check   # exit 1 when the CSV is out of date
  python3 tools/i18n_extract.py --missing # print keys without Polish as JSON
"""
import csv
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV_PATH = os.path.join(ROOT, "data", "i18n", "translations.csv")
IGNORE_PATH = os.path.join(ROOT, "tools", "i18n_ignore.txt")

CODE_DIRS = ["scripts", "autoload"]
CODE_SKIP_FILES = {"autoload/dev_auto.gd", "scripts/ui/ui_theme.gd"}
# Lines that never carry player-facing text.
SKIP_LINE = re.compile(
    r"^\s*#|print\(|printerr\(|push_error|push_warning|assert\(|check\(|_err\(|errors\.append|"
    r"NetSync\.make|get_node|has_node|find_child|set_meta|get_meta|has_meta|add_to_group|"
    r"is_in_group|get_nodes_in_group|get_first_node_in_group|\.name = \"|OS\.get_environment|"
    r"begins_with\(\"--|ClassDB|has_method|\.call\(\"|_test_fail|test_problem")
TEXT_DICT = re.compile(r"^const [A-Z_]*(TEXT|NAMES|LABELS) := \{")
DICT_VALUE = re.compile(r'"(?:[^"\\]|\\.)*"\s*:\s*"((?:[^"\\]|\\.)*)"')
LOC_CALL = re.compile(r'Loc\.(?:t|f|plural)\(\s*"(?:[^"\\]|\\.)*"(?:\s*,\s*"(?:[^"\\]|\\.)*")?')
LITERAL = re.compile(r'(?<![&^])"((?:[^"\\]|\\.)*)"')
# Files whose lower-case fragments are shown ("around you", "hold up to ..."); elsewhere a
# lower-case literal is an id or a test diagnostic.
LOWERCASE_OK = ("scripts/ui/", "scripts/items/item_generator.gd")

DATA_SKIP = {"assets.json", "assets_placeholders.json", "balance.json", "doors.json"}
# Keys built in code that the literal filter cannot tell from non-text ("%s %s" is the item
# kind line: rarity + slot, which Polish separates to avoid adjective agreement).
EXTRA_KEYS = ["%s %s"]
TEXT_FIELDS = {"name", "title", "description", "text", "origin", "effect_text", "label", "overrun", "danger", "reward",
               "tracker", "tracker_seen", "tracker_key", "cost_text",
               "message", "affix", "suffix", "group"}
# Id fields shown capitalized ("undead" -> "Undead", like GDScript's String.capitalize()).
CAP_FIELDS = {"element", "school", "creature_type", "target_creature", "flags"}


def capitalize(s):
    return " ".join(w.capitalize() for w in s.split("_"))


def unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def strip_comment(line):
    """The line without a trailing # comment (a # inside a string stays)."""
    quote = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\" and quote:
            i += 2
            continue
        if c == '"':
            quote = not quote
        elif c == "#" and not quote:
            return line[:i]
        i += 1
    return line


def looks_like_text(s, path):
    if not re.search(r"[A-Za-z]{2}", s):
        return False
    if re.match(r"^(res|user|uid)://", s) or s.startswith(("#", "--", "*")):
        return False
    if re.fullmatch(r"[a-z0-9_.:/\-<>|+*]+", s):  # ids, paths, input codes
        return False
    if re.search(r"[A-Za-z]_%d|_%s|^[a-z]+:%s|\w:\w", s):  # node names, sync paths
        return False
    if re.fullmatch(r"[A-Z][a-z]+[A-Z]\w*", s):  # CamelCase node / class names
        return False
    # A sentence around a filled-in name ("%s falls - ...", "+%d gold") is text even though its
    # first word is lower case.
    if re.match(r"^[\s+\-(]*%[sd] [a-z]+", s) or re.match(r"^[+\-]?%d [a-z]", s):
        return True
    first = re.sub(r"^[\s%+\-(.,:\\n\d]+[a-z]?\s*", "", s)
    if first[:1].islower() and not path.startswith(LOWERCASE_OK):
        return False
    return True


def code_keys(ignore):
    keys = []
    for top in CODE_DIRS:
        for dp, _dn, fn in sorted(os.walk(os.path.join(ROOT, top))):
            for f in sorted(fn):
                if not f.endswith(".gd"):
                    continue
                rel = os.path.relpath(os.path.join(dp, f), ROOT)
                if rel in CODE_SKIP_FILES:
                    continue
                in_text_dict = False
                for line in open(os.path.join(dp, f), encoding="utf-8"):
                    # Values of a const ..._TEXT / _NAMES / _LABELS dictionary are shown through
                    # Loc.t, even single lower-case words ("poisons").
                    if TEXT_DICT.match(line):
                        in_text_dict = True
                    if in_text_dict:
                        for m in DICT_VALUE.finditer(strip_comment(line)):
                            v = unescape(m.group(1))
                            if v not in ignore and re.search(r"[A-Za-z]{2}", v):
                                keys.append(v)
                        if "}" in strip_comment(line):
                            in_text_dict = False
                    if SKIP_LINE.search(line):
                        continue
                    code = strip_comment(line)
                    for m in LITERAL.finditer(code):
                        s = unescape(m.group(1))
                        if s in ignore or not looks_like_text(s, rel):
                            continue
                        keys.append(s)
                    # Whatever goes straight into Loc.t / Loc.f / Loc.plural is a key, even a
                    # lower-case word ("resets") or a fragment starting with a space.
                    for m in LOC_CALL.finditer(code):
                        for lit in LITERAL.finditer(m.group(0)):
                            s = unescape(lit.group(1))
                            if s not in ignore and re.search(r"[A-Za-z]{2}", s):
                                keys.append(s)
    return keys


def _walk(o, out, key=None):
    if isinstance(o, dict):
        for k, v in o.items():
            if k.startswith("_"):
                continue
            if k == "stat_names" and isinstance(v, dict):
                out.extend(str(x) for x in v.values())
            elif k == "options" and isinstance(v, list):
                out.extend(str(x) for x in v if isinstance(x, str))
            elif k in CAP_FIELDS and isinstance(v, (str, list)):
                out.extend(capitalize(str(x)) for x in (v if isinstance(v, list) else [v]))
            elif k in TEXT_FIELDS and isinstance(v, str):
                if re.search(r"[A-Za-z]", v) and (" " in v or v[:1].isupper()):
                    out.append(v)
            else:
                _walk(v, out, k)
    elif isinstance(o, list):
        for v in o:
            _walk(v, out, key)


def data_keys():
    keys = []
    data = os.path.join(ROOT, "data")
    for dp, _dn, fn in sorted(os.walk(data)):
        for f in sorted(fn):
            if not f.endswith(".json") or f in DATA_SKIP:
                continue
            with open(os.path.join(dp, f), encoding="utf-8") as fh:
                _walk(json.load(fh), keys)
    # Interaction prompts are built from a prop's verb and name (scripts/dungeon/prop.gd).
    with open(os.path.join(data, "props.json"), encoding="utf-8") as fh:
        props = json.load(fh)
    for p in props.values():
        if not isinstance(p, dict) or not (p.get("interactable") or p.get("npc") or p.get("gate")):
            continue
        name = str(p.get("name", ""))
        verb = str(p.get("verb", "Open"))
        keys.append("%s %s" % (verb, name if ("npc" in p or "gate" in p) else name.lower()))
    # Gear names (#64): the suffix pools, every quality prefix with its gendered forms, and each
    # item base's grammatical gender ("Sword [gender]" -> m / f / n / pl) the prefix agrees with.
    with open(os.path.join(data, "items", "affixes.json"), encoding="utf-8") as fh:
        affixes = json.load(fh)
    for pool in affixes.get("suffix_pools", {}).values():
        keys.extend(pool)
    for q in affixes.get("qualities", []):
        for pre in q.get("prefixes", []):
            keys.extend([pre] + ["%s [%s]" % (pre, g) for g in ("f", "n", "pl")])
    bases = os.path.join(data, "items", "bases")
    for f in sorted(os.listdir(bases)):
        if f.endswith(".json"):
            with open(os.path.join(bases, f), encoding="utf-8") as fh:
                b = json.load(fh)
            if b.get("name") and b.get("kind") != "backpack":
                keys.append("%s [gender]" % b["name"])
    # Hero body names (assets.json is otherwise only paths).
    with open(os.path.join(data, "assets.json"), encoding="utf-8") as fh:
        genders = json.load(fh).get("characters", {}).get("genders", {})
    keys.extend(str(g.get("name", "")) for g in genders.values() if g.get("name"))
    return keys


def read_csv():
    out = {}
    if os.path.exists(CSV_PATH):
        with open(CSV_PATH, encoding="utf-8", newline="") as fh:
            for row in list(csv.reader(fh))[1:]:
                if row:
                    out[row[0]] = row[1] if len(row) > 1 else ""
    return out


def render(keys, old):
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\n", quoting=csv.QUOTE_MINIMAL)
    w.writerow(["keys", "pl"])
    for k in keys:
        w.writerow([k, old.get(k, "")])
    return buf.getvalue()


# GDScript format placeholders (no space flag, so "5% damage" is plain text).
SPEC = re.compile(r"%[-+0]*\d*(?:\.\d+)?[scdoxXfv%]")


def validate(keys, old):
    """Polish entries that would break at runtime: missing, or with other format specifiers
    than the key (GDScript's % has no positional arguments, so the order must match)."""
    problems = []
    for k in keys:
        pl = old.get(k, "")
        if not pl:
            problems.append("no Polish: %r" % k[:70])
            continue
        want = SPEC.findall(k)
        for form in pl.split("|") if "|" in pl and "|" not in k else [pl]:
            if SPEC.findall(form) != want:
                problems.append("format %s != %s: %r" % (SPEC.findall(form), want, k[:70]))
    return problems


def main():
    ignore = set()
    if os.path.exists(IGNORE_PATH):
        ignore = {l.rstrip("\n") for l in open(IGNORE_PATH, encoding="utf-8") if l.strip() and not l.startswith("# ")}
    seen = {}
    for k in code_keys(ignore) + data_keys() + EXTRA_KEYS:
        if k.strip() and k not in seen and k not in ignore:
            seen[k] = True
    keys = list(seen)
    old = read_csv()
    text = render(keys, old)
    if "--missing" in sys.argv:
        print(json.dumps([k for k in keys if not old.get(k)], ensure_ascii=False, indent=1))
        return
    current = open(CSV_PATH, encoding="utf-8").read() if os.path.exists(CSV_PATH) else ""
    if "--check" in sys.argv:
        problems = validate(keys, old)
        if current != text:
            problems.insert(0, "translations.csv is out of date: run python3 tools/i18n_extract.py")
        for p in problems[:40]:
            print(p)
        if problems:
            print("%d translation problems" % len(problems))
            sys.exit(1)
        return
    os.makedirs(os.path.dirname(CSV_PATH), exist_ok=True)
    with open(CSV_PATH, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    missing = sum(1 for k in keys if not old.get(k))
    print("%d keys, %d without Polish" % (len(keys), missing))


if __name__ == "__main__":
    main()
