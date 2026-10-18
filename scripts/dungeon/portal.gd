extends Node2D
## Exit portal that appears when the floor boss dies. When every living player stands in it
## (or someone interacts with it and the rest are close), the host moves the party down.

var radius := 56.0


func _ready() -> void:
	add_to_group("portal")
	var entry := GameData.asset_entry("props.portal")
	var tex: Texture2D = load(str(entry.path))
	var frames := int(entry.get("frames", 1))
	var sf := SpriteFrames.new()
	sf.set_animation_speed("default", float(entry.get("fps", 8)))
	for f in frames:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(f * tex.get_width() / frames, 0, tex.get_width() / frames, tex.get_height())
		sf.add_frame("default", at)
	var a := AnimatedSprite2D.new()
	a.sprite_frames = sf
	a.offset = Vector2(0, -tex.get_height() / 2.0 + 4.0)
	a.modulate = Color(1.4, 1.3, 1.6)
	add_child(a)
	a.play("default")
	var l := PointLight2D.new()
	LightLayers.setup_light(l)
	l.texture = GameData.texture("fx.light")
	l.color = Color(0.65, 0.4, 1.0)
	l.energy = 1.6
	l.texture_scale = 2.0
	l.position = Vector2(0, -24)
	add_child(l)
	var p := CPUParticles2D.new()
	p.texture = GameData.texture("fx.spark")
	p.amount = 24
	p.lifetime = 1.4
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 22.0
	p.gravity = Vector2(0, -40)
	p.color = Color(1.0, 0.7, 1.6)
	p.position = Vector2(0, -24)
	var pm := CanvasItemMaterial.new()
	pm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = pm
	add_child(p)
	AudioManager.play_sfx_at("portal", global_position)


func interact_text() -> String:
	return Loc.t("Descend to the next floor")


func interact_pos() -> Vector2:
	return global_position
