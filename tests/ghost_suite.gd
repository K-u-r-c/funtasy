class_name GhostSuite
extends RefCounted
## #82 Ghosts roam the floor (scenario "ghost_lan", host + 2 clients): the host stays alive, the
## first client dies for real (downed, then a ghost), the second lies downed for the revive check.
## Checked on the host and on the ghost's own peer: the ghost walks (walls and closed doors still
## stop it), opens a door, its map grows; it can't take an item, attack, revive or be hit, and a
## monster next to it ignores it; it gives a blue light of about a torch's radius that lights the
## cells around it for its own sight only (never for the rules or the living), needs no torch and
## pauses a carried one; the living see it very faintly; it lives again on the next floor. With
## --shot=<dir>/<name> (windowed instances) the ghost's view and the host's view are saved.

var da: Node
var g: Node


func _init(dev_auto: Node) -> void:
	da = dev_auto


func snap(tag: String) -> void:
	if da.shot.is_empty() or DisplayServer.get_name() == "headless":
		return
	await da._snap(da.shot.get_base_dir(), "%s_%s" % [da.shot.get_file().get_basename(), tag])


## A closed plain door with open floor on both sides of it, nearest to `from`.
func plain_door(from: Vector2) -> Node:
	var best: Node = null
	for d in g.dungeon.doors:
		if d.is_open or d.sealed or d.floodgate or not d.kind.is_empty():
			continue
		if best == null or d.global_position.distance_to(from) < best.global_position.distance_to(from):
			best = d
	return best


## The floor spot just in front of `door` (south of a horizontal door, east of a side door).
static func door_front(door: Node) -> Vector2:
	var r: Rect2 = door.world_rect
	return Vector2(r.end.x + 10.0, r.get_center().y) if door.vertical else Vector2(r.get_center().x, r.end.y + 10.0)


