class_name CharacterSprite
extends Node2D
## Layered 8-direction character renderer. Each layer (body, one per equipment slot) is an
## AnimatedSprite2D built from the sprite sheets registered in data/assets.json, so gear changes
## the look by swapping a layer, and final Pixellab art drops in without code changes.
## Animations are named "<anim>_<dir>" with dir 0..7 = E, SE, S, SW, W, NW, N, NE.
## Worn pieces whose entry has "hide": true come with hide masks (<path>hide/<anim>.png, same
## layout): the body layer's shader drops the body pixels they cover (tools/gear_cut.gd).

const HIDE_SLOTS := ["head", "chest", "legs", "boots", "gloves"]
const BACK := "_back"  ## suffix of a held item's under-the-body layer (and of its frames key)
const BODY_HIDE_SHADER := preload("res://assets/shaders/body_hide.gdshader")

static var _frames_cache: Dictionary = {}

var anim := "idle"
var dir_index := 2
var _layers: Dictionary = {}  ## layer slot -> AnimatedSprite2D
var _layer_keys: Dictionary = {}  ## layer slot -> registry key
var _frame_size := 64
var _height := 0.0  ## visible body height in px (asset entry "height"), for bars and names above
var _order: Array = []
var _one_shot := false


func _init() -> void:
	_order = GameData.assets.get("characters", {}).get("layer_order", ["body"])


## One worn / held piece from a look entry [appearance, tint html, variant?] (Inventory.appearance
## format): the gender's art for it (or its fallback while the family isn't drawn), tinted and
## recoloured by its variant (#20).
func set_look_layer(slot: String, entry: Array, gender: String) -> void:
	var app := ItemLooks.drawn_appearance(str(entry[0]), gender)
	set_layer(slot, gear_key(app, gender), Color.from_string(str(entry[1]), Color.WHITE) if entry.size() > 1 else Color.WHITE)
	var mat: ShaderMaterial = ItemLooks.material(entry[2]) if entry.size() > 2 else null
	for s2 in [slot, slot + BACK]:
		if _layers.has(s2):
			_layers[s2].material = mat


## Sets (or clears with "") the art of one layer. `key` is a path into data/assets.json such as
## "characters.layers.weapon_sword" or "monsters.ghoul".
func set_layer(slot: String, key: String, tint: Color = Color.WHITE) -> void:
	if key.is_empty():
		if _layers.has(slot):
			# Out of the tree at once: a queued node would still draw this frame, and a layer
			# re-added in the same frame would get a renamed node next to it (#15).
			for s2 in [slot, slot + BACK]:
				if _layers.has(s2):
					var old: AnimatedSprite2D = _layers[s2]
					remove_child(old)
					old.queue_free()
					_layers.erase(s2)
					_layer_keys.erase(s2)
			_update_hide()
		return
	var spr: AnimatedSprite2D = _layers.get(slot)
	if spr == null:
		spr = AnimatedSprite2D.new()
		spr.name = slot
		spr.light_mask = LightLayers.SELF_LIT
		add_child(spr)
		_layers[slot] = spr
		_sort_layers()
	spr.modulate = tint
	if slot == "body" and spr.material == null:
		var mat := ShaderMaterial.new()
		mat.shader = BODY_HIDE_SHADER
		spr.material = mat
	if _layer_keys.get(slot, "") != key:
		_layer_keys[slot] = key
		spr.sprite_frames = _frames_for(key)
		var entry := GameData.asset_entry(key)
		_frame_size = int(entry.get("frame_size", GameData.assets.characters.frame_size))
		var feet := int(entry.get("feet_offset", GameData.assets.characters.feet_offset))
		spr.offset = Vector2(0, -_frame_size / 2.0 + feet)
		if slot == "body" or _height <= 0.0:
			_height = float(entry.get("height", (_frame_size - feet) * 0.75))
	_play_layer(spr)
	_sync_to_body(spr)
	if slot != "body":
		_update_hide()
		_set_back_layer(slot, key, tint)


