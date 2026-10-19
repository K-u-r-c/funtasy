class_name PreviewSuite
extends RefCounted
## #42 aim preview (scenario "preview", a solo mage): every hero skill in the data resolves to a
## preview shape that draws something; a tap casts on release; a held skill shows its preview and
## casts on release, not before; the preview says why when the cast can't happen (cooldown, cost);
## the preview follows the aim (cursor / stick); a charge-up skill (Power Shot) still starts on the
## press and fires on the release, with its preview showing while held.

var da: Node
var g: Node
var p: Player


func _init(dev_auto: Node) -> void:
	da = dev_auto


func _press(action: String) -> void:
	Input.action_press(action)
	await da.get_tree().physics_frame


func _release(action: String) -> void:
	Input.action_release(action)
	await da.get_tree().physics_frame
	await da.get_tree().physics_frame


func run() -> void:
	g = da._game()
	p = da._local()
	await da._wait(1.0)
	for e in g.enemies_root.get_children():
		e.queue_free()
	p.iframe_left = 9999.0
	# Every hero skill resolves to a shape the preview can draw.
	var bad: Array = []
	var kinds := {}
	for sid in GameData.skills:
		var sk: Dictionary = GameData.skills[sid]
		if not str(sid).split("_")[0] in ["warrior", "ranger", "mage", "priest"] or sk.get("passive", false):
			continue
		var shape := SkillShape.of(sk)
		kinds[shape.kind] = int(kinds.get(shape.kind, 0)) + 1
		if AimPreview.primitives(shape, Vector2.ZERO, Vector2(100, 0)).is_empty():
			bad.append(sid)
	da.check(bad.is_empty() and kinds.size() >= 9, "every hero skill resolves to a preview shape (%s; none drawn: %s)" % [kinds, bad])
	# A tap casts on release.
	p.skills[1] = "mage_fireball"
	p.resource.value = p.resource.max_value
	p.auto_aim = p.global_position + Vector2(120, 0)
	await da._wait(0.3)
	await _press("skill_1")
	await _release("skill_1")
	await da._wait(0.4)
	da.check(p.local_cd.has(1), "a tap casts the skill")
	# A hold shows the preview and casts only on release.
	p.local_cd.clear()
	p.cooldowns.clear()
	p.resource.value = p.resource.max_value
	await da._wait(0.3)
	await _press("skill_1")
	await da._wait(0.7)
	da.check(p.preview_slot() == 1 and not p.local_cd.has(1) and p.cooldown_left("mage_fireball") <= 0.0,
			"holding the key shows the preview and casts nothing yet")
	var info := p.preview_info(1)
	da.check(str(info.shape.kind) == "projectile" and str(info.why).is_empty() and Vector2(info.aim).is_equal_approx(p.aim_pos),
			"the preview is the fireball's path, valid, aimed at the cursor (%s)" % [info.shape.kind])
	p.auto_aim = p.global_position + Vector2(-80, 60)
	await da._wait(0.2)
	da.check(Vector2(p.preview_info(1).aim).is_equal_approx(p.aim_pos), "the preview follows the aim while held")
	await _release("skill_1")
	await da._wait(0.4)
	da.check(p.local_cd.has(1) and p.preview_slot() == -1, "releasing casts it and hides the preview")
	# Invalid: on cooldown, then without mana.
	await _press("skill_1")
	await da._wait(0.5)
	da.check(str(p.preview_info(1).why) == "Not ready", "on cooldown the preview says Not ready")
	await _release("skill_1")
	p.local_cd.clear()
	p.cooldowns.clear()
	p.resource.value = 0.0
	await _press("skill_1")
	await da._wait(0.5)
	da.check(str(p.preview_info(1).why) == "Not enough Mana", "without mana the preview says Not enough Mana")
	await _release("skill_1")
	await da._wait(0.3)
	da.check(not p.local_cd.has(1) or p.cooldown_left("mage_fireball") <= 0.0, "a refused cast starts no cooldown")
	p.resource.value = p.resource.max_value
	# A charge-up skill starts on the press, shows its preview while held and fires on release.
	p.skills[2] = "ranger_power_shot"
	p.local_cd.clear()
	p.cooldowns.clear()
	await da._wait(0.3)
	await _press("skill_2")
	await da._wait(0.4)
	da.check(not p.charging.is_empty() and p.preview_slot() == 2 and str(p.preview_info(2).shape.kind) == "line",
			"a charge-up skill starts charging on the press and previews its line")
	await _release("skill_2")
	await da._wait(0.4)
	da.check(p.charging.is_empty() and p.cooldown_left("ranger_power_shot") > 0.0, "releasing fires the charged shot")
	p.auto_aim = Vector2.INF
