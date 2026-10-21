class_name GfxSuite
extends RefCounted
## #81 gameplay effects (scenario "gfx" solo, "gfx_lan" host + client). Each effect is set off by
## its real mechanic and counted where it is drawn (GameplayFx.log, StatusFx.families, ScreenFx):
## dodge roll afterimages, dodge-chance avoid, parry and block sparks, crits (streak, hit-stop),
## the hit flash in the damage type's colour, every status family on an actor, leech motes, the
## shield ripple and thorns, a refused skill's slot shake, the low-health vignette and big-hit
## flash, the aggro "!", an elite's target line, a taunt, an interrupt, knockback dust, XP motes,
## gold and items flying to the HUD, the revive beam, splashes in water, heat over lava, floor
## marks and every elite modifier's signature. The screen-effects option turns shake, vignette
## and hit-stop off. Personal effects (vignette) only on their own hero's screen.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func n(kind: String) -> int:
	return int(GameplayFx.log.get(kind, 0))


func dummy(at: Vector2, extra: Dictionary = {}) -> Enemy:
	var d: Enemy = g.spawn_monster("training_dummy", at, false, extra)
	return d


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var start: Vector2 = g.nearest_floor(g.layout.start)
	p.host_teleport(start)
	var d0 := dummy(g.nearest_floor(start + Vector2(40, 0)))
	await da._wait(0.5)
	var ctx := Combat.instance.make_ctx(p, {"id": "test", "school": "physical"})
	ctx.cannot_miss = true
	# 1. Dodge roll afterimages.
	var k := n("dash")
	p._dodge_left = 0.25
	await da._wait(0.3)
	da.check(n("dash") > k, "a dodge roll leaves afterimages (%d)" % (n("dash") - k))
	# 2-3. Avoid, parry, block (the hero is hit by the dummy).
	var dctx := Combat.instance.make_ctx(d0, {"id": "test_attack", "school": "melee"})
	dctx.melee_hit = true
	p.run_mods = [{"stat": "dodge_uncapped", "value": 1.0, "source": "t"}]
	p.recompute_stats()
	k = n("avoid")
	Combat.instance.deal_damage(dctx, p, 5.0)
	await da._wait(0.1)
	da.check(n("avoid") > k, "a dodge-chance avoid blurs the hero aside")
	p.run_mods = []
	p.recompute_stats()
	p.status.apply("riposte", 3.0, 0.0, Combat.instance.make_ctx(p, {"id": "t", "school": "melee"}))
	k = n("parry")
	Combat.instance.deal_damage(dctx, p, 5.0)
	await da._wait(0.1)
	da.check(n("parry") > k, "a parry flashes sparks at the contact")
	p.run_mods = [{"stat": "block_chance", "value": 1.0, "source": "t"}]
	p.recompute_stats()
	k = n("block")
	dctx.cannot_miss = true
	for i in 6:  # block chance is capped below 100%
		p.facing = (d0.global_position - p.global_position).normalized()
		Combat.instance.deal_damage(dctx, p, 5.0)
		if n("block") > k:
			break
	await da._wait(0.1)
	da.check(n("block") > k, "a block glints on the shield")
	p.run_mods = []
	p.recompute_stats()
	p.health.hp = p.health.max_hp
	# Also the other avoided hits: a miss whiffs past, an immune hit rings on the ward.
	var mctx := Combat.instance.make_ctx(d0, {"id": "test_attack", "school": "melee"})
	mctx.melee_hit = true
	d0.stats.final["miss_chance"] = 1.0
	k = n("miss")
	Combat.instance.deal_damage(mctx, p, 5.0)
	d0.stats.final["miss_chance"] = 0.0
	p.iframe_left = 1.0
	var ki := n("immune")
	dctx.cannot_miss = true
	Combat.instance.deal_damage(dctx, p, 5.0)
	p.iframe_left = 0.0
	await da._wait(0.1)
	da.check(n("miss") > k and n("immune") > ki, "a miss whiffs past and an immune hit rings on the ward")
	# 4-5. Crit with hit-stop; hit flash colour.
	var cctx := ctx.duplicate()
	cctx.guaranteed_crit = true
	k = n("crit")
	await da._wait(0.5)
	var hs := n("hit_stop")
	Combat.instance.deal_damage(cctx, d0, 5.0)
	await da._wait(0.2)
	da.check(n("crit") > k and n("hit_stop") > hs, "a crit streaks the target and stops time for a blink")
	hs = n("hit_stop")
	Combat.instance.deal_damage(cctx, d0, 5.0)
	await da._wait(0.05)
	da.check(n("hit_stop") == hs, "a second crit right after doesn't stop time again")
	Combat.instance.deal_damage(ctx, d0, 5.0, {"damage_type": "fire"})
	await da._wait(0.02)
	da.check(d0._flash_color.is_equal_approx(Color.from_string(Combat.type_color("fire"), Color.WHITE)), "a fire hit flashes the fire colour")
	# 6. Every status family.
	var fam := {"burning": "burn", "poison": "poison", "bleed": "bleed", "frozen": "freeze", "chill": "chill", "stunned": "stun",
		"slowed": "slow", "rooted": "root", "chained": "shackle", "silenced": "silence", "feared": "fear", "blinded": "blind",
		"haste": "haste_potion", "enraged": "enrage", "invulnerable": "invulnerable", "cracks": "sunder", "marked": "hunters_mark"}
	var missing := []
	for f in fam:
		d0.status.clear_all()
		d0.status.apply(str(fam[f]), 4.0, 2.0, ctx)
		await da._wait(0.35)
		var sfx: StatusFx = d0.get_node("StatusFx")
		if not sfx.families.has(f):
			missing.append("%s (%s -> %s)" % [f, fam[f], sfx.families.keys()])
	d0.status.clear_all()
	da.check(missing.is_empty(), "every status shows on the actor (%d families)%s" % [fam.size(), "" if missing.is_empty() else ": %s" % [missing]])
	var unmapped := []
	for id in GameData.status_effects:
		var sd: Dictionary = GameData.status_effects[id]
		if bool(sd.get("debuff", false)) and str(sd.get("kind", "")) in ["cc", "dot", "mark"] and StatusFx.family_of(str(id)).is_empty():
			unmapped.append(id)
	da.check(unmapped.is_empty(), "every control, damage-over-time and mark status has a look%s" % ("" if unmapped.is_empty() else ": %s" % [unmapped]))
	# 7-8. Leech, shield ripple, thorns.
	p.run_mods = [{"stat": "leech", "value": 0.5, "source": "t"}, {"stat": "reflect_all", "value": 0.5, "source": "t"}]
	p.recompute_stats()
	p.health.hp = p.health.max_hp * 0.5
	var lctx := Combat.instance.make_ctx(p, {"id": "test", "school": "physical"})
	lctx.cannot_miss = true
	k = n("leech")
	Combat.instance.deal_damage(lctx, d0, 30.0)
	await da._wait(0.1)
	da.check(n("leech") > k, "leech sends red motes into the hero")
	k = n("reflect")
	Combat.instance.deal_damage(dctx, p, 10.0)
	await da._wait(0.1)
	da.check(n("reflect") > k, "thorns flash back at the attacker")
	p.run_mods = []
	p.recompute_stats()
	d0.health.absorb = 50.0
	k = n("absorb_hit")
	Combat.instance.deal_damage(ctx, d0, 10.0)
	await da._wait(0.1)
	da.check(n("absorb_hit") > k, "a hit on a shield ripples it")
	# 9. A refused skill press shakes its slot.
	k = n("slot_refused")
	p.local_cd[1] = [5.0, 5.0]
	Input.action_press("skill_1")
	await da._wait(0.15)
	Input.action_release("skill_1")
	await da._wait(0.1)
	p.local_cd.erase(1)
	da.check(n("slot_refused") > k, "pressing a skill on cooldown shakes its slot red")
	# 10. Low health and a big hit (local screen effects), and the option off.
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	var sfx2: ScreenFx = hud._screen_fx
	p.health.hp = p.health.max_hp
	await da._wait(0.2)
	var fl := sfx2.flashes
	p.health.hp = p.health.max_hp * 0.2
	await da._wait(0.3)
	da.check(sfx2.low and sfx2.flashes > fl, "low health pulses a red vignette; a big hit flashes the edges")
	Settings.screen_shake = false
	await da._wait(0.2)
	hs = n("hit_stop")
	Combat.instance.deal_damage(cctx, d0, 5.0)
	await da._wait(0.2)
	da.check(not sfx2.low and n("hit_stop") == hs, "with screen effects off: no vignette, no hit-stop")
	Settings.screen_shake = true
	p.health.hp = p.health.max_hp
	# 11. Aggro "!", an elite's target line, a taunt.
	k = n("aggro")
	var gh: Enemy = g.spawn_monster("ghoul", g.nearest_floor(start + Vector2(70, 20)), false, {"elite": ["vampiric"]})
	await da._wait(0.3)
	gh.set_physics_process(false)
	gh.aggro = true
	gh.target = p
	gh.target_peer = p.peer_id
	await da._wait(0.3)
	da.check(n("aggro") > k, "a monster that notices a hero pops a \"!\"")
	da.check(n("target_line") > 0, "an elite draws a faint line to the hero it is after")
	k = n("taunt")
	Combat.instance.run_effect({"type": "taunt", "radius": 200, "duration": 2.0}, ctx, p.global_position, p.global_position)
	await da._wait(0.1)
	da.check(n("taunt") > k, "a taunt flashes between the taunter and the monster")
	# 12-13. Interrupt, knockback.
	gh.casting = {"skill": "test", "left": 2.0, "total": 2.0}
	k = n("interrupt")
	Combat.instance.run_effect({"type": "interrupt", "target": "aim_enemy"}, ctx, p.global_position, gh.global_position)
	await da._wait(0.1)
	da.check(n("interrupt") > k, "an interrupt shatters the cast bar")
	k = n("knock")
	Combat.instance.knock(gh, Vector2(400, 0))
	await da._wait(0.1)
	da.check(n("knock") > k, "a knockback kicks up a dust trail")
	# 14. XP motes, gold and an item flying to the HUD.
	k = n("xp")
	gh.contributors[p.peer_id] = Time.get_ticks_msec() / 1000.0
	Combat.instance.deal_damage(ctx, gh, 999999.0, {"damage_type": "true"})
	await da._wait(0.3)
	da.check(n("xp") > k, "XP motes fly from the kill to the hero")
	for it in g.items_root.get_children():
		it.queue_free()
	await da._wait(0.1)
	var kg := n("fly_gold")
	ki = n("fly_item")
	g.loot.drop_item(LootTable.make_gold(5, RandomNumberGenerator.new()), p.global_position + Vector2(6, 0))
	g.loot.drop_item(ItemGenerator.generate_consumable("potion_health", 1, RandomNumberGenerator.new()), p.global_position + Vector2(-6, 0))
	await da._wait(0.3)
	for it in g.items_root.get_children():
		g.loot.try_pickup(p, it)
	await da._wait(0.3)
	da.check(n("fly_gold") > kg and n("fly_item") > ki, "picked-up gold flies to the gold count, an item to the backpack")
	# 16. Floor marks.
	k = n("decal_fire")
	Combat.instance.fx.ring(p.global_position + Vector2(40, 40), 50.0, "#ff6a20", "", "fire")
	await da._wait(0.05)
	da.check(n("decal_fire") > k, "a fire area scorches the floor for a while")
	# 17. Every elite modifier's signature.
	var mods: Array = GameData.elite_modifiers.keys()
	var no_sig := []
	for m in mods:
		var e: Enemy = g.spawn_monster("ghoul", g.nearest_floor(start + Vector2(-60, 30)), false, {"elite": [m]})
		await da._wait(0.15)
		if e.get_node("StatusFx").get_node_or_null("Elite_" + str(m)) == null:
			no_sig.append(m)
		e.queue_free()
	da.check(no_sig.is_empty(), "every elite modifier has its own signature (%d)%s" % [mods.size(), "" if no_sig.is_empty() else ": %s" % [no_sig]])
	# 16. Splashes in water (the Sewers, floor 2) and heat over lava (the Foundry, floor 3).
	g.start_floor(2)
	await da._wait(1.5)
	var water := Vector2.INF
	for y in g.dungeon.size.y:
		for x in g.dungeon.size.x:
			if water == Vector2.INF and g.dungeon.cell_at(Vector2i(x, y)) == DungeonGenerator.CELL_WATER:
				water = g.dungeon.cell_center(Vector2i(x, y))
	da.check(water != Vector2.INF, "the Sewers floor has water")
	if water != Vector2.INF:
		k = n("splash")
		for i in 12:
			p.host_teleport(water + Vector2(i % 2 * 6 - 3, 0))
			await da._wait(0.06)
		da.check(n("splash") > k, "footsteps splash in water")
	g.start_floor(3)
	await da._wait(1.5)
	var shimmer := 0
	for l in g.dungeon.lights:
		if is_instance_valid(l) and l.get_child_count() > 0 and l.get_child(0) is CPUParticles2D:
			shimmer += 1
	da.check(shimmer > 0, "heat shimmers over the Foundry's lava (%d pools)" % shimmer)