## Held items come as two sheets (#16): the part over the body and, in "back/", the part the body
## hides (`tools/bake_gear.gd`). The back part is a second layer under the body.
func _set_back_layer(slot: String, key: String, tint: Color) -> void:
	var back := slot + BACK
	var has_back := bool(GameData.asset_entry(key).get("back", false))
	if not has_back:
		if _layers.has(back):
			var old: AnimatedSprite2D = _layers[back]
			remove_child(old)
			old.queue_free()
			_layers.erase(back)
			_layer_keys.erase(back)
		return
	var spr: AnimatedSprite2D = _layers.get(back)
	if spr == null:
		spr = AnimatedSprite2D.new()
		spr.name = back
		spr.light_mask = LightLayers.SELF_LIT
		add_child(spr)
		_layers[back] = spr
	spr.modulate = tint
	if _layer_keys.get(back, "") != key + BACK:
		_layer_keys[back] = key + BACK
		spr.sprite_frames = _frames_for(key + BACK)
		spr.offset = _layers[slot].offset
	_sort_layers()
	_play_layer(spr)
	_sync_to_body(spr)


## Points the body shader at the current animation's hide masks of the worn pieces.
func _update_hide() -> void:
	var body: AnimatedSprite2D = _layers.get("body")
	if body == null or body.material == null:
		return
	var mat: ShaderMaterial = body.material
	for slot in HIDE_SLOTS:
		var tex: Texture2D = null
		if _layers.has(slot):
			var entry := GameData.asset_entry(_layer_keys[slot])
			var src := str(GameData.assets.characters.anims.get(anim, {}).get("from", anim))
			var path := str(entry.get("path", "")) + "hide/" + src + ".png"
			if bool(entry.get("hide", false)) and ResourceLoader.exists(path):
				tex = load(path)
		mat.set_shader_parameter("hide_" + slot, tex)
		mat.set_shader_parameter("on_" + slot, tex != null)


func clear_gear() -> void:
	for slot in _layers.keys():
		if slot != "body":
			set_layer(slot, "")


## The animation actually drawn for `a_name`: itself when the body has it, else its data
## "fallback" chain (e.g. a weapon attack the art doesn't have yet -> "attack").
func resolve(a_name: String) -> String:
	var body: AnimatedSprite2D = _layers.get("body")
	var anims: Dictionary = GameData.assets.characters.anims
	var a := a_name
	for i in 4:
		if body == null or body.sprite_frames == null or body.sprite_frames.has_animation("%s_%d" % [a, dir_index]):
			return a
		var fb := str(anims.get(a, {}).get("fallback", ""))
		if fb.is_empty():
			return a
		a = fb
	return a


## Plays `new_anim` facing `facing`. Looping animations restart only when changed.
func play(new_anim: String, facing: Vector2, force := false) -> void:
	var new_dir := dir_from_vector(facing) if facing != Vector2.ZERO else dir_index
	new_anim = resolve(new_anim)
	if new_anim == anim and new_dir == dir_index and not force:
		return
	var changed_dir := new_dir != dir_index
	anim = new_anim
	dir_index = new_dir
	if changed_dir:
		_sort_layers()
	for spr in _layers.values():
		_play_layer(spr, not force and changed_dir)


## Seconds one play of `a_name` takes on the body layer (its entry's frames / fps), 0 if missing.
func anim_length(a_name: String) -> float:
	var body: AnimatedSprite2D = _layers.get("body")
	var an := "%s_%d" % [resolve(a_name), dir_index]
	if body == null or body.sprite_frames == null or not body.sprite_frames.has_animation(an):
		return 0.0
	return body.sprite_frames.get_frame_count(an) / maxf(body.sprite_frames.get_animation_speed(an), 0.01)


## Height of the drawn body above the feet (data: "height" of the body's asset entry).
func visual_height() -> float:
	return _height if _height > 0.0 else 47.0


