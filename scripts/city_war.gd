class_name CityWar
## What the first hours of the invasion did to the streets: planted city trees (some burning, felled or burnt to stumps), wrecked
## cars, barricades, tank traps, fallen lamps and poles, rubble, shipping containers, standing street lamps. All of it is plain data
## in Scn (meshes, colliders, nav blocks, fires); World draws it. Own random streams, so the rest of the city does not change.
## The two central avenues (x = 0 and z = 0) keep a 7 m wide clear band: the tests and the direct way home use it.

const KEEP_CLEAR := [Rect2(-3.5, -City.IN_Z, 7.0, City.IN_Z * 2.0), Rect2(-City.IN_X, -3.5, City.IN_X * 2.0, 7.0)]
static var extra_clear: Array = []     # more rectangles the generators keep free (the lookout's fire escape: CityPlaces._old_block); reset by CityStory.reset()
const TREE_SPACING := [10.0, 14.0]
const CONCRETE := Color(0.6, 0.6, 0.58)
const STEEL := Color(0.22, 0.23, 0.25)
const RUST := Color(0.42, 0.22, 0.12)

static var occ: Scn.Occ
static var war_obstacles: Array = []     # {kind, pos: Vector3, yaw, rect}
static var burning_trees := 0
static var fallen_trees := 0
static var stump_trees := 0
static var damaged_cars := 0


static func _jit(c: Color, rng: RandomNumberGenerator, amt: float) -> Color:
	var k := 1.0 + rng.randf_range(-amt, amt)
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0), c.a)


static func _in_clear(r: Rect2) -> bool:
	for k in KEEP_CLEAR + extra_clear:
		if (k as Rect2).intersects(r):
			return true
	return false


static func _near_site(p: Vector2, extra: float) -> float:
	var best := 1.0e9
	for s in City.sites:
		var sc: Vector3 = s["center"]
		best = minf(best, p.distance_to(Vector2(sc.x, sc.z)) - float(s["radius"]) - extra)
	return best


static func _site_factor(p: Vector2, range_m: float) -> float:
	var best := 0.0
	for s in City.sites:
		var sc: Vector3 = s["center"]
		best = maxf(best, 1.0 - p.distance_to(Vector2(sc.x, sc.z)) / range_m)
	return clampf(best, 0.0, 1.0)


## Is the spot on a crossing, the start door or the home door (obstacles stay off those)?
static func _reserved(p: Vector2, pad: float) -> bool:
	for line in City.AVENUE_Z:
		if absf(p.y - line) < City.avenue_width(line) * 0.5 + pad and (p.x > -City.IN_X and p.x < City.IN_X):
			for lx in City.AVENUE_X:
				if absf(p.x - lx) < City.avenue_width(lx) * 0.5 + pad:
					return true
	if p.distance_to(Vector2(City.INSTITUTE_EXIT.x, 240.0)) < 14.0 or p.distance_to(Vector2(City.HOME_POS.x - 3.0, City.HOME_POS.z)) < 12.0:
		return true
	if _near_site(p, 2.0) < 4.0:
		return true
	return false


# ================================================================== trees

