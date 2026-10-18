class_name CityRoads
## Road paint and road damage as flat decals (Scn.decals): edge lines, centre lines (double solid on the wide avenues, dashed
## on streets), lane dashes, stop lines and zebra crossings at every junction of the through streets, manhole covers and drains,
## and the damage of the fighting: cracks, potholes, scorch marks, skid marks, scattered glass and debris, denser near the sites.

const MIN_WIDTH := 10.0           # through streets narrower than this (the 8 m footpaths) get no paint
const YELLOW := Color(0.92, 0.74, 0.2)
const WHITE := Color(0.76, 0.76, 0.72)


## World position of a point `u` across and `t` along the line `line` (a street along z when along_z).
static func _pt(line: float, u: float, t: float, along_z: bool) -> Vector2:
	return Vector2(line + u, t) if along_z else Vector2(t, line + u)


## A flat paint rectangle: u0..u1 across the street, t0..t1 along it.
static func _paint(line: float, u0: float, u1: float, t0: float, t1: float, along_z: bool, color: Color, kind: String = "paint") -> void:
	if t1 - t0 < 0.05:
		return
	var c := _pt(line, (u0 + u1) * 0.5, (t0 + t1) * 0.5, along_z)
	var size := Vector2(u1 - u0, t1 - t0) if along_z else Vector2(t1 - t0, u1 - u0)
	Scn.decal(kind, c, size, 0.0, color)


static func build(rng: RandomNumberGenerator) -> void:
	for along_z in [true, false]:
		var lines: Array = City.AVENUE_X if along_z else City.AVENUE_Z
		var cross: Array = City.AVENUE_Z if along_z else City.AVENUE_X
		var lim := City.IN_Z if along_z else City.IN_X
		for line in lines:
			var w := City.avenue_width(line)
			if w < MIN_WIDTH:
				continue
			# the stretches between the crossing streets; `junction` says whether that end of the stretch is a junction
			var segs: Array = []
			var prev := -lim + 6.0
			var prev_j := false
			for cl in cross:
				var cw := City.avenue_width(cl)
				segs.append([prev, cl - cw * 0.5, prev_j, true])
				prev = cl + cw * 0.5
				prev_j = true
			segs.append([prev, lim - 6.0, prev_j, false])
			for s in segs:
				_stretch(line, w, float(s[0]), float(s[1]), bool(s[2]), bool(s[3]), along_z, rng)
			_manholes(line, w, cross, lim, along_z, rng)
	_war_marks(rng)


static func _stretch(line: float, w: float, a: float, b: float, a_j: bool, b_j: bool, along_z: bool, rng: RandomNumberGenerator) -> void:
	if b - a < 8.0:
		return
	var edge := w * 0.5 - 1.9
	# edge lines, both sides, the whole stretch
	for sd in [-1.0, 1.0]:
		_paint(line, sd * edge - 0.075, sd * edge + 0.075, a, b, along_z, WHITE)
	# centre markings stay clear of the crossings
	var ca := a + (6.0 if a_j else 0.0)
	var cb := b - (6.0 if b_j else 0.0)
	if w >= 18.0:
		for sd in [-1.0, 1.0]:
			_paint(line, sd * 0.2 - 0.06, sd * 0.2 + 0.06, ca, cb, along_z, YELLOW)
		for sd in [-1.0, 1.0]:
			var t := ca + 1.5
			while t + 3.0 < cb:
				_paint(line, sd * w * 0.25 - 0.06, sd * w * 0.25 + 0.06, t, t + 3.0, along_z, WHITE)
				t += 9.0
	else:
		var t2 := ca + 1.5
		while t2 + 3.0 < cb:
			_paint(line, -0.075, 0.075, t2, t2 + 3.0, along_z, YELLOW)
			t2 += 8.0
	# stop line and zebra crossing at each junction end
	for end in [0, 1]:
		var is_j: bool = a_j if end == 0 else b_j
		if not is_j:
			continue
		var sgn := 1.0 if end == 0 else -1.0
		var base := a if end == 0 else b          # the junction edge
		var t_stop0: float = base + sgn * 5.0
		_paint(line, -edge, edge, minf(t_stop0, t_stop0 + sgn * 0.5), maxf(t_stop0, t_stop0 + sgn * 0.5), along_z, WHITE)
		var z0: float = base + sgn * 1.4
		var z1: float = base + sgn * 4.4
		var u := -edge + 0.5
		while u + 0.55 < edge:
			_paint(line, u, u + 0.55, minf(z0, z1), maxf(z0, z1), along_z, WHITE)
			u += 1.15


static func _manholes(line: float, w: float, cross: Array, lim: float, along_z: bool, rng: RandomNumberGenerator) -> void:
	var t := -lim + 20.0 + rng.randf() * 20.0
	while t < lim - 14.0:
		var ok := true
		for cl in cross:
			if absf(t - cl) < City.avenue_width(cl) * 0.5 + 6.0:
				ok = false
		if ok:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var c := _pt(line, side * w * 0.25, t, along_z)
			Scn.decal("disc", c, Vector2(0.9, 0.9), 0.0, Color(0.15, 0.15, 0.16))
			Scn.decal("disc", c, Vector2(0.62, 0.62), 0.0, Color(0.1, 0.1, 0.11), 0.056)
			# a storm drain at the kerb
			var dc := _pt(line, side * (w * 0.5 - 1.7), t + 9.0, along_z)
			var dsz := Vector2(0.35, 0.8) if along_z else Vector2(0.8, 0.35)
			Scn.decal("dark", dc, dsz, 0.0, Color(0.03, 0.03, 0.035))
		t += rng.randf_range(32.0, 46.0)


