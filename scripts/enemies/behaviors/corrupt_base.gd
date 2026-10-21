class_name CorruptBehavior
extends MonsterBehavior
## #74 Base of a corrupted monster's ability (data/corruption.json abilities): params are the
## ability's data. Every ability warns before it acts: `warn_at` puts the ring with its countdown
## where the danger lands (logged as "corrupt_<id>"), `act_after` runs it `warn` s later (and logs
## it fired), from the game's tree so it still happens when the monster has died.

var id := ""
var uses := 0  ## times the ability acted (tests)


func key() -> String:
	return "corrupt_" + id


func warn_at(pos: Vector2, radius: float, label: String = "", follow: NodePath = NodePath("")) -> void:
	Combat.instance.fx.warn.rpc(pos, radius, float(p("warn", 1.0)), key(), label, str(p("color", "#b07cff")), follow, "telegraph")


func act_after(what: Callable) -> void:
	var g := game()
	if g == null:
		return
	g.get_tree().create_timer(float(p("warn", 1.0))).timeout.connect(func():
		uses += 1
		Combat.instance.fx.fired.rpc(key())
		what.call())


## The monster's context for damage, made now (it may be gone when the ability lands).
func ctx() -> Dictionary:
	return Combat.instance.make_ctx(enemy, {"id": key(), "school": "spell", "damage_type": str(p("damage_type", "physical"))})