## The front-facing idle frame of every layer, bottom to top, for UI portraits:
## [[texture, modulate], ...].
func portrait_layers() -> Array:
	var out: Array = []
	for child in get_children():  # drawing order (held items' back parts first)
		var spr := child as AnimatedSprite2D
		if spr == null or not _layers.values().has(spr):
			continue
		var slot := str(_layers.find_key(spr))
		var an := "idle_2"
		if spr.sprite_frames and spr.sprite_frames.has_animation(an):
			var tex := spr.sprite_frames.get_frame_texture(an, 0)
			if slot == "body":
				tex = _masked_portrait_body(tex)
			out.append([tex, spr.modulate])
	return out


static var _portrait_cache: Dictionary = {}


## The portrait body frame with the worn pieces' hide masks applied (as the body shader does).
func _masked_portrait_body(tex: Texture2D) -> Texture2D:
	var masks: Array = []
	for slot in HIDE_SLOTS:
		if _layers.has(slot):
			var entry := GameData.asset_entry(_layer_keys[slot])
			var path := str(entry.get("path", "")) + "hide/idle.png"
			if bool(entry.get("hide", false)) and ResourceLoader.exists(path):
				masks.append(path)
	if masks.is_empty() or not tex is AtlasTexture:
		return tex
	var key := "%s|%s" % [_layer_keys.get("body", ""), ",".join(masks)]
	if _portrait_cache.has(key):
		return _portrait_cache[key]
	var region: Rect2i = Rect2i((tex as AtlasTexture).region)
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	for path in masks:
		var m: Image = (load(path) as Texture2D).get_image().get_region(region)
		m.convert(Image.FORMAT_RGBA8)
		for y in img.get_height():
			for x in img.get_width():
				if m.get_pixel(x, y).a > 0.5:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
	var out := ImageTexture.create_from_image(img)
	_portrait_cache[key] = out
	return out


func is_playing_one_shot() -> bool:
	for spr in _layers.values():
		return spr.is_playing() and not spr.sprite_frames.get_animation_loop(spr.animation)
	return false


## Gender ids from data/assets.json characters.genders (the lobby offers them in this order).
static func genders() -> Array:
	return GameData.assets.get("characters", {}).get("genders", {"male": {}}).keys()


static func valid_gender(g: String) -> String:
	return g if genders().has(g) else str(GameData.assets.get("characters", {}).get("default_gender", "male"))


static func body_key(gender: String) -> String:
	var def: Dictionary = GameData.assets.characters.get("genders", {}).get(valid_gender(gender), {})
	return "characters.layers." + str(def.get("body", "body_male"))


## Registry key of an item's look for a body: "<prefix><appearance>" when that gender has its own
## art (drawn on its body), otherwise a shared "<appearance>" entry, or "" (not drawn).
static func gear_key(appearance: String, gender: String) -> String:
	var def: Dictionary = GameData.assets.characters.get("genders", {}).get(valid_gender(gender), {})
	var layers: Dictionary = GameData.assets.characters.get("layers", {})
	var own := str(def.get("prefix", "")) + appearance
	if layers.has(own):
		return "characters.layers." + own
	return "characters.layers." + appearance if layers.has(appearance) else ""  # no art: not drawn


## Asset entry of the body layer (frame size, crops) for portraits.
func body_entry() -> Dictionary:
	var key: String = _layer_keys.get("body", "")
	return GameData.asset_entry(key) if not key.is_empty() else {}


## Seconds from the start of `a_name` on body `body_key_` to its impact frame (data "impact",
## following the "fallback" chain when the body has no sheet for it); 0 without one.
static func impact_time(body_key_: String, a_name: String) -> float:
	var anims: Dictionary = GameData.assets.characters.anims
	var entry := GameData.asset_entry(body_key_)
	var a := a_name
	for i in 4:
		var src := str(anims.get(a, {}).get("from", a))
		if ResourceLoader.exists(str(entry.get("path", "")) + src + ".png") or not anims.get(a, {}).has("fallback"):
			break
		a = str(anims[a].fallback)
	var def: Dictionary = anims.get(a, {}).duplicate()
	def.merge(entry.get("anims", {}).get(a, {}), true)
	if not def.has("impact"):
		return 0.0
	return float(def.impact) / maxf(float(def.get("fps", 10)), 1.0)


