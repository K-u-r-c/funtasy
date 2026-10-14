extends Node
## Music with crossfades and pooled one-shot sound effects. Tracks and sounds are referenced
## by keys from data/assets.json ("music.*", "sfx.*"), so swapping in Suno tracks only means
## dropping the files in assets/audio/ and editing that registry.

const SFX_VOICES := 16
const SFX_2D_VOICES := 24

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _current_key := ""
var _fade: Tween
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_2d: Array[AudioStreamPlayer2D] = []
var _cache: Dictionary = {}
## Headless test runs use the dummy audio driver; streams still playing there are reported as
## leaked at exit, which would drown real errors in the test logs. So nothing plays headless.
var _headless := DisplayServer.get_name() == "headless"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_active = _music_a
	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx.append(p)
	for i in SFX_2D_VOICES:
		var p2 := AudioStreamPlayer2D.new()
		p2.bus = "SFX"
		p2.max_distance = 900.0
		add_child(p2)
		_sfx_2d.append(p2)


## Crossfades to the track registered under music.<key>. Same key = no restart.
func play_music(key: String, fade_time: float = -1.0) -> void:
	if key == _current_key:
		return
	if _headless:
		_current_key = key
		return
	if fade_time < 0.0:
		fade_time = float(GameData.bal("audio.music_crossfade", 1.5))
	_current_key = key
	var stream := _stream("music." + key)
	var incoming := _music_b if _active == _music_a else _music_a
	var outgoing := _active
	_active = incoming
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	if stream:
		incoming.stream = stream
		incoming.volume_db = -60.0
		incoming.play()
		_fade.tween_property(incoming, "volume_db", 0.0, fade_time)
	_fade.tween_property(outgoing, "volume_db", -60.0, fade_time)
	_fade.chain().tween_callback(outgoing.stop)


func stop_music(fade_time: float = 1.0) -> void:
	_current_key = ""
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_active, "volume_db", -60.0, fade_time)
	_fade.tween_callback(_active.stop)


func play_sfx(key: String, pitch_jitter: float = 0.05) -> void:
	if _headless:
		return
	var stream := _stream("sfx." + key)
	if stream == null:
		return
	for p in _sfx:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.play()
			return


func play_sfx_at(key: String, pos: Vector2, pitch_jitter: float = 0.08) -> void:
	if _headless:
		return
	var stream := _stream("sfx." + key)
	if stream == null:
		return
	for p in _sfx_2d:
		if not p.playing:
			p.stream = stream
			p.global_position = pos
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.play()
			return


func _stream(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]
	var path := GameData.asset_path(key)
	var s: AudioStream = null
	if not path.is_empty() and ResourceLoader.exists(path):
		s = load(path)
		if key.begins_with("music."):
			_force_loop(s)
	else:
		push_warning("AudioManager: no stream for '%s'" % key)
	_cache[key] = s
	return s


## Music always loops regardless of how the file was imported.
func _force_loop(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		if w.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			var bytes_per_frame := (2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if w.stereo else 1)
			w.loop_end = w.data.size() / bytes_per_frame
	elif "loop" in s:
		s.set("loop", true)


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -60.0
	add_child(p)
	return p


func _exit_tree() -> void:
	# Stop everything so no playback outlives the AudioServer at shutdown.
	for p in [_music_a, _music_b]:
		p.stop()
		p.stream = null
	for p in _sfx:
		p.stop()
		p.stream = null
	for p in _sfx_2d:
		p.stop()
		p.stream = null
	_cache.clear()
