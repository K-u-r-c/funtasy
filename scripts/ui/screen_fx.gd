class_name ScreenFx
extends ColorRect
## #81, the local hero only: below `vignette.below` of its health a red vignette pulses at the
## screen's edges with a heartbeat; a hit that takes more than `big_hit.share` of its health in one
## go flashes the edges red. Both off with Settings.screen_shake (the "screen effects" option).

const SHADER := preload("res://assets/shaders/vignette.gdshader")

var low := false  ## the vignette is up (tests)
var flashes := 0
var _mat: ShaderMaterial
var _last_hp := -1.0
var _flash := 0.0
var _t := 0.0
var _beat := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material = _mat
	z_index = -1


func _process(delta: float) -> void:
	_t += delta
	var hud := get_parent()
	# The hero can be freed before the HUD when a session ends: check before the typed read.
	var ref: Variant = hud.get("player") if hud else null
	var p: Player = ref if is_instance_valid(ref) else null
	if p == null or not Settings.screen_shake or p.life_state != Player.Life.ALIVE:
		low = false
		_mat.set_shader_parameter("strength", 0.0)
		_last_hp = -1.0
		return
	var vcfg: Dictionary = GameplayFx.cfg("vignette")
	var bcfg: Dictionary = GameplayFx.cfg("big_hit")
	var frac := p.health.fraction()
	if _last_hp >= 0.0 and _last_hp - p.health.hp > p.health.max_hp * float(bcfg.get("share", 0.15)):
		_flash = 1.0
		flashes += 1
		GameplayFx.note("big_hit")
	_last_hp = p.health.hp
	_flash = maxf(_flash - delta / float(bcfg.get("time", 0.35)), 0.0)
	var below := float(vcfg.get("below", 0.3))
	low = frac < below
	var s := 0.0
	var tint := Color.from_string(str(vcfg.get("color", "#a00010")), Color.RED)
	if low:
		var period := float(vcfg.get("pulse", 1.1)) * (0.6 + 0.4 * frac / below)
		var ph := fmod(_t, period) / period
		s = (0.35 + 0.35 * (1.0 - frac / below)) * (0.7 + 0.3 * exp(-ph * 6.0))
		_beat -= delta
		if _beat <= 0.0:
			_beat = period
			AudioManager.play_sfx("heartbeat", 0.0)
			GameplayFx.note("heartbeat")
	if _flash > 0.0:
		tint = tint.lerp(Color.from_string(str(bcfg.get("color", "#ff2020")), Color.RED), _flash)
		s = maxf(s, 0.6 * _flash)
	_mat.set_shader_parameter("tint", tint)
	_mat.set_shader_parameter("strength", s)
	_mat.set_shader_parameter("inner", 0.55 - 0.15 * _flash)
