class_name Boss
extends Enemy
## Floor boss (data/bosses/*.json). Same AI as other monsters, plus HP-threshold phases that
## swap the ability list and can fire one-off abilities (e.g. enrage) when entered. Each phase
## can run arena mechanics (scripts/enemies/boss_mechanics/, host-only).

var phase := -1  ## replicated for the HUD
var mechanics: Array = []  ## host: BossMechanic modules of the current phase


func setup(data: Dictionary) -> void:
	super.setup(data)
	var sync: MultiplayerSynchronizer = get_node("StateSync")
	var cfg := sync.replication_config
	cfg.add_property(NodePath(".:phase"))
	cfg.property_set_spawn(NodePath(".:phase"), true)
	cfg.property_set_replication_mode(NodePath(".:phase"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)


func _configure_ai() -> void:
	_aggro_radius = float(def.get("aggro_radius", 320))
	_enter_phase(0)


func _think(game: Node) -> void:
	_check_phase()
	super._think(game)


func _check_phase() -> void:
	var phases: Array = def.phases
	var frac := health.fraction()
	for i in phases.size():
		if frac > float(phases[i].hp_above) or i == phases.size() - 1:
			if i > phase:
				_enter_phase(i)
			break


func _host_ai(delta: float) -> void:
	if not is_alive():
		return
	if aggro:  # arena mechanics run once the fight is on
		for m in mechanics:
			m.physics(delta)
	if mechanics_busy():
		_check_phase()
		return  # a mechanic drives the boss (whirlwind, flight...)
	super._host_ai(delta)


func mechanics_busy() -> bool:
	for m in mechanics:
		if m.busy():
			return true
	return false


func modify_damage_taken(amount: float, data: Dictionary) -> float:
	amount = super.modify_damage_taken(amount, data)
	for m in mechanics:
		amount = m.modify_damage_taken(amount, data)
	return amount


## Host: a player used an arena object; the mechanic that owns it handles it.
func on_mechanic_interact(p: Player, node: Node) -> bool:
	for m in mechanics:
		if m.on_interact(p, node):
			return true
	return false


func stop_mechanics() -> void:
	for m in mechanics:
		m.stop()
	mechanics.clear()


func on_death() -> void:
	if multiplayer.is_server():
		stop_mechanics()
	super.on_death()


func _enter_phase(i: int) -> void:
	phase = i
	var p: Dictionary = def.phases[i]
	if multiplayer.is_server():
		stop_mechanics()
		for md in p.get("mechanics", []):
			var scr: Script = load(GameData.BOSS_MECHANIC_DIR + str(md.id) + ".gd")
			var m: BossMechanic = scr.new()
			mechanics.append(m)
			m.setup(self, md)
	_abilities = p.abilities
	_preferred = p.get("preferred_range", [0, 60])
	for sid in p.get("on_enter", []):
		var ctx := Combat.instance.make_ctx(self, GameData.skill(sid))
		for eff in GameData.skill(sid).effects:
			Combat.instance.run_effect(eff, ctx, global_position, global_position)
	if p.has("message") and i > 0:
		var game := get_tree().get_first_node_in_group("game")
		if game:
			game.broadcast_message.rpc(str(p.message), "#ff5533")
		Combat.instance.fx.sound.rpc("roar", global_position)
