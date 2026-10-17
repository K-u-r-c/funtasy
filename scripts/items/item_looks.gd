class_name ItemLooks
extends RefCounted
## How an item looks (#20): its worn family (plate / mail / leather / cloth), its colour variant
## and the matching icon. Data: data/items/looks.json. The same variant recolours the worn sprite
## (assets/shaders/gear_variant.gdshader) and the icon (recolor_image), so they always match.

const SHADER := preload("res://assets/shaders/gear_variant.gdshader")

static var _icon_cache: Dictionary = {}
static var _legendary_cache: Dictionary = {}
static var _material_cache: Dictionary = {}


## Picks the family, appearance, icon and variant of a freshly generated armour / weapon item
## (seeded by `rng`, so the host's roll replicates with the item).
static func apply(item: Dictionary, rng: RandomNumberGenerator) -> void:
	var looks: Dictionary = GameData.item_looks
	var rarity := int(item.get("rarity", 1))
	var options: Array = looks.get("bases", {}).get(str(item.get("base", "")), [])
	var fams: Array = options.filter(func(o): return rarity >= int(o[1]) and rarity <= int(o[2])).map(func(o): return str(o[0]))
	if not fams.is_empty():
		var fam: String = fams[rng.randi_range(0, fams.size() - 1)]
		var spec: Array = looks.families.get(fam, {}).get(str(item.get("slot", "")), [])
		if not spec.is_empty():
			item.family = fam
			item.appearance = str(spec[0])
			if GameData.asset_exists(str(spec[1])):
				item.icon = str(spec[1])
	if not str(item.get("appearance", "")).is_empty():
		item.variant = default_variant(item)


## A legendary's look: the worn family its class wears for that slot (looks.json
## "legendary_families") and its own colours, taken from its icon so the hero wears what the
## inventory shows.
static func apply_legendary(item: Dictionary, lg: Dictionary) -> void:
	var looks: Dictionary = GameData.item_looks
	var slot := str(item.get("slot", ""))
	var by_class: Dictionary = looks.get("legendary_families", {}).get(str(lg.get("class", "")), {})
	var fam := str(by_class.get(slot, by_class.get("*", "")))
	var options: Array = looks.get("bases", {}).get(str(item.get("base", "")), [])
	if not options.any(func(o): return str(o[0]) == fam) and not options.is_empty():
		fam = str(options[-1][0])
	var spec: Array = looks.get("families", {}).get(fam, {}).get(slot, [])
	if not spec.is_empty():
		item.family = fam
		item.appearance = str(spec[0])
	if not str(item.get("appearance", "")).is_empty():
		item.look = {"variant": legendary_variant(str(lg.id), str(item.get("icon", "")))}


## Variant parameters from a legendary's icon: its dark / mid / light tones become the metal ramp,
## its main hue the colour of leather and cloth, its brightest saturated tone a glow.
static func legendary_variant(id: String, icon_key: String) -> Dictionary:
	if _legendary_cache.has(id):
		return _legendary_cache[id]
	var out := {"ramp": ["#3b2006", "#b37a1c", "#ffe596"], "metal_mix": 0.85, "sat_mult": 1.2, "val_mult": 1.05, "glow": "#ffcf6a40"}
	if GameData.asset_exists(icon_key):
		var img: Image = GameData.texture(icon_key).get_image()
		img.convert(Image.FORMAT_RGBA8)
		var cols: Array = []
		var hues := {}
		var accent := Color.BLACK
		for y in img.get_height():
			for x in img.get_width():
				var c: Color = img.get_pixel(x, y)
				if c.a < 0.5 or c.v < 0.15:
					continue
				cols.append(c)
				if c.s > 0.35:
					var hb := int(c.h * 12.0) % 12
					hues[hb] = int(hues.get(hb, 0)) + 1
					if c.v * c.s > accent.v * accent.s:
						accent = c
		if cols.size() >= 12:
			cols.sort_custom(func(a, b): return a.get_luminance() < b.get_luminance())
			var pick := func(f: float) -> Color: return cols[clampi(int(f * (cols.size() - 1)), 0, cols.size() - 1)]
			out.ramp = [pick.call(0.08).to_html(false), pick.call(0.5).to_html(false), pick.call(0.95).to_html(false)]
			if not hues.is_empty():
				var best: int = hues.keys()[0]
				for hb in hues:
					if int(hues[hb]) > int(hues[best]):
						best = hb
				out.hue_shift = fposmod((best + 0.5) / 12.0 - 0.07, 1.0)  # worn leather / cloth art is brown (~0.07)
			out.glow = Color(accent.r, accent.g, accent.b, 0.3).to_html(true)
	_legendary_cache[id] = out
	return out


