class_name StatusFx
extends Node2D
## #81: every status shows on the actor that has it, on every peer, from the replicated
## Status:shown: burning flames, poison bubbles, bleed drips, frozen crystals, chill breath,
## stunned stars, slowed ghost frames, roots / chains at the feet, a silence glyph, fear wisps, a
## blinding band, haste lines, an enraged aura, an invulnerable golden outline, weakened / broken
## cracks and a target sigil for marks. Each status maps to one family (data/fx.json
## "status_fx" names it, else rules on its flags, damage type and stats); the families are drawn
## small and additive so several at once stay readable. Elites also carry one signature per
## modifier (data/fx.json "elite_fx").

var actor: Actor
var families: Dictionary = {}  ## family -> colour now shown (read by the tests)
var _emitters: Dictionary = {}  ## family -> CPUParticles2D
var _t := 0.0
var _scan := 0.0
var _ghost_left := 0.0
var _step_left := 0.0
var _last_pos := Vector2.ZERO


func _init(a: Actor) -> void:
	actor = a
	name = "StatusFx"


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m
	if actor is Enemy and actor.is_elite():
		for mod in actor.elite:
			_elite_signature(str(mod))


## The family a status is drawn as ("" = none).
static func family_of(id: String) -> String:
	var over: Dictionary = GameData.fx.get("status_fx", {})
	if over.has(id):
		return str(over[id])
	var d: Dictionary = GameData.status_effects.get(id, {})
	var flags: Array = d.get("flags", [])
	if flags.has("invulnerable"):
		return "invulnerable"
	if flags.has("frozen"):
		return "frozen"
	if flags.has("stunned") or flags.has("knocked_down") or flags.has("asleep") or flags.has("disoriented"):
		return "stunned"
	if flags.has("shackled"):
		return "chained"
	if flags.has("rooted"):
		return "rooted"
	if flags.has("silenced"):
		return "silenced"
	if flags.has("feared"):
		return "feared"
	if flags.has("blinded"):
		return "blinded"
	var kind := str(d.get("kind", ""))
	if kind == "dot":
		match str(d.get("damage_type", "")):
			"fire":
				return "burning"
			"nature", "poison":
				return "poison"
			"physical":
				return "bleed"
			"frost":
				return "chill"
			"shadow", "arcane":
				return "feared"
	if kind == "mark":
		return "marked"
	var st: Dictionary = d.get("stats", {})
	var debuff := bool(d.get("debuff", false))
	if debuff and float(st.get("armor_mult", 1.0)) < 1.0 or debuff and float(st.get("damage_mult", 1.0)) < 1.0 or d.has("stack_stats") and debuff and float(d.stack_stats.get("armor_mult", 1.0)) < 1.0:
		return "cracks"
	if debuff and float(st.get("move_speed_mult", 1.0)) < 1.0:
		return "chill" if float(st.get("haste", 0.0)) < 0.0 else "slowed"
	if not debuff and float(st.get("damage_mult", 1.0)) > 1.05 and float(st.get("move_speed_mult", 1.0)) > 1.0:
		return "enraged"
	if not debuff and (float(st.get("haste", 0.0)) > 0.0 or float(st.get("move_speed_mult", 1.0)) > 1.0):
		return "haste"
	return ""


func _process(delta: float) -> void:
	_t += delta
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.2
		_refresh()
	var world: Node = Combat.instance.fx.world if Combat.instance and Combat.instance.fx else null
	var moving := actor.global_position.distance_to(_last_pos) > 0.4
	_last_pos = actor.global_position
	if families.has("slowed") and world:
		_ghost_left -= delta
		if _ghost_left <= 0.0 and moving and is_visible_in_tree():
			_ghost_left = 0.12
			GameplayFx.afterimage(world, actor, Color(0.5, 0.7, 1.0, 0.3), 0.35)
	# #81 16: footsteps splash in water and sludge.
	_step_left -= delta
	if moving and _step_left <= 0.0 and world and is_visible_in_tree():
		_step_left = float(GameplayFx.cfg("footsteps").get("every", 0.28))
		var game := get_tree().get_first_node_in_group("game")
		if game and game.dungeon:
			var cell: int = game.dungeon.cell_at(game.dungeon.cell_of(actor.global_position))
			if cell == DungeonGenerator.CELL_WATER or cell == DungeonGenerator.CELL_SLUDGE:
				var sc := Color("6a9a70") if cell == DungeonGenerator.CELL_SLUDGE else Color("8ab0c8")
				GameplayFx.burst(world, actor.global_position + Vector2(0, 2), sc, 6, 26.0, 70.0, Vector2.UP, Vector2(0, 90), 0.35, 1.6)
				GameplayFx.note("splash")
	queue_redraw()


