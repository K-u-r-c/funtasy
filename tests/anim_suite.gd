class_name AnimSuite
extends RefCounted
## #17: co-op animation sync. Host (warrior) and client (mage) each attack / cast, dodge and get hit;
## the other side records the hero's CharacterSprite.anim sequence and checks it saw every one-shot
## in order and facing the right way. Also: the owner never sees its own one-shot restart (no
## double play), a cast-time pose is held on both sides, the downed fall and loop, ghost, and a
## monster's attack seen by the client.

var da: Node
var g: Node
var p: Player

## Recording: actor -> [[anim, dir, frame], ...] (a row per change of anim / dir / frame).
var _rec: Array = []
var _rec_actor: Actor = null
var _rec_cb: Callable


func _init(dev_auto: Node) -> void:
	da = dev_auto


func _start_rec(actor: Actor) -> void:
	_stop_rec()
	_rec = []
	_rec_actor = actor
	_rec_cb = func() -> void:
		if not is_instance_valid(_rec_actor) or _rec_actor.sprite == null:
			return
		var body: AnimatedSprite2D = _rec_actor.sprite.get_node_or_null("body")
		var row := [_rec_actor.sprite.anim, _rec_actor.sprite.dir_index, body.frame if body else 0]
		if _rec.is_empty() or _rec[-1] != row:
			_rec.append(row)
	da.get_tree().process_frame.connect(_rec_cb)


func _stop_rec() -> void:
	if _rec_cb.is_valid() and da.get_tree().process_frame.is_connected(_rec_cb):
		da.get_tree().process_frame.disconnect(_rec_cb)


## The distinct anims of the recording, in order (consecutive repeats collapsed).
func _seq() -> Array:
	var out: Array = []
	for r in _rec:
		if out.is_empty() or out[-1] != r[0]:
			out.append(r[0])
	return out


## Is `want` a subsequence of `seq`?
static func in_order(seq: Array, want: Array) -> bool:
	var i := 0
	for a in seq:
		if i < want.size() and a == want[i]:
			i += 1
	return i == want.size()


## How many times one-shot `anim_name` started (entered, or its frame jumped back to 0).
func _starts(anim_name: String) -> int:
	var n := 0
	var prev: Array = []
	for r in _rec:
		if r[0] == anim_name and (prev.is_empty() or prev[0] != anim_name or (int(r[2]) < int(prev[2]) and prev[1] == r[1])):
			n += 1
		prev = r
	return n


## Direction rows recorded while `anim_name` played.
func _dirs_of(anim_name: String) -> Array:
	var out: Array = []
	for r in _rec:
		if r[0] == anim_name and not out.has(r[1]):
			out.append(r[1])
	return out


func _hit(target: Actor) -> void:
	var hero := target is Player
	if hero:
		target.iframe_left = 0.0
	target.health.hp = target.health.max_hp
	var ctx: Dictionary = Combat.instance.env_ctx(1.0)
	ctx.cannot_miss = true
	Combat.instance.deal_damage(ctx, target, 1.0)
	if hero:
		target.iframe_left = 9999.0


# =========================================================================================
# Host
# =========================================================================================


