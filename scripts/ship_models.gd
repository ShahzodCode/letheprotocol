class_name ShipModels
## Procedural landing craft, in the style of GunModels: boxes and cylinders merged into ONE cached two-surface mesh (lit + glowing)
## per detail level, so the ship in the park costs one draw call (plus its ground patch and two heat-shimmer quads).
## The craft is an alien wedge: a faceted, flat-shaded hull lofted through `SECTIONS` (a low blade of a nose, a hard chine down both
## flanks, a raised spine with a glass canopy), swept stub wings carrying two tapered engine nacelles with cold blue exhausts, four
## angled landing struts, chin cannons and a dorsal fin, gunmetal with glowing trim. A lowered rear ramp leads into a short
## vestibule: the interior itself is not modelled (a dark alcove behind a lit loading threshold: `Lander.threshold` is the area a
## later interior level hooks into).
##
## Model space: the nose is -z, the ramp at the back (+z), the ground is y = 0, the middle of the hull z = 0. World placement
## turns it (`City.LANDER_YAW`). `lander_boxes()` is the collision box set in the same space; `site_mesh()` the ground it landed
## on (scorch ring, crushed flowerbeds, fallen trees), cached too.

const LENGTH := 20.5                 # nose to the back wall (the ramp reaches 6 m further)
const WIDTH := 10.0                  # the hull (the engine pods stick out to +-7.3 m)
const HEIGHT := 6.0                  # the collision top (the dorsal block rises 0.8 m above it)
const SILL_Y := 1.5                  # the floor of the doorway; the ramp climbs from the ground to here
const RAMP_LEN := 6.0
const DOOR_W := 4.6
const NEAR_LOD_DIST := 85.0          # nearer than this the detailed mesh is shown

const DOOR_TOP := 5.2                # the doorway's lintel

const HULL := Color(0.34, 0.36, 0.4)
const HULL2 := Color(0.25, 0.26, 0.3)
const PLATE := Color(0.45, 0.47, 0.51)
const TRIM := Color(0.62, 0.6, 0.55)
const DARKP := Color(0.11, 0.12, 0.14)
const SOOT := Color(0.08, 0.075, 0.07)
const ENERGY := Color(0.45, 0.85, 1.0)
const ALARM := Color(1.0, 0.22, 0.12)
const COLD := Color(0.78, 0.9, 1.0)
const GLASS := Color(0.05, 0.09, 0.12)

## The hull's cross-sections, nose to stern: [z, belly half-width, belly y, chine hw, chine y, shoulder hw, shoulder y, spine hw, spine y].
## The stern (z 7 .. 10) is the last one extruded and cut round the doorway.
const SECTIONS := [
	[-11.0, 0.3, 2.05, 0.9, 2.45, 0.5, 2.75, 0.15, 2.9],
	[-8.5, 1.8, 1.55, 3.6, 2.7, 2.4, 4.3, 0.7, 5.0],
	[-4.0, 3.0, 1.15, 5.0, 2.9, 3.4, 5.4, 1.0, 6.4],
	[3.0, 3.2, 1.1, 5.0, 2.9, 3.4, 5.6, 1.0, 6.6],
	[7.0, 3.0, 1.1, 4.8, 2.9, 3.0, 5.8, 1.0, 6.5],
]

static var _meshes := {}             # "lander:2" / "lander:1" / "site" -> ArrayMesh


## The hull as one mesh. lod 2 adds armour plates, seams, vents, spine trim, exhaust petals, cannons, a turret and the ramp ribs.
static func lander_mesh(lod: int) -> ArrayMesh:
	var key := "lander:%d" % lod
	if not _meshes.has(key):
		_meshes[key] = _build_lander(lod).mesh()
	return _meshes[key]