## The variant an item shows: its own, else the one its family gives its rarity.
static func variant_of(item: Dictionary) -> String:
	if item.has("variant"):
		return str(item.variant)
	return default_variant(item) if not str(item.get("appearance", "")).is_empty() else ""


static func default_variant(item: Dictionary) -> String:
	var fam := str(item.get("family", "weapon" if item.get("kind", "") in ["weapon", "offhand"] else "plate"))
	var row: Array = GameData.item_looks.get("family_variants", {}).get(fam, [])
	if row.is_empty():
		return ""
	return str(row[clampi(int(item.get("rarity", 1)) - 1, 0, row.size() - 1)])


## Variant parameters: a named variant of looks.json, or an item's own (legendary) dictionary.
static func params(variant: Variant) -> Dictionary:
	if variant is Dictionary:
		return variant
	return GameData.item_looks.get("variants", {}).get(str(variant), {})


## A worn / held layer's material for a variant (null = drawn as is).
static func material(variant: Variant) -> ShaderMaterial:
	var p := params(variant)
	if p.is_empty():
		return null
	var key := JSON.stringify(p)
	if _material_cache.has(key):
		return _material_cache[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	var ramp: Array = p.get("ramp", ["#1a1a1a", "#808080", "#e6e6e6"])
	m.set_shader_parameter("ramp_dark", Color.from_string(str(ramp[0]), Color.BLACK))
	m.set_shader_parameter("ramp_mid", Color.from_string(str(ramp[1]), Color.GRAY))
	m.set_shader_parameter("ramp_light", Color.from_string(str(ramp[2]), Color.WHITE))
	m.set_shader_parameter("metal_mix", float(p.get("metal_mix", 0.0)))
	m.set_shader_parameter("hue_shift", float(p.get("hue_shift", 0.0)))
	m.set_shader_parameter("sat_mult", float(p.get("sat_mult", 1.0)))
	m.set_shader_parameter("val_mult", float(p.get("val_mult", 1.0)))
	m.set_shader_parameter("glow_color", Color.from_string(str(p.get("glow", "#00000000")), Color(0, 0, 0, 0)))
	_material_cache[key] = m
	return m


## The worn appearance actually drawn: the item's own, or its fallback while its art is missing.
static func drawn_appearance(appearance: String, gender: String) -> String:
	if not CharacterSprite.gear_key(appearance, gender).is_empty():
		return appearance
	return str(GameData.item_looks.get("fallback", {}).get(appearance, appearance))


## An item's icon, recoloured with its variant (cached per icon and variant).
static func icon(item: Dictionary) -> Texture2D:
	var key := str(item.get("icon", "items.backpack"))
	if not GameData.asset_exists(key):
		return null
	var base: Texture2D = GameData.texture(key)
	# A legendary's colours come from its own icon: the icon is shown as drawn.
	if item.has("legendary"):
		return base
	var variant: Variant = variant_of(item)
	var p := params(variant)
	if p.is_empty() or base == null:
		return base
	var ck := key + "|" + JSON.stringify(p)
	if not _icon_cache.has(ck):
		var img: Image = base.get_image()
		img.convert(Image.FORMAT_RGBA8)
		_icon_cache[ck] = ImageTexture.create_from_image(recolor_image(img, p))
	return _icon_cache[ck]


## CPU version of gear_variant.gdshader (same maths) for icons.
static func recolor_image(src: Image, p: Dictionary) -> Image:
	var img := src.duplicate()
	var ramp: Array = p.get("ramp", ["#1a1a1a", "#808080", "#e6e6e6"])
	var rd := Color.from_string(str(ramp[0]), Color.BLACK)
	var rm := Color.from_string(str(ramp[1]), Color.GRAY)
	var rl := Color.from_string(str(ramp[2]), Color.WHITE)
	var mix := float(p.get("metal_mix", 0.0))
	var hs := float(p.get("hue_shift", 0.0))
	var sm := float(p.get("sat_mult", 1.0))
	var vm := float(p.get("val_mult", 1.0))
	var glow := Color.from_string(str(p.get("glow", "#00000000")), Color(0, 0, 0, 0))
	for y in img.get_height():
		for x in img.get_width():
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.0 or c.v <= 0.12:
				continue
			var out: Color = c
			if c.s < 0.28:
				var l: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
				var r: Color = rd.lerp(rm, l * 2.0) if l < 0.5 else rm.lerp(rl, (l - 0.5) * 2.0)
				out = c.lerp(r, mix)
			else:
				out = Color.from_hsv(fposmod(c.h + hs, 1.0), clampf(c.s * sm, 0.0, 1.0), clampf(c.v * vm, 0.0, 1.0))
			var g: float = glow.a * smoothstep(0.55, 0.95, c.v)
			out = Color(out.r + glow.r * g, out.g + glow.g * g, out.b + glow.b * g, c.a)
			img.set_pixel(x, y, out)
	return img
