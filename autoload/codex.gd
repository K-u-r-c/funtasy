extends Node
## The permanent library codex (D18): which lore books this profile has read. It lives in
## <profile>/codex.json, outside saved games, so it survives wipes and new games. Every peer
## keeps its own; reading a book marks it here (the reader opens on the reader's machine only).

signal changed

var read: Dictionary = {}  ## lore id -> true


func _ready() -> void:
	var path := _path()
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			for id in d.get("read", []):
				read[str(id)] = true


func _path() -> String:
	return SaveSystem.base_dir + "codex.json"


func is_read(id: String) -> bool:
	return read.has(id)


func mark_read(id: String) -> void:
	if read.has(id) or not GameData.lore_books.has(id):
		return
	read[id] = true
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"read": read.keys()}, "\t"))
	changed.emit()


func count() -> int:
	return read.size()