static func _build_lander(lod: int) -> GunModels.Builder:
	var b := GunModels.Builder.new()
	var rot_ramp := Basis(Vector3.RIGHT, atan2(SILL_Y, RAMP_LEN))
	var hw := DOOR_W * 0.5
	# the faceted hull, nose to z = 7
	var rings: Array = []
	for s in SECTIONS:
		rings.append(_ring(_section(s), float(s[0])))
	_loft(b, rings, HULL)
	# the stern: the last section extruded to z = 10, cut into two cheeks, a lintel and a sill round the doorway
	var stern := _section(SECTIONS[SECTIONS.size() - 1])
	for sx in [-1.0, 1.0]:
		_loft(b, _prism(_clip(stern, 0, sx * hw, sx), 7.0, 10.0), HULL2)
	var mid_cut := _clip(_clip(stern, 0, -hw, 1.0), 0, hw, -1.0)
	_loft(b, _prism(_clip(mid_cut, 1, DOOR_TOP, 1.0), 7.0, 10.0), HULL2)
	_loft(b, _prism(_clip(mid_cut, 1, SILL_Y, -1.0), 7.0, 10.0), HULL2)
	# the alcove: dark lining, floor, the loading threshold (a cold white line) and a ceiling strip light, a glowing door frame
	b.box(Vector3(0, (SILL_Y + DOOR_TOP) * 0.5, 7.04), Vector3(DOOR_W, DOOR_TOP - SILL_Y, 0.06), DARKP)
	b.box(Vector3(0, DOOR_TOP - 0.03, 8.5), Vector3(DOOR_W, 0.06, 3.0), DARKP)
	b.box(Vector3(0, SILL_Y + 0.02, 8.5), Vector3(DOOR_W - 0.1, 0.04, 3.0), HULL2)
	b.box(Vector3(0, 2.1, 7.1), Vector3(DOOR_W - 0.3, 0.14, 0.12), COLD, true)
	b.box(Vector3(0, DOOR_TOP - 0.1, 8.4), Vector3(DOOR_W - 0.5, 0.06, 1.4), COLD, true)
	b.box(Vector3(0, DOOR_TOP + 0.08, 10.03), Vector3(DOOR_W + 0.3, 0.1, 0.06), ENERGY, true)
	# the canopy on the upper nose: dark glass with a glowing V along its brow
	var canopy: Array = []
	for c in [[-9.8, 0.35, 0.1], [-8.0, 1.1, 0.5], [-5.5, 1.0, 0.35]]:
		var sc := _section_at(float(c[0]))
		var y0: float = float(sc[8]) - 0.2
		var w: float = c[1]
		var h: float = c[2]
		canopy.append(_ring(PackedVector2Array([Vector2(-w, y0), Vector2(w, y0), Vector2(w * 0.6, y0 + h), Vector2(-w * 0.6, y0 + h)]), float(c[0])))
	_loft(b, canopy, GLASS)
	for k in [2, 3]:
		_bar(b, canopy[0][k], canopy[1][k], 0.06, ENERGY, true, 0.02)
	b.box(Vector3(0, 2.45, -11.04), Vector3(0.55, 0.1, 0.08), ALARM, true)                               # the sensor slit in the nose blade
	# a trim lip along both chines, a glowing seam under it amidships, the scorched keel plate
	for r in rings.size() - 1:
		for k in [2, 7]:
			_bar(b, rings[r][k], rings[r + 1][k], 0.14, TRIM, false, 0.04)
	for sx in [-1.0, 1.0]:
		_flank(b, 1.5, sx, true, 0.84, 0.9, 10.2, ENERGY, true)
	b.box(Vector3(0, 1.05, 1.25), Vector3(5.4, 0.12, 10.5), SOOT)
	for sx in [-1.0, 1.0]:
		# swept stub wings carrying the nacelles, a red light on each tip
		var rx: float = sx * 4.5
		var tx: float = sx * 7.8
		_loft(b, [PackedVector3Array([Vector3(rx, 2.95, -3.5), Vector3(rx, 3.1, 1.0), Vector3(rx, 2.95, 5.5), Vector3(rx, 2.8, 1.0)]),
				PackedVector3Array([Vector3(tx, 2.55, 3.4), Vector3(tx, 2.63, 4.6), Vector3(tx, 2.55, 5.7), Vector3(tx, 2.47, 4.6)])], HULL2)
		b.box(Vector3(sx * 7.84, 2.55, 4.6), Vector3(0.08, 0.1, 1.0), ALARM, true)
		# engine nacelles: a tapered body, an intake cowl that glows inside, a collar and the cold blue exhaust
		b.cyl(Vector3(sx * 5.9, 3.5, 3.3), 1.15, 6.6, HULL2, "z", false, 1.5, 12)
		b.box(Vector3(sx * 4.95, 3.55, 3.3), Vector3(1.3, 0.6, 4.6), PLATE)
		b.cyl(Vector3(sx * 5.9, 3.5, 0.05), 1.25, 0.4, PLATE, "z", false, -1.0, 12)
		b.cyl(Vector3(sx * 5.9, 3.5, -0.17), 0.85, 0.04, ENERGY, "z", true, -1.0, 12)
		b.cyl(Vector3(sx * 5.9, 3.5, 6.75), 1.55, 0.5, PLATE, "z", false, -1.0, 12)
		b.cyl(Vector3(sx * 5.9, 3.5, 7.02), 1.2, 0.08, ENERGY, "z", true, -1.0, 12)
		b.cyl(Vector3(sx * 5.9, 3.5, 7.08), 0.5, 0.1, SOOT, "z", false, -1.0, 8)
		# a fin on each nacelle, raked back and leaning out
		var fin_rot := Basis(Vector3.BACK, -sx * 0.3) * Basis(Vector3.RIGHT, 0.4)
		var fin_c := Vector3(sx * 6.3, 5.6, 5.0)
		b.box(fin_c, Vector3(0.14, 2.0, 2.4), HULL2, false, fin_rot)
		b.box(fin_c + fin_rot * Vector3(0, 1.0, 0.6), Vector3(0.18, 0.1, 0.5), ALARM, true, fin_rot)
		# four landing struts angled out to round foot pads
		for sz in [-5.5, 4.0]:
			var hip := Vector3(sx * 2.6, 1.2, sz)
			var foot := Vector3(sx * 3.9, 0.18, sz)
			b.box(hip, Vector3(1.0, 0.5, 1.0), HULL2)
			_bar(b, hip, foot, 0.42, DARKP, false, 0.0)
			b.cyl(foot - Vector3(0, 0.08, 0), 0.8, 0.2, HULL2, "y", false, -1.0, 10)
		# the ramp's side flanges
		b.box(Vector3(sx * (hw + 0.1), 0.95, 13.0), Vector3(0.2, 0.5, 6.1), HULL2, false, rot_ramp)
		b.box(Vector3(sx * (hw + 0.13), (SILL_Y + DOOR_TOP) * 0.5 + 0.04, 10.03), Vector3(0.1, DOOR_TOP - SILL_Y, 0.06), ENERGY, true)
	# the dorsal fin and its light
	var dfin := Basis(Vector3.RIGHT, 0.45)
	b.box(Vector3(0, 7.3, 5.0), Vector3(0.16, 1.6, 3.2), HULL2, false, dfin)
	b.box(Vector3(0, 7.3, 5.0) + dfin * Vector3(0, 0.8, 0.9), Vector3(0.2, 0.1, 0.6), ALARM, true, dfin)
	# the ramp: lowered from the sill (z = 10, y = 1.5) to the ground (z = 16)
	b.box(Vector3(0, SILL_Y * 0.5 + 0.03, 10.0 + RAMP_LEN * 0.5), Vector3(DOOR_W, 0.18, RAMP_LEN + 0.2), HULL, false, rot_ramp)
	if lod >= 2:
		# armour plates on both flanks, intake vents, the rest of the glowing seam, spine trim
		for sx in [-1.0, 1.0]:
			for i in 4:
				var z := -2.6 + float(i) * 2.4
				var shade := 0.92 + 0.16 * fposmod(float(i) * 0.618 + (0.3 if sx > 0.0 else 0.0), 1.0)
				_flank(b, z, sx, false, 0.08, 0.62, 2.1, Color(PLATE.r * shade, PLATE.g * shade, PLATE.b * shade))
				_flank(b, z, sx, true, 0.2, 0.72, 2.1, Color(HULL.r * shade * 1.1, HULL.g * shade * 1.1, HULL.b * shade * 1.1))
			for k in 3:
				_flank(b, -6.2 + float(k) * 0.55, sx, false, 0.2, 0.7, 0.18, DARKP, false, 0.05)
			_bar(b, rings[1][2 if sx > 0.0 else 7] + Vector3(0, -0.2, 0), rings[2][2 if sx > 0.0 else 7] + Vector3(0, -0.2, 0), 0.05, ENERGY, true, 0.03)
			# struts' pistons
			for sz in [-5.5, 4.0]:
				_bar(b, Vector3(sx * 2.3, 1.1, sz + 0.4), Vector3(sx * 3.6, 0.45, sz + 0.25), 0.16, TRIM, false, 0.0)
			# exhaust petals round each nozzle
			for p in 6:
				var a := TAU * float(p) / 6.0
				b.box(Vector3(sx * 5.9 + cos(a) * 1.45, 3.5 + sin(a) * 1.45, 7.2), Vector3(0.5, 0.5, 0.5), DARKP, false, Basis(Vector3.BACK, a))
			# glowing band round each nacelle and the ramp's edge lights
			b.cyl(Vector3(sx * 5.9, 3.5, 2.2), 1.35, 0.08, ENERGY, "z", true, -1.0, 12)
			_bar(b, Vector3(sx * (hw + 0.1), SILL_Y + 0.45, 10.0), Vector3(sx * (hw + 0.1), 0.45, 16.0), 0.05, ENERGY, true, 0.0)
			b.cyl(Vector3(sx * 1.8, 1.0, -1.5), 0.6, 0.06, ENERGY, "y", true, -1.0, 10)                              # repulsor pads under the belly
			b.cyl(Vector3(sx * 1.8, 1.0, 4.5), 0.6, 0.06, ENERGY, "y", true, -1.0, 10)
			b.cyl(Vector3(sx * 1.4, 7.4, 6.6), 0.04, 1.8, DARKP, "y", false, -1.0, 6)                                # antennas
		for r in rings.size() - 1:
			for k in [4, 5]:
				_bar(b, rings[r][k], rings[r + 1][k], 0.1, TRIM, false, 0.04)
		# seams across the hull
		for z in [-6.8, -1.2, 1.8, 5.6]:
			var sp := _section(_section_at(z))
			for k in 8:
				if k != 0:
					_bar(b, Vector3(sp[k].x, sp[k].y, z), Vector3(sp[(k + 1) % 8].x, sp[(k + 1) % 8].y, z), 0.06, DARKP, false, 0.03)
		# twin chin cannons and a dorsal turret
		b.box(Vector3(0, 1.3, -6.2), Vector3(2.4, 0.45, 2.2), DARKP)
		for sx in [-1.0, 1.0]:
			b.cyl(Vector3(sx * 0.7, 1.25, -8.4), 0.13, 3.0, DARKP, "z", false, -1.0, 8)
			b.box(Vector3(sx * 0.7, 1.25, -9.92), Vector3(0.12, 0.12, 0.04), ALARM, true)
		b.cyl(Vector3(0, 6.65, -1.5), 0.95, 0.5, PLATE, "y", false, -1.0, 12)
		b.box(Vector3(0, 7.05, -1.5), Vector3(1.2, 0.45, 1.4), HULL2)
		for sx in [-1.0, 1.0]:
			b.cyl(Vector3(sx * 0.25, 7.05, -3.0), 0.08, 1.8, DARKP, "z", false, -1.0, 6)
		# landing lights under the nose, ramp ribs
		b.box(Vector3(0, 1.6, -9.0), Vector3(1.2, 0.06, 0.3), COLD, true)
		for i in 6:
			var zz := 10.4 + float(i) * 0.95
			b.box(Vector3(0, SILL_Y - (zz - 10.0) * SILL_Y / RAMP_LEN + 0.13, zz), Vector3(DOOR_W - 0.4, 0.05, 0.12), DARKP, false, rot_ramp)
	return b


