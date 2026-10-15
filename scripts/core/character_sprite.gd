class_name CharacterSprite
extends Node2D
## Layered 8-direction character renderer. Each layer (body, one per equipment slot) is an
## AnimatedSprite2D built from the sprite sheets registered in data/assets.json, so gear changes
## the look by swapping a layer, and final Pixellab art drops in without code changes.
## Animations are named "<anim>_<dir>" with dir 0..7 = E, SE, S, SW, W, NW, N, NE.

static var _frames_cache: Dictionary = {}

var anim := "idle"
var dir_index := 2
var _layers: Dictionary = {}  ## layer slot -> AnimatedSprite2D
var _layer_keys: Dictionary = {}  ## layer slot -> registry key
var _frame_size := 64
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
	if _layer_keys.get(slot, "") != key:
		_layer_keys[slot] = key
		spr.sprite_frames = _frames_for(key)
		var entry := GameData.asset_entry(key)
		_frame_size = int(entry.get("frame_size", GameData.assets.characters.frame_size))
		var feet := int(entry.get("feet_offset", GameData.assets.characters.feet_offset))
		spr.offset = Vector2(0, -_frame_size / 2.0 + feet)
	_play_layer(spr)


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


func is_playing_one_shot() -> bool:
	for spr in _layers.values():
		return spr.is_playing() and not spr.sprite_frames.get_animation_loop(spr.animation)
	return false


static func dir_from_vector(v: Vector2) -> int:
	return wrapi(roundi(v.angle() / (PI / 4.0)), 0, 8)


func _play_layer(spr: AnimatedSprite2D, keep_frame := false) -> void:
	var name_ := "%s_%d" % [anim, dir_index]
	if spr.sprite_frames == null or not spr.sprite_frames.has_animation(name_):
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
		anims.merge(entry.anims, true)
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