func run_lan() -> void:
	g = da._game()
	p = da._local()
	await da._wait_until(func(): return g.players_root.get_child_count() >= 2, 10.0)
	await da._wait(1.0)
	var c: Player = da._other_player()
	for e in g.enemies_root.get_children():
		e.queue_free()
	await da._wait(0.3)
	var start: Vector2 = g.layout.start
	p.host_teleport(start)
	c.host_teleport(g.nearest_floor(start + Vector2(-70, 0)))
	for pl in [p, c]:
		pl.iframe_left = 9999.0
		pl.health.max_hp = maxf(pl.health.max_hp, 200.0)
	await da._wait(0.6)

	# --- the host acts, the client watches ----------------------------------------------
	NetworkManager.to_clients("DevAuto", "client_cmd", ["an_watch", 1])
	await da._wait(0.4)
	_start_rec(p)  # the host's own view of itself (no double play)
	p.auto_aim = p.global_position + Vector2(0, 60)  # attack facing the camera (S)
	Input.action_press("attack")
	await da._wait(0.12)
	Input.action_release("attack")
	await da._wait(0.7)
	p.auto_aim = p.global_position + Vector2(60, 0)
	Input.action_press("dodge")
	await da._wait(0.05)
	Input.action_release("dodge")
	await da._wait(0.6)
	_hit(p)
	await da._wait(0.6)
	_stop_rec()
	# Attack / cast names come from the weapons (#19): warrior sword -> slash, mage wand -> flick.
	var atk := Combat.anim_for(p, GameData.skill(str(GameData.classes[p.class_id].primary_attack)))
	var cst := Combat.anim_for(c, GameData.skill(str(GameData.classes[c.class_id].primary_attack)))
	da.check(_starts(atk) == 1, "the host's own %s plays once, not restarted by its echo (%d)" % [atk, _starts(atk)])
	NetworkManager.to_clients("DevAuto", "client_cmd", ["an_expect", [[atk, "dash", "hit"], {atk: 2}]])
	await da._wait(0.6)

	# --- a monster attacks, the client watches --------------------------------------------
	var m: Enemy = g.spawn_monster("skeletal_footman", g.nearest_floor(start + Vector2(50, 40)), false)
	await da._wait(0.8)
	m.status.apply("stun", 3.0, 1.0, null)  # no AI swings of its own during the check
	NetworkManager.to_clients("DevAuto", "client_cmd", ["an_watch_enemy", str(m.name)])
	await da._wait(0.3)
	m.play_action.rpc("attack", Vector2.LEFT)
	await da._wait(0.5)
	_hit(m)
	await da._wait(0.5)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["an_expect", [["attack", "hit"], {"attack": 4}]])
	await da._wait(0.6)
	m.queue_free()

	# --- the client acts, the host watches ----------------------------------------------
	_start_rec(c)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["an_act", [c.global_position + Vector2(-60, 0), cst]])
	await da._wait(1.9)
	_hit(c)
	await da._wait(0.7)
	_stop_rec()
	var seq := _seq()
	da.check(in_order(seq, [cst, "dash", "hit"]), "the host sees the client's %s, dash and hit in order (%s)" % [cst, seq])
	da.check(_dirs_of(cst).has(4), "the host sees the client's %s facing W (%s)" % [cst, _dirs_of(cst)])

	# --- a cast-time pose is held on both sides ------------------------------------------
	_start_rec(c)
	c.casting = {"skill": "mage_bolt", "aim": c.global_position + Vector2(-60, 0), "left": 1.0, "extra": {}}
	NetworkManager.to_clients("DevAuto", "client_cmd", ["an_held", cst])
	await da._wait(1.3)
	_stop_rec()
	var cast_rows := _rec.filter(func(r): return r[0] == cst).size()
	da.check(cast_rows > 0 and _rec.back()[0] != cst, "the host holds the client's %s pose and drops it after (%s)" % [cst, _seq()])

	# --- #15: both heroes in full class gear look the same on both sides as a fresh sprite ---
	var lobby := preload("res://scripts/ui/lobby.gd")
	p.appearance = lobby.class_look("warrior")
	c.appearance = lobby.class_look("priest")
	await da._wait(0.8)
	da.check(HeroArtSuite.vs_fresh(p, da.get_tree()) == 0 and HeroArtSuite.vs_fresh(c, da.get_tree()) == 0,
			"the host draws both geared heroes exactly like fresh sprites (#15)")
	NetworkManager.to_clients("DevAuto", "client_cmd", ["an_look", null])
	await da._wait(0.6)

	# --- downed fall, downed loop, ghost: derived from the replicated life state ----------
	NetworkManager.to_clients("DevAuto", "client_cmd", ["an_watch", 1])
	await da._wait(0.3)
	p.iframe_left = 0.0
	p.health.take(p.health.hp + p.health.absorb + 10.0)
	await da._wait(1.4)
	p.downed_left = 0.05
	await da._wait(0.6)
	NetworkManager.to_clients("DevAuto", "client_cmd", ["an_expect", [["death", "downed", "ghost"], {}]])
	await da._wait(0.6)
	p.revive(1.0)
	p.iframe_left = 9999.0
	NetworkManager.to_clients("DevAuto", "client_cmd", ["done", null])
	await da._wait(1.0)


# =========================================================================================
# Client
# =========================================================================================


func client_cmd(cmd: String, arg: Variant) -> void:
	g = da._game()
	p = da._local()
	match cmd:
		"an_watch":
			var who: Player = g.player_by_peer(int(arg))
			_start_rec(who)
			da.set_meta("anim_rec", self)
		"an_watch_enemy":
			_start_rec(g.enemies_root.get_node_or_null(str(arg)))
			da.set_meta("anim_rec", self)
		"an_expect":
			var rec: AnimSuite = da.get_meta("anim_rec")
			rec._stop_rec()
			var seq := rec._seq()
			da.check(in_order(seq, arg[0]), "the client sees %s in order (%s)" % [arg[0], seq])
			for a in arg[1]:
				da.check(rec._dirs_of(a).has(int(arg[1][a])), "the client sees %s facing dir %d (%s)" % [a, int(arg[1][a]), rec._dirs_of(a)])
		"an_act":
			_start_rec(p)
			var cst: String = arg[1]
			p.auto_aim = arg[0]  # cast facing W
			Input.action_press("attack")
			await da._wait(0.12)
			Input.action_release("attack")
			await da._wait(0.8)
			Input.action_press("dodge")
			await da._wait(0.05)
			Input.action_release("dodge")
			await da._wait(1.6)
			_stop_rec()
			da.check(_starts(cst) == 1, "the client's own %s plays once, not restarted by the host's echo (%d)" % [cst, _starts(cst)])
			da.check(in_order(_seq(), [cst, "dash", "hit"]), "the client sees its own %s, dash and hit (%s)" % [cst, _seq()])
			p.auto_aim = Vector2.INF
		"an_look":
			var bad := []
			for hero in g.players_root.get_children():
				var n := HeroArtSuite.vs_fresh(hero, da.get_tree())
				if n != 0:
					bad.append("%s: %d px" % [hero.display_name, n])
			da.check(bad.is_empty() and g.players_root.get_child_count() == 2, "the client draws both geared heroes exactly like fresh sprites (#15) %s" % [bad])
		"an_held":
			var ok: bool = await da._wait_until(func(): return p.held_anim == str(arg) and p.sprite.anim == str(arg), 0.6)
			da.check(ok, "the client sees its own held %s pose from the replicated state" % arg)
			var off: bool = await da._wait_until(func(): return p.held_anim.is_empty(), 1.5)
			da.check(off, "the held pose ends with the cast")
