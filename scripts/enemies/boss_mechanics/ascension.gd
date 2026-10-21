extends BossMechanic
## #74 An ascended boss's extra mechanic (data/bosses/<id>.json "ascended": {name, message,
## mechanic}), added to every phase of the fight. One module, a pattern per boss; every strike is
## warned first by rings with a countdown over the fog (CombatFx.warn, logged as `key`), the
## boss's message and a sound, and lands `warn` s later:
## - rows: `rows` lines of marks across the arena (`axis` x = rows, y = lanes) erupt one after
##   another, `step` s apart (Morvath's Grave Rows, Cernunnos's Wild Hunt; `knock` throws aside);
## - players: a mark under every hero (or, with target "lowest", the most hurt one, the mark riding
##   on them with `follow`), then a strike there, an optional lingering `zone` and `status`
##   (Vespera's Censer of Plague, Isolde's Carrion Dive);
## - echo: where every hero stood `delay_back` s ago (Memory Devourer's Lost Moments);
## - safe_circle: a ring of `radius` round the boss is the only safe ground; everyone outside is
##   struck (and `status`) (Malazar's Binding Index);
## - pull: every hero within `radius` is dragged to the boss, then a slam (Amalgam's Undertow);
## - summon: `burrows` marks beside the heroes, then `count` x `monster` climb out of each
##   (Krazik's Toll);
## - brand: one hero is branded - the mark rides on them - and erupts, hurting everyone near
##   (Ignis's Forge Brand);
## - geysers: `count` marks over the arena erupt one after another (Vulkania's Magma Geysers).

var strikes := 0  ## strikes landed (tests)
var _history: Array = []  ## echo: [time, {peer: pos}] of the last seconds
var _t := 0.0


func physics(delta: float) -> void:
	_t += delta
	if str(p("pattern", "")) == "echo":
		var snap := {}
		for pl in living_players():
			snap[pl.peer_id] = pl.global_position
		_history.append([_t, snap])
		while _history.size() > 0 and _t - float(_history[0][0]) > float(p("delay_back", 3.0)) + 0.5:
			_history.pop_front()
	super.physics(delta)


func key() -> String:
	return "ascended_" + str(p("key", "mechanic"))


func _warn(at: Vector2, r: float, label: String = "", follow: NodePath = NodePath(""), lead: float = -1.0) -> void:
	var l := float(p("warn", 1.6)) if lead < 0.0 else lead
	Combat.instance.fx.warn.rpc(at, r, l, key(), label, str(p("color", "#ff4d3d")), follow, "telegraph")


func _after(seconds: float, what: Callable) -> void:
	game().get_tree().create_timer(seconds).timeout.connect(func():
		if not is_instance_valid(boss) or not boss.is_alive():
			return
		what.call())


func _strike(at: Vector2, r: float, c: Dictionary) -> void:
	strikes += 1
	Combat.instance.apply_aoe({"type": "aoe", "radius": r, "damage": p("damage", {"base": 10, "coef": 1.4}), "damage_type": _dtype(),
		"fx": str(p("fx", "physical")), "color": str(p("color", "#ff4d3d")), "shake": 3}, c, at)
	if p("zone", null) is Dictionary:
		var z: Dictionary = p("zone", {}).duplicate()
		z.type = "zone"
		z.damage_type = _dtype()
		Combat.instance.add_zone(z, c, at)
	if p("knock", 0) and float(p("knock", 0)) > 0.0:
		for pl in living_players():
			if pl.global_position.distance_to(at) <= r + 8.0:
				Combat.instance.knock(pl, (pl.global_position - at).normalized() * float(p("knock", 160)))
	if p("status", "") != "":
		for pl in living_players():
			if pl.global_position.distance_to(at) <= r + 8.0:
				Combat.instance.apply_status(c, pl, str(p("status", "")), float(p("status_time", 4.0)), 1.0)


func _dtype() -> String:
	return {"nature": "nature", "fire": "fire", "arcane": "arcane", "shadow": "shadow"}.get(str(p("fx", "physical")), "physical")


func _announce(arg: String = "") -> void:
	var ad: Dictionary = boss.def.get("ascended", {})
	var msg := str(ad.get("message", ""))
	if not msg.is_empty():
		game().broadcast_message.rpc(msg, str(p("color", "#ffcf5c")), [arg] if msg.contains("%s") else [])
	Combat.instance.fx.sound.rpc(str(p("sfx", "roar")), boss.global_position)
	boss.play_action.rpc("cast", boss.facing)