## The 2D outline (x, y) of a hull section: belly, chines, shoulders, spine.
static func _section(s: Array) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-s[1], s[2]), Vector2(s[1], s[2]), Vector2(s[3], s[4]), Vector2(s[5], s[6]),
			Vector2(s[7], s[8]), Vector2(-s[7], s[8]), Vector2(-s[5], s[6]), Vector2(-s[3], s[4])])


## The hull section at any z, blended between the two nearest `SECTIONS`.
static func _section_at(z: float) -> Array:
	for i in SECTIONS.size() - 1:
		var a: Array = SECTIONS[i]
		var c: Array = SECTIONS[i + 1]
		if z <= float(c[0]) or i == SECTIONS.size() - 2:
			var t := clampf((z - float(a[0])) / (float(c[0]) - float(a[0])), 0.0, 1.0)
			var out := []
			for k in a.size():
				out.append(lerpf(float(a[k]), float(c[k]), t))
			return out
	return SECTIONS[0]


static func _ring(poly: PackedVector2Array, z: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in poly:
		out.append(Vector3(p.x, p.y, z))
	return out


static func _prism(poly: PackedVector2Array, z0: float, z1: float) -> Array:
	return [_ring(poly, z0), _ring(poly, z1)]


## The part of a convex outline on one side of a line: keeps p[axis] * sgn >= val * sgn (Sutherland-Hodgman).
static func _clip(poly: PackedVector2Array, axis: int, val: float, sgn: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var ina: bool = (a[axis] - val) * sgn >= -0.0001
		var inc: bool = (c[axis] - val) * sgn >= -0.0001
		if ina:
			out.append(a)
		if ina != inc:
			var t: float = (val - a[axis]) / (c[axis] - a[axis])
			if t > 0.0001 and t < 0.9999:
				out.append(a.lerp(c, t))
	return out


## A flat-shaded skin through rings of equal point count (each a convex outline), the first and last ring capped.
static func _loft(b: GunModels.Builder, rings: Array, col: Color, glowing: bool = false) -> void:
	var d: GunModels.Surf = b.glow if glowing else b.lit
	for r in rings.size() - 1:
		var ra: PackedVector3Array = rings[r]
		var rb: PackedVector3Array = rings[r + 1]
		var inside := (_centroid(ra) + _centroid(rb)) * 0.5
		for k in ra.size():
			var j := (k + 1) % ra.size()
			_quad(d, ra[k], ra[j], rb[j], rb[k], col, inside)
	var first: PackedVector3Array = rings[0]
	var last: PackedVector3Array = rings[rings.size() - 1]
	var axis := (_centroid(last) - _centroid(first)).normalized()
	_cap(d, first, -axis, col)
	_cap(d, last, axis, col)


static func _centroid(ring: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	return c / float(ring.size())


static func _cap(d: GunModels.Surf, ring: PackedVector3Array, n: Vector3, col: Color) -> void:
	var c := _centroid(ring)
	for k in ring.size():
		_tri(d, c, ring[k], ring[(k + 1) % ring.size()], n, col)


static func _quad(d: GunModels.Surf, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, col: Color, inside: Vector3) -> void:
	var n := (p2 - p0).cross(p3 - p1)
	if n.length_squared() < 1.0e-8:
		return
	n = n.normalized()
	if n.dot((p0 + p1 + p2 + p3) * 0.25 - inside) < 0.0:
		n = -n
	_tri(d, p0, p1, p2, n, col)
	_tri(d, p0, p2, p3, n, col)


## One triangle, wound the way Builder.box winds its faces (front face towards n).
static func _tri(d: GunModels.Surf, p0: Vector3, p1: Vector3, p2: Vector3, n: Vector3, col: Color) -> void:
	if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:
		var t := p1
		p1 = p2
		p2 = t
	var a := d.vert(p0, n, col)
	d.vert(p1, n, col)
	d.vert(p2, n, col)
	d.i.append_array(PackedInt32Array([a, a + 1, a + 2]))


## A square bar from a to c (trim lips, glowing seams, struts), pushed `lift` metres out from the hull's long axis.
static func _bar(b: GunModels.Builder, a: Vector3, c: Vector3, thick: float, col: Color, glowing: bool = false, lift: float = 0.03) -> void:
	var dir := c - a
	if dir.length() < 0.01:
		return
	var mid := (a + c) * 0.5
	var out := Vector3(mid.x, mid.y - 3.8, 0.0).normalized()
	var up := Vector3.UP if absf(dir.normalized().y) < 0.95 else Vector3.BACK
	b.box(mid + out * lift, Vector3(thick, thick, dir.length()), col, glowing, Basis.looking_at(dir.normalized(), up))


## A slab lying on a flank facet at depth z, from fraction t0 to t1 of the way across it: the upper facet runs chine -> shoulder,
## the lower one belly -> chine.
static func _flank(b: GunModels.Builder, z: float, sx: float, lower: bool, t0: float, t1: float, along: float, col: Color, glowing: bool = false, lift: float = 0.06) -> void:
	var s := _section_at(z)
	var i0 := 1 if lower else 3
	var p0 := Vector3(sx * float(s[i0]), float(s[i0 + 1]), z)
	var p1 := Vector3(sx * float(s[i0 + 2]), float(s[i0 + 3]), z)
	var u := (p1 - p0).normalized()
	var n := u.cross(Vector3.BACK) * sx
	var p := p0.lerp(p1, (t0 + t1) * 0.5) + n * lift
	b.box(p, Vector3(0.1, (p1 - p0).length() * (t1 - t0), along), col, glowing, Basis(n, u, n.cross(u)))


## Collision boxes in model space: {c: centre, s: size, rx: pitch (the ramp)}. The hull is solid from the ground up; the doorway is an
## alcove (floor, side walls) closed at its back by the hull: the interior stays behind the loading threshold.
static func lander_boxes() -> Array:
	var out: Array = []
	out.append({"c": Vector3(0, HEIGHT * 0.5, 0.5), "s": Vector3(WIDTH, HEIGHT, 13.0), "rx": 0.0})                    # body z -6 .. 7
	out.append({"c": Vector3(0, 2.5, -8.25), "s": Vector3(7.0, 5.0, 4.5), "rx": 0.0})                                # the narrower nose z -10.5 .. -6
	for sx in [-1.0, 1.0]:
		out.append({"c": Vector3(sx * (DOOR_W * 0.5 + (WIDTH - DOOR_W) * 0.25), HEIGHT * 0.5, 8.5), "s": Vector3((WIDTH - DOOR_W) * 0.5, HEIGHT, 3.0), "rx": 0.0})   # beside the doorway
		out.append({"c": Vector3(sx * 5.9, 3.5, 3.5), "s": Vector3(2.9, 3.0, 7.0), "rx": 0.0})                         # engine pods
	out.append({"c": Vector3(0, 5.3, 8.5), "s": Vector3(DOOR_W, 1.4, 3.0), "rx": 0.0})                                # header over the door
	out.append({"c": Vector3(0, SILL_Y * 0.5, 8.5), "s": Vector3(DOOR_W, SILL_Y, 3.0), "rx": 0.0})                    # the alcove floor
	var a := atan2(SILL_Y, RAMP_LEN)
	out.append({"c": Vector3(0, SILL_Y * 0.5 - 0.02, 10.0 + RAMP_LEN * 0.5), "s": Vector3(DOOR_W, 0.3, RAMP_LEN / cos(a)), "rx": a})   # the ramp
	return out


## World position (given the ship's transform) of the top of the ramp / the loading threshold, and the foot of the ramp.
static func ramp_top_local() -> Vector3:
	return Vector3(0, SILL_Y, 10.0)


static func ramp_foot_local() -> Vector3:
	return Vector3(0, 0.0, 10.0 + RAMP_LEN)


## The ground the craft came down on: a scorched ring with burn streaks, crushed flowerbeds with spilled petals, three trees it knocked
## over (a trunk and a flattened crown each) and a bench smashed to planks. Model space again (the ship's origin on the ground).
static func site_mesh() -> ArrayMesh:
	if _meshes.has("site"):
		return _meshes["site"]
	var b := GunModels.Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	var soil := Color(0.2, 0.15, 0.1)
	# scorch: two dark discs and streaks blown outwards
	b.cyl(Vector3(0, 0.05, 0), 15.0, 0.03, Color(0.12, 0.11, 0.08), "y", false, -1.0, 20)
	b.cyl(Vector3(0, 0.07, 1.0), 10.5, 0.03, SOOT, "y", false, -1.0, 20)
	for i in 14:
		var a := TAU * float(i) / 14.0 + rng.randf_range(-0.15, 0.15)
		var len := rng.randf_range(5.0, 9.0)
		var r := 11.0 + len * 0.5
		b.box(Vector3(cos(a) * r, 0.065, sin(a) * r), Vector3(rng.randf_range(0.6, 1.4), 0.02, len), Color(0.08, 0.075, 0.06), false, Basis(Vector3.UP, -a + PI * 0.5))
	# crushed flowerbeds round the ship: churned soil with flattened stems and petals
	for bed in [Vector3(-10.5, 0, -8.0), Vector3(-9.5, 0, 6.5), Vector3(10.0, 0, -9.0), Vector3(11.0, 0, 2.0), Vector3(-3.0, 0, -13.0), Vector3(4.0, 0, 14.5)]:
		var yaw := rng.randf_range(0.0, PI)
		b.box(bed + Vector3(0, 0.1, 0), Vector3(3.6, 0.2, 1.4), soil, false, Basis(Vector3.UP, yaw))
		b.box(bed + Vector3(0, 0.22, 0), Vector3(3.0, 0.05, 0.9), Color(0.22, 0.34, 0.14), false, Basis(Vector3.UP, yaw + 0.1))
		for k in 7:
			var off := Basis(Vector3.UP, yaw) * Vector3(rng.randf_range(-1.6, 1.6), 0.26, rng.randf_range(-0.6, 0.6))
			var col := [Color(0.85, 0.2, 0.25), Color(0.95, 0.8, 0.2), Color(0.9, 0.5, 0.7), Color(0.95, 0.95, 0.95)][rng.randi() % 4] as Color
			b.box(bed + off, Vector3(0.22, 0.04, 0.22), col, false, Basis(Vector3.UP, rng.randf() * TAU))
	# trees that were knocked over: trunk + flattened crown, lying away from the hull
	for tr in [[Vector3(-8.5, 0, -2.0), 3.0], [Vector3(9.5, 0, -6.0), 0.2], [Vector3(2.5, 0, -12.5), -1.4]]:
		var yaw2: float = tr[1]
		var base: Vector3 = tr[0]
		var bas := Basis(Vector3.UP, yaw2)
		b.box(base + bas * Vector3(0, 0.3, 0), Vector3(0.55, 0.55, 6.5), Color(0.34, 0.24, 0.15), false, bas)
		b.box(base + bas * Vector3(0, 0.55, -4.6), Vector3(4.2, 1.1, 3.6), Color(0.14, 0.27, 0.12), false, bas)
		b.box(base + bas * Vector3(0.6, 0.9, -4.2), Vector3(2.8, 0.9, 2.6), Color(0.18, 0.33, 0.14), false, bas)
		b.box(base + bas * Vector3(0, 0.15, 3.4), Vector3(1.4, 0.3, 0.9), Color(0.3, 0.2, 0.12), false, bas)        # the torn root plate
	for k in 5:
		b.box(Vector3(-6.0 + rng.randf_range(-1.5, 1.5), 0.1, 9.0 + rng.randf_range(-1.5, 1.5)), Vector3(1.4, 0.06, 0.16), Color(0.45, 0.32, 0.2), false, Basis(Vector3.UP, rng.randf() * TAU))   # planks
	_meshes["site"] = b.mesh()
	return _meshes["site"]


# ================================================================== the node

## The landing craft in the world: hull mesh (distance LOD), the ground patch, the collider body (meta "hull" lets bullets spark),
## the loading threshold area, two heat-shimmer columns, a spark, and the descent (`begin_landing`).
class Lander extends Node3D:
	signal touched_down
	signal entered_threshold

	const DROP_H := 70.0
	const DROP_TIME := 9.0

	var hull: MeshInstance3D
	var site: MeshInstance3D
	var body: StaticBody3D
	var threshold: Area3D
	var shimmer: Array[MeshInstance3D] = []
	var lod := -1
	var landed := false
	var _fall_t := -1.0                    # 0 .. DROP_TIME while descending, -1 otherwise
	var _spark_light: OmniLight3D
	var _spark_fx: CPUParticles3D
	var _spark_t := 0.0
	var _engine: AudioStreamPlayer3D
	var _dust: CPUParticles3D

	func _init() -> void:
		visible = false

	func build() -> void:
		site = MeshInstance3D.new()
		site.mesh = ShipModels.site_mesh()
		site.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		site.material_override = _vertex_material()
		add_child(site)
		hull = MeshInstance3D.new()
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(hull)
		set_lod(1)
		body = StaticBody3D.new()
		body.collision_layer = Game.L_WORLD
		body.collision_mask = 0
		body.set_meta("hull", self)
		for bx in ShipModels.lander_boxes():
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = bx["s"]
			cs.shape = sh
			cs.transform = Transform3D(Basis(Vector3.RIGHT, float(bx["rx"])), bx["c"])
			body.add_child(cs)
		hull.add_child(body)
		threshold = Area3D.new()
		threshold.collision_layer = 0
		threshold.collision_mask = Game.L_PLAYER
		var tcs := CollisionShape3D.new()
		var tsh := BoxShape3D.new()
		tsh.size = Vector3(ShipModels.DOOR_W - 0.6, 2.6, 1.6)
		tcs.shape = tsh
		tcs.position = Vector3(0, ShipModels.SILL_Y + 1.4, 8.4)
		threshold.add_child(tcs)
		threshold.body_entered.connect(func(n: Node3D) -> void:
			if n is Player and landed:
				entered_threshold.emit())
		hull.add_child(threshold)
		# heat shimmer rising from the engines (the Veil's additive column shader on two billboards: no particles)
		var shader := Shader.new()
		shader.code = Veil.SHIMMER_SHADER
		var smat := ShaderMaterial.new()
		smat.shader = shader
		var quad := QuadMesh.new()
		quad.size = Vector2(5.0, 13.0)
		quad.center_offset = Vector3(0, 0.5, 0)
		for sx in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = smat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3(sx * 5.9, 4.8, 5.0)
			mi.extra_cull_margin = 8.0
			hull.add_child(mi)
			shimmer.append(mi)
		# one spark (a shell hit the hull): a light that flashes 0.12 s and a puff of bright particles, both reused
		_spark_light = OmniLight3D.new()
		_spark_light.light_color = Color(1.0, 0.85, 0.5)
		_spark_light.light_energy = 5.0
		_spark_light.omni_range = 8.0
		_spark_light.shadow_enabled = false
		_spark_light.visible = false
		_spark_light.top_level = true
		add_child(_spark_light)
		_spark_fx = CPUParticles3D.new()
		_spark_fx.one_shot = true
		_spark_fx.emitting = false
		_spark_fx.amount = 22
		_spark_fx.lifetime = 0.5
		_spark_fx.explosiveness = 1.0
		_spark_fx.spread = 60.0
		_spark_fx.initial_velocity_min = 3.0
		_spark_fx.initial_velocity_max = 9.0
		_spark_fx.gravity = Vector3(0, -14, 0)
		_spark_fx.top_level = true
		var sm := BoxMesh.new()
		sm.size = Vector3(0.05, 0.05, 0.16)
		var smat2 := StandardMaterial3D.new()
		smat2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat2.albedo_color = Color(1.0, 0.92, 0.6)
		smat2.disable_fog = true
		sm.material = smat2
		_spark_fx.mesh = sm
		add_child(_spark_fx)
		# dust thrown up at touchdown
		_dust = CPUParticles3D.new()
		_dust.one_shot = true
		_dust.emitting = false
		_dust.amount = 36
		_dust.lifetime = 2.2
		_dust.explosiveness = 0.9
		_dust.direction = Vector3.UP
		_dust.spread = 90.0
		_dust.initial_velocity_min = 3.0
		_dust.initial_velocity_max = 9.0
		_dust.gravity = Vector3(0, -1.0, 0)
		_dust.damping_min = 2.0
		_dust.damping_max = 4.0
		var dm := QuadMesh.new()
		dm.size = Vector2(3.0, 3.0)
		var dmat := StandardMaterial3D.new()
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.albedo_color = Color(0.5, 0.45, 0.38, 0.35)
		dmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		dm.material = dmat
		_dust.mesh = dm
		_dust.position = Vector3(0, 0.5, 0)
		add_child(_dust)
		_engine = AudioStreamPlayer3D.new()
		_engine.stream = Sfx.get_sound("hum")
		_engine.max_distance = 260.0
		_engine.unit_size = 40.0
		_engine.volume_db = 6.0
		add_child(_engine)
		set_process(false)
		_set_colliders(false)

	static func _vertex_material() -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.95
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		return m

	func set_lod(l: int) -> void:
		if l == lod:
			return
		lod = l
		hull.mesh = ShipModels.lander_mesh(l)

	## Called every few tenths of a second with the player's distance.
	func update_lod(dist: float) -> void:
		set_lod(2 if dist < ShipModels.NEAR_LOD_DIST else 1)
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if dist < 140.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _set_colliders(on: bool) -> void:
		for c in body.get_children():
			(c as CollisionShape3D).disabled = not on
		threshold.monitoring = on

	## The craft comes down out of the sky over DROP_TIME seconds, throws up dust and is solid from then on.
	func begin_landing() -> void:
		if landed or _fall_t >= 0.0:
			return
		visible = true
		_fall_t = 0.0
		hull.position.y = DROP_H
		_set_colliders(false)
		_engine.pitch_scale = 0.5
		_engine.play()
		set_process(true)

	func land_now() -> void:
		visible = true
		_fall_t = -1.0
		hull.position = Vector3.ZERO
		hull.rotation = Vector3.ZERO
		landed = true
		_set_colliders(true)
		_engine.stop()
		set_process(false)

	func hide_ship() -> void:
		visible = false
		landed = false
		_fall_t = -1.0
		_set_colliders(false)
		_engine.stop()
		set_process(false)

	func _process(delta: float) -> void:
		if _fall_t >= 0.0:
			_fall_t += delta
			var k := clampf(_fall_t / DROP_TIME, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - k, 2.6)             # fast at first, settling gently at the end
			hull.position.y = DROP_H * (1.0 - e)
			hull.rotation = Vector3(sin(_fall_t * 1.3) * 0.02 * (1.0 - e), sin(_fall_t * 0.5) * 0.03 * (1.0 - e), cos(_fall_t * 1.7) * 0.02 * (1.0 - e))
			_engine.pitch_scale = lerpf(0.5, 0.8, e)
			if k >= 1.0:
				_fall_t = -1.0
				hull.position = Vector3.ZERO
				hull.rotation = Vector3.ZERO
				landed = true
				_set_colliders(true)
				_engine.stop()
				_dust.restart()
				Sfx.play_at(get_tree().current_scene, global_position + Vector3(0, 3, 0), "far_boom", 8.0, 1.0, 400.0, 60.0)
				touched_down.emit()
				if _spark_t <= 0.0:
					set_process(false)
		if _spark_t > 0.0:
			_spark_t -= delta
			if _spark_t <= 0.0:
				_spark_light.visible = false
				if _fall_t < 0.0:
					set_process(false)

	## A shell hit the hull at `pos`: a bright spark.
	func spark(pos: Vector3, normal: Vector3) -> void:
		_spark_light.global_position = pos + normal * 0.6
		_spark_light.visible = true
		_spark_fx.global_position = pos + normal * 0.05
		_spark_fx.direction = normal
		_spark_fx.restart()
		_spark_t = 0.12
		set_process(true)
