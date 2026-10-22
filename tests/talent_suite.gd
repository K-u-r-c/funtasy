class_name TalentSuite
extends RefCounted
## #27 talent checks on a solo host (scenario "talents", one class per run):
## - points per level (talents and free stat points) come from data (#45: 1 and 5), a save that
##   spent more than the new totals is refunded, and every branch's top tier is reachable;
## - every passive node can be learned once its branch has the points its tier needs, and each of
##   its mods changes the stat (or skill modifier) it names, in the right direction;
## - the new passives (icon "tl_*") number at least 20, have icons and numbers in their text;
## - the tree panel shows every node and the gamepad / keyboard focus reaches all of them;
## - #47: the tree is a valid graph (GameData.tree_problems), a rank without its prerequisite or
##   on the closed side of a fork is refused by the host, a save that no longer fits is refunded,
##   and over LAN (scenario "talents_lan") the host refuses the client the same way.

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
	await tree_rules()
	shared_root()
	if p.class_id == "mage":
		await meteor_deeper()
	await every_node()
	await panel()


## #47 over LAN: the client asks for ranks through the real RPC; the host refuses a node without
## its prerequisite and the closed side of a fork (the client reads why), and learns them once
## the path is taken.
func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	var c: Player = da._other_player()
	c.level = 20
	c.talents = {}
	c.talent_points = 19
	await da._wait(0.5)
	var tree := c.talent_tree()
	var child: Dictionary = {}
	for nd in tree.nodes:
		if int(nd.get("tier", 0)) == 1 and not nd.has("exclusive") and not c.is_free_node(c.talent_node(str(nd.requires[0]))):
			child = nd
			break
	var side: Dictionary = {}
	for nd in tree.nodes:
		if nd.has("exclusive") and nd.branch == child.branch and int(nd.get("tier", 0)) == 1:
			side = nd
			break
	var gate_fill: Array = []
	for nd in tree.nodes:
		if nd.branch == child.branch and int(nd.get("tier", 0)) == 0 and not c.is_free_node(nd) and nd.get("type", "") == "passive" and nd.id != child.requires[0]:
			gate_fill.append(nd.id)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["tl_learn", [child.id, child.requires[0], side.id, c.fork_sibling(side).id, side.requires[0], gate_fill,
			int(child.get("requires_rank", 1)), int(side.get("requires_rank", 1))]])
	await da._wait(6.0)
	da.check(int(c.talents.get(child.id, 0)) == 1 and int(c.talents.get(side.id, 0)) == 1 and int(c.talents.get(c.fork_sibling(side).id, 0)) == 0,
			"host: the client's %s and %s were learned in order, the other side of the fork %s never" % [child.id, side.id, c.fork_sibling(side).id])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await da._wait(1.0)


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"tl_learn":
			var got: Array = []
			var cb := func(t: String, _col: Color): got.append(t)
			EventBus.hud_message.connect(cb)
			var learn := func(id: String) -> void:
				p.request_learn_talent.rpc_id(1, id)
				await da._wait(0.4)
			# Enough points in the branch for tier 1, then the child without its prerequisite.
			for fid in arg[5]:
				await learn.call(str(fid))
				await learn.call(str(fid))
			await learn.call(str(arg[0]))
			da.check(int(p.talents.get(str(arg[0]), 0)) == 0 and got.has(Loc.t("Requires another talent first")),
					"client: the host refuses %s without %s and says why (%s)" % [arg[0], arg[1], got])
			for i in int(arg[6]):
				await learn.call(str(arg[1]))
			await learn.call(str(arg[0]))
			da.check(int(p.talents.get(str(arg[0]), 0)) == 1, "client: with %s learned, %s is learned" % [arg[1], arg[0]])
			got.clear()
			for i in int(arg[7]):
				await learn.call(str(arg[4]))
			await learn.call(str(arg[2]))
			await learn.call(str(arg[3]))
			da.check(int(p.talents.get(str(arg[2]), 0)) == 1 and int(p.talents.get(str(arg[3]), 0)) == 0 and got.has(Loc.t("You took the other path of this fork")),
					"client: after %s the host refuses the other side %s (%s)" % [arg[2], arg[3], got])
			EventBus.hud_message.disconnect(cb)


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
	# Spent within the new totals on a valid tree (tier-0 passives): kept.
	var small := {}
	n = 0
	for nd0 in tree.nodes:
		if nd0.get("type", "") == "passive" and int(nd0.get("tier", 0)) == 0 and not p.is_free_node(nd0) and n < 9:
			var r0 := mini(int(nd0.get("max_rank", 1)), 9 - n)
			small[nd0.id] = r0
			n += r0
	ch.talents = small
	ch.allocated = {"strength": 20, "stamina": 25}
	GameState.characters[p.peer_id] = ch
	p._host_init()
	da.check(p.talent_points == 9 - n and p.stat_points == 0 and p.talents == small and int(p.allocated.get("stamina", 0)) == 25 and p.points_refunded.is_empty(),
			"a level 10 save within the new totals keeps its %d talents and 45 stat points" % n)
	# Every point can be spent: with 1 point per level every branch's top tier opens by level 15,
	# whichever side of its forks is taken (GameData.tree_problems checks the gates per fork).
	var tp := int(tree.get("tier_points", 2))
	var per := int(GameData.bal("progression.talent_points_per_level"))
	var top_level := 1 + int(ceil(float(5 * tp + 1) / per))
	var short := GameData.tree_problems(tree).filter(func(s): return str(s).contains("needs"))
	da.check(top_level <= 15 and short.is_empty(), "every branch's top tier opens by level %d (gate %d points a tier)%s" % [top_level, tp, "" if short.is_empty() else ": short %s" % [short]])
	GameState.characters[p.peer_id] = keep
	p._host_init()