static func trees(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7
	burning_trees = 0
	fallen_trees = 0
	stump_trees = 0
	# the park trees (placed by hand in CityPlaces) are always healthy and have no planter
	for pt in City.trees:
		var pp: Vector2 = pt["pos"]
		pt["state"] = "ok"
		pt["planter"] = false
		pt["rect"] = Rect2(pp - Vector2(0.35, 0.35), Vector2(0.7, 0.7))
		pt["k"] = 1.0
		pt["conifer"] = false
		pt["crown"] = _jit(Color(0.15, 0.3, 0.12).lerp(Color(0.26, 0.4, 0.15), fposmod(pp.x * 0.13 + pp.y * 0.29, 1.0)), rng, 0.05)
		pt["yaw"] = 0.0
		pt["prop"] = false
		Scn.cyl_solid(Vector3(pp.x, 0.0, pp.y), float(pt["r"]), 3.0)
		_tree_visual(pt, rng)
	for along_z in [true, false]:
		var lines: Array = City.AVENUE_X if along_z else City.AVENUE_Z
		var cross: Array = City.AVENUE_Z if along_z else City.AVENUE_X
		var lim := City.IN_Z if along_z else City.IN_X
		for line in lines:
			var w := City.avenue_width(line)
			if w < 12.0:
				continue
			for side in [-1.0, 1.0]:
				var t := -lim + rng.randf_range(12.0, 18.0)
				while t < lim - 14.0:
					var u: float = side * (w * 0.5 - 0.5)
					var p := Vector2(line + u, t) if along_z else Vector2(t, line + u)
					var ok := true
					for cl in cross:
						if absf(t - cl) < City.avenue_width(cl) * 0.5 + 5.0:
							ok = false
					if p.distance_to(Vector2(City.INSTITUTE_EXIT.x, 245.0)) < 9.0 or p.distance_to(Vector2(City.HOME_POS.x - 4.0, City.HOME_POS.z)) < 8.0:
						ok = false
					if _near_site(p, 4.0) < 0.0:
						ok = false
					if not extra_clear.is_empty() and _in_clear(Rect2(p - Vector2(1.5, 1.5), Vector2(3.0, 3.0))):
						ok = false
					if ok:
						_add_tree(p, rng, true, line == 0.0, along_z, side)
					t += rng.randf_range(TREE_SPACING[0], TREE_SPACING[1])
	# small groups in the plazas
	for st in City.streets:
		if st["cls"] != "plaza":
			continue
		var r: Rect2 = (st["rect"] as Rect2).grow(-2.2)
		if r.size.x < 4.0 or r.size.y < 4.0:
			continue
		var n := rng.randi_range(2, 4)
		var placed: Array = []
		for i in n:
			for tries in 8:
				var p2 := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
				var far := true
				for q in placed:
					if (q as Vector2).distance_to(p2) < 3.6:
						far = false
				if far and _near_site(p2, 2.0) > 0.0 and not _in_clear(Rect2(p2 - Vector2(1, 1), Vector2(2, 2))):
					placed.append(p2)
					_add_tree(p2, rng, true, false, true, 1.0)
					break


## One city tree in a square planter. `state` is rolled here: about 15% burning, 10% fallen, 10% black stump.
static func _add_tree(p: Vector2, rng: RandomNumberGenerator, planter: bool, on_axis: bool, along_z: bool, side: float) -> void:
	var h := rng.randf_range(7.5, 11.5)
	var roll := rng.randf()
	var state := "ok"
	if roll < 0.10:
		state = "fallen"
	elif roll < 0.20:
		state = "stump"
	var rect := Rect2(p - Vector2(0.5, 0.5), Vector2(1.0, 1.0))
	var tree := {"pos": p, "h": h, "r": 0.3, "state": state, "planter": planter, "rect": rect,
		"k": rng.randf_range(0.85, 1.2), "conifer": rng.randf() < 0.3,
		"crown": _jit(Color(0.15, 0.3, 0.12).lerp(Color(0.26, 0.4, 0.15), rng.randf()), rng, 0.1), "yaw": 0.0, "prop": false}
	var pl_col := _jit(CONCRETE, rng, 0.08)
	Scn.box(Vector3(p.x, 0.25, p.y), Vector3(1.0, 0.5, 1.0), pl_col)
	Scn.box(Vector3(p.x, 0.51, p.y), Vector3(0.8, 0.04, 0.8), Color(0.2, 0.14, 0.09))
	Scn.solid(Vector3(p.x, 0.25, p.y), Vector3(1.0, 0.5, 1.0))
	Scn.block(rect, 0.2)
	if state == "fallen":
		# falls across the road (or along the pavement on the two central avenues, which stay open)
		var across := Vector2(-side, 0.0) if along_z else Vector2(0.0, -side)
		var along := Vector2(0.0, 1.0) if along_z else Vector2(1.0, 0.0)
		var d := across.rotated(rng.randf_range(-0.55, 0.55)) if not on_axis else along * (1.0 if rng.randf() < 0.5 else -1.0)
		tree["yaw"] = atan2(d.x, d.y)
		tree["prop"] = rng.randf() < 0.35
		var length := h * 0.62
		var end := p + d * length
		# keep the fallen tree out of the 7 m band, whatever happened above
		if _in_clear(Rect2(minf(p.x, end.x) - 1.5, minf(p.y, end.y) - 1.5, absf(end.x - p.x) + 3.0, absf(end.y - p.y) + 3.0)):
			tree["state"] = "stump"
			state = "stump"
	match state:
		"burning":
			burning_trees += 1
			Scn.fire("tree", Vector3(p.x, 0.5 + h * 0.75, p.y), 1.0)
			Scn.cyl_solid(Vector3(p.x, 0.5, p.y), 0.28, 3.0)
		"fallen":
			fallen_trees += 1
			_fell(tree, rng)
			Scn.cyl_solid(Vector3(p.x, 0.5, p.y), 0.3, 2.2 if tree["prop"] else 1.0)
		"stump":
			stump_trees += 1
			Scn.cyl_solid(Vector3(p.x, 0.5, p.y), 0.32, 1.4)
		_:
			Scn.cyl_solid(Vector3(p.x, 0.5, p.y), 0.28, 3.0)
	_tree_visual(tree, rng)
	City.trees.append(tree)


## The meshes of one tree in its state (trunk, crown shapes, charring, the stump of a felled one).
static func _tree_visual(tree: Dictionary, rng: RandomNumberGenerator) -> void:
	var p: Vector2 = tree["pos"]
	var h: float = tree["h"] * float(tree["k"])
	var y0 := 0.5 if tree["planter"] else 0.0
	var crown: Color = tree["crown"]
	var trunk_col := Color(0.32, 0.22, 0.14)
	var char_col := Color(0.09, 0.07, 0.06)
	var base := Vector3(p.x, y0, p.y)
	match String(tree["state"]):
		"stump":
			Scn.between("cyl", base, base + Vector3(0, 1.4, 0), 0.6, char_col)
			Scn.box(base + Vector3(0.05, 1.5, 0), Vector3(0.45, 0.35, 0.3), char_col.lightened(0.05), rng.randf() * TAU, Basis(Vector3(0, 0, 1), 0.4))
		"fallen":
			var top := 2.1 if tree["prop"] else 1.0
			Scn.between("cyl", base, base + Vector3(0, top, 0), 0.56, trunk_col)
			Scn.box(base + Vector3(0, top, 0), Vector3(0.5, 0.25, 0.3), Color(0.6, 0.5, 0.35), rng.randf() * TAU, Basis(Vector3(0, 0, 1), 0.35))       # the splintered top
			var tr: Array = tree["trunk"]
			Scn.between("cyl", tr[0], tr[1], 0.76, trunk_col.darkened(0.1))
		"burning":
			Scn.between("cyl", base, base + Vector3(0, h * 0.5, 0), 0.5 * float(tree["k"]), char_col)
			var ph := rng.randf()
			Scn.part("fire", Transform3D(Basis.from_scale(Vector3(h * 0.5, h * 0.42, h * 0.5)), base + Vector3(0, h * 0.62, 0)), Color(ph, 0, 0))
			Scn.part("fire", Transform3D(Basis.from_scale(Vector3(h * 0.32, h * 0.3, h * 0.32)), base + Vector3(h * 0.1, h * 0.88, h * 0.04)), Color(fposmod(ph + 0.37, 1.0), 0, 0))
		_:
			Scn.between("cyl", base, base + Vector3(0, h * 0.5, 0), 0.5 * float(tree["k"]), trunk_col)
			if tree["conifer"]:
				Scn.part("cone", Transform3D(Basis.from_scale(Vector3(h * 0.4, h * 0.55, h * 0.4)), base + Vector3(0, h * 0.42, 0)), crown.darkened(0.15))
				Scn.part("cone", Transform3D(Basis.from_scale(Vector3(h * 0.3, h * 0.42, h * 0.3)), base + Vector3(0, h * 0.78, 0)), crown)
			else:
				Scn.part("sphere", Transform3D(Basis.from_scale(Vector3(h * 0.54, h * 0.44, h * 0.54)), base + Vector3(0, h * 0.62, 0)), crown)
				Scn.part("sphere", Transform3D(Basis.from_scale(Vector3(h * 0.34, h * 0.3, h * 0.34)), base + Vector3(h * 0.1, h * 0.88, h * 0.05)), crown.lightened(0.08))


## The fallen trunk and its crown: a collider the player must jump (lying on the ground) or crouch under (propped up on its stump).
static func _fell(tree: Dictionary, rng: RandomNumberGenerator) -> void:
	var p: Vector2 = tree["pos"]
	var h: float = tree["h"]
	var yaw: float = tree["yaw"]
	var d := Vector2(sin(yaw), cos(yaw))
	var length := h * 0.62
	var prop: bool = tree["prop"]
	var a := Vector3(p.x + d.x * 0.3, 2.1 if prop else 0.45, p.y + d.y * 0.3)
	var b := Vector3(p.x + d.x * length, 0.42, p.y + d.y * length)
	if not prop:
		a.y = 0.45
	var dir3 := (b - a).normalized()
	var xax := Vector3.UP.cross(dir3).normalized()
	var yax := dir3.cross(xax)
	var len3 := a.distance_to(b)
	Scn.solid_xf(Transform3D(Basis(xax, yax, dir3), (a + b) * 0.5), Vector3(0.8, 0.8, len3))
	# the crown lies on the ground at the far end
	var crown := Vector3(p.x + d.x * (length + 1.4), 0.7, p.y + d.y * (length + 1.4))
	Scn.part("sphere", Transform3D(Basis.from_scale(Vector3(3.0, 1.5, 3.0)), crown), tree["crown"])
	Scn.solid(Vector3(crown.x, 0.5, crown.z), Vector3(2.4, 1.0, 2.4))
	# the navigation grid blocks the trunk's swept bounds and the crown
	var tb := Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(b.x - a.x), absf(b.z - a.z))).grow(0.5)
	Scn.block(tb, 0.2)
	Scn.block(Rect2(Vector2(crown.x, crown.z) - Vector2(1.3, 1.3), Vector2(2.6, 2.6)), 0.2)
	tree["trunk"] = [a, b]
	tree["prop_clear"] = prop