func _refresh() -> void:
	var now := {}
	if is_instance_valid(actor) and actor.is_alive():
		for s in actor.status.shown:
			var f := family_of(str(s[0]))
			if not f.is_empty() and not now.has(f):
				now[f] = Color.from_string(str(GameData.status_effects.get(str(s[0]), {}).get("color", "#ffffff")), Color.WHITE)
	for f in families.keys():
		if not now.has(f):
			_set_emitter(f, false)
	for f in now:
		if not families.has(f):
			GameplayFx.note("status_" + str(f))
			_set_emitter(f, true, now[f])
	families = now


## Particle families (the drawn ones are in _draw).
const PARTICLES := {
	"burning": {"amount": 10, "life": 0.6, "at": Vector2(0, -14), "box": Vector2(8, 10), "dir": Vector2.UP, "speed": [14, 30], "gravity": Vector2(0, -50), "size": [1.5, 3.0], "color": "#ff7a20"},
	"poison": {"amount": 6, "life": 0.9, "at": Vector2(0, -18), "box": Vector2(9, 12), "dir": Vector2.UP, "speed": [6, 14], "gravity": Vector2(0, -12), "size": [1.5, 2.8], "color": "#7ee040"},
	"bleed": {"amount": 5, "life": 0.7, "at": Vector2(0, -16), "box": Vector2(7, 8), "dir": Vector2.DOWN, "speed": [4, 10], "gravity": Vector2(0, 90), "size": [1.0, 2.0], "color": "#c01818"},
	"frozen": {"amount": 8, "life": 1.0, "at": Vector2(0, -16), "box": Vector2(10, 14), "dir": Vector2.UP, "speed": [2, 6], "gravity": Vector2(0, 0), "size": [1.5, 3.0], "color": "#bdf0ff"},
	"chill": {"amount": 5, "life": 0.8, "at": Vector2(4, -26), "box": Vector2(2, 2), "dir": Vector2(1, -0.3), "speed": [8, 14], "gravity": Vector2(0, -6), "size": [1.5, 2.5], "color": "#cfefff"},
	"feared": {"amount": 6, "life": 1.0, "at": Vector2(0, -20), "box": Vector2(10, 12), "dir": Vector2.UP, "speed": [6, 12], "gravity": Vector2(0, -16), "size": [1.5, 2.5], "color": "#a040d0"},
	"haste": {"amount": 6, "life": 0.35, "at": Vector2(0, -14), "box": Vector2(10, 12), "dir": Vector2.LEFT, "speed": [30, 50], "gravity": Vector2(0, 0), "size": [1.0, 1.5], "color": "#ffe9a0"},
	"enraged": {"amount": 8, "life": 0.6, "at": Vector2(0, -8), "box": Vector2(12, 4), "dir": Vector2.UP, "speed": [10, 22], "gravity": Vector2(0, -30), "size": [1.0, 2.0], "color": "#ff2a2a"},
}


func _set_emitter(f: String, on: bool, c: Color = Color.WHITE) -> void:
	var e: CPUParticles2D = _emitters.get(f)
	if not on:
		if e:
			e.emitting = false
		return
	var spec: Dictionary = PARTICLES.get(f, {})
	if spec.is_empty():
		return
	if e == null:
		e = CPUParticles2D.new()
		e.texture = GameData.texture("fx.pixel")
		e.amount = int(spec.amount)
		e.lifetime = float(spec.life)
		e.position = spec.at
		e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		e.emission_rect_extents = spec.box
		e.direction = spec.dir
		e.spread = 25.0
		e.gravity = spec.gravity
		e.initial_velocity_min = float(spec.speed[0])
		e.initial_velocity_max = float(spec.speed[1])
		e.scale_amount_min = float(spec.size[0])
		e.scale_amount_max = float(spec.size[1])
		e.use_parent_material = true
		add_child(e)
		_emitters[f] = e
	var base := Color.from_string(str(spec.color), c)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(base.r * 1.6, base.g * 1.6, base.b * 1.6, 0.9))
	ramp.set_color(1, Color(base, 0.0))
	e.color_ramp = ramp
	e.emitting = true