static func dir_from_vector(v: Vector2) -> int:
	return wrapi(roundi(v.angle() / (PI / 4.0)), 0, 8)


## A layer added or swapped mid-animation starts on the body's frame (#15): the body shader cuts
## the body with the masks of the body's current frame, so a piece one frame off leaves holes.
func _sync_to_body(spr: AnimatedSprite2D) -> void:
	var body: AnimatedSprite2D = _layers.get("body")
	if body == null or spr == body or not spr.visible or body.sprite_frames == null:
		return
	if spr.animation == body.animation and spr.sprite_frames.get_frame_count(spr.animation) > body.frame:
		spr.set_frame_and_progress(body.frame, body.frame_progress)


## Software composite of what is drawn right now (layer order, visibility, frame, tint and the
## body's hide masks), feet at (size / 2, size - 1 - feet offset). For tests and art audits.
func compose() -> Image:
	var out := Image.create(_frame_size, _frame_size, false, Image.FORMAT_RGBA8)
	for child in get_children():
		var spr := child as AnimatedSprite2D
		if spr == null or not spr.visible or spr.sprite_frames == null or not spr.sprite_frames.has_animation(spr.animation):
			continue
		var at := spr.sprite_frames.get_frame_texture(spr.animation, spr.frame) as AtlasTexture
		if at == null:
			continue
		var region := Rect2i(at.region)
		var src := _image_of(at.atlas).get_region(region)
		var masks: Array = []
		if spr == _layers.get("body") and spr.material is ShaderMaterial:
			for slot in HIDE_SLOTS:
				var mt: Variant = spr.material.get_shader_parameter("hide_" + slot)
				if spr.material.get_shader_parameter("on_" + slot) and mt is Texture2D:
					masks.append(_image_of(mt).get_region(region))
		var tint: Color = spr.modulate * modulate
		var shift := Vector2i(spr.offset - _layers.get("body", spr).offset)
		for y in src.get_height():
			for x in src.get_width():
				var c := src.get_pixel(x, y)
				if c.a <= 0.0 or masks.any(func(m: Image) -> bool: return m.get_pixel(x, y).a > 0.5):
					continue
				var q := Vector2i(x, y) + shift
				if q.x < 0 or q.y < 0 or q.x >= _frame_size or q.y >= _frame_size:
					continue
				c *= tint
				var d := out.get_pixelv(q)
				var a := c.a + d.a * (1.0 - c.a)
				out.set_pixelv(q, Color((c.r * c.a + d.r * d.a * (1.0 - c.a)) / a, (c.g * c.a + d.g * d.a * (1.0 - c.a)) / a, (c.b * c.a + d.b * d.a * (1.0 - c.a)) / a, a) if a > 0.0 else Color(0, 0, 0, 0))
	return out


## Pixels any layer draws in `a_name` over every direction and frame, in frame coordinates
## (used by the lobby preview to fit held weapons and wide poses).
func used_rect(a_name: String) -> Rect2i:
	var out := Rect2i()
	for spr in _layers.values():
		if spr.sprite_frames == null:
			continue
		for d in 8:
			var an := "%s_%d" % [a_name, d]
			if not spr.sprite_frames.has_animation(an):
				continue
			for f in spr.sprite_frames.get_frame_count(an):
				var at := spr.sprite_frames.get_frame_texture(an, f) as AtlasTexture
				if at == null:
					continue
				var u := _image_of(at.atlas).get_region(Rect2i(at.region)).get_used_rect()
				if u.size != Vector2i.ZERO:
					out = u if out.size == Vector2i.ZERO else out.merge(u)
	return out


