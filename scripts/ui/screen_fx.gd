class_name ScreenFx
extends CanvasLayer
## Full-screen effects driven by the local hero's status flags (D32 / D33): `monochrome` (Tome
## Prison) turns the world into parchment, `ink_obscure` (Ink Horror) splashes ink blots. Sits under
## the HUD so the interface stays readable.

var _rect: ColorRect
var _mat: ShaderMaterial
var _mono := 0.0
var _ink := 0.0


func _ready() -> void:
	layer = 5
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/screen_fx.gdshader")
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


func _process(delta: float) -> void:
	var game := get_tree().get_first_node_in_group("game")
	var lp: Variant = game.local_player if game else null
	var alive: bool = is_instance_valid(lp) and lp.is_inside_tree()
	var want_mono := 1.0 if alive and lp.status.has_flag("monochrome") else 0.0
	var want_ink := 1.0 if alive and lp.status.has_flag("ink_obscure") else 0.0
	if want_ink > 0.0 and _ink <= 0.01:
		_mat.set_shader_parameter("seed", randf() * 100.0)
	_mono = move_toward(_mono, want_mono, delta * 2.0)
	_ink = move_toward(_ink, want_ink, delta * 3.0)
	_rect.visible = _mono > 0.001 or _ink > 0.001
	_mat.set_shader_parameter("mono", _mono)
	_mat.set_shader_parameter("ink", _ink * 0.85)
