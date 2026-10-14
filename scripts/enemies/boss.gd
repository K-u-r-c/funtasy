class_name Boss
extends Enemy
## Floor boss (data/bosses/*.json). Same AI as other monsters, plus HP-threshold phases that
## swap the ability list and can fire one-off abilities (e.g. enrage) when entered.

var phase := -1  ## replicated for the HUD


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
	var phases: Array = def.phases
	var frac := health.fraction()
	for i in phases.size():
		if frac > float(phases[i].hp_above) or i == phases.size() - 1:
			if i > phase:
				_enter_phase(i)
			break
	super._think(game)


func _enter_phase(i: int) -> void:
	phase = i
	var p: Dictionary = def.phases[i]
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
