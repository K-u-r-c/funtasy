class_name NpcTalk
extends Node
## #78, local (one in the HUD): the floor's NPCs speak when the local hero first sees them - the
## merchant (Archibald / Malphas), the blacksmith and the caged prisoner - with a line from
## data/npc_lines.json in a SpeechBubble over their head. Sight follows the monsters' rules for
## this hero alone (Visibility.sees: range, light, nothing blocking), so never through a wall or a
## closed door, and only on the screen of the hero who sees them. Once per NPC per floor; a hero who
## met the NPC on an earlier floor gets a shorter "again" line; a prisoner thanks its rescuer when
## the cage opens.

static var met: Dictionary = {}  ## npc key -> true: met by this peer's hero this run
var spoken: Dictionary = {}  ## npc key -> the line said on this floor (tests)
var bubbles: Array = []  ## the bubbles shown on this floor (tests)
var _t := 0.0
var _freed_said := false


func _ready() -> void:
	EventBus.floor_started.connect(func(_d): reset_floor())


func reset_floor() -> void:
	spoken.clear()
	_freed_said = false
	for b in bubbles:
		if is_instance_valid(b):
			b.queue_free()
	bubbles.clear()


## The floor's speakers: [{key, node, head}].
func speakers() -> Array:
	var game := get_tree().get_first_node_in_group("game")
	if game == null or game.dungeon == null:
		return []
	var out: Array = []
	var props: Dictionary = game.dungeon.props
	if props.has("Merchant") and is_instance_valid(props.Merchant):
		out.append({"key": str(props.Merchant.def.get("npc", "")), "node": props.Merchant, "head": 50.0})
	if props.has("Forge_npc") and is_instance_valid(props.Forge_npc):
		out.append({"key": "blacksmith", "node": props.Forge_npc, "head": 56.0})
	if props.has("Event_prisoner") and is_instance_valid(props.Event_prisoner) and game.events:
		var pd: Dictionary = game.events.prisoner_def()
		if not pd.is_empty():
			out.append({"key": "prisoner_%s" % str(pd.get("id", "")), "node": props.Event_prisoner, "head": 58.0})
	return out


func _process(delta: float) -> void:
	_t += delta
	if _t < 0.15:
		return
	_t = 0.0
	var game := get_tree().get_first_node_in_group("game")
	if game == null or game.get("visibility") == null:
		return
	var me: Player = game.local_player if is_instance_valid(game.local_player) else null
	if me == null or me.life_state == Player.Life.GHOST:
		return
	for s in speakers():
		var key: String = s.key
		var node: Node2D = s.node
		var freed := key.begins_with("prisoner_") and str(game.events.st("prisoner").get("state", "")) == "freed"
		if freed:
			if not _freed_said and spoken.has(key) and game.visibility.sees(node.global_position):
				_freed_said = true
				_say(s, "freed", game, me)
			continue
		if spoken.has(key) or not game.visibility.sees(node.global_position + Vector2(0, -s.head * 0.5)):
			continue
		_say(s, "again" if met.has(key) else "first", game, me)


func _say(s: Dictionary, pool: String, game: Node, me: Player) -> void:
	var line := pick_line(str(s.key), pool, game, me)
	spoken[s.key] = line
	met[s.key] = true
	if line.is_empty():
		return
	var b := SpeechBubble.new()
	b.setup(s.node, line, float(s.head))
	get_parent().add_child(b)
	bubbles.append(b)


## A line of `pool` for NPC `key` that fits the floor and the party, translated, with its
## placeholders filled ("" when the pool is empty).
static func pick_line(key: String, pool: String, game: Node, me: Player) -> String:
	var npc: Dictionary = GameData.npc_lines.get("npcs", {}).get(key, {})
	var biome := str(game.floor_def.get("id", game.floor_def.get("biome", ""))) if game else ""
	var solo: bool = game == null or game.players_root.get_child_count() <= 1
	var lines: Array = []
	for l in npc.get(pool, []):
		if l is String:
			lines.append(l)
		elif l is Dictionary:
			if l.has("biome") and str(l.biome) != biome:
				continue
			if l.has("party") and (str(l.party) == "solo") != solo:
				continue
			lines.append(str(l.text))
	if lines.is_empty():
		return ""
	var line := Loc.t(str(lines[randi() % lines.size()]))
	line = line.replace("{floor}", str(int(game.depth) if game else 1))
	line = line.replace("{biome}", Loc.t(str(game.floor_def.get("name", ""))) if game else "")
	line = line.replace("{hero}", me.display_name if me else "")
	return line