## The talents (id -> rank) a hero needs to take `nd`: its prerequisite chain at the ranks each
## step asks for, then whole ranks of other open nodes lower in the branch (never the closed side
## of a fork) until the branch has the points `nd` needs.
func plan_for(nd: Dictionary) -> Dictionary:
	var t := {}
	var groups := {}
	if nd.has("exclusive"):
		groups[str(nd.exclusive)] = str(nd.id)
	var c := nd
	while not c.get("requires", []).is_empty():
		var par := p.talent_node(str(c.requires[0]))
		if not p.is_free_node(par):
			t[par.id] = maxi(int(t.get(par.id, 0)), int(c.get("requires_rank", 1)))
		if par.has("exclusive"):
			groups[str(par.exclusive)] = str(par.id)
		c = par
	var have := 0
	for k in t:
		have += int(t[k])
	var need := p.branch_gate(nd)
	for tier in int(nd.get("tier", 0)):
		for f in p.talent_tree().nodes:
			if have >= need:
				return t
			if f.branch != nd.branch or int(f.get("tier", 0)) != tier or p.is_free_node(f) or t.has(f.id) or f.id == nd.id:
				continue
			if f.has("exclusive") and groups.get(str(f.exclusive), str(f.id)) != str(f.id):
				continue
			var ok := true
			for r in f.get("requires", []):
				var rn := p.talent_node(str(r))
				ok = ok and (p.is_free_node(rn) or int(t.get(rn.id, 0)) >= int(f.get("requires_rank", 1)))
			if not ok:
				continue
			t[f.id] = int(f.get("max_rank", 1))
			have += int(f.max_rank) if f.has("max_rank") else 1
			if f.has("exclusive"):
				groups[str(f.exclusive)] = str(f.id)
	return t


