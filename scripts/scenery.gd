class_name Scn
## Collector for the small scenery the war left behind (barriers, planters, beams, rubble, road marks...). City and its helper
## classes push plain data in here during generation; WorldWar turns it into MultiMeshes (one draw call per mesh type) and
## simple box / cylinder colliders. Nothing here is a node.
##   parts   : unit meshes with a transform and an sRGB colour each ("box", "cyl", "sphere", "cone", "col" = tapered smoke column,
##             "fire" = a sphere drawn by the flickering fire shader)
##   decals  : flat marks on the asphalt ("paint", "dark", "debris" boxes, "disc" cylinders)
##   colliders / cyl_colliders : what the player and bullets hit
##   blocks  : rectangles the navigation grid must treat as solid
##   fires   : things that burn or spark (Fires shows flames, smoke and a few lights only near the player)

static var parts := {"box": [], "cyl": [], "sphere": [], "cone": [], "col": [], "fire": [], "glow": [], "glass": []}
static var decals := {"paint": [], "dark": [], "debris": [], "disc": []}
static var colliders: Array = []        # {xf: Transform3D, size: Vector3}
static var cyl_colliders: Array = []    # {pos: Vector3 (base centre), r: float, h: float}
static var kerbs: Array = []            # Rect2: raised pavement edges (only the player collides with these)
static var blocks: Array = []           # {rect: Rect2, margin: float}
static var fires: Array = []            # {kind: String, pos: Vector3, s: float}
static var lamps: Array = []            # Vector3: standing street lamps (decor + thin collider)


static func reset() -> void:
	for k in parts:
		parts[k] = []
	for k in decals:
		decals[k] = []
	colliders = []
	cyl_colliders = []
	kerbs = []
	blocks = []
	fires = []
	lamps = []


## A rotated (yaw) box of `size` centred at `c`; `extra` is an additional local rotation (tilt) applied before the yaw.
static func box_xf(c: Vector3, size: Vector3, yaw: float = 0.0, extra: Basis = Basis.IDENTITY) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * extra * Basis.from_scale(size), c)


static func box(c: Vector3, size: Vector3, color: Color, yaw: float = 0.0, extra: Basis = Basis.IDENTITY) -> void:
	(parts["box"] as Array).append([box_xf(c, size, yaw, extra), color])


static func part(kind: String, xf: Transform3D, color: Color) -> void:
	(parts[kind] as Array).append([xf, color])


## A cylinder (or any of the unit meshes whose long axis is y) running from a to b with diameter `d`.
static func between(kind: String, a: Vector3, b: Vector3, d: float, color: Color) -> void:
	part(kind, between_xf(a, b, d), color)


static func between_xf(a: Vector3, b: Vector3, d: float) -> Transform3D:
	var dir := b - a
	var len := dir.length()
	var y := dir / maxf(len, 0.0001)
	var ref := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	var x := y.cross(ref).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x * d, y * len, z * d), (a + b) * 0.5)


## A solid box for bullets and feet. `size` is the full size, `c` the centre.
static func solid(c: Vector3, size: Vector3, yaw: float = 0.0, extra: Basis = Basis.IDENTITY) -> void:
	colliders.append({"xf": Transform3D(Basis(Vector3.UP, yaw) * extra, c), "size": size})


static func solid_xf(xf: Transform3D, size: Vector3) -> void:
	colliders.append({"xf": xf, "size": size})


static func cyl_solid(base: Vector3, r: float, h: float) -> void:
	cyl_colliders.append({"pos": base, "r": r, "h": h})


static func block(rect: Rect2, margin: float = 0.3) -> void:
	blocks.append({"rect": rect, "margin": margin})


## The axis-aligned footprint of a yawed rectangle (half sizes `half`) centred on `c`.
static func footprint(c: Vector2, half: Vector2, yaw: float) -> Rect2:
	var cs := absf(cos(yaw))
	var sn := absf(sin(yaw))
	var e := Vector2(cs * half.x + sn * half.y, sn * half.x + cs * half.y)
	return Rect2(c - e, e * 2.0)


static func fire(kind: String, pos: Vector3, s: float = 1.0) -> void:
	fires.append({"kind": kind, "pos": pos, "s": s})


## Decals lie flat on the ground: `kind` paint / dark / debris are boxes (size x, z; thickness 0.02), disc is a cylinder.
static func decal(kind: String, c: Vector2, size: Vector2, yaw: float, color: Color, y: float = 0.0) -> void:
	var h := 0.02
	var base_y := 0.03 if kind == "paint" else (0.042 if kind == "dark" else (0.052 if kind == "disc" else 0.06))
	if y > 0.0:
		base_y = y
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(size.x, h if kind != "debris" else 0.05, size.y)), Vector3(c.x, base_y, c.y))
	(decals[kind] as Array).append([xf, color])


## Small spatial hash of rectangles, so the generators can ask "is this spot taken?" quickly.
class Occ:
	var cells := {}
	const CELL := 8.0

	func add(r: Rect2) -> void:
		for k in _keys(r):
			if not cells.has(k):
				cells[k] = []
			(cells[k] as Array).append(r)

	func hits(r: Rect2, pad: float = 0.0) -> bool:
		var g := r.grow(pad)
		for k in _keys(g):
			if cells.has(k):
				for o in cells[k]:
					if (o as Rect2).intersects(g):
						return true
		return false

	func _keys(r: Rect2) -> Array:
		var out: Array = []
		for ix in range(floori(r.position.x / CELL), floori(r.end.x / CELL) + 1):
			for iz in range(floori(r.position.y / CELL), floori(r.end.y / CELL) + 1):
				out.append(Vector2i(ix, iz))
		return out
