class_name BossSuite
extends RefCounted
## Headless boss checks (scenario "bosses", solo host): every boss is spawned in the boss room
## next to an invulnerable hero; each phase is forced by setting the boss's health, the boss
## must use one of the phase's abilities, and every arena mechanic of the phase runs its own
## test_trigger / test_check. --biome=<id> limits the run to one biome's bosses.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run(biome: String = "") -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	var ids: Array = GameData.bosses.keys()
	ids.sort()
	var n := 0
	for id in ids:
		if not biome.is_empty() and str(GameData.bosses[id].get("biome", "")) != biome:
			continue
		n += 1
		await check_boss(str(id))
	da.check(n > 0, "boss suite ran %d bosses" % n)


func check_boss(id: String) -> void:
	for e in g.enemies_root.get_children():
		e.queue_free()
	Combat.instance.clear_floor()
	await da._wait(0.4)
	var boss_pos: Vector2 = g.layout.boss_pos
	_keep_hero()
	p.host_teleport(g.nearest_floor(boss_pos + Vector2(0, 70)))
	var boss: Enemy = g.spawn_monster(id, boss_pos, true)
	await da._wait(0.3)
	if not is_instance_valid(boss):
		da.check(false, "%s spawned" % id)
		return
	boss.add_threat(p, 10.0)
	var phases: Array = boss.def.phases
	for i in phases.size():
		if i > 0:
			boss.health.absorb = 0.0
			boss.health.hp = boss.health.max_hp * maxf(float(phases[i - 1].hp_above) - 0.03, 0.02)
			await _wait_for(func(): return boss.phase >= i, 6.0)
		da.check(boss.phase == i, "%s entered phase %d" % [id, i + 1])
		# One of the phase's abilities, unless a mechanic keeps the boss busy the whole time.
		var used := false
		var t := 0.0
		while t < 10.0 and not used and is_instance_valid(boss):
			_keep_hero()
			var uses: Dictionary = Combat.instance.get_meta("uses", {})
			for sid in phases[i].abilities:
				if uses.has("%s:%s" % [boss.name, sid]):
					used = true
			if boss.mechanics_busy():
				used = true
			await da._wait(0.25)
			t += 0.25
		da.check(used, "%s used a phase %d ability" % [id, i + 1])
		for m in boss.mechanics.duplicate():
			await m.test_trigger(self)
			var mt := 0.0
			var err := "not checked"
			while mt < float(m.params.get("test_wait", 4.0)):
				_keep_hero()
				err = m.test_check(self)
				if err.is_empty():
					break
				await da._wait(0.25)
				mt += 0.25
			da.check(err.is_empty(), "%s phase %d mechanic %s%s" % [id, i + 1, m.params.get("id", "?"), "" if err.is_empty() else ": " + err])
	# The kill: mechanics clean up their arena objects.
	var ctx := Combat.instance.make_ctx(p, {"id": "test_kill", "school": "spell"})
	var guard := 0
	while is_instance_valid(boss) and boss.is_alive() and guard < 300:
		guard += 1
		boss.health.absorb = 0.0
		Combat.instance.deal_damage(ctx, boss, boss.health.max_hp * 0.2, {"damage_type": "true"})
		await da.get_tree().physics_frame
	da.check(not is_instance_valid(boss) or not boss.is_alive(), "%s dies" % id)
	await da._wait(0.5)
	var leftovers := 0
	for k in g.dungeon.props:
		if str(k).begins_with("Cage_") or str(k).begins_with("Shrine_"):
			leftovers += 1
	da.check(leftovers == 0, "%s left no arena objects behind" % id)
	p.status.clear_all()


func _wait_for(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		_keep_hero()
		if cond.call():
			return true
		await da._wait(0.2)
		t += 0.2
	return false


## Keeps the hero standing without wiping the statuses the mechanics put on them.
func _keep_hero() -> void:
	if p.life_state != Player.Life.ALIVE:
		p.revive(1.0)
	p.iframe_left = 9999.0
	p.health.hp = p.health.max_hp
	for s in p.status.effects:
		var seen: Array = p.get_meta("test_seen_status", [])
		if not seen.has(s.id):
			seen.append(s.id)
			p.set_meta("test_seen_status", seen)
