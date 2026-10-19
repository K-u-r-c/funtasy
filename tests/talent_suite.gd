class_name TalentSuite
extends RefCounted
## #27 talent checks on a solo host (scenario "talents", one class per run):
## - points per level (talents and free stat points) come from data (#45: 1 and 5), a save that
##   spent more than the new totals is refunded, and every branch's top tier is reachable;
## - every passive node can be learned once its branch has the points its tier needs, and each of
##   its mods changes the stat (or skill modifier) it names, in the right direction;
## - the new passives (icon "tl_*") number at least 20, have icons and numbers in their text;
## - the tree panel shows every node and the gamepad / keyboard focus reaches all of them.

var da: Node
var g: Node
var p: Player

## Stats a "<stat>_pct" mod scales as a whole (the others become "<stat>_mult" multipliers).
const RELATIVE := ["strength", "stamina", "agility", "intellect", "armor", "max_hp", "max_resource", "move_speed", "resource_regen", "crit_damage"]


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	p.iframe_left = 9999.0
	await points_per_level()
	await old_save()
	await every_node()
	await panel()


func points_per_level() -> void:
	var tp := p.talent_points
	var sp := p.stat_points
	p.add_xp(Player.xp_to_next(p.level))
	await da._wait(0.3)
	var want_t := int(GameData.bal("progression.talent_points_per_level"))
	var want_s := int(GameData.bal("progression.stat_points_per_level"))
	da.check(want_t == 1 and want_s == 5 and p.talent_points == tp + want_t and p.stat_points == sp + want_s,
			"a level gives %d talent points and %d stat points (+%d / +%d)" % [want_t, want_s, p.talent_points - tp, p.stat_points - sp])


## #45: a level 10 hero has 9 talent and 45 stat points. A save from the #27 rules (3 / 10 per
## level) that spent 27 talents and 90 stat points loads with both pools refunded whole and a
## message; one that spent within the new totals keeps everything; loading twice changes nothing.
func old_save() -> void:
	var keep: Dictionary = GameState.characters.get(p.peer_id, {})
	var tree := p.talent_tree()
	var spent := {}
	var n := 0
	for nd in tree.nodes:
		if nd.get("type", "") == "passive" and not p.is_free_node(nd) and n < 27:
			var r := mini(int(nd.get("max_rank", 1)), 27 - n)
			spent[nd.id] = r
			n += r
	var ch: Dictionary = p.to_character()
	ch.level = 10
	ch.xp = 0
	ch.talents = spent
	ch.allocated = {"strength": 40, "stamina": 50}
	ch.erase("bonus_talent_points")
	ch.erase("bonus_stat_points")
	GameState.characters[p.peer_id] = ch
	var got: Array = []
	var cb := func(t: String, _col: Color): got.append(t)
	EventBus.hud_message.connect(cb)
	for i in 2:
		p._host_init()
		da.check(n == 27 and p.talent_points == 9 and p.stat_points == 45 and p.talents.is_empty() and p.allocated.is_empty() \
				and p.points_refunded == ["stat", "talent"] and p.loadout_error(p.skills).is_empty(),
				"an over-spent level 10 save (27 talents, 90 stat points) loads refunded: %d talent and %d stat points to spend, a valid loadout (load %d)" % [p.talent_points, p.stat_points, i + 1])
	await da._wait(2.5)
	EventBus.hud_message.disconnect(cb)
	da.check(got.has(Loc.t("Talent and stat points refunded: spend them again.")), "the hero is told the points were refunded (%s)" % [got])
	# Spent within the new totals: kept.
	var small := {}
	n = 0
	for k in spent:
		if n + int(spent[k]) <= 9:
			small[k] = spent[k]
			n += int(spent[k])
	ch.talents = small
	ch.allocated = {"strength": 20, "stamina": 25}
	GameState.characters[p.peer_id] = ch
	p._host_init()
	da.check(p.talent_points == 9 - n and p.stat_points == 0 and p.talents == small and int(p.allocated.get("stamina", 0)) == 25 and p.points_refunded.is_empty(),
			"a level 10 save within the new totals keeps its %d talents and 45 stat points" % n)
	# Every point can be spent: with 1 point per level every branch's top tier opens by level 15.
	var tp := int(tree.get("tier_points", 2))
	var per := int(GameData.bal("progression.talent_points_per_level"))
	var top_level := 1 + int(ceil(float(5 * tp + 1) / per))
	var short: Array = []
	for br in tree.get("branches", []):
		for tier in range(1, 6):
			var below := 0
			for nd in tree.nodes:
				if str(nd.get("branch", "")) == str(br.id) and int(nd.get("tier", 0)) < tier and not p.is_free_node(nd):
					below += int(nd.get("max_rank", 1))
			if below < tier * tp:
				short.append("%s tier %d" % [br.id, tier])
	da.check(top_level <= 15 and short.is_empty(), "every branch's top tier opens by level %d (gate %d points a tier)%s" % [top_level, tp, "" if short.is_empty() else ": short %s" % [short]])
	GameState.characters[p.peer_id] = keep
	p._host_init()


