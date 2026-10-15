class_name CharacterSprite
extends Node2D
## Layered 8-direction character renderer. Each layer (body, one per equipment slot) is an
## AnimatedSprite2D built from the sprite sheets registered in data/assets.json, so gear changes
## the look by swapping a layer, and final Pixellab art drops in without code changes.
## Animations are named "<anim>_<dir>" with dir 0..7 = E, SE, S, SW, W, NW, N, NE.
## Worn pieces whose entry has "hide": true come with hide masks (<path>hide/<anim>.png, same
## layout): the body layer's shader drops the body pixels they cover (tools/gear_cut.gd).

const HIDE_SLOTS := ["head", "chest", "legs", "boots", "gloves"]
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


## Sets (or clears with "") the art of one layer. `key` is a path into data/assets.json such as
## "characters.layers.weapon_sword" or "monsters.ghoul".
func set_layer(slot: String, key: String, tint: Color = Color.WHITE) -> void:
	if key.is_empty():
		if _layers.has(slot):
			_layers[slot].queue_free()
			_layers.erase(slot)
			_layer_keys.erase(slot)
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
	if slot != "body":
		_update_hide()


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
			var path := str(entry.get("path", "")) + "hide/" + anim + ".png"
			if bool(entry.get("hide", false)) and ResourceLoader.exists(path):
				tex = load(path)
		mat.set_shader_parameter("hide_" + slot, tex)
		mat.set_shader_parameter("on_" + slot, tex != null)


func clear_gear() -> void:
	for slot in _layers.keys():
		if slot != "body":
			set_layer(slot, "")


## Plays `new_anim` facing `facing`. Looping animations restart only when changed.
func play(new_anim: String, facing: Vector2, force := false) -> void:
	var new_dir := dir_from_vector(facing) if facing != Vector2.ZERO else dir_index
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
	var an := "%s_%d" % [a_name, dir_index]
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
	var slots: Array = _order.duplicate()
	for slot in _layers:
		if not slots.has(slot):
			slots.append(slot)
	for slot in slots:
		if not _layers.has(slot):
			continue
		var spr: AnimatedSprite2D = _layers[slot]
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


static func dir_from_vector(v: Vector2) -> int:
	return wrapi(roundi(v.angle() / (PI / 4.0)), 0, 8)


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


## Weapons and off-hands are drawn behind the body when facing away from the camera.
func _sort_layers() -> void:
	var behind := dir_index in [5, 6, 7]
	var idx := 0
	var ordered: Array = []
	for slot in _order:
		if _layers.has(slot):
			ordered.append(slot)
	for slot in _layers:
		if not ordered.has(slot):
			ordered.append(slot)
	if behind:
		for s in ["offhand", "weapon"]:
			if ordered.has(s):
				ordered.erase(s)
				ordered.push_front(s)
	for slot in ordered:
		move_child(_layers[slot], idx)
		idx += 1


static func _frames_for(key: String) -> SpriteFrames:
	if _frames_cache.has(key):
		return _frames_cache[key]
	var entry := GameData.asset_entry(key)
	var folder: String = entry.get("path", "")
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
		var path: String = folder + a + ".png"
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		# Optional normal maps (e.g. from Pixellab): same layout in entry.normal.
		if entry.has("normal") and ResourceLoader.exists(str(entry.normal) + a + ".png"):
			var ct := CanvasTexture.new()
			ct.diffuse_texture = tex
			ct.normal_texture = load(str(entry.normal) + a + ".png")
			tex = ct
		var frames := int(anims[a].frames)
		for d in 8:
			var an := "%s_%d" % [a, d]
			sf.add_animation(an)
			sf.set_animation_speed(an, float(anims[a].fps))
			sf.set_animation_loop(an, bool(anims[a].loop))
			for f in frames:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(f * size, d * size, size, size)
				sf.add_frame(an, at)
	_frames_cache[key] = sf
	return sf
