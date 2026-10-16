extends MonsterBehavior
## Echo of the Unwritten: wears a random hero's look (spawn data copy_peer, picked by Game for
## monsters with "copy_random_player") and fights with that class's basic kit from `kits`.
## params: kits ({class: [ability ids]})

var copied := ""


func _ready() -> void:
	var g := game()
	var pl: Player = g.player_by_peer(enemy.copy_peer) if g and enemy.copy_peer > 0 else null
	if pl == null:
		return
	copied = pl.class_id
	var kits: Dictionary = p("kits", {})
	if kits.has(copied):
		enemy._abilities = kits[copied]
		enemy._update_reach()


func test_check(_suite: RefCounted) -> String:
	return "" if copied != "" else "copied nobody"