## #47: the tree is a valid graph; the host refuses a rank without its prerequisite (or below the
## rank it asks for) and the closed side of a fork, with a message; an old save that doesn't fit
## the tree is refunded whole.
func tree_rules() -> void:
	var tree := p.talent_tree()
	var problems := GameData.tree_problems(tree)
	var roots := 0
	var keystones_leaf := true
	for nd in tree.nodes:
		roots += 1 if nd.get("requires", []).is_empty() else 0
		for other in tree.nodes:
			if str(nd.get("type", "")) == "keystone" and Array(other.get("requires", [])).has(nd.id):
				keystones_leaf = false
	da.check(problems.is_empty() and keystones_leaf and roots > 0 and roots < tree.nodes.size() / 2,
			"%s: the talent tree is a valid graph: %d roots, every other node has a prerequisite, keystones at path ends%s" % [p.class_id, roots, "" if problems.is_empty() else ": %s" % [problems]])
	var keep_level := p.level
	p.level = 30
	var got: Array = []
	var cb := func(txt: String, _col: Color): got.append(txt)
	EventBus.hud_message.connect(cb)
	# Without the prerequisite: refused.
	var child: Dictionary = {}
	for nd in tree.nodes:
		if int(nd.get("tier", 0)) == 2 and nd.get("type", "") != "keystone" and not nd.get("requires", []).is_empty():
			child = nd
			break
	var plan := plan_for(child)
	var t2 := plan.duplicate()
	t2.erase(str(child.requires[0]))
	p.talents = t2
	p.talent_points = 99
	p.request_learn_talent.rpc_id(1, str(child.id))
	await da._wait(0.3)
	da.check(int(p.talents.get(child.id, 0)) == 0 and got.has(Loc.t("Requires another talent first")),
			"the host refuses %s without its prerequisite %s (%s)" % [child.id, child.requires[0], got])
	p.talents = plan
	p.request_learn_talent.rpc_id(1, str(child.id))
	await da._wait(0.3)
	da.check(int(p.talents.get(child.id, 0)) == 1, "with the prerequisite %s, %s is learned" % [child.requires[0], child.id])
	# The closed side of a fork: refused.
	var side: Dictionary = {}
	for nd in tree.nodes:
		if nd.has("exclusive"):
			side = nd
			break
	var other := p.fork_sibling(side)
	var plan2 := plan_for(side)
	plan2[side.id] = 1
	p.talents = plan2
	got.clear()
	p.request_learn_talent.rpc_id(1, str(other.id))
	await da._wait(0.3)
	da.check(int(p.talents.get(other.id, 0)) == 0 and got.has(Loc.t("You took the other path of this fork")),
			"with %s learned, the other side of its fork %s is refused (%s)" % [side.id, other.id, got])
	EventBus.hud_message.disconnect(cb)
	# A save from the old trees (a node without its prerequisite, both sides of a fork): refunded.
	var keep: Dictionary = GameState.characters.get(p.peer_id, {})
	var ch: Dictionary = p.to_character()
	ch.level = 20
	ch.talents = {str(child.id): 1, str(side.id): 1, str(other.id): 1}
	ch.loadout = p.default_loadout()
	GameState.characters[p.peer_id] = ch
	p._host_init()
	da.check(p.talents.is_empty() and p.talent_points == 19 and p.points_refunded == ["talent"] and p.loadout_error(p.skills).is_empty(),
			"a save whose talents no longer fit the tree is refunded: %d points to spend, a valid loadout" % p.talent_points)
	GameState.characters[p.peer_id] = keep
	p._host_init()
	p.level = keep_level
	p.talents = {}
	p.talent_points = p._talent_points_total()
	p.recompute_stats()


## #106: the starting skills (primary + basic skill) are the shared root, in no branch; no branch
## node hangs from them; a fresh hero finds only tier-0 nodes open, in every branch alike.
func shared_root() -> void:
	var tree := p.talent_tree()
	var cdef: Dictionary = GameData.classes[p.class_id]
	var starters: Array = [str(cdef.primary_attack)] + Array(cdef.skills)
	var root_skills: Array = []
	var hang: Array = []
	for nd in tree.nodes:
		if str(nd.get("branch", "")) == GameData.TALENT_ROOT:
			root_skills.append(str(nd.skill))
		for r in nd.get("requires", []):
			if str(p.talent_node(str(r)).get("branch", "")) == GameData.TALENT_ROOT:
				hang.append(nd.id)
	root_skills.sort()
	starters.sort()
	da.check(root_skills == starters, "%s: the starting skills are the shared root (%s)" % [p.class_id, root_skills])
	da.check(hang.is_empty(), "no branch node requires a starting skill (%s)" % [hang])
	var keep_t := p.talents
	var keep_pts := p.talent_points
	p.talents = {}
	p.talent_points = 1
	var counts := {}
	var deeper: Array = []
	for br in tree.branches:
		counts[br.id] = 0
	for nd in tree.nodes:
		if p.is_free_node(nd) or not counts.has(str(nd.get("branch", ""))):
			continue
		if p.talent_block_reason(nd).is_empty():
			counts[nd.branch] += 1
			if int(nd.get("tier", 0)) > 0:
				deeper.append(nd.id)
	p.talents = keep_t
	p.talent_points = keep_pts
	var lo := 99
	var hi := 0
	for k in counts:
		lo = mini(lo, counts[k])
		hi = maxi(hi, counts[k])
	da.check(deeper.is_empty() and lo >= 3 and hi - lo <= 1, "a fresh %s finds every branch alike: only tier-0 nodes open (%s)%s" % [p.class_id, counts, "" if deeper.is_empty() else ", deeper: %s" % [deeper]])


