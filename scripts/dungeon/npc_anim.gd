class_name NpcAnim
extends Node2D
## #77: the blacksmith's idle on every peer (merchants.json blacksmith.anim): he works his anvil
## in bursts of hammer strikes (the hammer lifted, raised, brought down; sparks, a light flash and
## a quiet clang on the impact frame), rests between them, now and then wipes his brow, and looks
## up when the local hero comes near. An upgrade (work_piece) makes him strike the piece three
## times and quench it in the barrel. Purely visual: nothing here is replicated.
## #113: a merchant (anim.mode "merchant": Archibald, Malphas) breathes through its looping `idle`
## clip and, every `rest` seconds, plays one of its `gestures` (Archibald turns a coin, Malphas
## reads his contract). A missing sheet leaves the static sprite.

var cfg: Dictionary = {}
var sprite: Sprite2D
var base_tex: Texture2D
var _base_offset := Vector2.ZERO
var frames: Dictionary = {}  ## clip -> [AtlasTexture]
var log: Array = []  ## clips started (tests)
var impacts := 0  ## impact frames shown (tests)
var _queue: Array = []  ## [clip, frame, time] steps still to play
var _t := 0.0
var _rest := 1.0
var _look_cd := 0.0
var _rng := RandomNumberGenerator.new()
var _flash: PointLight2D
var _piece_strikes := 0


func setup(npc_id: String, spr: Sprite2D) -> void:
	name = "NpcAnim"
	cfg = GameData.merchants.get(npc_id, {}).get("anim", {})
	sprite = spr
	base_tex = spr.texture
	_base_offset = spr.offset
	for clip in cfg:
		if not cfg[clip] is Dictionary or not cfg[clip].has("sheet"):
			continue
		var c: Dictionary = cfg[clip]
		var sheet: Texture2D = GameData.texture(str(c.get("sheet", "")))
		var list: Array = []
		if sheet:
			var n := int(c.get("frames", 1))
			var fw := sheet.get_width() / maxi(n, 1)
			for i in n:
				var at := AtlasTexture.new()
				at.atlas = sheet
				at.region = Rect2(i * fw, 0, fw, sheet.get_height())
				list.append(at)
		frames[clip] = list
	_rng.seed = hash(npc_id)
	_rest = _rng.randf_range(0.3, 1.2)
	_flash = PointLight2D.new()
	LightLayers.setup_light(_flash)
	_flash.texture = GameData.texture("fx.light")
	_flash.color = Color.from_string(str(cfg.get("sparks", "#ffb040")), Color.ORANGE)
	_flash.energy = 0.0
	_flash.position = _impact_offset()
	LightLayers.register(_flash, 70.0)
	add_child(_flash)


func _impact_offset() -> Vector2:
	var o: Array = cfg.get("impact", [-9, -12])
	return Vector2(float(o[0]), float(o[1]))


func _process(delta: float) -> void:
	_flash.energy = maxf(_flash.energy - delta * 6.0, 0.0)
	_look_cd -= delta
	if str(cfg.get("mode", "")) == "merchant":
		_merchant(delta)
		return
	if _queue.is_empty():
		_rest -= delta
		if _wants_look():
			_play_look()
		elif _rest <= 0.0:
			if _rng.randf() < float(cfg.get("wipe_chance", 0.3)):
				_play_wipe()
			else:
				var s: Array = cfg.get("strikes", [2, 4])
				_play_strikes(_rng.randi_range(int(s[0]), int(s[1])))
		return
	_t -= delta
	while _t <= 0.0 and not _queue.is_empty():
		var step: Array = _queue.pop_front()
		_show(str(step[0]), int(step[1]))
		_t += float(step[2])
		if step.size() > 3:
			_event(str(step[3]))
	if _queue.is_empty():
		_show("", -1)
		var r: Array = cfg.get("rest", [1.4, 2.6])
		_rest = _rng.randf_range(float(r[0]), float(r[1]))


## #113: the idle loop between gestures; a gesture now and then.
func _merchant(delta: float) -> void:
	if _queue.is_empty():
		_rest -= delta
		var gestures: Array = cfg.get("gestures", []).filter(func(g): return not frames.get(str(g), []).is_empty())
		if _rest <= 0.0 and not gestures.is_empty():
			var clip := str(gestures[_rng.randi_range(0, gestures.size() - 1)])
			log.append(clip)
			for i in frames[clip].size():
				_queue.append([clip, i, float(cfg[clip].get("time", 0.12))])
			var r: Array = cfg.get("rest", [5.0, 9.0])
			_rest = _rng.randf_range(float(r[0]), float(r[1]))
		elif not frames.get("idle", []).is_empty():
			if log.is_empty() or log[-1] != "idle":
				log.append("idle")
			var n: int = frames.idle.size()
			for i in n:
				_queue.append(["idle", i, float(cfg.idle.get("time", 0.16))])
	_t -= delta
	while _t <= 0.0 and not _queue.is_empty():
		var step: Array = _queue.pop_front()
		_show(str(step[0]), int(step[1]))
		_t += float(step[2])


