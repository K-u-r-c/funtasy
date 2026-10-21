class_name EventTracker
extends VBoxContainer
## #72, the HUD tracker's event lines: one per event the local hero has found, with its icon in
## its colour and what it asks of the party now ("Arena - wave 2 of 3 in 4", "You carry the cell
## key: free the prisoner"). Rebuilt when the text changes; warnings pulse.

var lines: Dictionary = {}  ## id -> text shown (tests)
var _rows: Dictionary = {}  ## id -> [HBoxContainer, Label]
var _t := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 2)


func _process(delta: float) -> void:
	_t += delta
	var game := get_tree().get_first_node_in_group("game")
	var fe: FloorEvents = game.events if game else null
	if fe == null:
		return
	var want: Dictionary = {}
	for id in fe.entries:
		var line := text_for(fe, id, game)
		if not line.is_empty():
			want[id] = line
	for id in _rows.keys():
		if not want.has(id):
			_rows[id][0].queue_free()
			_rows.erase(id)
	for id in want:
		if not _rows.has(id):
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 5)
			var ic := UITheme.icon(str(FloorEvents.def(id).get("icon", "")), 16)
			ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			h.add_child(ic)
			var l := UITheme.label("", Color.from_string(str(FloorEvents.def(id).get("color", "#ffffff")), Color.WHITE).lightened(0.25), UITheme.FONT_SMALL)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(150, 0)
			h.add_child(l)
			add_child(h)
			_rows[id] = [h, l]
		var lab: Label = _rows[id][1]
		if lab.text != want[id]:
			lab.text = want[id]
		var hot := warning(fe, id)
		lab.add_theme_color_override("font_color", UITheme.WARN if hot else Color.from_string(str(FloorEvents.def(id).get("color", "#ffffff")), Color.WHITE).lightened(0.25))
		_rows[id][0].modulate.a = 0.6 + 0.4 * absf(sin(_t * 5.0)) if hot else 1.0
	lines = want
	visible = not want.is_empty()


## Is the event's line a warning right now (doors sealing, a wave coming, a mimic awake)?
static func warning(fe: FloorEvents, id: String) -> bool:
	match id:
		"arena":
			var a := fe.st("arena")
			return str(a.get("state", "")) == "sealing" or (str(a.get("state", "")) == "fight" and a.get("warned", false) and float(a.get("at", -1.0)) >= 0.0)
		"cursed_chest":
			return str(fe.st("cursed_chest").get("state", "")) in ["waking", "mimic"]
	return false


## The line for event `id` ("" = not shown: not found yet).
static func text_for(fe: FloorEvents, id: String, game: Node) -> String:
	var d := FloorEvents.def(id)
	var s := fe.st(id)
	var found: bool = fe.seen.has(id) or (id == "vault" and fe.lever_seen)
	match id:
		"arena":
			var state := str(s.get("state", "idle"))
			var t: float = game.floor_time
			var waves: int = d.get("waves", []).size()
			match state:
				"sealing":
					return Loc.f("The arena seals in %d", [ceili(maxf(float(s.get("at", t)) - t, 0.0))])
				"fight":
					var at := float(s.get("at", -1.0))
					if at < 0.0:
						return Loc.f("Arena - wave %d of %d", [int(s.get("wave", 0)), waves])
					return Loc.f("Arena - wave %d of %d in %d", [int(s.get("wave", 0)) + 1, waves, ceili(maxf(at - t, 0.0))])
				"done":
					return Loc.t("The arena is won") if found else ""
			return Loc.t(str(d.get("tracker", ""))) if found else ""
		"vault":
			if not found:
				return ""
			if s.get("open", false):
				return Loc.t("The vault is open")
			return Loc.t(str(d.get("tracker_seen" if fe.lever_seen else "tracker", "")))
		"shrine":
			if not found:
				return ""
			var mine := str(s.get("taken", {}).get(str(fe.multiplayer.get_unique_id()), ""))
			if not mine.is_empty():
				for b in d.get("bargains", []):
					if str(b.id) == mine:
						return Loc.f("Bargain struck: %s", [Loc.t(str(b.name))])
			return Loc.t(str(d.get("tracker", "")))
		"cursed_chest":
			if not found:
				return ""
			match str(s.get("state", "closed")):
				"waking", "mimic":
					return Loc.t("The chest was a mimic!")
				"opened", "dead":
					return Loc.t("The cursed chest is spent")
			return Loc.t(str(d.get("tracker", "")))
		"prisoner":
			if not found and not s.get("key", false):
				return ""
			var pd := fe.prisoner_def()
			if str(s.get("state", "")) == "freed":
				return Loc.f("%s fights beside you", [str(pd.get("name", ""))]) if str(s.get("outcome", "")) == "ally" else Loc.f("%s is free", [str(pd.get("name", ""))])
			return Loc.t(str(d.get("tracker_key" if s.get("key", false) else "tracker", "")))
	return ""
