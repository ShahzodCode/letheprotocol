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
		"pulse":   # enemy energy carbine: bright zap with a falling tone
			var lp7 := 0.0
			s = _make(0.22, func(t: float) -> float:
				lp7 += (rng.randf_range(-1, 1) - lp7) * 0.6
				var zap := sin(TAU * (1500.0 - 4500.0 * t) * t) * exp(-t * 22.0)
				return (zap * 0.7 + lp7 * exp(-t * 60.0) * 0.5) * 0.8)
		"whip":    # the invaders' pulse rifle: no bang, a sharp piercing whip-crack with a thin falling zip and almost no tail
			var lpw := 0.0
			s = _make(0.32, func(t: float) -> float:
				var n := rng.randf_range(-1, 1)
				lpw += (n - lpw) * 0.7
				var crack := (n - lpw * 0.4) * exp(-t * 130.0)
				var zip := sin(TAU * (5200.0 - 9000.0 * t) * t) * exp(-t * 48.0)
				var snap := sin(TAU * 310.0 * t) * exp(-t * 55.0) * 0.35
				return (crack * 0.8 + zip * 0.55 + snap) * 0.85)
		"hum":     # the pulse rifle's charge hum, a looping 1 s of whole-cycle tones so the loop is seamless (played quietly while it is in hand)
			s = _make(1.0, func(t: float) -> float:
				var wob := 0.75 + 0.25 * sin(TAU * 3.0 * t)
				return (sin(TAU * 110.0 * t) * 0.5 + sin(TAU * 220.0 * t) * 0.3 + sin(TAU * 331.0 * t) * 0.12 + sin(TAU * 441.0 * t) * 0.06) * wob * 0.5)
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(1.0 * RATE)
		"far_gun":    # the war far away: eight muffled shots in two or three ragged bursts (2.2 s, played from a random direction)
			var shots: Array = []
			var bt := 0.05
			for i in 8:
				shots.append(bt)
				bt += rng.randf_range(0.07, 0.13) if i % 3 != 2 else rng.randf_range(0.35, 0.55)
			var lpf := 0.0
			s = _make(2.2, func(t: float) -> float:
				var n := rng.randf_range(-1, 1)
				lpf += (n - lpf) * 0.11
				var out := 0.0
				for st in shots:
					var dt: float = t - float(st)
					if dt >= 0.0 and dt < 0.5:
						out += lpf * exp(-dt * 26.0) * 1.3 + sin(TAU * 78.0 * dt) * exp(-dt * 20.0) * 0.5
				return out * 0.5)
		"far_boom":   # a heavy explosion far off: a slow deep thump and a long rumble, no crack (3 s)
			var lpb := 0.0
			s = _make(3.0, func(t: float) -> float:
				lpb += (rng.randf_range(-1, 1) - lpb) * 0.035
				var thump := sin(TAU * (52.0 - 20.0 * minf(t, 1.2)) * t) * exp(-t * 2.4) * 1.0
				var rumble := lpb * exp(-t * 1.1) * 3.2
				return (thump + rumble) * minf(t / 0.04, 1.0) * 0.6)
		"snipe":   # marksman: heavy crack with a long tail
			var lp8 := 0.0
			s = _make(0.8, func(t: float) -> float:
				lp8 += (rng.randf_range(-1, 1) - lp8) * 0.25
				var crack := lp8 * exp(-t * 20.0)
				var boom := sin(TAU * (90.0 - 70.0 * t) * t) * exp(-t * 7.0)
				var ring := sin(TAU * (700.0 - 500.0 * t) * t) * exp(-t * 9.0) * 0.3
				return (crack + boom * 0.9 + ring) * 0.9)
		"longshot":   # the LR-9: a flat hard crack, a deep boom and a long rolling tail that carries across the park (1.7 s)
			var lp9 := 0.0
			var lp9b := 0.0
			s = _make(1.7, func(t: float) -> float:
				lp9 += (rng.randf_range(-1, 1) - lp9) * 0.45
				lp9b += (rng.randf_range(-1, 1) - lp9b) * 0.04
				var crack := lp9 * exp(-t * 55.0) * 1.3
				var boom := sin(TAU * (70.0 - 40.0 * minf(t, 0.5)) * t) * exp(-t * 6.5) * 1.1
				var roll := lp9b * exp(-t * 2.2) * 2.4 * minf(t / 0.05, 1.0)
				var ring := sin(TAU * (900.0 - 600.0 * minf(t, 0.4)) * t) * exp(-t * 14.0) * 0.18
				return clampf((crack + boom + roll + ring) * 0.8, -1.0, 1.0))
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
		"climb":   # a hand / boot on a ladder rung: a short metallic knock with a faint ring
			var lpc := 0.0
			s = _make(0.14, func(t: float) -> float:
				lpc += (rng.randf_range(-1, 1) - lpc) * 0.3
				var knock := sin(TAU * 240.0 * t) * exp(-t * 38.0) * 0.7
				var ring := (sin(TAU * 1180.0 * t) + sin(TAU * 1730.0 * t) * 0.6) * exp(-t * 24.0) * 0.22
				return (lpc * exp(-t * 90.0) * 0.5 + knock + ring) * 0.8)
		"pain":    # a hard landing: a grunt (falling voiced tone with a breath of noise), longer for harder falls
			var lpp := 0.0
			s = _make(0.42, func(t: float) -> float:
				lpp += (rng.randf_range(-1, 1) - lpp) * 0.12
				var f0 := 150.0 - 70.0 * t
				var voice := sin(TAU * f0 * t) * 0.6 + sin(TAU * f0 * 2.0 * t) * 0.3 + sin(TAU * f0 * 3.2 * t) * 0.15
				return (voice * sin(PI * minf(t / 0.42, 1.0)) * exp(-t * 4.0) + lpp * exp(-t * 14.0) * 0.5) * 0.9)
		"swing":
			var lp6 := 0.0
			s = _make(0.22, func(t: float) -> float:
				lp6 += (rng.randf_range(-1, 1) - lp6) * 0.2
				return lp6 * sin(PI * t / 0.22) * 0.5)
		"stab":    # silent takedown: a short wet thrust, a dull knock and a faint steel scrape (never a gunshot)
			var lp9 := 0.0
			s = _make(0.18, func(t: float) -> float:
				lp9 += (rng.randf_range(-1, 1) - lp9) * 0.25
				var thrust := lp9 * sin(PI * minf(t / 0.09, 1.0)) * exp(-t * 14.0)
				var knock := sin(TAU * 95.0 * t) * exp(-t * 30.0) * 0.8
				var scrape := sin(TAU * (2400.0 - 5000.0 * t) * t) * exp(-t * 26.0) * 0.12
				return (thrust * 0.6 + knock + scrape) * 0.7)
		"breath":  # a soldier breathing hard through a helmet: filtered noise, slow in / out, slightly metallic (loops, 1.8 s)
			var b1 := 0.0
			var b2 := 0.0
			s = _make(1.8, func(t: float) -> float:
				var n := rng.randf_range(-1, 1)
				b1 += (n - b1) * 0.2
				b2 += (b1 - b2) * 0.03
				var band := (b1 - b2) * 2.2
				var env := 0.0
				if t < 0.8:
					env = pow(sin(PI * t / 0.8), 1.6) * 0.55          # breathe in
				elif t > 0.95 and t < 1.75:
					env = pow(sin(PI * (t - 0.95) / 0.8), 1.4) * 0.8   # breathe out
				var ring := sin(TAU * 1150.0 * t) * 0.1 + sin(TAU * 1730.0 * t) * 0.05
				return (band + ring * band) * env)
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(1.8 * RATE)
		"explosion":   # deep boom, hard crack at the start, crackling tail
			var lpx := 0.0
			var lpc := 0.0
			s = _make(2.2, func(t: float) -> float:
				var n := rng.randf_range(-1, 1)
				lpx += (n - lpx) * 0.5
				lpc += (n - lpc) * 0.12
				var crack := lpx * exp(-t * 28.0) * 1.0
				var boom := sin(TAU * (70.0 - 38.0 * minf(t, 1.0)) * t) * exp(-t * 2.6) * 1.1
				var rumble := lpc * exp(-t * 2.0) * 0.9
				var pops := (n if absf(n) > 0.985 else 0.0) * exp(-t * 1.8) * 1.4 * (0.4 + 0.6 * sin(t * 40.0) * sin(t * 40.0))
				return (crack + boom + rumble + pops) * 0.85)
		"radio":   # short radio crackle with a squelch click at the start and end
			var lpr := 0.0
			s = _make(0.38, func(t: float) -> float:
				var n := rng.randf_range(-1, 1)
				lpr += (n - lpr) * 0.6
				var body := lpr * 0.5 * (1.0 if t < 0.3 else 0.0) * (0.6 + 0.4 * sin(t * 220.0))
				var blip := sin(TAU * 1700.0 * t) * exp(-t * 60.0) * 0.5 + sin(TAU * 1300.0 * maxf(0.0, t - 0.3)) * exp(-maxf(0.0, t - 0.3) * 80.0) * (1.0 if t > 0.3 else 0.0) * 0.5
				return body + blip)
		"clink":   # grenade against the ground
			s = _make(0.14, func(t: float) -> float:
				return (sin(TAU * 1900.0 * t) * 0.4 + sin(TAU * 3100.0 * t) * 0.25 + rng.randf_range(-1, 1) * 0.2) * exp(-t * 45.0))
		"crowd":   # panicking crowd far and near: layered, band-filtered noise bursts (loops, 6 s) - deliberately no voices
			var bumps: Array = []
			for i in 22:
				bumps.append([rng.randf() * 6.0, rng.randf_range(0.18, 0.5), rng.randf_range(0.08, 0.4), rng.randf_range(0.25, 0.85)])   # centre, width, filter coefficient, level
			var f1 := [0.0, 0.0, 0.0]
			var f2 := [0.0, 0.0, 0.0]
			s = _make(6.0, func(t: float) -> float:
				var n := rng.randf_range(-1, 1)
				var out := 0.0
				for li in 3:
					var co := 0.06 + 0.1 * li
					f1[li] += (n - f1[li]) * co
					f2[li] += (f1[li] - f2[li]) * co * 0.4
					var band: float = (f1[li] - f2[li]) * (2.2 + li)
					var env := 0.0
					for b in bumps:
						var dt := t - float(b[0])
						if absf(dt) < 3.0 * float(b[1]):
							env += float(b[3]) * exp(-dt * dt / (2.0 * float(b[1]) * float(b[1]))) * (1.0 if (int(float(b[2]) * 100.0) % 3) == li else 0.25)
					out += band * minf(env, 1.0)
				return out * 0.55)
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(6.0 * RATE)
		"chime":   # objective complete: two rising bell notes
			s = _make(0.7, func(t: float) -> float:
				var a := sin(TAU * 880.0 * t) * exp(-t * 7.0)
				var t2 := maxf(0.0, t - 0.14)
				var b := sin(TAU * 1318.5 * t2) * exp(-t2 * 6.0) * (1.0 if t >= 0.14 else 0.0)
				return (a * 0.45 + b * 0.5 + sin(TAU * 2637.0 * t2) * exp(-t2 * 14.0) * 0.1))
		"death":
			s = _make(0.5, func(t: float) -> float:
				return (sin(TAU * (130.0 - 160.0 * t) * t) * 0.8 + rng.randf_range(-1, 1) * 0.15) * exp(-t * 6.0))
		"alarm":   # the lander's siren: a square-ish tone swinging between 500 and 900 Hz, 1.6 s, loops (whole cycles)
			s = _make(1.6, func(t: float) -> float:
				var w := TAU / 1.6
				var ph := TAU * (700.0 * t + 200.0 * (1.0 - cos(w * t)) / w)
				return (signf(sin(ph)) * 0.22 + sin(ph) * 0.3 + sin(ph * 2.0) * 0.08) * 0.8)
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(1.6 * RATE)
		"slam":    # a bulkhead door shutting: a hard metal knock and a low thud
			var lps := 0.0
			s = _make(0.7, func(t: float) -> float:
				lps += (rng.randf_range(-1, 1) - lps) * 0.3
				var knock := lps * exp(-t * 26.0)
				var thud := sin(TAU * (95.0 - 40.0 * minf(t, 0.4)) * t) * exp(-t * 9.0)
				var ring := (sin(TAU * 410.0 * t) + sin(TAU * 655.0 * t) * 0.6) * exp(-t * 14.0) * 0.25
				return (knock * 0.9 + thud * 0.9 + ring) * 0.85)
		"laugh":   # a deep slow laugh: four voiced "ha" pulses (a falling 80-95 Hz buzz shaped by two vowel formants), 1.7 s
			var pulses := [0.0, 0.38, 0.74, 1.08]
			s = _make(1.7, func(t: float) -> float:
				var out := 0.0
				for pi in 4:
					var dt: float = t - float(pulses[pi])
					if dt < 0.0 or dt > 0.3:
						continue
					var f0 := (96.0 - 14.0 * float(pi)) * (1.0 - 0.18 * dt)
					var env := sin(PI * clampf(dt / 0.3, 0.0, 1.0))
					env = env * env
					for k in range(1, 15):
						var fk := f0 * float(k)
						var wgt := exp(-pow((fk - 650.0) / 260.0, 2.0)) + 0.6 * exp(-pow((fk - 1150.0) / 320.0, 2.0)) + 0.35 / float(k)
						out += sin(TAU * fk * dt) * wgt * env
				return out * 0.16)
		"knock":   # knuckles on a wooden door below the floor: three dull, muffled knocks (1.1 s)
			var lpk := 0.0
			s = _make(1.1, func(t: float) -> float:
				lpk += (rng.randf_range(-1, 1) - lpk) * 0.12
				var out := 0.0
				for k in 3:
					var dt := t - 0.3 * float(k)
					if dt >= 0.0:
						out += (sin(TAU * 140.0 * dt) * 0.8 + lpk * 2.0) * exp(-dt * 40.0)
				return out * 0.8)
		"crash":   # the front door kicked in: a splintering crack, a heavy thud and the frame rattling (1.2 s)
			var lpc := 0.0
			s = _make(1.2, func(t: float) -> float:
				var n := rng.randf_range(-1, 1)
				lpc += (n - lpc) * 0.45
				var crack := n * exp(-t * 30.0) * 0.8
				var splinter := lpc * exp(-t * 6.0) * (0.5 + 0.5 * sin(TAU * 23.0 * t)) * 0.5
				var thud := sin(TAU * (80.0 - 30.0 * minf(t, 0.5)) * t) * exp(-t * 7.0)
				var rattle := lpc * maxf(0.0, sin(TAU * 11.0 * t)) * exp(-maxf(t - 0.3, 0.0) * 5.0) * (1.0 if t > 0.3 else 0.0) * 0.4
				return (crack + splinter + thud + rattle) * 0.9)
		"boots":   # heavy boots crossing the floor overhead: six low, muffled thuds (2.4 s)
			var lpb := 0.0
			s = _make(2.4, func(t: float) -> float:
				lpb += (rng.randf_range(-1, 1) - lpb) * 0.08
				var out := 0.0
				for k in 6:
					var dt := t - (0.12 + 0.38 * float(k) + 0.05 * float(k % 2))
					if dt >= 0.0:
						out += (sin(TAU * 62.0 * dt) + lpb * 1.5) * exp(-dt * 22.0)
				return out * 0.7)
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
static func play_at(parent: Node, pos: Vector3, id: String, volume_db: float = 0.0, pitch: float = 1.0, max_dist: float = 80.0, unit_size: float = 8.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_sound(id)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = unit_size
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