func _show(clip: String, i: int) -> void:
	var list: Array = frames.get(clip, [])
	sprite.texture = list[i] if i >= 0 and i < list.size() else base_tex
	# A taller frame (a gesture reaching up, #113) keeps its feet where the static sprite's are.
	if base_tex and sprite.texture:
		sprite.offset = _base_offset - Vector2(0, (sprite.texture.get_height() - base_tex.get_height()) / 2.0)


func _wants_look() -> bool:
	if _look_cd > 0.0 or frames.get("look", []).is_empty():
		return false
	var game := get_tree().get_first_node_in_group("game")
	var ref: Variant = game.local_player if game else null
	if not is_instance_valid(ref):
		return false
	var me: Node2D = ref
	return me.global_position.distance_to(global_position) < float(cfg.get("look_radius", 150.0))


func _play_look() -> void:
	log.append("look")
	_look_cd = float(cfg.get("look_every", 9.0))
	var n: int = frames.look.size()
	var ft := float(cfg.get("look_time", 0.12))
	var mid := n / 2
	for i in range(0, mid + 1):
		_queue.append(["look", i, ft if i < mid else float(cfg.get("look_hold", 1.2))])
	for i in range(mid + 1, n):
		_queue.append(["look", i, ft])


func _play_wipe() -> void:
	log.append("wipe")
	for i in frames.get("wipe", []).size():
		_queue.append(["wipe", i, float(cfg.get("wipe_time", 0.12))])


## `count` hammer strikes: the hammer lifted (the clip backwards), held raised, brought down to
## the impact frame (sparks and the clang), then settled.
func _play_strikes(count: int, last_event: String = "") -> void:
	var list: Array = frames.get("strike", [])
	if list.is_empty():
		return
	log.append("strike")
	var n := list.size()
	var hit := clampi(int(cfg.get("impact_frame", 4)), 1, n - 1)
	for k in count:
		for i in range(n - 1, 0, -1):
			_queue.append(["strike", i, float(cfg.get("lift_time", 0.09))])
		_queue.append(["strike", 0, float(cfg.get("raised_hold", 0.16))])
		for i in range(1, hit):
			_queue.append(["strike", i, float(cfg.get("strike_time", 0.05))])
		_queue.append(["strike", hit, float(cfg.get("impact_hold", 0.3)), "impact"])
		for i in range(hit + 1, n):
			_queue.append(["strike", i, float(cfg.get("lift_time", 0.09))])
	if not last_event.is_empty():
		_queue[-1].append(last_event)


## An upgrade: three strikes on the piece, then the quench.
func work_piece() -> void:
	_queue.clear()
	_t = 0.0
	_piece_strikes = 3
	_play_strikes(3, "quench")


func _event(kind: String) -> void:
	var at := global_position + _impact_offset()
	match kind:
		"impact":
			impacts += 1
			_flash.energy = 1.6 if _piece_strikes > 0 else 0.9
			_sparks(at, 14 if _piece_strikes > 0 else 8)
			# A working smith is heard faintly across the room; a commissioned strike rings out.
			AudioManager.play_sfx_at("forge_strike" if _piece_strikes > 0 else "forge_ambience", at, 0.1,
				0.0 if _piece_strikes > 0 else float(cfg.get("ambience_volume", -16.0)))
			_piece_strikes = maxi(_piece_strikes - 1, 0)
		"quench":
			var game := get_tree().get_first_node_in_group("game")
			var bpos: Vector2 = game.layout.get("forge", {}).get("barrel", global_position) if game else global_position
			_steam(bpos + Vector2(0, -14))
			AudioManager.play_sfx_at("forge_quench", bpos)


func _sparks(at: Vector2, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.45
	p.direction = Vector2(0, -1)
	p.spread = 75.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 120.0
	p.gravity = Vector2(0, 260)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.7))
	grad.set_color(1, Color.from_string(str(cfg.get("sparks", "#ffb040")), Color.ORANGE) * Color(1, 1, 1, 0))
	p.color_ramp = grad
	p.material = CanvasItemMaterial.new()
	p.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.global_position = at
	p.z_index = 2
	get_parent().get_parent().add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func _steam(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.pixel")
	p.amount = 22
	p.one_shot = true
	p.explosiveness = 0.6
	p.lifetime = 1.4
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 34.0
	p.gravity = Vector2(0, -12)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.92, 0.95, 0.55))
	grad.set_color(1, Color(0.8, 0.82, 0.86, 0.0))
	p.color_ramp = grad
	p.global_position = at
	p.z_index = 2
	get_parent().get_parent().add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
