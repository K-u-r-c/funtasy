extends BossMechanic
## Vulkania P1: she dives into the magma for `under` s (untargetable, only her spines show) while
## geysers erupt under the heroes every `geyser_every` s, then surfaces for `over` s.
## params: under (7), over (7), geyser_every (1.6), damage (dict)

var _under := false
var _left := 0.0
var _geyser := 0.0
var geysers := 0


func _ready() -> void:
	_left = 2.0


func busy() -> bool:
	return _under


func physics(delta: float) -> void:
	_left -= delta
	if _left <= 0.0:
		_under = not _under
		_left = float(p("under", 7.0)) if _under else float(p("over", 7.0))
		if _under:
			Combat.instance.apply_status(ctx(), boss, "submerged_lava", _left + 0.2, 0.0)
			Combat.instance.fx.sound.rpc("splash", boss.global_position)
		else:
			boss.status.remove("submerged_lava")
	if not _under:
		return
	_geyser -= delta
	if _geyser > 0.0:
		return
	_geyser = float(p("geyser_every", 1.6))
	var c := ctx()
	for pl in living_players():
		Combat.instance.run_effect({"type": "delayed", "delay": 1.0, "at": "self", "telegraph": {"radius": 36, "color": "#ff5511"},
			"effects": [{"type": "aoe", "radius": 36, "damage": p("damage", {"base": 6, "coef": 1.1}), "damage_type": "fire", "color": "#ff7a2a", "fx": "explosion"}]},
			c, pl.global_position, pl.global_position)
		geysers += 1


func stop() -> void:
	_under = false
	if is_instance_valid(boss):
		boss.status.remove("submerged_lava")


func test_trigger(_suite: RefCounted) -> void:
	_left = 0.0


func test_check(_suite: RefCounted) -> String:
	return "" if geysers > 0 and boss.status.has("submerged_lava") else "no dive"
