class_name NpcSuite
extends RefCounted
## #78 NPC speech bubbles (scenario "npc_talk" solo, "npc_talk_lan" host + client): every NPC has
## at least ten first lines, all in Polish too; a bubble appears the first time the NPC comes into
## the hero's own sight - not through a closed door or a wall - once per floor, with an "again"
## line on a later floor; it stays on screen and off the hero; only the hero who sees it gets it.

var da: Node
var g: Node
var p: Player
var talk: NpcTalk


func _init(dev_auto: Node) -> void:
	da = dev_auto


func run() -> void:
	g = da._game()
	p = da._local()
	p.iframe_left = 9999.0
	talk = da.get_tree().get_first_node_in_group("hud").npc_talk
	await da._wait(1.0)
	pools()
	NpcTalk.met.clear()
	await merchant_floor()
	await forge_floor(false)
	await forge_floor(true)
	await prisoner_floor()
	for k in ["force_merchant", "force_forge", "force_events", "test_prisoner"]:
		GameState.remove_meta(k)


## Every NPC: ten or more first lines and some "again" lines, every one with its Polish text.
func pools() -> void:
	var bad := []
	var npcs: Dictionary = GameData.npc_lines.get("npcs", {})
	for key in npcs:
		var firsts: Array = npcs[key].get("first", [])
		if firsts.size() < 10 or npcs[key].get("again", []).is_empty():
			bad.append("%s: %d first lines" % [key, firsts.size()])
		for pool in ["first", "again", "freed"]:
			for l in npcs[key].get(pool, []):
				var txt := str(l.text) if l is Dictionary else str(l)
				TranslationServer.set_locale("pl")
				var tr := TranslationServer.translate(txt)
				TranslationServer.set_locale("en")
				if tr == txt or tr.is_empty():
					bad.append("%s: no Polish for '%s'" % [key, txt.substr(0, 30)])
	for want in ["archibald", "malphas", "blacksmith"]:
		if not npcs.has(want):
			bad.append("no lines for %s" % want)
	for pd in FloorEvents.def("prisoner").get("prisoners", []):
		if not npcs.has("prisoner_%s" % pd.id):
			bad.append("no lines for prisoner %s" % pd.id)
	da.check(bad.is_empty(), "every NPC has 10+ lines and 'again' lines, all in English and Polish (%d NPCs)%s" % [npcs.size(), "" if bad.is_empty() else ": %s" % [bad.slice(0, 4)]])


func _floor(depth: int) -> void:
	g.start_floor(depth)
	await da._wait(1.5)
	p = da._local()
	p.iframe_left = 9999.0
	for e in g.enemies_root.get_children():
		e.queue_free()


func _bubble_for(node: Node) -> SpeechBubble:
	for b in talk.bubbles:
		if is_instance_valid(b) and b.speaker == node:
			return b
	return null


## Archibald behind his sealed door: silent; door open and in sight: he speaks, once.
func merchant_floor() -> void:
	GameState.set_meta("force_merchant", "archibald")
	GameState.set_meta("force_events", "none")
	await _floor(2)
	var m: Node = g.dungeon.props.get("Merchant")
	var door: Node = g.dungeon.leaf_door("merchant")
	if m == null or door == null:
		da.check(false, "the floor has Archibald's room")
		return
	var room: Rect2i = g.layout.rooms[int(g.layout.merchant.room)].rect
	var away := signf(door.world_rect.get_center().y - float(room.get_center().y) * g.dungeon.tile)
	p.host_teleport(g.nearest_floor(door.interact_pos() + Vector2(0, away * 40.0)))
	await da._wait(1.5)
	da.check(not talk.spoken.has("archibald") and p.global_position.distance_to(m.global_position) < 400.0,
		"behind his closed door Archibald stays silent (%.0f px away)" % p.global_position.distance_to(m.global_position))
	door.host_unseal()
	await da._wait(0.4)
	p.host_teleport(m.global_position + Vector2(0, 70))
	await da._wait_until(func(): return talk.spoken.has("archibald"), 3.0)
	var b := _bubble_for(m)
	da.check(talk.spoken.has("archibald") and b != null, "in sight, Archibald speaks: \"%s\"" % talk.spoken.get("archibald", ""))
	if b:
		await da._wait(0.8)
		var vp: Vector2 = da.get_viewport().get_visible_rect().size
		var inside := Rect2(Vector2.ZERO, vp).encloses(Rect2(b.position, b.size))
		var hp: Vector2 = p.get_global_transform_with_canvas().origin
		var hero := Rect2(hp + Vector2(-18, -58), Vector2(36, 62))
		da.check(inside and not Rect2(b.position, b.size).intersects(hero) and b._label.visible_characters > 0,
			"the bubble types out inside the screen and clear of the hero")
		var firsts: Array = GameData.npc_lines.npcs.archibald.first.map(func(l): return Loc.t(str(l.text) if l is Dictionary else str(l)).replace("{floor}", str(g.depth)))
		da.check(firsts.has(talk.spoken.archibald), "a first-meeting line from his pool")
	var n := talk.bubbles.size()
	p.host_teleport(g.nearest_floor(g.layout.start))
	await da._wait(1.0)
	p.host_teleport(m.global_position + Vector2(0, 70))
	await da._wait(1.0)
	da.check(talk.bubbles.size() == n, "once per floor: no second bubble on the way back")
	await da._wait(8.0)
	da.check(not is_instance_valid(b) or b.modulate.a < 0.05, "the bubble fades after it was read")


