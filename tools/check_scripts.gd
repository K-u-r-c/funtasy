extends SceneTree
## Loads every GDScript in the project so parse/type errors show up in one headless run:
##   godot --headless --path . -s tools/check_scripts.gd


var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_check()
	return false


func _check() -> void:
	var files: Array = []
	_collect("res://", files)
	var bad := 0
	for f in files:
		var s: Script = load(f)
		if s == null or not s.can_instantiate():
			bad += 1
			print("BROKEN: ", f)
	print("checked %d scripts, %d broken" % [files.size(), bad])
	quit(1 if bad > 0 else 0)


func _collect(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		_collect(dir_path.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
