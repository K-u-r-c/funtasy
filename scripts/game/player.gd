extends CharacterBody2D
## Top-down player. The owning peer has authority and drives movement; hp/alive are owned by
## that peer too and replicated by the MultiplayerSynchronizer. The host damages players via RPC.

const SPEED := 90.0
const MAX_HP := 5
const ATTACK_COOLDOWN := 0.35
const ATTACK_RANGE := 28.0
const ATTACK_DAMAGE := 1
const INVULN_TIME := 0.8
const COLORS := [
	Color(0.35, 0.65, 1.0), Color(1.0, 0.5, 0.4), Color(0.5, 0.9, 0.5), Color(1.0, 0.85, 0.35)
]

var peer_id := 1
var color_index := 0
var display_name := ""
# Replicated (see player.tscn).
var hp: int = MAX_HP
var alive := true
var facing := Vector2.DOWN

var _attack_cd := 0.0
var _invuln := 0.0
var _swing := 0.0


func _enter_tree() -> void:
	peer_id = int(str(name))
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	add_to_group("players")


func _physics_process(delta: float) -> void:
	_swing = maxf(_swing - delta, 0.0)
	_invuln = maxf(_invuln - delta, 0.0)
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	queue_redraw()
	if not is_multiplayer_authority():
		return
	if not alive or get_tree().get_first_node_in_group("game").input_blocked:
		velocity = Vector2.ZERO
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()
	if dir != Vector2.ZERO:
		facing = dir.normalized()
	if Input.is_action_pressed("attack") and _attack_cd <= 0.0:
		_attack_cd = ATTACK_COOLDOWN
		_attack()


func _attack() -> void:
	_show_swing.rpc(facing)
	var game := get_tree().get_first_node_in_group("game")
	for e in get_tree().get_nodes_in_group("enemies"):
		var to_enemy: Vector2 = e.global_position - global_position
		var close := to_enemy.length() < 8.0  # standing on the player: direction is meaningless
		if to_enemy.length() <= ATTACK_RANGE and (close or to_enemy.normalized().dot(facing) > 0.2):
			game.hit_enemy.rpc_id(1, str(e.name), ATTACK_DAMAGE)


@rpc("any_peer", "call_local", "unreliable")
func _show_swing(dir: Vector2) -> void:
	facing = dir
	_swing = 0.15


## Called by the host when an enemy touches this player.
@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int) -> void:
	if not is_multiplayer_authority() or not _from_host():
		return
	if not alive or _invuln > 0.0:
		return
	hp = maxi(hp - amount, 0)
	_invuln = INVULN_TIME
	if hp == 0:
		alive = false


## Host moves everyone to the new floor's start room and revives the fallen at half health.
@rpc("any_peer", "call_local", "reliable")
func teleport(pos: Vector2, revive: bool) -> void:
	if not is_multiplayer_authority() or not _from_host():
		return
	global_position = pos
	velocity = Vector2.ZERO
	if revive and not alive:
		alive = true
		hp = ceili(MAX_HP / 2.0)


func _from_host() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == 0 or sender == 1


func _draw() -> void:
	var base: Color = COLORS[color_index % COLORS.size()]
	if not alive:
		draw_circle(Vector2.ZERO, 6.0, Color(0.5, 0.5, 0.55, 0.45))
		return
	var tint := base if _invuln <= 0.0 or int(_invuln * 20.0) % 2 == 0 else base.lightened(0.6)
	draw_rect(Rect2(-5, -5, 10, 10), tint)
	draw_rect(Rect2(-5, -5, 10, 10), Color.BLACK, false, 1.0)
	draw_circle(facing * 4.0, 1.6, Color.WHITE)
	if _swing > 0.0:
		var a := facing.angle()
		draw_arc(Vector2.ZERO, ATTACK_RANGE * 0.8, a - 0.9, a + 0.9, 10, Color(1, 1, 1, _swing / 0.15), 3.0)
	# Name tag.
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-20, -10), display_name, HORIZONTAL_ALIGNMENT_CENTER, 40.0, 8, Color(1, 1, 1, 0.85))
