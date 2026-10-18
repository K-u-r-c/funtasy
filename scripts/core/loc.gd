class_name Loc
extends RefCounted
## Translation helpers (#32). Every player-facing string goes through here (or Object.tr): keys
## are the English source text, the Polish lives in data/i18n/translations.csv (Godot CSV
## translation, registered in project.godot). Texts sent between peers travel as an English key
## plus arguments and are translated by the peer that shows them.


## The translation of `s` in the current language (`s` itself when there is none).
static func t(s: String) -> String:
	if s.is_empty():
		return s
	return String(TranslationServer.translate(s))


## `key` translated, then formatted with `args`; string arguments are translated too (names,
## stats, item names), a stat modifier {stat, value} becomes "+3 Strength" and an array of
## them a comma list.
static func f(key: String, args: Array = []) -> String:
	var a: Array = []
	for v in args:
		if v is String:
			a.append(name(v))
		elif v is Dictionary and v.has("stat"):
			a.append(Merchants.mod_text(v))
		elif v is Array:
			a.append(", ".join(v.map(func(m): return Merchants.mod_text(m) if m is Dictionary else name(str(m)))))
		else:
			a.append(v)
	var k := t(key)
	return k % a if not a.is_empty() else k


## "%d point" / "%d points" with `n` filled in. A translation of the plural key may hold
## several forms split by "|": Polish uses "few|many" (2-4 punkty, 5 punktów).
static func plural(n: int, one: String, other: String) -> String:
	if n == 1:
		return t(one) % n if "%d" in one else t(one)
	var forms := t(other).split("|")
	var form := forms[0]
	if forms.size() > 1:
		var few := n % 10 >= 2 and n % 10 <= 4 and not (n % 100 >= 12 and n % 100 <= 14)
		form = forms[0] if few else forms[1]
	return form % n if "%d" in form else form


## A name: a plain key, or an item name built from a base and a suffix ("Greataxe of the
## Falcon" -> base + suffix translated separately), or a backpack ("Pack (16 slots)").
static func name(s: String) -> String:
	var direct := t(s)
	if direct != s or s.is_empty():
		return direct
	var best := ""
	for id in GameData.item_bases:
		var bn := str(GameData.item_bases[id].get("name", ""))
		if not bn.is_empty() and s.begins_with(bn + " ") and bn.length() > best.length():
			best = bn
	if best.is_empty():
		# An elite monster: "Vampiric Frenzied Ghoul" = modifier names + the monster name.
		for id in GameData.elite_modifiers:
			var en := str(GameData.elite_modifiers[id].get("name", ""))
			if not en.is_empty() and s.begins_with(en + " "):
				return "%s %s" % [t(en), name(s.substr(en.length() + 1))]
		return s
	var rest := s.substr(best.length() + 1)
	if rest.begins_with("(") and rest.ends_with(")"):
		return "%s %s" % [t(best), f("(%d slots)", [int(rest.trim_prefix("(").to_int())])]
	return "%s %s" % [t(best), t(rest)]


## The display name of an item dictionary in the current language.
static func item_name(item: Dictionary) -> String:
	return name(str(item.get("name", "?")))