func every_node() -> void:
	var tree := p.talent_tree()
	var tier_points := int(tree.get("tier_points", 2))
	var keep_level := p.level
	p.level = 30
	# A flat armor and mana base so that "+x% armor / mana" has something to scale.
	p.run_mods.append({"stat": "armor", "value": 60.0, "source": "test"})
	var news := 0
	var bad: Array = []
	var bare: Array = []
	var checked := 0
	for nd in tree.nodes:
		if nd.get("type", "") != "passive":
			continue
		if str(nd.get("icon", "")).begins_with("tl_"):
			news += 1
			if not GameData.asset_exists("icons." + str(nd.icon)):
				bare.append("%s: no icon" % nd.id)
			if not str(nd.get("description", "")).contains("%") and not str(nd.get("description", "")).to_lower().contains("one more"):
				bare.append("%s: no number" % nd.id)
		# Prerequisites: lower tiers of the branch up to the points the node's tier needs.
		var need := int(nd.get("tier", 0)) * tier_points
		var t := {}
		var have := 0
		for f in tree.nodes:
			if have >= need:
				break
			if f.branch != nd.branch or int(f.get("tier", 0)) >= int(nd.tier) or p.is_free_node(f) or f.id == nd.id:
				continue
			var r := mini(int(f.get("max_rank", 1)), need - have)
			t[f.id] = r
			have += r
		for req in nd.get("requires", []):
			t[req] = 1
		p.talents = t
		p.recompute_stats()
		var before: Dictionary = p.stats.final.duplicate()
		var smods_before: Dictionary = p.stats.skill_mods.duplicate(true)
		p.talent_points = 99
		p.request_learn_talent.rpc_id(1, str(nd.id))
		await da.get_tree().process_frame
		if int(p.talents.get(nd.id, 0)) != 1:
			bad.append("%s can't be learned (%d / %d points in %s)" % [nd.id, have, need, nd.branch])
			continue
		p.recompute_stats()
		for m in nd.get("mods", []):
			var why := _effect_missing(m, before, smods_before)
			if not why.is_empty():
				bad.append("%s: %s" % [nd.id, why])
		checked += 1
	p.run_mods = p.run_mods.filter(func(m): return str(m.get("source", "")) != "test")
	p.talents = {}
	p.level = keep_level
	p.talent_points = p._talent_points_total()
	p.recompute_stats()
	da.check(news >= 20, "%s has %d new passive talents (at least 20)" % [p.class_id, news])
	# The tree is never full before the level cap (tomes aside): more ranks than points.
	var ranks := 0
	for nd2 in tree.nodes:
		ranks += 0 if p.is_free_node(nd2) else int(nd2.get("max_rank", 1))
	var at_cap := (int(GameData.bal("progression.max_level")) - 1) * int(GameData.bal("progression.talent_points_per_level"))
	da.check(ranks > at_cap, "%s: the tree holds %d ranks, more than the %d points of a level %d hero" % [p.class_id, ranks, at_cap, int(GameData.bal("progression.max_level"))])
	da.check(bare.is_empty(), "every new %s passive has an icon and its numbers in the tooltip%s" % [p.class_id, "" if bare.is_empty() else ": %s" % [bare]])
	da.check(checked > 0 and bad.is_empty(), "all %d %s passives can be learned and change the stats they name%s" % [checked, p.class_id, "" if bad.is_empty() else ": %s" % [bad]])


## "" when mod `m` (rank 1) moved its stat from `before` to the current stats the way it says.
func _effect_missing(m: Dictionary, before: Dictionary, smods_before: Dictionary) -> String:
	var v := float(m.value)
	if m.has("skill"):
		for sid in (m.skill if m.skill is Array else [m.skill]):
			var b0 := float(smods_before.get(sid, {}).get(m.field, 0.0))
			var b1 := float(p.stats.skill_mods.get(sid, {}).get(m.field, 0.0))
			if absf(b1 - b0 - v) > 0.0001:
				return "%s %s %.3f -> %.3f" % [sid, m.field, b0, b1]
		return ""
	var stat := str(m.stat)
	var key := stat
	var relative := false
	if stat.ends_with("_pct") or stat.ends_with("_mult"):
		var base := stat.trim_suffix("_pct").trim_suffix("_mult")
		relative = RELATIVE.has(base)
		key = base if relative else base + "_mult"
	var a := float(before.get(key, 0.0))
	var b := float(p.stats.final.get(key, 0.0))
	var change := (b / a - 1.0) if relative and a != 0.0 else b - a
	if signf(change) != signf(v) or absf(change) < absf(v) * 0.4:
		return "%s %.3f -> %.3f (mod %+.3f)" % [key, a, b, v]
	return ""


## The tree shows every node; walking the focus with the arrow keys from the first node reaches
## all of them (and the reset button), and every node lies inside the window.
func panel() -> void:
	var hud: Node = da.get_tree().get_first_node_in_group("hud")
	hud.open_overlay(hud.menu_panel("talents"))
	await da._wait(0.6)
	var tp: Node = hud._overlay
	var nodes: int = p.talent_tree().nodes.size()
	var buttons: Dictionary = tp._buttons
	var seen := {}
	var start: Control = buttons.values()[0][0]
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Control = queue.pop_back()
		if seen.has(c):
			continue
		seen[c] = true
		for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
			var np := c.get_focus_neighbor(side)
			if np.is_empty():
				continue
			var n: Node = c.get_node_or_null(np)
			if n is Control and not seen.has(n):
				queue.append(n)
	var reached := 0
	var outside: Array = []
	var view := Rect2(Vector2.ZERO, da.get_viewport().get_visible_rect().size)
	for id in buttons:
		var b: Control = buttons[id][0]
		if seen.has(b):
			reached += 1
		if not view.encloses(b.get_global_rect()):
			outside.append(id)
	da.check(buttons.size() == nodes and reached == nodes, "the talent panel shows all %d nodes and the arrow keys / d-pad reach %d of them" % [nodes, reached])
	da.check(outside.is_empty(), "every talent node lies inside the window (%s)" % [outside])
	hud.close_overlay()