func run_lan() -> void:
	g = da._game()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 3, 15.0)
	da.check(g.players_root.get_child_count() >= 3, "three heroes in the run")
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	var host_p: Player = da._local()
	var others: Array = g.players_root.get_children().filter(func(pl): return pl != host_p)
	others.sort_custom(func(a, b): return a.peer_id < b.peer_id)
	var ghost: Player = others[0]
	var downed: Player = others[1]
	for pl in g.players_root.get_children():
		pl.iframe_left = 0.0
	host_p.iframe_left = 9999.0
	# A carried torch before dying: the ghost's timer must wait for it.
	ghost.host_take_torch()
	await da._wait(0.3)
	# 1. A real death: downed, then a ghost when nobody revives it.
	ghost.on_death()
	ghost.downed_left = 0.3
	await da._wait(1.0)
	da.check(ghost.life_state == Player.Life.GHOST and not g._wiped, "host: the client is a ghost, the run goes on")
	da.check(ghost.collision_layer == 0 and ghost.collision_mask == Player.GHOST_MASK and not ghost.is_targetable(),
		"host: nothing collides with the ghost, it still collides with walls and doors, nothing can target it")
	var torch_before := ghost.torch_left
	await da._wait(1.2)
	da.check(torch_before > 250.0 and is_equal_approx(ghost.torch_left, torch_before), "host: the ghost's carried torch is paused (%.1f s left)" % ghost.torch_left)
	# 2. The downed one lies near; the host keeps standing (no wipe).
	downed.on_death()
	downed.downed_left = 60.0
	var start: Vector2 = g.nearest_floor(g.layout.start)
	ghost.host_teleport(start)
	downed.host_teleport(start + Vector2(20, 0))
	host_p.host_teleport(start + Vector2(-60, 0))
	await da._wait(1.0)
	# 3. Monsters ignore it and it can't be hit.
	var m: Enemy = g.spawn_monster("ghoul", start + Vector2(0, 30), false)
	await da._wait(2.0)
	var hp := ghost.health.hp
	var ctx := Combat.instance.make_ctx(m, {"id": "test_hit", "school": "melee"})
	var dealt := Combat.instance.deal_damage(ctx, ghost, 50.0)
	da.check(dealt == 0.0 and ghost.health.hp == hp, "host: a blow at the ghost does nothing")
	da.check(m.target != ghost and not m.threat.threat.has(ghost), "host: the monster beside the ghost doesn't target it (target %s)" % [m.target.display_name if m.target else "none"])
	m.queue_free()
	# 4. An item at its feet, the downed teammate beside it: the ghost gets neither.
	g.loot.drop_item(g.gold_key_item(), start + Vector2(4, 4))
	await da._wait(0.5)
	var keys: int = g.party_keys
	NetworkManager.to_clients("DevAuto", "client_cmd", ["gh_hands", ghost.peer_id])
	await da._wait(3.0)
	da.check(g.party_keys == keys and g.items_root.get_child_count() > 0, "host: the ghost's Interact doesn't take the item")
	da.check(downed._reviver == null and downed.revive_progress == 0.0 and downed.life_state == Player.Life.DOWNED, "host: the ghost can't revive the downed teammate")
	da.check(Combat.instance.projectiles.is_empty(), "host: the ghost's attack fires nothing")
	for it in g.items_root.get_children():
		it.queue_free()
	# 5. A door: the ghost walks up and opens it.
	var door := plain_door(start)
	da.check(door != null, "a closed plain door to try")
	if door:
		ghost.host_teleport(door_front(door))
		await da._wait(0.8)
		NetworkManager.to_clients("DevAuto", "client_cmd", ["gh_door", [ghost.peer_id, str(door.get_path())]])
		await da._wait(2.0)
		da.check(door.is_open, "host: the ghost opened the door")
	# 6. It walks; its light: the cells around it, for its own sight only.
	var walk_from := ghost.global_position
	# Through the door it opened, into the unexplored rooms behind it.
	var through := "" if door == null else ("move_left" if door.vertical else "move_up")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["gh_walk", [ghost.peer_id, through]])
	await da._wait(3.5)
	da.check(ghost.global_position.distance_to(walk_from) > 40.0, "host: the ghost walked (%.0f px)" % ghost.global_position.distance_to(walk_from))
	da.check(not LightLayers.is_lit(da.get_tree(), ghost.global_position + Vector2(60, 0), true) or _other_light_near(ghost.global_position + Vector2(60, 0)),
		"host: the ghost's light isn't a light for the rules")
	var gs: Node2D = ghost.sprite
	var a_max := float(GameData.bal("ghost.alpha_others"))
	da.check(gs.visible and gs.modulate.a > 0.0 and gs.modulate.a <= a_max + 0.01, "host: the living see the ghost very faintly (alpha %.2f)" % gs.modulate.a)
	da.check(ghost._ghost_light.is_visible_in_tree() and ghost._ghost_light.energy <= float(GameData.bal("ghost.light_energy_others")) + 0.01,
		"host: only a hint of its light shows to the living")
	# The living hero steps up to the ghost for the screenshot.
	host_p.host_teleport(g.nearest_floor(ghost.global_position + Vector2(-70, 20)))
	await da._wait(1.0)
	await snap("living_view")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["gh_snap", ghost.peer_id])
	await da._wait(1.5)
	# 7. Next floor: it lives again.
	downed.revive(0.5)
	g.start_floor(g.depth + 1)
	await da._wait(2.5)
	da.check(ghost.life_state == Player.Life.ALIVE and ghost.collision_mask == Player.LIVING_MASK and ghost.is_targetable(), "host: the ghost lives again on the next floor")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["gh_alive", ghost.peer_id])
	await da._wait(1.5)


