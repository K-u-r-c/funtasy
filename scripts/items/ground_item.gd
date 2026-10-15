class_name GroundItem
extends Node2D
## An item lying on the floor, shared by everyone (first come, first served). Spawned by the
## host's MultiplayerSpawner; glows in its rarity color (outline shader + real light +
## sparkles for Rare and above) so it can be spotted from afar.

const GLOW_SHADER := preload("res://assets/shaders/item_glow.gdshader")

var item: Dictionary = {}
var _icon: Sprite2D
var _t := 0.0


func setup(data: Dictionary) -> void:
	name = data.name
	position = data.pos
	item = data.item


func _ready() -> void:
	add_to_group("ground_items")
	var rar := GameData.rarity(int(item.get("rarity", 1)))
	var color := Color.from_string(rar.color, Color.WHITE)
	var shadow := Sprite2D.new()
	shadow.texture = GameData.texture("fx.shadow")
	shadow.scale = Vector2(0.6, 0.6)
	add_child(shadow)
	_icon = Sprite2D.new()
	_icon.texture = GameData.texture(str(item.get("icon", "items.backpack")))
	_icon.scale = Vector2(0.75, 0.75)
	var mat := ShaderMaterial.new()
	mat.shader = GLOW_SHADER
	mat.set_shader_parameter("glow_color", color)
	mat.set_shader_parameter("intensity", 0.5 + 0.25 * int(item.get("rarity", 1)))
	_icon.material = mat
	add_child(_icon)
	var light := PointLight2D.new()
	LightLayers.setup_light(light)
	light.texture = GameData.texture("fx.light")
	light.color = color
	light.energy = float(rar.get("light_energy", 0.6))
	light.texture_scale = 0.45 + 0.08 * int(item.get("rarity", 1))
	light.position = Vector2(0, -8)
	add_child(light)
	if int(item.get("rarity", 1)) >= 3:
		var p := CPUParticles2D.new()
		p.texture = GameData.texture("fx.spark")
		p.amount = 4 + 2 * int(item.rarity)
		p.lifetime = 1.2
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 8.0
		p.direction = Vector2(0, -1)
		p.spread = 20.0
		p.gravity = Vector2(0, -20)
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 12.0
		p.scale_amount_min = 0.3
		p.scale_amount_max = 0.7
		p.color = Color(color.r * 1.6, color.g * 1.6, color.b * 1.6)
		p.position = Vector2(0, -8)
		var pm := CanvasItemMaterial.new()
		pm.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = pm
		add_child(p)
	_t = randf() * TAU


func _process(delta: float) -> void:
	_t += delta * 2.5
	_icon.position = Vector2(0, -12 + sin(_t) * 2.0)


func interact_text() -> String:
	return "Pick up %s" % item.get("name", "item")


func interact_pos() -> Vector2:
	return global_position
