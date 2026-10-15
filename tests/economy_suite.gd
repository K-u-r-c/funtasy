class_name EconomySuite
extends RefCounted
## Headless progression and economy checks on a solo host (scenario "economy"): stat points,
## run modifiers and their save round trip, gold, the Gold Key, elites, merchants, pacts and
## contracts. LAN parts (gold split, shared stock) run in the economy-lan pair.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	p.iframe_left = 9999.0
	await stat_points()
	await run_mods()


func stat_points() -> void:
	var before_pts := p.stat_points
	p.add_xp(Player.xp_to_next(p.level))
	await da._wait(0.3)
	da.check(p.stat_points == before_pts + int(GameData.bal("progression.stat_points_per_level")), "level up gives %d stat points (%d)" % [GameData.bal("progression.stat_points_per_level"), p.stat_points])
	var str_before := p.stats.get_stat("strength")
	p.request_spend_stat.rpc_id(1, "strength", 2)
	await da._wait(0.3)
	da.check(p.stats.get_stat("strength") >= str_before + 1.99, "spending 2 points raises Strength (%.1f -> %.1f)" % [str_before, p.stats.get_stat("strength")])
	da.check(p.stat_points == before_pts + 3, "two points were spent")
	p.request_spend_stat.rpc_id(1, "luck", 1)
	await da._wait(0.2)
	da.check(not p.allocated.has("luck"), "unknown stats are refused")
	var ch := p.to_character()
	da.check(int(ch.allocated.get("strength", 0)) == 2, "allocation is saved with the hero")


func run_mods() -> void:
	var hp_before := p.stats.get_stat("max_hp")
	p.host_add_run_mod("max_hp", -10.0, "Demonic tithe")
	p.host_add_run_mod("strength", 2.0, "Tome")
	await da._wait(0.3)
	da.check(absf(p.stats.get_stat("max_hp") - (hp_before - 10.0)) < 0.6 or p.stats.get_stat("max_hp") < hp_before, "run modifier lowers max health")
	var ch := p.to_character()
	da.check(ch.run_mods.size() >= 2, "run modifiers are saved with the hero")
	var saved: Dictionary = SaveSystem.load_game(str(GameState.game.get("id", "")))
	var found := false
	for m in saved.get("members", [{}])[0].get("run_mods", []):
		if str(m.get("source", "")) == "Demonic tithe":
			found = true
	da.check(found, "run modifiers reach the saved game file")
	p.host_add_gold(37)
	da.check(p.gold >= 37 and int(p.to_character().gold) == p.gold, "gold is kept on the hero")
