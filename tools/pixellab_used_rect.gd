extends SceneTree
## Prints the used (non-transparent) rect of PNG files: used by tools/pixellab_build_char.py.
func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var im := Image.load_from_file(a)
		print(a.get_file(), " ", im.get_size(), " used ", im.get_used_rect())
	quit()
