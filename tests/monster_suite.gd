class_name MonsterSuite
extends RefCounted
## Headless monster checks (scenario "monsters", solo host): every monster definition (minus
## test-only ones) is spawned next to an invulnerable hero; it must use its abilities, and each
## of its behaviour modules runs its own test_trigger / test_check. --biome=<id> limits the run
## to one biome's monsters.

var da: Node
var g: Node
var p: Player
var start := Vector2.ZERO


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run(biome: String = "") -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.4)
	start = g.layout.start
	var ids: Array = GameData.monsters.keys()
	ids.sort()
	var n := 0
	for id in ids:
		var def: Dictionary = GameData.monsters[id]
		if def.get("test_only", false) or (def.ai.get("abilities", []).is_empty() and def.get("behaviors", []).is_empty()):
			continue
		if not biome.is_empty() and str(def.get("biome", "")) != biome:
			continue
		n += 1
		await check_monster(str(id))
	da.check(n > 0, "monster suite ran %d monsters" % n)


func check_monster(id: String) -> void:
	var def: Dictionary = GameData.monsters[id]
	_keep_hero()
	p.host_teleport(start)
	var e: Enemy = g.spawn_monster(id, g.nearest_floor(start + Vector2(80, 0)), false)
	await da._wait(0.3)
	if not is_instance_valid(e):
		da.check(false, "%s spawned" % id)
		return
	e.add_threat(p, 10.0)
	var abilities: Array = def.ai.get("abilities", [])
	var used := abilities.is_empty()
	var t := 0.0
	while t < 8.0 and not used and is_instance_valid(e):
		_keep_hero()
		var uses: Dictionary = Combat.instance.get_meta("uses", {})
		for sid in abilities:
			if uses.has("%s:%s" % [e.name, sid]):
				used = true
		await da._wait(0.25)
		t += 0.25
	# Ambushers (mimics, perched gargoyles, ink pools) only strike once their behaviour springs:
	# their ability check waits until the behaviour tests below have run.
	if used:
		da.check(used, "%s used one of its abilities" % id)
	if is_instance_valid(e):
		for b in e.behaviors:
			await b.test_trigger(self)
			var bt := 0.0
			var err := "not checked"
			while bt < float(b.params.get("test_wait", 4.0)):
				_keep_hero()
				err = b.test_check(self)
				if err.is_empty():
					break
				await da._wait(0.25)
				bt += 0.25
			da.check(err.is_empty(), "%s behaviour %s%s" % [id, b.params.get("id", "?"), "" if err.is_empty() else ": " + err])
	if not used:
		var t2 := 0.0
		while t2 < 6.0 and not used:
			_keep_hero()
			var uses2: Dictionary = Combat.instance.get_meta("uses", {})
			for sid in abilities:
				if uses2.has("%s:%s" % [e.name if is_instance_valid(e) else "", sid]):
					used = true
			await da._wait(0.25)
			t2 += 0.25
		da.check(used, "%s used one of its abilities" % id)
	for m in g.enemies_root.get_children():
		m.queue_free()
	Combat.instance.clear_floor()
	await da._wait(0.3)


func _keep_hero() -> void:
	if p.life_state != Player.Life.ALIVE:
		p.revive(1.0)
	p.iframe_left = 9999.0
	p.health.hp = p.health.max_hp
	p.status.clear_all()