## Where frame row 0 is drawn relative to the node (feet) at scale 1.
func frame_top() -> float:
	var body: AnimatedSprite2D = _layers.get("body")
	return (body.offset.y if body else -_frame_size / 2.0) - _frame_size / 2.0


static var _image_cache: Dictionary = {}


static func _image_of(tex: Texture2D) -> Image:
	var key: Variant = tex.resource_path if not tex.resource_path.is_empty() else tex.get_instance_id()
	if not _image_cache.has(key):
		var t2: Texture2D = (tex as CanvasTexture).diffuse_texture if tex is CanvasTexture else tex
		var img: Image = t2.get_image()
		img.convert(Image.FORMAT_RGBA8)
		_image_cache[key] = img
	return _image_cache[key]


func _play_layer(spr: AnimatedSprite2D, keep_frame := false) -> void:
	var name_ := "%s_%d" % [anim, dir_index]
	# A piece without this animation (e.g. gear on a ghost) isn't drawn.
	spr.visible = spr.sprite_frames != null and spr.sprite_frames.has_animation(name_)
	if spr.name == "body":
		_update_hide()
	if not spr.visible:
		return
	var frame := spr.frame
	var progress := spr.frame_progress
	spr.play(name_)
	if keep_frame:
		spr.set_frame_and_progress(mini(frame, spr.sprite_frames.get_frame_count(name_) - 1), progress)


## Layer order from data; the held items' back parts go under the body (#16: which pixels are
## behind is baked per frame, not decided by the direction here).
func _sort_layers() -> void:
	var idx := 0
	var ordered: Array = []
	for slot in _layers:
		if str(slot).ends_with(BACK):
			ordered.append(slot)
	for slot in _order:
		if _layers.has(slot):
			ordered.append(slot)
	for slot in _layers:
		if not ordered.has(slot):
			ordered.append(slot)
	for slot in ordered:
		move_child(_layers[slot], idx)
		idx += 1


static func _frames_for(key: String) -> SpriteFrames:
	if _frames_cache.has(key):
		return _frames_cache[key]
	var is_back := key.ends_with(BACK)
	var entry := GameData.asset_entry(key.trim_suffix(BACK) if is_back else key)
	var folder: String = str(entry.get("path", "")) + ("back/" if is_back else "")
	var size := int(entry.get("frame_size", GameData.assets.characters.frame_size))
	var anims: Dictionary = GameData.assets.characters.anims.duplicate(true)
	if entry.has("anims"):
		# Per-field override: an entry may change frames/fps and keep the shared "loop".
		for a in entry.anims:
			if anims.has(a):
				anims[a].merge(entry.anims[a], true)
			else:
				anims[a] = entry.anims[a]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for a in anims:
		# "from": the frames of another sheet (spin = slash, revive = death backwards).
		var src := str(anims[a].get("from", a))
		var path: String = folder + src + ".png"
		if not ResourceLoader.exists(path) or not anims.has(src):
			continue
		var tex: Texture2D = load(path)
		# Optional normal maps (e.g. from Pixellab): same layout in entry.normal.
		if entry.has("normal") and ResourceLoader.exists(str(entry.normal) + src + ".png"):
			var ct := CanvasTexture.new()
			ct.diffuse_texture = tex
			ct.normal_texture = load(str(entry.normal) + src + ".png")
			tex = ct
		var frames := int(anims[src].frames)
		var order: Array = range(frames)
		if anims[a].get("reverse", false):
			order.reverse()
		for d in 8:
			var an := "%s_%d" % [a, d]
			sf.add_animation(an)
			sf.set_animation_speed(an, float(anims[a].fps))
			sf.set_animation_loop(an, bool(anims[a].loop))
			for f in order:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(f * size, d * size, size, size)
				sf.add_frame(an, at)
	_frames_cache[key] = sf
	return sf
