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


## Predator's Breeches: a poisoned kill readies the dodge roll at once.
func hook_reset_dodge(combat: Node, actor: Actor, _pr: Dictionary, _data: Dictionary) -> void:
	if actor is Player:
		actor.host_reset_dodge()
		combat.fx.number.rpc(actor.global_position, "Dodge ready", "info")


## Wolfpack Talisman: a damage stack per living ally in range (the status holds the count).
func hook_wolfpack(_combat: Node, actor: Actor, pr: Dictionary, _data: Dictionary) -> void:
	var game := actor.get_tree().get_first_node_in_group("game")
	if game == null:
		return
	var n := 0
	for p in game.players_root.get_children():
		if p != actor and p.is_alive() and p.global_position.distance_to(actor.global_position) <= float(pr.get("radius", 300)):
			n += 1
	var st := str(pr.get("status", "wolfpack"))
	actor.status.remove(st)
	# The wearer counts as one of the pack, so a solo hero keeps a single stack.
	for i in n + 1:
		actor.status.apply(st, 1.4, 0.0, Combat.instance.env_ctx(0.0))


## Robe of Seven Cataclysms: switching elements empowers the next spell.
func hook_seven_cataclysms(_combat: Node, actor: Actor, _pr: Dictionary, data: Dictionary) -> void:
	var el := str(GameData.skills.get(str(data.get("skill", "")), {}).get("element", ""))
	if el.is_empty():
		return
	var last := str(actor.get_meta("last_element", ""))
	if actor.status.has("elemental_flux"):
		actor.status.remove("elemental_flux")  # spent on this cast
	if not last.is_empty() and last != el:
		actor.status.apply("elemental_flux", 8.0, 0.0, Combat.instance.env_ctx(0.0))
	actor.set_meta("last_element", el)


## Shroud of the Nethermancer: a foe slain by a dark spell bursts for 15% of its max HP.
func hook_nether_burst(combat: Node, actor: Actor, pr: Dictionary, data: Dictionary) -> void:
	var victim: Variant = data.get("target")
	if not is_instance_valid(victim):
		return
	var ctx: Dictionary = combat.make_ctx(actor, {"id": "nether_burst", "school": "spell", "damage_type": "shadow"})
	ctx.from_proc = true
	var amount: float = victim.health.max_hp * float(pr.get("pct", 0.15))
	for e in combat.enemies_of(actor.team, victim.global_position, float(pr.get("radius", 90))):
		if e != victim:
			combat.deal_damage(ctx, e, amount, {"damage_type": "shadow", "area": true})
	combat.fx.ring.rpc(victim.global_position, float(pr.get("radius", 90)), "#7030a0", "explosion")


## Staff of the Shattered Sky: every 5th spell calls down lightning on a random nearby foe.
func hook_fifth_cast(combat: Node, actor: Actor, pr: Dictionary, _data: Dictionary) -> void:
	var n := int(actor.get_meta("fifth_cast", 0)) + 1
	if n < int(pr.get("every", 5)):
		actor.set_meta("fifth_cast", n)
		return
	actor.set_meta("fifth_cast", 0)
	var foes: Array = combat.enemies_of(actor.team, actor.global_position, 360.0)
	if foes.is_empty():
		return
	var t: Actor = foes[randi() % foes.size()]
	var ctx: Dictionary = combat.make_ctx(actor, {"id": "sky_strike", "school": "spell", "damage_type": "lightning"})
	ctx.from_proc = true
	combat.deal_damage(ctx, t, float(ctx.power) * 1.5 + 10.0, {"damage_type": "lightning"})
	combat.fx.beam.rpc(t.global_position + Vector2(0, -220), t.global_position, "#c0e0ff", 0.25, "chain")
	combat.fx.sound.rpc("lightning", t.global_position)


## Grimoire of Forbidden Truths: the spell's effects again toward the same aim, free.
func hook_echo_cast(combat: Node, actor: Actor, _pr: Dictionary, data: Dictionary) -> void:
	var sk := GameData.skills.get(str(data.get("skill", "")), {}) as Dictionary
	if sk.is_empty() or sk.get("channel") != null or sk.has("charge_time"):
		return
	var aim: Vector2 = actor.get("aim_pos") if actor.get("aim_pos") != null else actor.global_position
	var ctx: Dictionary = combat.make_ctx(actor, sk)
	ctx.from_proc = true
	for eff in sk.get("effects", []):
		if str(eff.type) in ["projectile", "hit", "chain", "aoe", "line", "beam"]:
			combat.run_effect(eff, ctx, actor.global_position, aim)
	combat.fx.number.rpc(actor.global_position, "Echo", "info")


## Boots of Righteous Zeal: Rebuke carries the priest to the front of the target.
func hook_zeal_leap(_combat: Node, actor: Actor, pr: Dictionary, data: Dictionary) -> void:
	var aim: Vector2 = actor.get("aim_pos") if actor.get("aim_pos") != null else actor.global_position
	var to := aim - actor.global_position
	var step: float = minf(to.length() - 24.0, float(pr.get("range", 100)))
	if step <= 4.0:
		return
	var game := actor.get_tree().get_first_node_in_group("game")
	var dest: Vector2 = actor.global_position + to.normalized() * step
	if game:
		dest = game.nearest_floor(dest)
	actor.host_teleport(dest)
	Combat.instance.fx.blink.rpc(actor.global_position, dest)


## Guide's Radiant Leggings: allies close behind the priest run faster.
func hook_guide_aura(_combat: Node, actor: Actor, pr: Dictionary, _data: Dictionary) -> void:
	var game := actor.get_tree().get_first_node_in_group("game")
	if game == null:
		return
	for p in Combat.instance.allies_of(actor.team, actor.global_position, float(pr.get("radius", 160))):
		if p == actor or not p.is_alive():
			continue
		var off: Vector2 = p.global_position - actor.global_position
		if off.length() <= float(pr.get("radius", 160)) and off.dot(actor.facing) < 0.0:
			p.status.apply(str(pr.get("status", "guided")), 1.4, 0.0, Combat.instance.env_ctx(0.0))


## Exorcist's Iron Striders: undead and demons underfoot are stunned and seared.
func hook_exorcist_trample(combat: Node, actor: Actor, pr: Dictionary, _data: Dictionary) -> void:
	var ctx: Dictionary = combat.make_ctx(actor, {"id": "trample", "school": "spell", "damage_type": "holy"})
	ctx.from_proc = true
	for e in combat.enemies_of(actor.team, actor.global_position, float(pr.get("radius", 30))):
		if Array(pr.get("creatures", ["undead", "demon"])).has(e.creature_type()):
			combat.apply_status(ctx, e, "stun", 1.0, 0.0)
			combat.deal_damage(ctx, e, float(pr.get("damage", 100)) * Combat.legendary_scale(actor.level), {"damage_type": "holy"})