func _other_light_near(pos: Vector2) -> bool:
	for l in da.get_tree().get_nodes_in_group(LightLayers.GROUP):
		if not l.has_meta("ghost_of") and not l.has_meta("personal") and l.is_visible_in_tree() and l.global_position.distance_to(pos) <= float(l.get_meta("radius", 0.0)):
			return true
	return false


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	var me: int = da.multiplayer.get_unique_id()
	var p: Player = da._local()
	var who := "client %d" % me
	var target_peer: int = int(arg[0]) if arg is Array else int(arg)
	if target_peer != me:
		return
	match cmd:
		"gh_hands":
			da.set_meta("gh_discovered", _discovered(g))
			da.check(p.life_state == Player.Life.GHOST, "%s: my hero is a ghost" % who)
			# The camera stays on the ghost.
			da.check(g.camera.target == p and g.visibility.viewer == p, "%s: the camera and sight follow my ghost (no spectating)" % who)
			var offered: Dictionary = g.find_interactable(p, 0)
			da.check(offered.is_empty() or offered.get("kind") == "door", "%s: the ghost is offered no item and no revive (got '%s')" % [who, str(offered.get("kind", ""))])
			for it in g.items_root.get_children():
				p.request_interact.rpc_id(1, it.get_path())
			for pl in g.players_root.get_children():
				if pl.life_state == Player.Life.DOWNED:
					p.request_revive.rpc_id(1, pl.peer_id, true)
			p.request_skill.rpc_id(1, 0, p.global_position + Vector2(40, 0))
			p.request_use_quick.rpc_id(1, "q")
			await da._wait(1.0)
			for pl in g.players_root.get_children():
				if pl.life_state == Player.Life.DOWNED:
					p.request_revive.rpc_id(1, pl.peer_id, false)
		"gh_door":
			await da._wait(0.3)
			var door: Node = da.get_node_or_null(NodePath(str(arg[1])))
			p.aim_pos = door.world_rect.get_center()
			await da._wait(0.2)
			var offered: Dictionary = g.find_interactable(p, 0)
			da.check(offered.get("node") == door, "%s: the ghost is offered the door ('%s')" % [who, str(offered.get("text", ""))])
			p.request_interact.rpc_id(1, door.get_path())
		"gh_walk":
			var before: int = da.get_meta("gh_discovered", _discovered(g))
			var from := p.global_position
			# Walk the free way (the longest open run of the four directions).
			var best := "move_right" if str(arg[1]).is_empty() else str(arg[1])
			var best_n := -1 if str(arg[1]).is_empty() else 99
			for dir in [["move_right", Vector2i(1, 0)], ["move_left", Vector2i(-1, 0)], ["move_down", Vector2i(0, 1)], ["move_up", Vector2i(0, -1)]]:
				var c: Vector2i = g.dungeon.cell_of(from)
				var n := 0
				while n < 12 and not g.dungeon.blocks_sight(c + dir[1] * (n + 1)):
					n += 1
				if n > best_n:
					best_n = n
					best = dir[0]
			Input.action_press(best)
			await da._wait(2.0)
			Input.action_release(best)
			await da._wait(0.6)
			da.check(p.global_position.distance_to(from) > 40.0, "%s: my ghost walks (%.0f px %s)" % [who, p.global_position.distance_to(from), best])
			da.check(_discovered(g) > before, "%s: my ghost's map grows as it explores (%d -> %d cells)" % [who, before, _discovered(g)])
			# Its own light: blue, about a torch's radius, no torch needed.
			var l: PointLight2D = p._ghost_light
			var want := float(GameData.bal("lighting.carried_torch_radius")) * float(GameData.bal("ghost.light_radius_mult"))
			da.check(l.is_visible_in_tree() and absf(float(l.get_meta("radius", 0.0)) - want) < 0.5 and l.color.b > l.color.r and p.torch_sync > 0 and not p._torch_node.visible,
				"%s: my ghost shines a blue light of %.0f px (a torch's %.0f) without its torch" % [who, float(l.get_meta("radius", 0.0)), float(GameData.bal("lighting.carried_torch_radius"))])
			var lit_cells := 0
			var c0: Vector2i = g.dungeon.cell_of(p.global_position)
			for dx in range(-3, 4):
				if g.visibility.is_cell_visible(c0 + Vector2i(dx, 0)) or g.dungeon.blocks_sight(c0 + Vector2i(dx, 0)):
					lit_cells += 1
			da.check(lit_cells >= 6, "%s: the cells around my ghost are lit and seen (%d / 7 in its row)" % [who, lit_cells])
			da.check(p.sprite.modulate.a >= float(GameData.bal("ghost.alpha_own")) * 0.6, "%s: I see my own ghost clearly (alpha %.2f)" % [who, p.sprite.modulate.a])
		"gh_snap":
			await snap("ghost_view")
		"gh_alive":
			da.check(p.life_state == Player.Life.ALIVE and p.collision_mask == Player.LIVING_MASK, "%s: alive again on the next floor" % who)


static func _discovered(game: Node) -> int:
	var n := 0
	for b in game.dungeon.discovered:
		n += int(b)
	return n
