class_name Inventory
extends RefCounted
## Equipment slots + backpack + quick-slot assignments. Pure data and rules: the host owns the
## authoritative copy per player and sends snapshots to the owning client for display.
## A two-handed weapon occupies both weapon slots (stored in main_hand, off_hand stays empty).

const SLOTS := ["head", "chest", "legs", "boots", "gloves", "main_hand", "off_hand", "ring_1", "ring_2", "necklace"]
const SLOT_NAMES := {
	"head": "Head", "chest": "Chest", "legs": "Legs", "boots": "Boots", "gloves": "Gloves",
	"main_hand": "Right hand", "off_hand": "Left hand", "ring_1": "Ring", "ring_2": "Ring", "necklace": "Necklace",
}

var equipment: Dictionary = {}
var backpack: Array = []
var capacity := 12
var quick: Dictionary = {"q": "", "e": ""}


func to_dict() -> Dictionary:
	return {"equipment": equipment.duplicate(true), "backpack": backpack.duplicate(true), "capacity": capacity, "quick": quick.duplicate()}


func load_dict(d: Dictionary) -> void:
	equipment = d.get("equipment", {}).duplicate(true)
	backpack = d.get("backpack", []).duplicate(true)
	capacity = int(d.get("capacity", capacity))
	quick = d.get("quick", {"q": "", "e": ""}).duplicate()


func free_slots() -> int:
	return capacity - backpack.size()


## Adds an item to the backpack (stacking consumables). Returns "" or an error message.
func add(item: Dictionary) -> String:
	if item.get("kind") == "consumable":
		var max_stack := int(GameData.consumables.get(item.base, {}).get("max_stack", 1))
		var remaining := int(item.get("count", 1))
		for it in backpack:
			if it.get("kind") == "consumable" and it.base == item.base and int(it.count) < max_stack:
				var take := mini(max_stack - int(it.count), remaining)
				it.count = int(it.count) + take
				remaining -= take
				if remaining <= 0:
					_auto_quick(item.base)
					return ""
		if remaining > 0:
			if free_slots() <= 0:
				return "Backpack is full"
			var copy := item.duplicate(true)
			copy.count = remaining
			backpack.append(copy)
		_auto_quick(item.base)
		return ""
	if free_slots() <= 0:
		return "Backpack is full"
	backpack.append(item)
	return ""


func can_add(item: Dictionary) -> bool:
	if free_slots() > 0:
		return true
	if item.get("kind") == "consumable":
		var max_stack := int(GameData.consumables.get(item.base, {}).get("max_stack", 1))
		for it in backpack:
			if it.get("kind") == "consumable" and it.base == item.base and int(it.count) + int(item.get("count", 1)) <= max_stack:
				return true
	return false


## Equips backpack[index]. Displaced items go back into the backpack.
func equip_from_backpack(index: int, char_level: int) -> String:
	if index < 0 or index >= backpack.size():
		return "No such item"
	var item: Dictionary = backpack[index]
	if not item.get("kind") in ["weapon", "offhand", "armor", "jewelry"]:
		return "Can't equip that"
	if int(item.get("req", 1)) > char_level:
		return "Requires level %d (you are level %d)" % [int(item.req), char_level]
	# D8: a ring legendary is unique - two copies can't be worn together.
	if item.has("legendary") and str(item.get("slot", "")) == "ring":
		for rs in ["ring_1", "ring_2"]:
			if str(equipment.get(rs, {}).get("legendary", "")) == str(item.legendary):
				return "You already wear %s" % item.name
	var targets := _target_slots(item)
	var displaced: Array = []
	for s in targets.clear:
		if equipment.has(s):
			displaced.append(s)
	# The equipped item leaves the backpack, so one slot frees up.
	if displaced.size() > free_slots() + 1:
		return "Not enough backpack space"
	backpack.remove_at(index)
	for s in displaced:
		backpack.append(equipment[s])
		equipment.erase(s)
	equipment[targets.slot] = item
	return ""


func unequip(slot: String) -> String:
	if not equipment.has(slot):
		return "Nothing equipped"
	if free_slots() <= 0:
		return "Backpack is full"
	backpack.append(equipment[slot])
	equipment.erase(slot)
	return ""


func take_backpack(index: int) -> Dictionary:
	if index < 0 or index >= backpack.size():
		return {}
	return backpack.pop_at(index)


func take_equipped(slot: String) -> Dictionary:
	var it: Dictionary = equipment.get(slot, {})
	equipment.erase(slot)
	return it


