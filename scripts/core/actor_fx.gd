class_name ActorFx
extends Node2D
## Effects drawn on an actor (#33), on every peer:
## - one-shots the host asks for (CombatFx.actor_fx): a heal burst, a buff or cleanse flash;
## - loops read from replicated state: a glow while a heal over time runs (Status:shown) and a
##   shield bubble while an absorb holds (Health:absorb), which shatters when it breaks.
## The keys, placement and scale come from data/fx.json.

var actor: Actor
var _loops: Dictionary = {}  ## role -> AnimatedSprite2D
var _had_absorb := false


func _init(a: Actor) -> void:
	actor = a
	name = "ActorFx"


func _process(_delta: float) -> void:
	if not is_instance_valid(actor) or actor.health == null:
		return
	var alive := actor.is_alive()
	var hot := false
	if alive:
		for s in actor.status.shown:
			var def: Dictionary = GameData.status_effects.get(str(s[0]), {})
			if str(def.get("kind", "")) == "hot" and not def.get("debuff", false):
				hot = true
				break
	_set_loop("hot", hot)
	var shield := alive and actor.health.absorb > 0.5
	_set_loop("shield", shield)
	if _had_absorb and not shield and alive:
		play("shield_break")
	_had_absorb = shield


## A one-shot effect of `role` (data/fx.json "actor") on this actor.
func play(role: String) -> void:
	var spec: Dictionary = GameData.fx.get("actor", {}).get(role, {})
	var a := make(spec, false)
	if a == null:
		return
	add_child(a)
	a.play("default")
	a.animation_finished.connect(a.queue_free)
	var l := _light(spec)
	if l:
		var t := l.create_tween()
		t.tween_property(l, "energy", 0.0, float(spec.light.get("time", 0.6)))
		t.tween_callback(l.queue_free)


func _set_loop(role: String, on: bool) -> void:
	var cur: AnimatedSprite2D = _loops.get(role)
	if on and cur == null:
		cur = make(GameData.fx.get("loop", {}).get(role, {}), true)
		if cur:
			add_child(cur)
			cur.play("default")
			_loops[role] = cur
			var l := _light(GameData.fx.get("loop", {}).get(role, {}))
			if l:
				l.reparent(cur, false)
	elif not on and cur != null:
		cur.queue_free()
		_loops.erase(role)


## The spec's coloured light on the actor (it lights the hero sprite too), or null.
func _light(spec: Dictionary) -> PointLight2D:
	if not spec.has("light"):
		return null
	var ls: Dictionary = spec.light
	var l := PointLight2D.new()
	LightLayers.setup_light(l)
	l.texture = GameData.texture("fx.light")
	l.color = Color.from_string(str(ls.get("color", "#ffffff")), Color.WHITE)
	l.energy = float(ls.get("energy", 1.0))
	LightLayers.register(l, float(ls.get("radius", 48)))
	l.position = Vector2(0, -12)
	add_child(l)
	return l


## An animated sprite for a {key, at, scale, behind} spec, its anchor put on the actor's centre or
## feet; additive, so it glows in the dark.
func make(spec: Dictionary, loop: bool) -> AnimatedSprite2D:
	var key := str(spec.get("key", ""))
	if key.is_empty() or not GameData.asset_exists(key):
		return null
	var a := CombatFx.anim_sprite(key, loop)
	if a == null:
		return null
	var sc := float(spec.get("scale", 1.0))
	a.scale = Vector2(sc, sc)
	var h: float = actor.sprite.visual_height() if actor.sprite else 32.0
	a.position = Vector2(0, -h * 0.45) if str(spec.get("at", "center")) == "center" else Vector2.ZERO
	a.show_behind_parent = bool(spec.get("behind", false))
	a.z_index = 0 if a.show_behind_parent else 1
	return a
