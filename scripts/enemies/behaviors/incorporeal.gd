extends MonsterBehavior
## Banshee: an incorporeal body takes `reduction` less physical damage. params: reduction (0.5)


func modify_damage_taken(amount: float, data: Dictionary) -> float:
	return amount * (1.0 - float(p("reduction", 0.5))) if str(data.get("damage_type", "")) == "physical" else amount


func test_check(_suite: RefCounted) -> String:
	return "" if modify_damage_taken(100.0, {"damage_type": "physical"}) < 60.0 and modify_damage_taken(100.0, {"damage_type": "fire"}) > 99.0 else "not incorporeal"