## LAN: the client sees the host's effects on itself and on monsters; its own vignette is its own.
func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	var start: Vector2 = g.nearest_floor(g.layout.start)
	p.host_teleport(start)
	c.host_teleport(g.nearest_floor(start + Vector2(30, 30)))
	var d0 := dummy(g.nearest_floor(start + Vector2(60, 0)))
	await da._wait(0.8)
	var ctx := Combat.instance.make_ctx(p, {"id": "test", "school": "physical"})
	ctx.cannot_miss = true
	var cctx := ctx.duplicate()
	cctx.guaranteed_crit = true
	var hs: int = GameplayFx.log.get("hit_stop", 0)
	Combat.instance.deal_damage(cctx, d0, 5.0)
	da.check(GameplayFx.log.get("hit_stop", 0) == hs and Engine.time_scale == 1.0, "host with a client: a crit never stops the shared world")
	d0.status.apply("burn", 6.0, 1.0, ctx)
	d0.health.absorb = 50.0
	Combat.instance.deal_damage(ctx, d0, 10.0)
	var dctx := Combat.instance.make_ctx(d0, {"id": "test_attack", "school": "melee"})
	c.run_mods = [{"stat": "dodge_uncapped", "value": 1.0, "source": "t"}]
	c.recompute_stats()
	Combat.instance.deal_damage(dctx, c, 5.0)
	c.run_mods = []
	c.recompute_stats()
	# The client goes down and the host revives it: the beam shows on both.
	c.life_state = Player.Life.DOWNED
	c.downed_left = 30.0
	c._reviver = p
	await da._wait(0.6)
	da.check(c.reviver_peer == p.peer_id and GameplayFx.log.get("revive_beam", 0) > 0, "host: the revive beam shows while the revive channels")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["gf_seen", d0.get_path()])
	await da._wait(1.0)
	c._reviver = null
	c.revive(1.0)
	await da._wait(0.3)
	# The client's hero at low health: its vignette, not the host's.
	c.health.hp = c.health.max_hp * 0.2
	await da._wait(0.5)
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	da.check(not hud._screen_fx.low, "host: a teammate's low health doesn't pulse my vignette")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["gf_low", null])
	await da._wait(1.0)
	c.health.hp = c.health.max_hp


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	var me: Player = da._local()
	match cmd:
		"gf_seen":
			var d: Node = da.get_node_or_null(NodePath(str(arg)))
			var fams: Dictionary = d.get_node("StatusFx").families if d else {}
			da.check(int(GameplayFx.log.get("crit", 0)) > 0 and int(GameplayFx.log.get("absorb_hit", 0)) > 0 and int(GameplayFx.log.get("avoid", 0)) > 0,
				"client: the crit, the shield ripple and my avoid show here (%s)" % [GameplayFx.log])
			da.check(fams.has("burning"), "client: the burning monster burns on my screen too")
			da.check(int(GameplayFx.log.get("revive_beam", 0)) > 0, "client: the revive beam shows on my screen")
		"gf_low":
			var hud: Node = da.get_tree().get_first_node_in_group("hud")
			da.check(hud._screen_fx.low and int(GameplayFx.log.get("heartbeat", 0)) > 0, "client: my low health pulses my vignette with a heartbeat")