# ================================================================== cars

## Called by City._make_cars for every parked car: final placement (basis, origin, footprint) from yaw, roll and size.
static func finish_car(c: Dictionary) -> void:
	var sz: Vector3 = c["size"]
	var roll: float = c.get("roll", 0.0)
	var yaw: float = c["yaw"]
	var pos: Vector3 = c["pos"]
	var yb := Basis(Vector3.UP, yaw)
	var rb := Basis(Vector3(0, 0, 1), roll)
	# lowest point and horizontal middle of the rolled box (the car's local frame: x width, y up from the ground, z length)
	var min_y := 1.0e9
	var min_x := 1.0e9
	var max_x := -1.0e9
	for cx in [-0.5, 0.5]:
		for cy in [0.0, 1.0]:
			var v := rb * Vector3(cx * sz.x, cy * sz.y, 0.0)
			min_y = minf(min_y, v.y)
			min_x = minf(min_x, v.x)
			max_x = maxf(max_x, v.x)
	var local_shift := Vector3(-(min_x + max_x) * 0.5, -min_y - float(c.get("sink", 0.0)), 0.0)
	c["basis"] = yb * rb
	c["origin"] = pos + yb * local_shift
	var half := Vector3(sz.x, sz.y, sz.z) * 0.5
	var lo := Vector2(1.0e9, 1.0e9)
	var hi := Vector2(-1.0e9, -1.0e9)
	for cx in [-1.0, 1.0]:
		for cy in [0.0, 1.0]:
			for cz in [-1.0, 1.0]:
				var v2: Vector3 = (c["basis"] as Basis) * Vector3(cx * half.x, cy * sz.y, cz * half.z) + (c["origin"] as Vector3)
				lo = lo.min(Vector2(v2.x, v2.z))
				hi = hi.max(Vector2(v2.x, v2.z))
	c["rect"] = Rect2(lo, hi - lo)


