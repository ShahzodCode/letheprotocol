class_name Sfx
## Synthesised sounds (no audio files): built once, cached, played through throw-away AudioStreamPlayers.

const RATE := 22050
static var _cache := {}


static func _make(duration: float, fn: Callable) -> AudioStreamWAV:
	var n := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(fn.call(t), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


static func get_sound(id: String) -> AudioStreamWAV:
	if _cache.has(id):
		return _cache[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var s: AudioStreamWAV
	match id:
		"pistol":
			var lp := 0.0
			s = _make(0.45, func(t: float) -> float:
				lp += (rng.randf_range(-1, 1) - lp) * 0.55
				var crack := lp * exp(-t * 38.0)
				var body := sin(TAU * (190.0 - 420.0 * t) * t) * exp(-t * 20.0)
				var tail := lp * 0.15 * exp(-t * 7.0)
				return (crack * 0.9 + body * 0.7 + tail) * 0.9)
		"rifle":
			var lp2 := 0.0
			s = _make(0.5, func(t: float) -> float:
				lp2 += (rng.randf_range(-1, 1) - lp2) * 0.35
				var crack := lp2 * exp(-t * 30.0)
				var body := sin(TAU * (130.0 - 260.0 * t) * t) * exp(-t * 14.0)
				var tail := lp2 * 0.25 * exp(-t * 6.0)
				return (crack * 1.0 + body * 0.8 + tail) * 0.95)
		"click":
			s = _make(0.06, func(t: float) -> float:
				return sin(TAU * 1800.0 * t) * exp(-t * 90.0) * 0.5)
		"mag_out":
			s = _make(0.14, func(t: float) -> float:
				return (rng.randf_range(-1, 1) * 0.6 + sin(TAU * 420.0 * t) * 0.5) * exp(-t * 40.0) * 0.6)
		"mag_in":
			s = _make(0.18, func(t: float) -> float:
				return (rng.randf_range(-1, 1) * 0.4 + sin(TAU * 260.0 * t) * 0.7) * exp(-t * 28.0) * 0.7)
		"bolt":
			s = _make(0.16, func(t: float) -> float:
				var k := 1.0 if t < 0.07 else 0.8
				var tt := fmod(t, 0.07)
				return (rng.randf_range(-1, 1) * 0.5 + sin(TAU * 900.0 * tt) * 0.5) * exp(-tt * 70.0) * 0.6 * k)
		"hit":
			s = _make(0.07, func(t: float) -> float:
				return sin(TAU * 1500.0 * t) * exp(-t * 55.0) * 0.45)
		"headshot":
			s = _make(0.14, func(t: float) -> float:
				return (sin(TAU * 2200.0 * t) + sin(TAU * 1650.0 * t)) * 0.3 * exp(-t * 30.0))
		"thump":   # bullet into a body
			s = _make(0.12, func(t: float) -> float:
				return (sin(TAU * 110.0 * t) * 0.8 + rng.randf_range(-1, 1) * 0.2) * exp(-t * 35.0))
		"impact":  # bullet into ground / rock
			var lp3 := 0.0
			s = _make(0.1, func(t: float) -> float:
				lp3 += (rng.randf_range(-1, 1) - lp3) * 0.4
				return lp3 * exp(-t * 45.0) * 0.6)
		"hurt":
			s = _make(0.3, func(t: float) -> float:
				return (sin(TAU * (90.0 - 40.0 * t) * t) * 0.9 + rng.randf_range(-1, 1) * 0.2) * exp(-t * 11.0))
		"step":
			var lp4 := 0.0
			s = _make(0.1, func(t: float) -> float:
				lp4 += (rng.randf_range(-1, 1) - lp4) * 0.15
				return lp4 * exp(-t * 40.0) * 0.8)
		"land":
			var lp5 := 0.0
			s = _make(0.2, func(t: float) -> float:
				lp5 += (rng.randf_range(-1, 1) - lp5) * 0.1
				return (lp5 * 0.8 + sin(TAU * 70.0 * t) * 0.6) * exp(-t * 18.0))
		"swing":
			var lp6 := 0.0
			s = _make(0.22, func(t: float) -> float:
				lp6 += (rng.randf_range(-1, 1) - lp6) * 0.2
				return lp6 * sin(PI * t / 0.22) * 0.5)
		"death":
			s = _make(0.5, func(t: float) -> float:
				return (sin(TAU * (130.0 - 160.0 * t) * t) * 0.8 + rng.randf_range(-1, 1) * 0.15) * exp(-t * 6.0))
		_:
			s = _make(0.05, func(t: float) -> float: return 0.0)
	_cache[id] = s
	return s


## Fire-and-forget 2D sound.
static func play(parent: Node, id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = get_sound(id)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Fire-and-forget positional sound (quieter and duller with distance via the engine's attenuation).
static func play_at(parent: Node, pos: Vector3, id: String, volume_db: float = 0.0, pitch: float = 1.0, max_dist: float = 80.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_sound(id)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 8.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
