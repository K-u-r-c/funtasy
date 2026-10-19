extends Node
## Global, peer-local signal hub. Systems emit here instead of holding references to each
## other. Nothing in here is networked: every peer emits its own events.

# Run / floor flow
signal floor_started(depth: int)
signal floor_cleared(depth: int)
signal boss_engaged(boss: Node)
signal boss_defeated(boss: Node)
signal party_wiped
signal run_ended

# Local player
signal local_player_spawned(player: Node)
signal local_inventory_changed
signal local_stats_changed
signal local_cooldown_started(slot: int, duration: float)
signal local_level_up(level: int)
signal local_loadout_changed
signal interact_prompt(text: String, index: int, count: int)
signal friendly_target_changed(peer_id: int)  ## local player picked / cleared a teammate (#39)
signal hostile_target_changed(enemy_name: String)  ## local player locked / cleared an enemy (#41)

# Feedback
signal damage_number(pos: Vector2, amount: int, kind: String)
signal hud_message(text: String, color: Color)
signal screen_shake(strength: float, duration: float)

# Settings
signal bindings_changed
signal game_settings_changed
signal input_device_changed(is_gamepad: bool)

# UI overlays (inventory, talents, map, pause) block gameplay input while open.
signal ui_overlay_changed(open: bool)

## The interface language changed (#32): screens rebuild their texts.
signal locale_changed