static func wreck_cars(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1313
	occ = Scn.Occ.new()
	for t in City.trees:
		occ.add(t["rect"] if t.has("rect") else Rect2((t["pos"] as Vector2) - Vector2(0.4, 0.4), Vector2(0.8, 0.8)))
	for c in City.cars:
		occ.add(c["rect"])
	damaged_cars = 0
	# 1. the parked cars: about 40%, more around the battle sites
	var originals := City.cars.duplicate()
	for c in originals:
		var cp: Vector3 = c["pos"]
		var near := _site_factor(Vector2(cp.x, cp.z), 130.0)
		if rng.randf() < 0.1 + 0.35 * near:
			_damage(c, rng)
		elif near > 0.3 and rng.randf() < 0.18:
			_skew(c, rng)
	# 2. abandoned cars across the lanes, and cars rammed into others
	var through: Array = []
	for along_z in [true, false]:
		for line in (City.AVENUE_X if along_z else City.AVENUE_Z):
			if City.avenue_width(line) >= 10.0:
				through.append([line, along_z])
	var made := 0
	for tries in 420:
		if made >= 24:
			break
		var tl: Array = through[rng.randi() % through.size()]
		var line: float = tl[0]
		var along_z: bool = tl[1]
		var w := City.avenue_width(line)
		var lim := City.IN_Z if along_z else City.IN_X
		var t := rng.randf_range(-lim + 20.0, lim - 20.0)
		var u := rng.randf_range(-w * 0.5 + 2.5, w * 0.5 - 2.5)
		var p := Vector2(line + u, t) if along_z else Vector2(t, line + u)
		if _reserved(p, 7.0):
			continue
		var ct: Dictionary = City.CAR_TYPES[rng.randi() % 4]          # hatch, sedan, suv, van
		var sz: Vector3 = ct["size"]
		var yaw := (0.0 if along_z else PI * 0.5) + rng.randf_range(0.35, 1.25) * (1.0 if rng.randf() < 0.5 else -1.0)
		var car := _new_car(ct, Vector3(p.x, 0.0, p.y), yaw, sz, rng)
		finish_car(car)
		if _in_clear(car["rect"]) or occ.hits(car["rect"], 0.3):
			continue
		_add_car(car)
		made += 1
		if rng.randf() < 0.5:
			_damage(car, rng)
		# sometimes another car rammed into its side
		if rng.randf() < 0.25:
			var ct2: Dictionary = City.CAR_TYPES[rng.randi() % 3]
			var side := Basis(Vector3.UP, yaw) * Vector3(1.0, 0.0, 0.0)
			var ram_pos := Vector3(p.x, 0.0, p.y) + side * (sz.x * 0.5 + (ct2["size"] as Vector3).z * 0.5 - 0.35)
			var ram := _new_car(ct2, ram_pos, yaw + PI * 0.5 + rng.randf_range(-0.15, 0.15), ct2["size"], rng)
			finish_car(ram)
			if not _in_clear(ram["rect"]):
				_add_car(ram)
				_damage(ram, rng, "crushed")
	# 3. burnt-out delivery vans at the kerbs of the through streets
	var vans := 0
	for tries in 200:
		if vans >= 8:
			break
		var tl2: Array = through[rng.randi() % through.size()]
		var line2: float = tl2[0]
		var az: bool = tl2[1]
		var w2 := City.avenue_width(line2)
		if w2 < 12.0:
			continue
		var lim2 := City.IN_Z if az else City.IN_X
		var t2 := rng.randf_range(-lim2 + 20.0, lim2 - 20.0)
		var side2 := -1.0 if rng.randf() < 0.5 else 1.0
		var u2: float = side2 * (w2 * 0.5 - 1.25 - 1.05)
		var p2 := Vector2(line2 + u2, t2) if az else Vector2(t2, line2 + u2)
		if _reserved(p2, 8.0):
			continue
		var van := _new_car(City.CAR_TYPES[3], Vector3(p2.x, 0.0, p2.y), (0.0 if az else PI * 0.5) + (PI if rng.randf() < 0.5 else 0.0), (City.CAR_TYPES[3]["size"] as Vector3) * 1.0, rng)
		finish_car(van)
		if _in_clear(van["rect"]) or occ.hits(van["rect"], 0.3):
			continue
		_add_car(van)
		_damage(van, rng, "burnt")
		vans += 1
	damaged_cars = 0
	for c in City.cars:
		if String(c.get("dmg", "")) != "":
			damaged_cars += 1


static func _new_car(ct: Dictionary, pos: Vector3, yaw: float, size: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var palette := [Color(0.1, 0.1, 0.12), Color(0.75, 0.75, 0.78), Color(0.55, 0.1, 0.1), Color(0.15, 0.25, 0.45), Color(0.8, 0.7, 0.2),
		Color(0.3, 0.32, 0.34), Color(0.9, 0.9, 0.9), Color(0.12, 0.35, 0.25), Color(0.85, 0.4, 0.1)]
	return {"pos": pos, "type": ct["name"], "size": size, "yaw": yaw, "color": palette[rng.randi() % palette.size()],
		"accent": palette[rng.randi() % palette.size()], "cargo": Color(0.6, 0.6, 0.62), "stripe": false, "two_tone": false,
		"along_z": absf(cos(yaw)) > 0.7, "dmg": "", "roll": 0.0, "crush": 0.0, "doors": false, "burnt": false, "fire": false}


static func _add_car(car: Dictionary) -> void:
	City.cars.append(car)
	occ.add(car["rect"])


## Tilt a parked car so a corner touches the kerb or a wall (it ran into it).
static func _skew(c: Dictionary, rng: RandomNumberGenerator) -> void:
	var old_yaw: float = c["yaw"]
	var old_rect: Rect2 = c["rect"]
	c["yaw"] = old_yaw + rng.randf_range(0.4, 0.8) * (1.0 if rng.randf() < 0.5 else -1.0)
	finish_car(c)
	if occ.hits(c["rect"], -0.2) and not (c["rect"] as Rect2).encloses(old_rect):
		var others := false
		for o in City.cars:
			if o != c and (o["rect"] as Rect2).intersects(c["rect"]):
				others = true
		if others or _in_clear(c["rect"]):
			c["yaw"] = old_yaw
			finish_car(c)
			return
	c["dmg"] = "crashed"
	c["doors"] = rng.randf() < 0.4


## Burnt-out shell, burning, flipped on its side or roof, crushed, or doors hanging open.
static func _damage(c: Dictionary, rng: RandomNumberGenerator, force: String = "") -> void:
	var kind := force
	if kind == "":
		var r := rng.randf()
		kind = "burnt" if r < 0.28 else ("burning" if r < 0.42 else ("side" if r < 0.54 else ("roof" if r < 0.62 else ("crushed" if r < 0.84 else "doors"))))
	if (kind == "side" or kind == "roof") and (String(c["type"]) == "bus" or String(c["type"]) == "truck"):
		kind = "burnt"          # the big ones stay on their wheels
	match kind:
		"burnt", "burning":
			c["burnt"] = true
			c["color"] = _jit(Color(0.1, 0.075, 0.06), rng, 0.25)
			c["accent"] = c["color"]
			c["stripe"] = false
			c["two_tone"] = false
			c["sink"] = 0.12
			c["fire"] = kind == "burning"
		"side":
			c["roll"] = (PI * 0.5) * (1.0 if rng.randf() < 0.5 else -1.0)
		"roof":
			c["roll"] = PI
		"crushed":
			c["crush"] = rng.randf_range(0.5, 0.75)
		"doors":
			c["doors"] = true
	c["dmg"] = kind
	if rng.randf() < 0.3 and kind in ["burnt", "crushed", "doors"]:
		c["doors"] = true
	finish_car(c)
	# a flipped car is wider: if it now lands on a tree or in the clear band, leave it on its wheels (burnt) instead
	if kind == "side" or kind == "roof":
		var rect: Rect2 = c["rect"]
		var blocked := _in_clear(rect)
		for t in City.trees:
			if rect.grow(0.2).intersects(t["rect"]):
				blocked = true
		if blocked:
			c["roll"] = 0.0
			c["dmg"] = "burnt"
			c["burnt"] = true
			c["color"] = _jit(Color(0.1, 0.075, 0.06), rng, 0.25)
			c["accent"] = c["color"]
			c["sink"] = 0.12
			finish_car(c)
	if c["dmg"] == "burning" or c.get("fire", false):
		var rr: Rect2 = c["rect"]
		Scn.fire("car", Vector3(rr.get_center().x, 1.2, rr.get_center().y), 1.0)
	occ.add(c["rect"])


# ================================================================== obstacles

static func obstacles(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 777
	war_obstacles.clear()
	if occ == null:
		occ = Scn.Occ.new()
	# 1. the through streets: dense on the avenues, thinner on the streets
	for along_z in [true, false]:
		var lines: Array = City.AVENUE_X if along_z else City.AVENUE_Z
		var lim := City.IN_Z if along_z else City.IN_X
		for line in lines:
			var w := City.avenue_width(line)
			if w < 10.0:
				continue
			var chance := 0.85 if w >= 18.0 else (0.55 if w >= 12.0 else 0.3)
			var t := -lim + 25.0
			while t < lim - 25.0:
				t += rng.randf_range(16.0, 30.0)
				if rng.randf() > chance:
					continue
				var u := rng.randf_range(-w * 0.5 + 3.0, w * 0.5 - 3.0)
				var p := Vector2(line + u, t) if along_z else Vector2(t, line + u)
				_place_random(p, 0.0 if along_z else PI * 0.5, w, rng, false)
	# 2. rings of defences round every battle site
	for s in City.sites:
		var sc: Vector3 = s["center"]
		var open := minf(minf(City.avenue_width(sc.x), City.avenue_width(sc.z)), 30.0) * 0.5
		var n := rng.randi_range(7, 10)
		var a0 := rng.randf() * TAU
		for i in n:
			var a := a0 + TAU * float(i) / float(n) + rng.randf_range(-0.2, 0.2)
			var rad := minf(open * 0.95, 12.0) + rng.randf_range(0.0, 7.0)
			var p2 := Vector2(sc.x + cos(a) * rad, sc.z + sin(a) * rad)
			_place_random(p2, -a + PI * 0.5, 12.0, rng, true)
	# 3. the back lanes stay quiet: a rare piece of rubble or a lone barrier
	for st in City.streets:
		var cls: String = st["cls"]
		if cls != "walk" and cls != "alley" and cls != "street":
			continue
		var r: Rect2 = st["rect"]
		var narrow := minf(r.size.x, r.size.y)
		var long_side := maxf(r.size.x, r.size.y)
		if narrow > 13.0 or narrow < 5.5 or long_side < 18.0:
			continue          # only the real back streets (6 and 12 m), and nothing in an alley: those stay quiet
		if rng.randf() > (0.2 if cls == "street" else 0.08):
			continue
		var p3 := Vector2(rng.randf_range(r.position.x + 3.0, maxf(r.position.x + 3.1, r.end.x - 3.0)), rng.randf_range(r.position.y + 3.0, maxf(r.position.y + 3.1, r.end.y - 3.0)))
		var along_x := r.size.x > r.size.y
		_try_obstacle("rubble" if rng.randf() < 0.6 else "jersey", p3, PI * 0.5 if along_x else 0.0, rng)
	_containers(rng)
	_lamps(rng)


## Rubble at a spot (used by the building damage: debris fallen into the street); false if the place is taken.
static func try_rubble(p: Vector2, rng: RandomNumberGenerator) -> bool:
	if occ == null:
		return false
	return _try_obstacle("rubble", p, rng.randf() * PI, rng)


static func _place_random(p: Vector2, yaw: float, width: float, rng: RandomNumberGenerator, site: bool) -> void:
	var roll := rng.randf()
	if site:
		roll = rng.randf() * 0.9
	var kind: String
	if roll < 0.22:
		kind = "jersey_line"
	elif roll < 0.40:
		kind = "sandbags"
	elif roll < 0.52:
		kind = "barricade"
	elif roll < 0.62:
		kind = "tank_trap"
	elif roll < 0.72:
		kind = "lamp_down"
	elif roll < 0.78:
		kind = "pole_down"
	elif roll < 0.95:
		kind = "rubble"
	else:
		kind = "jersey"
	if width < 12.0 and kind == "jersey_line":
		kind = "jersey"
	_try_obstacle(kind, p, yaw, rng)


static func _footprint_of(kind: String, p: Vector2, yaw: float) -> Rect2:
	var half := Vector2(1.5, 0.4)
	match kind:
		"jersey":
			half = Vector2(1.5, 0.4)
		"jersey_line":
			half = Vector2(4.6, 0.5)
		"sandbags":
			half = Vector2(1.9, 0.8)
		"barricade":
			half = Vector2(2.2, 0.9)
		"tank_trap":
			half = Vector2(0.9, 0.9)
		"lamp_down":
			half = Vector2(3.8, 0.8)
		"pole_down":
			half = Vector2(3.4, 1.4)
		"rubble":
			half = Vector2(2.0, 1.6)
	return Scn.footprint(p, half, yaw)


static func _try_obstacle(kind: String, p: Vector2, yaw: float, rng: RandomNumberGenerator) -> bool:
	var rect := _footprint_of(kind, p, yaw)
	if absf(p.x) > City.IN_X - 6.0 or absf(p.y) > City.IN_Z - 6.0:
		return false
	if _in_clear(rect) or occ.hits(rect, 0.5) or _reserved(p, 4.0):
		return false
	if _hits_building(rect):
		return false
	occ.add(rect)
	war_obstacles.append({"kind": kind, "pos": Vector3(p.x, 0.0, p.y), "yaw": yaw, "rect": rect})
	var c3 := Vector3(p.x, 0.0, p.y)
	match kind:
		"jersey":
			_jersey(c3, yaw, rng)
		"jersey_line":
			for i in 3:
				var off := (float(i) - 1.0) * 3.1
				var pos := c3 + Basis(Vector3.UP, yaw) * Vector3(off, 0.0, float(i % 2) * 0.35 - 0.1)
				_jersey(pos, yaw + rng.randf_range(-0.08, 0.08), rng)
		"sandbags":
			_sandbags(c3, yaw, rng)
		"barricade":
			_barricade(c3, yaw, rng)
		"tank_trap":
			_tank_trap(c3, yaw, rng)
		"lamp_down":
			_lamp_down(c3, yaw, rng)
		"pole_down":
			_pole_down(c3, yaw, rng)
		"rubble":
			rubble(c3, yaw, rng, 1.0)
	return true


static func _hits_building(rect: Rect2) -> bool:
	for b in City.buildings:
		if (b["rect"] as Rect2).grow(0.3).intersects(rect):
			return true
	return false


static func _jersey(c: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var col := _jit(Color(0.62, 0.62, 0.6), rng, 0.1)
	Scn.prop(c + Vector3(0, 0.15, 0), Vector3(3.0, 0.3, 0.6), col, yaw)                         # the wide foot...
	Scn.prop(c + Vector3(0, 0.58, 0), Vector3(3.0, 0.56, 0.36), col.lightened(0.04), yaw)       # ...and the narrower body on it
	Scn.block(Scn.footprint(Vector2(c.x, c.z), Vector2(1.5, 0.3), yaw), 0.3)


static func _sandbags(c: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var basis := Basis(Vector3.UP, yaw)
	for row in 3:
		var n := 6 - (row if row < 2 else 1)
		for i in n:
			var off := (float(i) - float(n - 1) * 0.5) * 0.58
			var wing := absf(off) * 0.12
			var pos := c + basis * Vector3(off, 0.15 + 0.29 * row, wing - 0.2)
			Scn.box(pos, Vector3(0.58, 0.28, 0.4), _jit(Color(0.5, 0.45, 0.32).lerp(Color(0.38, 0.4, 0.3), rng.randf()), rng, 0.08), yaw + rng.randf_range(-0.1, 0.1))
	# the stack narrows: two rows of six bags, one of five on top (the wings bend a little back)
	Scn.solid(c + basis * Vector3(0, 0.29, -0.15), Vector3(3.5, 0.58, 0.72), yaw)
	Scn.solid(c + basis * Vector3(0, 0.73, -0.2), Vector3(2.9, 0.3, 0.55), yaw)
	Scn.block(Scn.footprint(Vector2(c.x, c.z), Vector2(1.75, 0.45), yaw), 0.3)


## A barricade the city guard threw together: crates, a sofa, a wardrobe, a door, a tipped table.
static func _barricade(c: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var wood := Color(0.42, 0.3, 0.19)
	for i in 4:
		var off := -1.6 + float(i) * 1.05
		var pos := c + basis * Vector3(off, 0.45, rng.randf_range(-0.2, 0.2))
		Scn.prop(pos, Vector3(0.9, 0.9, 0.9), _jit(wood.lerp(Color(0.5, 0.42, 0.3), rng.randf()), rng, 0.12), yaw + rng.randf_range(-0.2, 0.2))
	Scn.prop(c + basis * Vector3(-1.1, 1.3, 0), Vector3(0.85, 0.8, 0.85), _jit(wood, rng, 0.15), yaw + 0.3)
	Scn.prop(c + basis * Vector3(0.3, 0.45, 0.45), Vector3(1.9, 0.5, 0.8), Color(0.3, 0.36, 0.48), yaw)                 # sofa seat
	Scn.prop(c + basis * Vector3(0.3, 0.85, 0.75), Vector3(1.9, 0.5, 0.2), Color(0.3, 0.36, 0.48), yaw)                # sofa back
	Scn.prop(c + basis * Vector3(1.55, 0.95, -0.15), Vector3(0.55, 1.9, 0.9), Color(0.55, 0.5, 0.42), yaw + 0.08)       # wardrobe
	Scn.box(c + basis * Vector3(-0.2, 1.05, -0.4), Vector3(1.0, 2.0, 0.05), Color(0.8, 0.78, 0.7), yaw, Basis(Vector3.FORWARD, 0.0) * Basis(Vector3(1, 0, 0), -0.32))   # door (a thin leaning sheet: the crates behind it hold the line)
	Scn.prop(c + basis * Vector3(-1.9, 0.3, 0.2), Vector3(0.9, 0.6, 1.4), Color(0.4, 0.28, 0.18), yaw + 0.5)           # table on its side
	Scn.block(Scn.footprint(Vector2(c.x, c.z), Vector2(2.2, 0.8), yaw), 0.3)


static func _tank_trap(c: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var col := _jit(Color(0.25, 0.25, 0.27).lerp(RUST, rng.randf() * 0.6), rng, 0.1)
	# three beams crossed at their middles, the whole thing tipped so it rests on its points
	var tip := Basis(Vector3(1, 0, 1).normalized(), 0.62)
	var spin := Basis(Vector3.UP, yaw)
	for k in 3:
		var beam := Vector3(2.2, 0.2, 0.2) if k == 0 else (Vector3(0.2, 2.2, 0.2) if k == 1 else Vector3(0.2, 0.2, 2.2))
		Scn.part("box", Transform3D(spin * tip * Basis.from_scale(beam), c + Vector3(0, 0.75, 0)), col)
	Scn.solid(c + Vector3(0, 0.7, 0), Vector3(1.5, 1.4, 1.5), yaw)
	Scn.block(Scn.footprint(Vector2(c.x, c.z), Vector2(0.8, 0.8), yaw), 0.3)


## A street lamp lying across the pavement and kerb, head smashed, sometimes with live wires.
static func _lamp_down(c: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var a := c + basis * Vector3(-3.4, 0.5, 0.0)
	var b := c + basis * Vector3(3.4, 0.2, 0.0)
	Scn.between("cyl", a, b, 0.22, Color(0.3, 0.32, 0.34))
	Scn.box(b + basis * Vector3(0.5, 0.1, 0.0), Vector3(1.3, 0.16, 0.34), Color(0.25, 0.26, 0.28), yaw + 0.1)
	Scn.box(c + basis * Vector3(-3.8, 0.12, 0.0), Vector3(0.7, 0.24, 0.7), Color(0.45, 0.45, 0.46), yaw)               # broken base
	Scn.solid((a + b) * 0.5, Vector3(7.4, 0.5, 0.4), yaw, Basis(Vector3(0, 0, 1), -0.04))
	Scn.block(Scn.footprint(Vector2(c.x, c.z), Vector2(3.8, 0.4), yaw), 0.3)
	if rng.randf() < 0.55:
		Scn.fire("spark", b + basis * Vector3(1.0, 0.2, 0.3), 1.0)
		for k in 3:
			Scn.box(b + basis * Vector3(1.0 + k * 0.5, 0.05, 0.4 * float(k % 2) - 0.1), Vector3(0.5, 0.03, 0.04), Color(0.05, 0.05, 0.05), yaw + float(k) * 0.9)


## A snapped power pole: a leaning stump, the top half on the ground with its cross-arm, wires trailing and sparking.
static func _pole_down(c: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var wood := Color(0.34, 0.25, 0.17)
	var base := c + basis * Vector3(-2.6, 0.0, 0.0)
	Scn.between("cyl", base, base + Vector3(0.25, 3.4, 0.0), 0.38, wood)
	Scn.cyl_solid(base, 0.25, 2.5)
	var top := c + basis * Vector3(2.6, 0.45, 0.4)
	var from := base + Vector3(0.25, 3.4, 0.0)
	Scn.between("cyl", from, top, 0.32, wood.darkened(0.15))
	Scn.box(top + basis * Vector3(0.1, 0.1, 0.0), Vector3(0.12, 0.12, 2.2), Color(0.3, 0.22, 0.14), yaw)
	for k in 3:
		var wz := -0.8 + float(k) * 0.8
		var wa := top + basis * Vector3(0.1, 0.15, wz)
		var wb := c + basis * Vector3(0.4 + float(k), 0.04, 1.8 + wz * 0.6)
		Scn.between("cyl", wa, wb, 0.04, Color(0.05, 0.05, 0.05))
	Scn.solid((from + top) * 0.5, Vector3(0.5, 0.5, from.distance_to(top)), 0.0, Basis.looking_at((top - from).normalized(), Vector3.UP))
	Scn.block(Scn.footprint(Vector2(c.x, c.z), Vector2(3.2, 1.0), yaw), 0.3)
	Scn.fire("spark", top + Vector3(0, 0.4, 0), 1.3)


static func rubble(c: Vector3, yaw: float, rng: RandomNumberGenerator, k: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	Scn.box(c + Vector3(0, 0.2 * k, 0), Vector3(3.2 * k, 0.4 * k, 2.4 * k), Color(0.32, 0.31, 0.3), yaw)
	for i in int(rng.randf_range(9.0, 15.0) * k):
		var off := Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.1, 1.1)) * k
		var sz := Vector3(rng.randf_range(0.3, 1.1), rng.randf_range(0.2, 0.7), rng.randf_range(0.3, 1.0)) * k
		var g := rng.randf_range(0.28, 0.62)
		var col := Color(g, g * 0.96, g * 0.9) if rng.randf() < 0.8 else Color(0.38, 0.2, 0.14)
		var rot := Basis(Vector3(1, 0, 0), rng.randf_range(-0.5, 0.5)) * Basis(Vector3(0, 0, 1), rng.randf_range(-0.5, 0.5))
		Scn.box(c + basis * off + Vector3(0, 0.35 * k + sz.y * 0.3, 0), sz, col, yaw + rng.randf() * TAU, rot)
	# a bent rebar sticking out
	Scn.between("cyl", c + Vector3(0.3, 0.5, 0.2), c + Vector3(0.9, 1.5, -0.3) * k, 0.05, Color(0.3, 0.2, 0.15))
	# a heap: the slab it lies on, and a narrower, higher core of big pieces (the loose rim of small stones is walked through)
	Scn.solid(c + Vector3(0, 0.2 * k, 0), Vector3(3.2 * k, 0.4 * k, 2.4 * k), yaw)
	Scn.solid(c + Vector3(0, 0.6 * k, 0), Vector3(2.2 * k, 0.8 * k, 1.6 * k), yaw)
	Scn.block(Scn.footprint(Vector2(c.x, c.z), Vector2(1.6, 1.25) * k, yaw), 0.3)


const CONTAINER_COLORS := [Color(0.55, 0.16, 0.11), Color(0.14, 0.28, 0.46), Color(0.72, 0.5, 0.12), Color(0.18, 0.36, 0.22), Color(0.42, 0.42, 0.44), Color(0.5, 0.25, 0.1)]

static func _containers(rng: RandomNumberGenerator) -> void:
	City.containers.clear()
	for tries in 400:
		if City.containers.size() >= 18:
			break
		var through_x := rng.randf() < 0.5
		var lines: Array = City.AVENUE_X if through_x else City.AVENUE_Z
		var line: float = lines[rng.randi() % lines.size()]
		var w := City.avenue_width(line)
		if w < 12.0:
			continue
		var lim := City.IN_Z if through_x else City.IN_X
		var t := rng.randf_range(-lim + 25.0, lim - 25.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var u: float = side * (w * 0.5 - 1.3 - 1.2)
		var p := Vector2(line + u, t) if through_x else Vector2(t, line + u)
		var yaw := 0.0 if through_x else PI * 0.5
		var rect := Scn.footprint(p, Vector2(1.25, 3.1), yaw)
		if _in_clear(rect) or occ.hits(rect, 0.5) or _reserved(p, 7.0) or _hits_building(rect):
			continue
		occ.add(rect)
		var col: Color = _jit(CONTAINER_COLORS[rng.randi() % CONTAINER_COLORS.size()], rng, 0.12)
		var basis := Basis(Vector3.UP, yaw)
		var c3 := Vector3(p.x, 0.0, p.y)
		Scn.box(c3 + Vector3(0, 1.3, 0), Vector3(2.4, 2.6, 6.06), col, yaw)
		for k in 8:
			var rz := -2.7 + float(k) * 0.77
			for sd in [-1.0, 1.0]:
				Scn.box(c3 + basis * Vector3(sd * 1.21, 1.3, rz), Vector3(0.06, 2.45, 0.12), col.darkened(0.25), yaw)
		Scn.box(c3 + basis * Vector3(0, 1.3, 3.06), Vector3(2.2, 2.4, 0.08), col.darkened(0.3), yaw)
		Scn.solid(c3 + Vector3(0, 1.3, 0), Vector3(2.4, 2.6, 6.06), yaw)
		Scn.block(rect, 0.2)
		war_obstacles.append({"kind": "container", "pos": c3, "yaw": yaw, "rect": rect})
		City.containers.append({"pos": c3, "yaw": yaw, "top": 2.6, "rect": rect})


## Standing street lamps along the kerbs of the through streets (thin pole, arm, lamp head).
static func _lamps(rng: RandomNumberGenerator) -> void:
	for along_z in [true, false]:
		var lines: Array = City.AVENUE_X if along_z else City.AVENUE_Z
		var cross: Array = City.AVENUE_Z if along_z else City.AVENUE_X
		var lim := City.IN_Z if along_z else City.IN_X
		for line in lines:
			var w := City.avenue_width(line)
			if w < 12.0:
				continue
			for side in [-1.0, 1.0]:
				var t := -lim + 30.0 + (0.0 if side < 0.0 else 18.0)
				while t < lim - 30.0:
					var u: float = side * (w * 0.5 - 0.25)
					var p := Vector2(line + u, t) if along_z else Vector2(t, line + u)
					var ok := true
					for cl in cross:
						if absf(t - cl) < City.avenue_width(cl) * 0.5 + 3.0:
							ok = false
					for tr in City.trees:
						if (tr["pos"] as Vector2).distance_to(p) < 2.4:
							ok = false
					for ec in extra_clear:                  # the lookout's fire escape stands there: no lamp
						if (ec as Rect2).grow(0.6).has_point(p):
							ok = false
					if ok and not _reserved(p, 3.0) and not occ.hits(Rect2(p - Vector2(0.4, 0.4), Vector2(0.8, 0.8)), 0.0):
						var toward := Vector3(-side, 0.0, 0.0) if along_z else Vector3(0.0, 0.0, -side)
						var base := Vector3(p.x, 0.0, p.y)
						Scn.between("cyl", base, base + Vector3(0, 7.2, 0), 0.18, Color(0.28, 0.3, 0.32))
						Scn.between("cyl", base + Vector3(0, 7.1, 0), base + Vector3(0, 7.4, 0) + toward * 1.6, 0.1, Color(0.28, 0.3, 0.32))
						Scn.box(base + Vector3(0, 7.3, 0) + toward * 1.7, Vector3(0.9, 0.12, 0.4), Color(0.8, 0.8, 0.74) if rng.randf() < 0.8 else Color(0.2, 0.2, 0.22), 0.0 if not along_z else 0.0)
						Scn.cyl_solid(base, 0.11, 7.0)
						Scn.block(Rect2(p - Vector2(0.15, 0.15), Vector2(0.3, 0.3)), 0.25)
						occ.add(Rect2(p - Vector2(0.4, 0.4), Vector2(0.8, 0.8)))          # later planners (fire escapes, the story) keep off the pole
					t += 36.0


# ================================================================== cover on the 12 m streets

const COVER_JUNCTION := 7.0                 # the first / last metres of a stretch (the junction mouths) stay clear
const COVER_SPACING := [12.0, 16.0]         # distance along the street between two cover objects (they alternate sides)
const COVER_SIDE := [2.0, 3.0]              # how far from the middle line an object stands
const COVER_KINDS := {"car": 45, "bus": 12, "containers": 25, "facade": 18}
const COVER_HAND_PAD := 12.0                # the hand-built places and this much round them get no planted cover

## A staggered chain of cover along every 12 m street: wrecked cars, bus wrecks, container pairs, fallen facade, alternating left and
## right of the middle line, so that in any 40 m there is a place out of sight of the far end (tests/stealth_audit.gd measures it).
## Cars go through the usual car list (WorldCars draws them); the rest are shared-mesh boxes with box colliders (Scn). Own random
## stream. Never in the 7 m bands of x = 0 / z = 0, the junction mouths, the battle sites or the story places.
static func street_cover(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 9191
	if occ == null:
		occ = Scn.Occ.new()
	var hand: Array = []
	for hb in [City.INSTITUTE_BLOCK, City.HOME_BLOCK, City.PARK_BLOCK, City.COURT_BLOCK]:
		hand.append((hb as Rect2).grow(COVER_HAND_PAD))
	var total_w := 0
	for k in COVER_KINDS:
		total_w += int(COVER_KINDS[k])
	for st in City.streets:
		if st["cls"] != "street":
			continue
		var r: Rect2 = st["rect"]
		if absf(minf(r.size.x, r.size.y) - 12.0) > 1.0:
			continue
		var az := r.size.y > r.size.x
		var lo := r.position.y if az else r.position.x
		var hi := r.end.y if az else r.end.x
		var mid_lat := r.get_center().x if az else r.get_center().y
		var cuts: Array = []
		for o in City.streets:
			var orr: Rect2 = o["rect"]
			if orr == r or minf(orr.size.x, orr.size.y) < 9.5 or (orr.size.x > orr.size.y) != az:
				continue
			var it := r.intersection(orr)
			if it.size.x > 0.0 and it.size.y > 0.0:
				cuts.append([it.position.y, it.end.y] if az else [it.position.x, it.end.x])
		for h in hand:
			var it2 := r.intersection(h as Rect2)
			if it2.size.x > 0.0 and it2.size.y > 0.0:
				cuts.append([it2.position.y, it2.end.y] if az else [it2.position.x, it2.end.x])
		cuts.sort_custom(func(a, b): return a[0] < b[0])
		var mouths: Array = []                      # where narrow streets open onto this one: kept clear so the dashes across stay open
		for o2 in City.streets:
			var nr: Rect2 = o2["rect"]
			if minf(nr.size.x, nr.size.y) <= 8.5 and (nr.size.x > nr.size.y) != az:
				var it3 := r.grow(0.4).intersection(nr)
				if it3.size.x > 0.0 and it3.size.y > 0.0:
					mouths.append([it3.position.y, it3.end.y] if az else [it3.position.x, it3.end.x])
		var segs: Array = []
		var cur := lo
		for c in cuts:
			if c[0] > cur:
				segs.append([cur, c[0]])
			cur = maxf(cur, c[1])
		if hi > cur:
			segs.append([cur, hi])
		for sg in segs:
			var a: float = float(sg[0]) + COVER_JUNCTION
			var b: float = float(sg[1]) - COVER_JUNCTION
			if b - a < 8.0:
				continue
			var n := maxi(1, roundi((b - a) / ((COVER_SPACING[0] + COVER_SPACING[1]) * 0.5)))
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			for i in n:
				var u := a + (float(i) + 0.5) * (b - a) / float(n) + rng.randf_range(-1.5, 1.5)
				var lat := mid_lat + side * rng.randf_range(COVER_SIDE[0], COVER_SIDE[1])
				side = -side
				var roll := rng.randi() % total_w
				var kind := "car"
				for k in COVER_KINDS:
					roll -= int(COVER_KINDS[k])
					if roll < 0:
						kind = k
						break
				for shift in [0.0, 2.5, -2.5]:
					var p := Vector2(lat, u + shift) if az else Vector2(u + shift, lat)
					if _cover_try(kind, p, az, r, rng, mouths):
						break


static func _cover_try(kind: String, p: Vector2, az: bool, street: Rect2, rng: RandomNumberGenerator, mouths: Array) -> bool:
	var reach := 7.0 if kind == "containers" else (6.0 if kind == "bus" else (3.0 if kind == "car" else 2.8))
	var pu := p.y if az else p.x
	for mo in mouths:
		if pu + reach > float(mo[0]) - 1.5 and pu - reach < float(mo[1]) + 1.5:
			return false
	var along_yaw := 0.0 if az else PI * 0.5
	if absf(p.x) > City.IN_X - 6.0 or absf(p.y) > City.IN_Z - 6.0 or _reserved(p, 4.0):
		return false
	var c3 := Vector3(p.x, 0.0, p.y)
	match kind:
		"car", "bus":
			var ct: Dictionary = City.CAR_TYPES[5] if kind == "bus" else City.CAR_TYPES[rng.randi() % 4]
			var yaw := along_yaw + rng.randf_range(-0.45, 0.45) + (PI if rng.randf() < 0.5 else 0.0)
			var car := _new_car(ct, c3, yaw, ct["size"], rng)
			finish_car(car)
			var cr: Rect2 = car["rect"]
			if not street.grow(-0.8).encloses(cr) or _in_clear(cr) or occ.hits(cr, 0.5) or _hits_building(cr):
				return false
			_add_car(car)
			_damage(car, rng, "burnt" if kind == "bus" else "")
			return true
		"containers":
			var basis := Basis(Vector3.UP, along_yaw)
			var step := basis * Vector3(0.0, 0.0, 6.5)
			var rects: Array = []
			for k in 2:
				var cp := c3 + step * float(k) - step * 0.5
				rects.append([cp, Scn.footprint(Vector2(cp.x, cp.z), Vector2(1.25, 3.1), along_yaw)])
			for rr in rects:
				if not street.grow(-0.8).encloses(rr[1]) or _in_clear(rr[1]) or occ.hits(rr[1], 0.5) or _hits_building(rr[1]):
					return false
			var col: Color = _jit(CONTAINER_COLORS[rng.randi() % CONTAINER_COLORS.size()], rng, 0.12)
			for rr in rects:
				var cp2: Vector3 = rr[0]
				var ccol := _jit(col, rng, 0.08)
				Scn.prop(cp2 + Vector3(0, 1.3, 0), Vector3(2.4, 2.6, 6.06), ccol, along_yaw + rng.randf_range(-0.04, 0.04))
				Scn.box(cp2 + basis * Vector3(0, 1.3, 3.06), Vector3(2.2, 2.4, 0.08), ccol.darkened(0.3), along_yaw)
				Scn.block(rr[1], 0.2)
				occ.add(rr[1])
			return true
		_:
			var yaw2 := along_yaw + rng.randf_range(-0.3, 0.3)
			var fp := Scn.footprint(p, Vector2(2.4, 1.6), yaw2)
			if not street.grow(-0.8).encloses(fp) or _in_clear(fp) or occ.hits(fp, 0.5) or _hits_building(fp):
				return false
			var stone := _jit(Color(0.58, 0.57, 0.55), rng, 0.08)
			Scn.prop(c3 + Vector3(0, 0.6, 0), Vector3(4.2, 1.2, 2.2), _jit(Color(0.34, 0.33, 0.32), rng, 0.1), yaw2)               # the heap...
			Scn.prop(c3 + Basis(Vector3.UP, yaw2) * Vector3(0.2, 1.75, 0.5), Vector3(3.6, 0.3, 2.4), stone, yaw2, Basis(Vector3.RIGHT, 0.5))     # ...and a slab of facade leaning on it
			Scn.box(c3 + Basis(Vector3.UP, yaw2) * Vector3(-1.0, 1.3, -0.7), Vector3(0.18, 0.18, 2.6), Color(0.28, 0.24, 0.22), yaw2 + 0.4, Basis(Vector3.RIGHT, 0.3))   # a bent beam
			Scn.block(fp, 0.3)
			occ.add(fp)
			return true
	return false