## The blacksmith behind a wall (next to his room, door shut): silent; then in sight. On a second
## forge floor a hero who met him gets an "again" line.
func forge_floor(second: bool) -> void:
	GameState.set_meta("force_forge", "on")
	GameState.set_meta("force_merchant", "malphas")
	await _floor(3 if not second else 4)
	var smith: Node = g.dungeon.props.get("Forge_npc")
	var door: Node = g.dungeon.leaf_door("forge")
	if smith == null or door == null:
		da.check(false, "the floor has the forge")
		return
	if door.is_open:
		door.host_set_open(false)
	await da._wait(0.3)
	if not second:
		# Beside the room, behind its wall, within sight range.
		var r: Rect2i = g.layout.rooms[int(g.layout.forge.room)].rect
		var spot := Vector2.INF
		for c in [Vector2i(r.position.x - 2, r.get_center().y), Vector2i(r.end.x + 1, r.get_center().y), Vector2i(r.get_center().x, r.position.y - 2)]:
			if DungeonGenerator.walkable(g.dungeon.cell_at(c)):
				spot = g.dungeon.cell_center(c)
				break
		if spot == Vector2.INF:
			spot = g.nearest_floor(door.interact_pos() + Vector2(0, 50))
		p.host_teleport(spot)
		await da._wait(1.5)
		da.check(not talk.spoken.has("blacksmith"), "behind his wall the smith stays silent")
	door.host_set_open(true)
	await da._wait(0.3)
	p.host_teleport(smith.global_position + Vector2(0, 70))
	await da._wait_until(func(): return talk.spoken.has("blacksmith"), 3.0)
	var pool := "again" if second else "first"
	var lines: Array = GameData.npc_lines.npcs.blacksmith[pool].map(func(l): return Loc.t(str(l.text) if l is Dictionary else str(l)).replace("{floor}", str(g.depth)))
	da.check(lines.has(str(talk.spoken.get("blacksmith", ""))), "the smith says a %s line: \"%s\"" % [pool, talk.spoken.get("blacksmith", "")])


## The prisoner speaks from the cage when seen, and thanks the party when freed.
func prisoner_floor() -> void:
	GameState.set_meta("force_events", "prisoner")
	GameState.set_meta("test_prisoner", "reward")
	GameState.set_meta("force_forge", "off")
	await _floor(4)
	var cage: Node = g.dungeon.props.get("Event_prisoner")
	if cage == null:
		da.check(false, "the floor has the prisoner")
		return
	var key := "prisoner_%s" % g.events.prisoner_def().get("id", "")
	p.host_teleport(g.nearest_floor(cage.global_position + Vector2(0, 60)))
	await da._wait_until(func(): return talk.spoken.has(key), 3.0)
	da.check(talk.spoken.has(key) and not str(talk.spoken[key]).is_empty(), "%s calls out from the cage: \"%s\"" % [key, talk.spoken.get(key, "")])
	g.events.state.prisoner.key = true
	p.host_teleport(g.nearest_floor(cage.global_position + Vector2(0, 34)))
	await da._wait(0.3)
	var n := talk.bubbles.size()
	g.host_interact(p, cage)
	await da._wait_until(func(): return talk.bubbles.size() > n, 3.0)
	da.check(talk.bubbles.size() > n, "freed, the prisoner thanks the party")


# =========================================================================================
# LAN
# =========================================================================================


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	talk = da.get_tree().get_first_node_in_group("hud").npc_talk
	GameState.set_meta("force_forge", "on")
	GameState.set_meta("force_events", "none")
	g.start_floor(2)
	await da._wait(2.0)
	p = da._local()
	for e in g.enemies_root.get_children():
		e.queue_free()
	var c: Player = da._other_player()
	c.iframe_left = 9999.0
	p.iframe_left = 9999.0
	var smith: Node = g.dungeon.props.get("Forge_npc")
	var door: Node = g.dungeon.leaf_door("forge")
	door.host_set_open(true)
	p.host_teleport(g.nearest_floor(g.layout.start))
	c.host_teleport(smith.global_position + Vector2(0, 70))
	await da._wait(2.0)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["npc_seen", null])
	await da._wait(1.0)
	da.check(not talk.spoken.has("blacksmith"), "host: my hero is far away - no bubble on my screen")
	await da._wait(1.0)
	for k in ["force_forge", "force_events"]:
		GameState.remove_meta(k)


func client_cmd(cmd: String, _arg: Variant) -> void:
	g = da._game()
	talk = da.get_tree().get_first_node_in_group("hud").npc_talk
	match cmd:
		"npc_seen":
			da.check(talk.spoken.has("blacksmith") and talk.bubbles.size() >= 1, "client: my hero sees the smith - his bubble is on my screen: \"%s\"" % talk.spoken.get("blacksmith", ""))