func _draw() -> void:
	if families.is_empty() or not is_instance_valid(actor):
		return
	var head := Vector2(0, -40)
	if families.has("stunned"):
		# Stars circling over the head.
		for i in 3:
			var a := _t * 4.0 + i * TAU / 3.0
			var p := head + Vector2(cos(a) * 10.0, sin(a) * 3.5)
			_star(p, 2.5, Color(1.0, 0.95, 0.5, 0.95))
	if families.has("silenced"):
		var g := head + Vector2(0, -2)
		draw_circle(g, 6.0, Color(0.75, 0.6, 1.0, 0.35))
		draw_arc(g, 6.0, 0.0, TAU, 16, Color(0.8, 0.7, 1.0, 0.9), 1.2)
		draw_line(g + Vector2(-4, 4), g + Vector2(4, -4), Color(0.9, 0.8, 1.0, 0.95), 1.5)
	if families.has("marked"):
		# A target sigil over the head.
		var m := head + Vector2(0, -6)
		var c: Color = families.marked
		var s := 1.0 + 0.1 * sin(_t * 5.0)
		draw_arc(m, 6.0 * s, 0.0, TAU, 20, Color(c, 0.9), 1.5)
		for k in 4:
			var v := Vector2.from_angle(k * PI / 2.0) * 8.0 * s
			draw_line(m + v * 0.6, m + v, Color(c, 0.9), 1.5)
	if families.has("rooted") or families.has("chained"):
		var chained := families.has("chained")
		var col := Color(0.6, 0.45, 0.2, 0.9) if not chained else Color(0.7, 0.7, 0.75, 0.9)
		for i in 5:
			var a2 := i * TAU / 5.0 + 0.3
			var base := Vector2(cos(a2) * 10.0, sin(a2) * 4.0)
			draw_line(base, base + Vector2(cos(a2) * -3.0, -6.0 - 2.0 * sin(_t * 3.0 + i)), col, 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.4))
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 20, col, 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if families.has("blinded"):
		draw_rect(Rect2(Vector2(-9, -33), Vector2(18, 4)), Color(0.05, 0.05, 0.1, 0.85))
	if families.has("invulnerable"):
		var k2 := 0.6 + 0.4 * sin(_t * 6.0)
		draw_set_transform(Vector2(0, -16), 0.0, Vector2(0.75, 1.0))
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.3, 0.55 * k2), 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if families.has("cracks"):
		var cc := Color(1.0, 0.45, 0.2, 0.75)
		draw_polyline(PackedVector2Array([Vector2(-6, -24), Vector2(-2, -19), Vector2(-4, -14), Vector2(1, -10)]), cc, 1.2)
		draw_polyline(PackedVector2Array([Vector2(5, -22), Vector2(2, -17), Vector2(6, -13)]), cc, 1.2)
	if families.has("frozen"):
		for i in 4:
			var a3 := i * TAU / 4.0 + 0.4
			var p3 := Vector2(cos(a3) * 9.0, -14.0 + sin(a3) * 9.0)
			_crystal(p3, Color(0.75, 0.95, 1.0, 0.85))


func _star(p: Vector2, r: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(p + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, c)


func _crystal(p: Vector2, c: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(2, 0), p + Vector2(0, 4), p + Vector2(-2, 0)]), c)


## #81 17: one signature per elite modifier (data/fx.json "elite_fx": a particle look around the
## elite in the modifier's colour), so each modifier reads apart from the others.
func _elite_signature(mod: String) -> void:
	var spec: Dictionary = GameData.fx.get("elite_fx", {}).get(mod, {})
	if spec.is_empty():
		return
	var c := Color.from_string(str(GameData.elite_modifiers.get(mod, {}).get("color", "#ffffff")), Color.WHITE)
	var e := CPUParticles2D.new()
	e.name = "Elite_" + mod
	e.texture = GameData.texture("fx.pixel")
	e.amount = int(spec.get("amount", 8))
	e.lifetime = float(spec.get("life", 1.0))
	e.position = Vector2(0, float(spec.get("y", -14)))
	match str(spec.get("shape", "ring")):
		"ring":
			e.emission_shape = CPUParticles2D.EMISSION_SHAPE_RING
			e.emission_ring_radius = float(spec.get("radius", 16))
			e.emission_ring_inner_radius = float(spec.get("radius", 16)) * 0.8
		_:
			e.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			e.emission_sphere_radius = float(spec.get("radius", 14))
	e.direction = Vector2(0, -1) if str(spec.get("dir", "up")) == "up" else (Vector2(0, 1) if str(spec.get("dir", "")) == "down" else Vector2.ZERO)
	e.spread = float(spec.get("spread", 30))
	e.gravity = Vector2(0, float(spec.get("gravity", -20)))
	e.initial_velocity_min = float(spec.get("speed", 10)) * 0.5
	e.initial_velocity_max = float(spec.get("speed", 10))
	e.orbit_velocity_min = float(spec.get("orbit", 0.0))
	e.orbit_velocity_max = float(spec.get("orbit", 0.0))
	e.radial_accel_min = float(spec.get("radial", 0.0))
	e.radial_accel_max = float(spec.get("radial", 0.0))
	e.scale_amount_min = float(spec.get("size", 1.5)) * 0.6
	e.scale_amount_max = float(spec.get("size", 1.5))
	var ramp := Gradient.new()
	ramp.set_color(0, Color(c.r * 1.7, c.g * 1.7, c.b * 1.7, 0.9))
	ramp.set_color(1, Color(c, 0.0))
	e.color_ramp = ramp
	e.use_parent_material = true
	add_child(e)
	GameplayFx.note("elite_" + mod)
