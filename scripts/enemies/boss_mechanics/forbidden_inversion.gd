extends BossMechanic
## Malazar P1 - Forbidden Inversion: every `every` s the party's movement controls invert for
## `duration` s, or (every other time) direct heals on them deal damage instead.
## params: every (15), duration (4)

var _n := 0
var cast := 0


func trigger() -> void:
	_n += 1
	var st := "inverted_controls" if _n % 2 == 1 else "inverted_healing"
	var c := ctx()
	for pl in living_players():
		Combat.instance.apply_status(c, pl, st, float(p("duration", 4.0)), 0.0)
	game().broadcast_message.rpc("Forbidden Inversion! %s" % ("Your steps betray you!" if st == "inverted_controls" else "Healing burns!"), "#a080ff")
	boss.play_action.rpc("cast", boss.facing)
	cast += 1


func test_check(suite: RefCounted) -> String:
	return "" if cast > 0 and (suite.p.status.has_flag("invert_move") or suite.p.status.has_flag("heal_inverted")) else "no inversion"
