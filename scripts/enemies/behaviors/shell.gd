extends MonsterBehavior
## Magma Carapace: an obsidian shell takes `reduction` less physical damage. Frost damage, or a
## melee blow from a blunt weapon (mace, warhammer, shield), shatters it for good.
## params: reduction (0.6), blunt ([bases])

var shattered := false


func _ready() -> void:
	set_state("shelled")


func modify_damage_taken(amount: float, data: Dictionary) -> float:
	if shattered:
		return amount
	var att: Variant = data.get("attacker")
	var blunt := false
	if data.get("melee", false) and is_instance_valid(att) and att is Player:
		for slot in att.inv.equipment:
			if Array(p("blunt", ["mace", "warhammer", "shield"])).has(str(att.inv.equipment[slot].get("base", ""))):
				blunt = true
	if str(data.get("damage_type", "")) == "frost" or blunt:
		shattered = true
		set_state("")
		Combat.instance.fx.ring.rpc(enemy.global_position, 26.0, "#202020", "explosion")
		Combat.instance.fx.number.rpc(enemy.global_position, "Shell shattered!", "info")
		return amount
	return amount * (1.0 - float(p("reduction", 0.6))) if str(data.get("damage_type", "")) == "physical" else amount


func test_trigger(suite: RefCounted) -> void:
	var c := Combat.instance.make_ctx(suite.p, {"id": "t", "school": "spell", "damage_type": "frost"})
	Combat.instance.deal_damage(c, enemy, 1.0, {"damage_type": "frost"})


func test_check(_suite: RefCounted) -> String:
	return "" if shattered else "shell holds against frost"