## #105: Meteor Strike sits on tier 3 under Overload (Cataclysm below it); a fresh mage can't
## learn it, a mage on the path past the tier gate can; a hero from before the simple start keeps
## it free.
func meteor_deeper() -> void:
	var nd := p.talent_node("m_s_meteor")
	var cat := p.talent_node("m_cataclysm")
	da.check(int(nd.get("tier", 0)) == 3 and Array(nd.get("requires", [])) == ["m_overload"] and Array(cat.get("requires", [])) == ["m_s_meteor"],
		"Meteor Strike is a tier-3 node under Overload, Cataclysm grows from it (tier %d, %s)" % [int(nd.get("tier", 0)), nd.get("requires", [])])
	var keep_level := p.level
	var got: Array = []
	var cb := func(txt: String, _col: Color): got.append(txt)
	EventBus.hud_message.connect(cb)
	p.level = 2
	p.talents = {}
	p.talent_points = 1
	p.request_learn_talent.rpc_id(1, "m_s_meteor")
	await da._wait(0.3)
	da.check(int(p.talents.get("m_s_meteor", 0)) == 0 and not p.unlocked_skills().has("mage_meteor") and got.has(Loc.t("Requires another talent first")),
		"a level 2 mage can't learn Meteor Strike (%s)" % [got])
	p.level = 30
	p.talents = plan_for(nd)
	p.talent_points = 99
	p.request_learn_talent.rpc_id(1, "m_s_meteor")
	await da._wait(0.3)
	da.check(int(p.talents.get("m_s_meteor", 0)) == 1 and p.unlocked_skills().has("mage_meteor"), "on the path past the tier gate Meteor Strike is learned (%s)" % [p.talents.keys()])
	EventBus.hud_message.disconnect(cb)
	p.talents = {}
	var keep_legacy := p.legacy_kit
	p.legacy_kit = true
	da.check(p.is_free_node(nd) and p.unlocked_skills().has("mage_meteor"), "a hero from before the simple start keeps Meteor Strike for free")
	p.legacy_kit = keep_legacy
	p.level = keep_level
	p.talent_points = p._talent_points_total()
	p.recompute_stats()


func every_node() -> void:
	var tree := p.talent_tree()
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
		# #47: its prerequisite chain and enough of the open branch below it for the gate.
		var t := plan_for(nd)
		var have := 0
		for k in t:
			have += int(t[k])
		var need := p.branch_gate(nd)
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
	# #116: the starting skills (the shared root) aren't drawn.
	var nodes: int = p.talent_tree().nodes.filter(func(nd): return str(nd.get("branch", "")) != GameData.TALENT_ROOT).size()
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
	# #116: no button for a starting skill; every branch's first row sits right under its heading.
	var roots := buttons.values().filter(func(e): return str(e[1].get("branch", "")) == GameData.TALENT_ROOT)
	var top := INF
	for id in buttons:
		top = minf(top, buttons[id][0].position.y)
	da.check(roots.is_empty() and top < tp.HEAD_H + tp.ROW_H, "the starting skills aren't drawn; the branches start under their headings (top row at %.0f)" % top)
	hud.close_overlay()
