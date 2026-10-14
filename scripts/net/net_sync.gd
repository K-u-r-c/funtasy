class_name NetSync
extends RefCounted
## Builds MultiplayerSynchronizers in code. Must be called before the owning node enters the
## tree (e.g. from _init or a spawn function) so the spawn state is included.


## `on_change`: synced reliably when the value changes. `always`: streamed unreliably.
static func make(root: Node, sync_name: String, on_change: Array, always: Array, interval: float = 0.05) -> MultiplayerSynchronizer:
	var cfg := SceneReplicationConfig.new()
	for p in on_change:
		var path := NodePath(p)
		cfg.add_property(path)
		cfg.property_set_spawn(path, true)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	for p in always:
		var path2 := NodePath(p)
		cfg.add_property(path2)
		cfg.property_set_spawn(path2, true)
		cfg.property_set_replication_mode(path2, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var s := MultiplayerSynchronizer.new()
	s.name = sync_name
	s.replication_config = cfg
	s.root_path = NodePath("..")
	s.replication_interval = interval
	s.delta_interval = 0.0
	root.add_child(s)
	return s