## Cracks, potholes, scorch, skids, glass and debris on the through streets and the bigger side streets; far more near the sites.
static func _war_marks(rng: RandomNumberGenerator) -> void:
	for st in City.streets:
		var cls: String = st["cls"]
		var r: Rect2 = st["rect"]
		if r.size.x < 2.5 or r.size.y < 2.5:
			continue
		var density := 1.0 / 420.0
		if cls == "alley" or cls == "walk":
			density = 1.0 / 1500.0
		var n := r.get_area() * density
		var near_site := 0.0
		for s in City.sites:
			var sc: Vector3 = s["center"]
			var d := r.get_center().distance_to(Vector2(sc.x, sc.z))
			near_site = maxf(near_site, 1.0 - d / 110.0)
		n *= 1.0 + maxf(near_site, 0.0) * 2.5
		var count := int(n) + (1 if rng.randf() < n - floorf(n) else 0)
		for i in count:
			var p := Vector2(rng.randf_range(r.position.x + 0.5, r.end.x - 0.5), rng.randf_range(r.position.y + 0.5, r.end.y - 0.5))
			# the very first screen of the game (the lobby door) and the central junction stay tidy
			if p.distance_to(Vector2(City.INSTITUTE_EXIT.x, City.INSTITUTE_EXIT.z)) < 6.0:
				continue
			# nothing right in the middle of the central avenues (flat, clean sight lines for the tests)
			_cluster(p, rng, near_site)


static func _cluster(p: Vector2, rng: RandomNumberGenerator, near: float) -> void:
	var roll := rng.randf()
	var yaw := rng.randf() * TAU
	if roll < 0.22:
		# a crack with two branches
		var len := rng.randf_range(3.0, 9.0)
		var dir := Vector2(cos(yaw), sin(yaw))
		Scn.decal("dark", p + dir * len * 0.5, Vector2(rng.randf_range(0.05, 0.12), len), -yaw + PI * 0.5, Color(0.04, 0.04, 0.045))
		for k in 2:
			var by := yaw + rng.randf_range(-0.9, 0.9)
			var bl := rng.randf_range(1.5, 4.0)
			var bp := p + dir * len * rng.randf_range(0.3, 0.8)
			Scn.decal("dark", bp + Vector2(cos(by), sin(by)) * bl * 0.5, Vector2(0.05, bl), -by + PI * 0.5, Color(0.04, 0.04, 0.045))
	elif roll < 0.38:
		var r := rng.randf_range(0.4, 1.0)
		Scn.decal("disc", p, Vector2(r * 1.5, r * 1.3), yaw, Color(0.3, 0.3, 0.3))      # broken edge
		Scn.decal("disc", p, Vector2(r, r * 0.85), yaw, Color(0.08, 0.07, 0.065), 0.058)
	elif roll < 0.52:
		var r2 := rng.randf_range(1.1, 3.2) * (1.0 + near * 0.4)
		Scn.decal("disc", p, Vector2(r2 * 1.3, r2), yaw, Color(0.1, 0.095, 0.09), 0.047)
		Scn.decal("disc", p, Vector2(r2 * 0.7, r2 * 0.55), yaw, Color(0.045, 0.04, 0.04), 0.057)
	elif roll < 0.66:
		var len2 := rng.randf_range(5.0, 12.0)
		var dir2 := Vector2(cos(yaw), sin(yaw))
		var side := Vector2(-dir2.y, dir2.x) * 0.9
		for sd in [-1.0, 1.0]:
			Scn.decal("dark", p + side * sd + dir2 * len2 * 0.5, Vector2(0.22, len2), -yaw + PI * 0.5, Color(0.05, 0.05, 0.055))
	elif roll < 0.84:
		for k in int(rng.randf_range(5.0, 11.0)):
			var q := p + Vector2(rng.randf_range(-1.8, 1.8), rng.randf_range(-1.8, 1.8))
			var gs := rng.randf_range(0.04, 0.16)
			Scn.decal("debris", q, Vector2(gs, gs * rng.randf_range(0.5, 1.4)), rng.randf() * TAU, Color(0.62, 0.78, 0.82).darkened(rng.randf_range(0.0, 0.3)))
	else:
		for k in int(rng.randf_range(3.0, 7.0)):
			var q2 := p + Vector2(rng.randf_range(-2.2, 2.2), rng.randf_range(-2.2, 2.2))
			var ds := rng.randf_range(0.1, 0.5)
			var g := rng.randf_range(0.18, 0.42)
			Scn.decal("debris", q2, Vector2(ds, ds * rng.randf_range(0.5, 1.2)), rng.randf() * TAU, Color(g, g * 0.92, g * 0.8))
