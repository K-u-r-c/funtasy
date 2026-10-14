extends SceneTree
## Prints the absolute user:// directory (used by tools/run_tests.sh to clean test profiles).


func _init() -> void:
	print("USERDIR=" + ProjectSettings.globalize_path("user://"))
	quit()
