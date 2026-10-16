extends FloorMechanic
## Crypt - grave urns: breaking one has a `chance` (15%) to release a poisonous miasma cloud
## dealing `pct` of max HP per second for `duration` s to everyone inside.

func on_prop_broken(prop: Node) -> void:
	if str(prop.get("type")) != "grave_urn" or randf() >= float(p("chance", 0.15)):
		return
	var ctx := Combat.instance.env_ctx(0.0)
	Combat.instance.add_zone({"type": "zone", "radius": float(p("radius", 56)), "duration": float(p("duration", 4.0)), "tick": 1.0,
		"color": "#7a9a3a", "damage": {"base": 0, "coef": 0, "pct_target_max_hp": float(p("pct", 0.04))}, "damage_type": "nature"}, ctx, prop.global_position)
	game.broadcast_message.rpc("A cloud of grave miasma bursts from the urn!", "#9ac04a")
	released += 1


var released := 0


func test_trigger(suite: RefCounted) -> void:
	var saved: float = float(p("chance", 0.15))
	params.chance = 1.0
	var at: Vector2 = suite.p.global_position + Vector2(40, 0)
	game.dungeon.spawn_prop.rpc("TestUrn", "grave_urn", game.nearest_floor(at))
	await suite.da._wait(0.2)
	var urn: Node = game.dungeon.props.get("TestUrn")
	if urn:
		urn.take_damage(999.0, Combat.instance.test_ctx(suite.p, {"id": "t", "school": "melee"}))
	params.chance = saved


func test_check(_suite: RefCounted) -> String:
	return "" if released > 0 else "no miasma"