func count_of(base_id: String) -> int:
	var n := 0
	for it in backpack:
		if it.get("kind") == "consumable" and it.base == base_id:
			n += int(it.count)
	return n


func consume(base_id: String) -> bool:
	for i in backpack.size():
		var it: Dictionary = backpack[i]
		if it.get("kind") == "consumable" and it.base == base_id:
			it.count = int(it.count) - 1
			if int(it.count) <= 0:
				backpack.remove_at(i)
			return true
	return false


func consumable_types() -> Array:
	var out: Array = []
	for it in backpack:
		if it.get("kind") == "consumable" and not out.has(it.base):
			out.append(it.base)
	return out


## Appearance per visual layer for the layered sprite: layer -> [registry key, tint html].
func appearance() -> Dictionary:
	var out := {}
	var layer_for := {"head": "head", "chest": "chest", "legs": "legs", "boots": "boots", "gloves": "gloves",
		"main_hand": "weapon", "off_hand": "offhand"}
	for slot in layer_for:
		var it: Dictionary = equipment.get(slot, {})
		if it.is_empty() or str(it.get("appearance", "")).is_empty():
			continue
		var layer: String = layer_for[slot]
		# A one-handed weapon in the left hand is drawn as the off-hand layer.
		if slot == "off_hand" and it.get("kind") == "weapon":
			layer = "offhand"
		# The colour variant (#20) recolours the worn art; items without one keep the old soft tint.
		var variant: Variant = it.get("look", {}).get("variant", null) if it.has("look") else null
		if variant == null:
			variant = ItemLooks.variant_of(it)
		if not str(variant).is_empty():
			out[layer] = [str(it.appearance), "#ffffff", variant]
			continue
		var rar := GameData.rarity(int(it.get("rarity", 1)))
		var tint := Color.from_string(str(it.get("tint", "#ffffff")), Color.WHITE).lerp(Color.from_string(rar.color, Color.WHITE), 0.3)
		tint = Color.WHITE.lerp(tint, float(GameData.bal("inventory.appearance_tint", 0.4)))
		out[layer] = [str(it.appearance), tint.to_html(false)]
	return out


func _target_slots(item: Dictionary) -> Dictionary:
	var slot: String = item.slot
	match slot:
		"ring":
			if not equipment.has("ring_1"):
				return {"slot": "ring_1", "clear": []}
			if not equipment.has("ring_2"):
				return {"slot": "ring_2", "clear": []}
			return {"slot": "ring_1", "clear": ["ring_1"]}
		"weapon":
			if int(item.get("hands", 1)) == 2:
				# Quivers (Ranger) stay with a bow; Grip of the Titan keeps a shield with a 2H weapon.
				var off: Dictionary = equipment.get("off_hand", {})
				if off.get("with_two_hand", false) or (_wears_flag("titan_grip") and off.get("base", "") == "shield"):
					return {"slot": "main_hand", "clear": ["main_hand"]}
				return {"slot": "main_hand", "clear": ["main_hand", "off_hand"]}
			var main: Dictionary = equipment.get("main_hand", {})
			if main.is_empty():
				return {"slot": "main_hand", "clear": []}
			if int(main.get("hands", 1)) == 2:
				return {"slot": "main_hand", "clear": ["main_hand"]}
			if not equipment.has("off_hand"):
				return {"slot": "off_hand", "clear": []}
			return {"slot": "main_hand", "clear": ["main_hand"]}
		"offhand":
			var main2: Dictionary = equipment.get("main_hand", {})
			var clear: Array = ["off_hand"]
			var keeps: bool = item.get("with_two_hand", false) or (_wears_flag("titan_grip") and item.get("base", "") == "shield")
			if int(main2.get("hands", 1)) == 2 and not keeps:
				clear.append("main_hand")
			return {"slot": "off_hand", "clear": clear}
	return {"slot": slot, "clear": [slot]}


## The worn items equipping `item` would take off (#11): both hands for a 2H weapon, a 2H weapon
## for an off-hand item, nothing when it goes into an empty slot.
func replaced_by(item: Dictionary) -> Array:
	var out: Array = []
	for s in _target_slots(item).clear:
		if equipment.has(s):
			out.append(equipment[s])
	return out


## A legendary flag on a worn item (Grip of the Titan).
func _wears_flag(flag: String) -> bool:
	for s in equipment:
		if Array(equipment[s].get("flags", [])).has(flag):
			return true
	return false


func _auto_quick(base_id: String) -> void:
	if quick.values().has(base_id):
		return
	for k in ["q", "e"]:
		if str(quick.get(k, "")).is_empty():
			quick[k] = base_id
			return