func trigger() -> void:
	var players := living_players()
	if players.is_empty():
		return
	var c := ctx()
	var warn := float(p("warn", 1.6))
	var r := float(p("radius", 40))
	match str(p("pattern", "")):
		"rows":
			_announce()
			var room := boss_room().grow(-24)
			var n := int(p("rows", 3))
			var along_x := str(p("axis", "x")) == "x"
			var length := room.size.x if along_x else room.size.y
			var marks := maxi(int(length / (r * 2.0)), 3)
			for k in n:
				var off := randf_range(0.15, 0.85) if n == 1 else (k + 0.5) / n + randf_range(-0.08, 0.08)
				var pts: Array = []
				for i in marks:
					var u := (i + 0.5) / marks
					pts.append(Vector2(lerpf(room.position.x, room.end.x, u), lerpf(room.position.y, room.end.y, off)) if along_x
						else Vector2(lerpf(room.position.x, room.end.x, off), lerpf(room.position.y, room.end.y, u)))
				var lead := warn + float(p("step", 0.4)) * k
				for i in pts.size():
					# One countdown per row; the other marks are rings only.
					_warn(pts[i], r, "" if i == pts.size() / 2 else "-", NodePath(""), lead)
				_after(lead, func():
					Combat.instance.fx.fired.rpc(key())
					for at in pts:
						_strike(at, r, c))
		"players":
			var targets: Array = players
			if str(p("target", "")) == "lowest":
				targets = [players.reduce(func(a, b): return a if a.health.fraction() <= b.health.fraction() else b)]
			_announce(targets[0].display_name)
			for pl in targets:
				var follow: bool = p("follow", false)
				var at: Vector2 = pl.global_position
				_warn(at, r, "", pl.get_path() if follow else NodePath(""))
				var who: Node = pl
				_after(warn, func():
					var hit_at: Vector2 = who.global_position if follow and is_instance_valid(who) else at
					Combat.instance.fx.fired.rpc(key())
					_strike(hit_at, r, c))
		"echo":
			_announce()
			var back := float(p("delay_back", 3.0))
			var snap: Dictionary = {}
			for h in _history:
				if _t - float(h[0]) >= back:
					snap = h[1]
			if snap.is_empty():
				for pl in players:
					snap[pl.peer_id] = pl.global_position
			for peer in snap:
				_warn(snap[peer], r)
			_after(warn, func():
				Combat.instance.fx.fired.rpc(key())
				for peer in snap:
					_strike(snap[peer], r, c))
		"safe_circle":
			_announce()
			# The safe ground: a ring round the boss, rides with it; the danger is everywhere else.
			Combat.instance.fx.warn.rpc(boss.global_position, r, warn, key(), "Safe", "#7dff9a", NodePath(""), "telegraph")
			_after(warn, func():
				Combat.instance.fx.fired.rpc(key())
				Combat.instance.fx.ring.rpc(boss.global_position, r, str(p("color", "#6ee3f0")), str(p("fx", "arcane")))
				for pl in living_players():
					if pl.global_position.distance_to(boss.global_position) > r:
						strikes += 1
						Combat.instance.deal_damage(c, pl, Combat.instance.value_of_spec(p("damage", {"base": 14, "coef": 1.8}), c), {"damage_type": _dtype(), "area": true})
						if p("status", "") != "":
							Combat.instance.apply_status(c, pl, str(p("status", "")), float(p("status_time", 2.5)), 1.0))
		"pull":
			_announce()
			_warn(boss.global_position, float(p("radius", 300)), "Undertow")
			_after(warn, func():
				Combat.instance.fx.fired.rpc(key())
				for pl in living_players():
					var d: float = pl.global_position.distance_to(boss.global_position)
					if d <= float(p("radius", 300)):
						Combat.instance.knock(pl, (boss.global_position - pl.global_position).normalized() * minf(float(p("strength", 260)), d))
				_after(0.45, func(): _strike(boss.global_position, float(p("slam_radius", 80)), c)))
		"summon":
			_announce()
			var spots: Array = []
			for i in int(p("burrows", 3)):
				var pl: Node = players[i % players.size()]
				spots.append(game().nearest_floor(pl.global_position + Vector2.from_angle(randf() * TAU) * 60.0))
			for at in spots:
				_warn(at, r, "Burrow")
			_after(warn, func():
				Combat.instance.fx.fired.rpc(key())
				for at in spots:
					strikes += 1
					Combat.instance.fx.ring.rpc(at, r, str(p("color", "#9a8a5a")), "physical")
					game().summon_monsters(str(p("monster", "plague_rat")), int(p("count", 2)), at, 14.0, boss))
		"brand":
			var pl: Node = players[randi() % players.size()]
			_announce(pl.display_name)
			_warn(pl.global_position, r, "Brand", pl.get_path())
			_after(warn, func():
				if is_instance_valid(pl):
					Combat.instance.fx.fired.rpc(key())
					_strike(pl.global_position, r, c))
		"geysers":
			_announce()
			var room := boss_room().grow(-32)
			for i in int(p("count", 6)):
				var at := Vector2(randf_range(room.position.x, room.end.x), randf_range(room.position.y, room.end.y))
				if i < players.size():
					at = players[i].global_position + Vector2(randf_range(-20, 20), randf_range(-14, 14))
				var lead := warn + float(p("step", 0.35)) * i
				_warn(at, r, "", NodePath(""), lead)
				_after(lead, func():
					Combat.instance.fx.fired.rpc(key())
					_strike(at, r, c))


func test_trigger(suite: RefCounted) -> void:
	if str(p("pattern", "")) == "echo":
		_t += 4.0
	trigger()
	await suite.da._wait(float(p("warn", 1.6)) + float(p("step", 0.0)) * 3.0 + 0.8)


func test_check(_suite: RefCounted) -> String:
	return "" if strikes > 0 and Telegraph.lead_of(key()) >= float(p("warn", 1.6)) - 0.05 else "no strike after its warning (%d, lead %.2f)" % [strikes, Telegraph.lead_of(key())]
