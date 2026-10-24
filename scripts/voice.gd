class_name Voice
extends Node
## The few voiced lines: clips generated once with Cartesia (Sonic 3.5) and saved in audio/voices (no API and nothing at run time but loading a WAV;
## tools/make_voices.ps1 + tools/voice_lines.json are the older Windows-voice version of the same lines). The invaders shout in Russian with three
## native Russian male voices (Sergei, Alexei, Dmitri; subtitles stay English), the ship intercom is a Russian woman (Natalia), the Commander is a
## deep English voice (Ronald) at speed 0.85, the city guard an English one (Parker), the home scenes Noah (Henry), his mother (Rory) and Mira (Daisy); the Commander's kill count has clips for 1 to 30 (more: "so many"). A clip is found by hashing the subtitle that Game.radio_line shows
## (sha1, first 12 hex), so no line has to be registered in the code that says it. Lines without a clip are subtitles only.

const DIR := "res://audio/voices/"
## style -> [playback pitch min, max, volume dB]. Each soldier gets his own pitch inside the range (a deep one, a thin one).
const STYLES := {
	"soldier": [0.95, 1.05, -2.0],          # each line already has one of three Russian voices (Cartesia); the playback pitch only varies a little
	"intercom": [1.0, 1.0, -3.0],
	"commander": [1.0, 1.0, 2.0],          # slowed and deepened already at generation (Cartesia, speed 0.85)
	"guard": [1.0, 1.0, -3.0],
	"noah": [1.0, 1.0, 0.0],               # Noah (Henry), his mother (Rory) and Mira (Daisy): the home scenes (HomeScene)
	"mum": [1.0, 1.0, 0.0],
	"mira": [1.0, 1.0, -1.0],
}

var _index: Dictionary = {}
var _player: AudioStreamPlayer
var _queue: Array = []              # streams still to play after the current one
var _rng := RandomNumberGenerator.new()
var _cache: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	var f := FileAccess.open(DIR + "index.json", FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			_index = parsed
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_next)
	Game.radio_line.connect(_on_line)


func _clip(id: String) -> AudioStream:
	if not _cache.has(id):
		var path := DIR + id + ".wav"
		_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _cache[id]


func _on_line(text: String) -> void:
	var id := text.sha1_text().substr(0, 12)
	if not _index.has(id):
		return
	var style := String(_index[id])
	var s := _clip(id)
	if s != null:
		_say([s], style)


## The Commander's first line: the number of the dead, then the rest (clips num_N / cmd_rest, or cmd_many when the count is zero or too big).
func say_count(n: int) -> void:
	var mx := int(_index.get("_count_max", 0))
	var seq: Array = []
	if n >= 1 and n <= mx and _clip("num_%d" % n) != null:
		seq = [_clip("num_%d" % n), _clip("cmd_rest")]
	else:
		seq = [_clip("cmd_many")]
	seq = seq.filter(func(x): return x != null)
	if not seq.is_empty():
		_say(seq, "commander")


func _say(seq: Array, style: String) -> void:
	var st: Array = STYLES.get(style, [1.0, 1.0, 0.0])
	_player.stop()
	_queue = seq.duplicate()
	_player.pitch_scale = _rng.randf_range(float(st[0]), float(st[1]))
	_player.volume_db = float(st[2])
	_next()


func _next() -> void:
	if _queue.is_empty():
		return
	_player.stream = _queue.pop_front()
	_player.play()


## Stop whatever is being said (a checkpoint restore, the end of the scene).
func hush() -> void:
	_queue.clear()
	_player.stop()


## Seconds the clip of a subtitle takes to play (0 when it has none): the Commander's scene waits for his voice.
func duration(text: String) -> float:
	var id := text.sha1_text().substr(0, 12)
	if not _index.has(id):
		return 0.0
	var s := _clip(id)
	var st: Array = STYLES.get(String(_index[id]), [1.0, 1.0, 0.0])
	return 0.0 if s == null else s.get_length() / float(st[0])


func count_duration(n: int) -> float:
	var mx := int(_index.get("_count_max", 0))
	var parts: Array = ["num_%d" % n, "cmd_rest"] if n >= 1 and n <= mx else ["cmd_many"]
	var total := 0.0
	for p in parts:
		var s := _clip(p)
		if s != null:
			total += s.get_length()
	return total / float((STYLES["commander"] as Array)[0])
