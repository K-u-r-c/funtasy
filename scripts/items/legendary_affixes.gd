class_name LegendaryAffixes
extends RefCounted
## Code hooks for the few legendary affixes (and keystones) that a data proc recipe cannot express.
## A proc names one with {"hook": "<id>", ...}; every hook is a function `hook_<id>`.

static var _probe: LegendaryAffixes


static func has_hook(id: String) -> bool:
	if _probe == null:
		_probe = LegendaryAffixes.new()
	return _probe.has_method("hook_" + id)



## Temporal Singularity (Mage T5): a fatal blow rewinds the hero 5 seconds (position and HP).
func hook_rewind(combat: Node, actor: Actor, _pr: Dictionary, data: Dictionary) -> void:
	var hist: Array = actor.get("history") if actor.get("history") != null else []
	if hist.is_empty():
		return
	var snap: Dictionary = hist[0]
	data.prevented = true
	actor.host_teleport(snap.pos)
	combat.get_tree().create_timer(0.01).timeout.connect(func():
		if is_instance_valid(actor) and actor.is_alive():
			actor.health.hp = maxf(actor.health.hp, minf(float(snap.hp), actor.health.max_hp)))
	combat.fx.number.rpc(actor.global_position, "Rewind", "info")
