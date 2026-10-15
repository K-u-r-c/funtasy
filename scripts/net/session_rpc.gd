class_name SessionRpc
extends Node
## Per-session RPC relay for the autoloads (GameState, NetworkManager, DevAuto).
##
## Why: Godot 4.7.x release builds print "Attempt to disconnect a nonexistent connection ...
## 'tree_exited'" for every node that took part in RPCs when the multiplayer peer is reset
## (godotengine/godot#123751). Autoloads can't be freed, so their RPCs go through this node,
## which NetworkManager frees right before resetting the peer.
##
## Only whitelisted methods can be reached, so a client can't call arbitrary autoload code.

const FROM_HOST := {
	"GameState": ["_sync_game", "_sync_roster", "_sync_settings"],
	"NetworkManager": ["_begin_run", "_return_to_lobby", "_end_session"],
	"DevAuto": ["client_cmd"],
}
const FROM_CLIENTS := {
	"GameState": ["_submit_choice"],
	"NetworkManager": ["_report_loaded"],
}


## Host -> one peer or all (reliable, call_local).
@rpc("authority", "call_local", "reliable")
func host_call(target: String, method: String, args: Array) -> void:
	if not Array(FROM_HOST.get(target, [])).has(method):
		return
	get_node("/root/" + target).callv(method, args)


## Client -> host (reliable). The target can still read multiplayer.get_remote_sender_id().
@rpc("any_peer", "call_local", "reliable")
func client_call(target: String, method: String, args: Array) -> void:
	if not multiplayer.is_server() or not Array(FROM_CLIENTS.get(target, [])).has(method):
		return
	get_node("/root/" + target).callv(method, args)
