class_name GunModels
## Procedural weapon models: each weapon is a few dozen boxes and cylinders (barrels, handguards, magazines, grips, stocks,
## optics, glowing coils) merged into ONE mesh with two surfaces (lit + glowing), cached per weapon and detail level, so
## 40 soldiers holding the same gun share it. The same geometry gives the viewmodel (lod 2), the gun in an enemy's hands
## and the pick-up on the ground (lod 1), and the side-on silhouette the HUD draws (profile()).
##
## Guns are built with the barrel along -z, the top of the receiver at y = 0 and the middle of the gun's length at z = 0,
## the muzzle at z = -length / 2. Everything except the iron sights stays at or below y = 0, so aiming along the sights
## never looks through the gun (see Weapons._ads_pos). Melee weapons are built with the guard at the origin, the blade
## along -z and the grip behind it (+z).

const SIGHT_H := 0.02          # keep equal to Weapons.SIGHT_H

const METAL := Color(0.17, 0.18, 0.21)
const DARK := Color(0.07, 0.07, 0.08)
const POLY := Color(0.11, 0.11, 0.12)
const STEEL := Color(0.62, 0.64, 0.68)
const LIGHT := Color(0.32, 0.34, 0.38)
const TAN := Color(0.42, 0.37, 0.28)
const WHITE := Color(1.0, 1.0, 1.0)

const FACES := [
	[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
	[Vector3.LEFT, Vector3.BACK, Vector3.UP],
	[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
	[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
	[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
]

static var _meshes := {}       # "id:lod" -> ArrayMesh
static var _profiles := {}     # id -> Array of [Rect2, Color, glow]


## One surface worth of geometry.
class Surf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func vert(p: Vector3, nrm: Vector3, col: Color) -> int:
		v.append(p)
		n.append(nrm)
		c.append(col)
		return v.size() - 1


## Collects parts, then turns them into one two-surface mesh (lit + glowing).
class Builder:
	var lit := Surf.new()
	var glow := Surf.new()
	var rects: Array = []      # side view: [Rect2 (z, y), Color, glow]

	func box(centre: Vector3, size: Vector3, col: Color, glowing: bool = false, rot: Basis = Basis.IDENTITY) -> void:
		var d: Surf = glow if glowing else lit
		var half := size * 0.5
		for f in GunModels.FACES:
			var n: Vector3 = f[0]
			var u: Vector3 = f[1]
			var v: Vector3 = f[2]
			var c := Vector3(n.x * half.x, n.y * half.y, n.z * half.z)
			var uu := u * (absf(u.x) * half.x + absf(u.y) * half.y + absf(u.z) * half.z)
			var vv := v * (absf(v.x) * half.x + absf(v.y) * half.y + absf(v.z) * half.z)
			var nn := (rot * n).normalized()
			var a := d.vert(centre + rot * (c - uu - vv), nn, col)
			d.vert(centre + rot * (c + uu - vv), nn, col)
			d.vert(centre + rot * (c + uu + vv), nn, col)
			d.vert(centre + rot * (c - uu + vv), nn, col)
			d.i.append_array(PackedInt32Array([a, a + 2, a + 1, a, a + 3, a + 2]))
		_rect(centre, rot, half, col, glowing)

	## A cylinder (or cone: r2 >= 0 gives the radius at +z) along an axis: "z" (barrel direction), "x" or "y".
	func cyl(centre: Vector3, radius: float, length: float, col: Color, axis: String = "z", glowing: bool = false, r2: float = -1.0, segs: int = 8) -> void:
		var d: Surf = glow if glowing else lit
		var rot := Basis.IDENTITY
		if axis == "x":
			rot = Basis().rotated(Vector3.UP, PI * 0.5)
		elif axis == "y":
			rot = Basis().rotated(Vector3.RIGHT, PI * 0.5)
		var rb := radius if r2 < 0.0 else r2
		var h := length * 0.5
		var base := d.v.size()
		for k in segs:
			var a := TAU * float(k) / float(segs)
			var nn := (rot * Vector3(cos(a), sin(a), 0.0)).normalized()
			d.vert(centre + rot * Vector3(cos(a) * radius, sin(a) * radius, -h), nn, col)
			d.vert(centre + rot * Vector3(cos(a) * rb, sin(a) * rb, h), nn, col)
		for k in segs:
			var j := (k + 1) % segs
			var a0 := base + k * 2
			var b0 := base + j * 2
			d.i.append_array(PackedInt32Array([a0, a0 + 1, b0, b0, a0 + 1, b0 + 1]))
		for end in 2:
			var cn := (rot * Vector3(0, 0, -1.0 if end == 0 else 1.0)).normalized()
			var r_end := radius if end == 0 else rb
			var cz := -h if end == 0 else h
			var cb := d.vert(centre + rot * Vector3(0, 0, cz), cn, col)
			for k in segs:
				var a2 := TAU * float(k) / float(segs)
				d.vert(centre + rot * Vector3(cos(a2) * r_end, sin(a2) * r_end, cz), cn, col)
			for k in segs:
				d.i.append_array(PackedInt32Array([cb, cb + 1 + k, cb + 1 + (k + 1) % segs]))
		var rm := maxf(radius, rb)
		var ext := Vector3(rm, rm, h)
		if axis == "x":
			ext = Vector3(h, rm, rm)
		elif axis == "y":
			ext = Vector3(rm, h, rm)
		_rect(centre, Basis.IDENTITY, ext, col, glowing)

	func _rect(centre: Vector3, rot: Basis, half: Vector3, col: Color, glowing: bool) -> void:
		var lo := Vector2(1.0e9, 1.0e9)
		var hi := Vector2(-1.0e9, -1.0e9)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p := centre + rot * Vector3(sx * half.x, sy * half.y, sz * half.z)
					lo = Vector2(minf(lo.x, p.z), minf(lo.y, p.y))
					hi = Vector2(maxf(hi.x, p.z), maxf(hi.y, p.y))
		rects.append([Rect2(lo, hi - lo), col, glowing])

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		for pair in [[lit, false], [glow, true]]:
			var d: Surf = pair[0]
			if d.v.is_empty():
				continue
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = d.v
			arr[Mesh.ARRAY_NORMAL] = d.n
			arr[Mesh.ARRAY_COLOR] = d.c
			arr[Mesh.ARRAY_INDEX] = d.i
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mat := StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.vertex_color_is_srgb = true
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			if bool(pair[1]):
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			else:
				mat.roughness = 0.8
				mat.metallic = 0.05
				mat.metallic_specular = 0.3
			m.surface_set_material(m.get_surface_count() - 1, mat)
		return m


# ---------------------------------------------------------------- public API

static func _builder_for(id: String, lod: int) -> Builder:
	var b := Builder.new()
	var g: Color = WeaponsDB.WEAPONS[id].get("glow", Color(0.9, 0.7, 0.3))
	var length: float = WeaponsDB.WEAPONS[id]["length"]
	match id:
		"pistol":
			_pistol(b, lod)
		"rifle":
			_rifle(b, lod, g, length)
		"carbine":
			_carbine(b, lod, g, length)
		"hmg":
			_hmg(b, lod, g, length)
		"railgun":
			_railgun(b, lod, g)
		"sniper":
			_longrifle(b, lod, g, length)
		"knife":
			_knife(b, lod, g)
		"blade":
			_blade(b, lod, g)
		_:
			b.box(Vector3(0, -0.03, 0), Vector3(0.05, 0.06, length), METAL)
	return b


## A MeshInstance3D with the weapon (shared, cached mesh). lod 2 = full detail, 1 = for the world (pick-ups, soldiers' hands).
static func build(id: String, lod: int = 1) -> MeshInstance3D:
	var key := "%s:%d" % [id, lod]
	if not _meshes.has(key):
		_meshes[key] = _builder_for(id, lod).mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Side-on silhouette for the HUD: [Rect2 (x = z, y), Color, glow] in metres, barrel towards -x... see HUD._Icon.
static func profile(id: String) -> Array:
	if not _profiles.has(id):
		_profiles[id] = _builder_for(id, 1).rects
	return _profiles[id]


## Where the hand holds the weapon (a point on the grip), in model space.
static func grip(id: String) -> Vector3:
	match id:
		"pistol":
			return Vector3(0, -0.11, 0.07)
		"rifle":
			return Vector3(0, -0.11, 0.13)
		"carbine":
			return Vector3(0, -0.14, 0.15)
		"hmg":
			return Vector3(0, -0.19, 0.24)
		"railgun":
			return Vector3(0, -0.14, 0.2)
		"sniper":
			return Vector3(0, -0.15, 0.2)
		"knife":
			return Vector3(0, 0, 0.065)
		"blade":
			return Vector3(0, 0, 0.11)
	return Vector3.ZERO


## The muzzle (or blade tip), in model space.
static func muzzle(id: String) -> Vector3:
	match id:
		"pistol":
			return Vector3(0, -0.02, -0.15)
		"rifle":
			return Vector3(0, -0.04, -0.475)
		"carbine":
			return Vector3(0, -0.045, -0.378)
		"hmg":
			return Vector3(0, -0.06, -0.485)
		"railgun":
			return Vector3(0, -0.0475, -0.58)
		"sniper":
			return Vector3(0, -0.045, -0.68)
	return Vector3(0, 0, -0.3)


# ---------------------------------------------------------------- the weapons

static func _sights(b: Builder, length: float, col: Color, g: Color) -> void:
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.016, SIGHT_H * 0.5, length * 0.25), Vector3(0.008, SIGHT_H, 0.012), col)
	b.box(Vector3(0, SIGHT_H * 0.5, -length * 0.45), Vector3(0.006, SIGHT_H, 0.008), col)
	b.box(Vector3(0, SIGHT_H, -length * 0.45), Vector3(0.003, 0.003, 0.003), g, true)


static func _pistol(b: Builder, lod: int) -> void:
	b.box(Vector3(0, -0.02, 0.0), Vector3(0.03, 0.04, 0.2), METAL)                          # slide
	b.box(Vector3(0, -0.055, 0.0), Vector3(0.028, 0.03, 0.18), POLY)                        # frame
	b.cyl(Vector3(0, -0.02, -0.12), 0.009, 0.04, STEEL)                                      # barrel tip
	b.box(Vector3(0, -0.11, 0.07), Vector3(0.03, 0.095, 0.05), POLY, false, Basis().rotated(Vector3.RIGHT, -0.25))   # grip
	b.box(Vector3(0, -0.08, 0.0), Vector3(0.01, 0.015, 0.07), DARK)                         # trigger guard
	b.box(Vector3(0, -0.16, 0.075), Vector3(0.032, 0.008, 0.052), DARK)                     # magazine base
	b.box(Vector3(0, 0.007, 0.09), Vector3(0.012, 0.014, 0.01), DARK)                       # sights
	b.box(Vector3(0, 0.006, -0.1), Vector3(0.006, 0.012, 0.008), DARK)
	if lod >= 2:
		for k in 3:
			b.box(Vector3(0.0, -0.02, 0.05 + k * 0.012), Vector3(0.032, 0.03, 0.005), DARK)   # slide serrations


## PR-1 pulse rifle (the invaders' own rifle, formerly the M4): long, slim and humming. A bone-pale shroud over a graphite
## receiver, a white glowing channel down both flanks, an emitter ring at the muzzle, a skeletal stock and a charge cell in front of the grip.
static func _rifle(b: Builder, lod: int, g: Color, length: float) -> void:
	var bone := Color(0.78, 0.74, 0.66)
	var rust := Color(0.34, 0.19, 0.12)
	b.box(Vector3(0, -0.04, 0.03), Vector3(0.05, 0.075, 0.44), Color(0.14, 0.13, 0.14))   # graphite receiver
	b.box(Vector3(0, -0.03, -0.2), Vector3(0.042, 0.052, 0.34), bone)                         # shroud
	b.box(Vector3(0, -0.012, -0.2), Vector3(0.02, 0.012, 0.3), DARK)                          # top spine
	b.cyl(Vector3(0, -0.035, -0.42), 0.012, 0.1, STEEL)                                        # barrel
	b.cyl(Vector3(0, -0.035, -0.462), 0.022, 0.016, g, "z", true)                             # emitter ring
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.0225, -0.03, -0.2), Vector3(0.004, 0.012, 0.32), g, true)         # glowing channel on the flanks
		b.box(Vector3(sx * 0.0265, -0.04, 0.03), Vector3(0.003, 0.012, 0.3), g, true)
	b.box(Vector3(0, -0.04, 0.3), Vector3(0.034, 0.03, 0.18), DARK)                           # skeletal stock: upper rail
	b.box(Vector3(0, -0.085, 0.3), Vector3(0.034, 0.024, 0.18), DARK)                         # lower rail
	b.box(Vector3(0, -0.06, 0.395), Vector3(0.04, 0.09, 0.016), rust)                         # butt pad
	b.box(Vector3(0, -0.105, -0.03), Vector3(0.036, 0.075, 0.09), DARK)                       # charge cell
	b.box(Vector3(0, -0.11, 0.13), Vector3(0.03, 0.09, 0.04), POLY, false, Basis().rotated(Vector3.RIGHT, -0.3))      # grip
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.019, -0.105, -0.03), Vector3(0.003, 0.05, 0.05), g, true)      # cell charge strips
			b.box(Vector3(sx * 0.0255, -0.045, 0.2), Vector3(0.004, 0.04, 0.12), rust)         # rust side plates
		b.box(Vector3(0, -0.098, 0.115), Vector3(0.008, 0.028, 0.008), DARK)                    # trigger
		b.box(Vector3(0, -0.09, 0.095), Vector3(0.01, 0.012, 0.07), DARK)                       # trigger guard
	_sights(b, length, DARK, g)


## PC-24: a bullpup in pale armour grey (like the rifleman's own gun): the cell sits behind the grip, a low sensor rail on top.
static func _carbine(b: Builder, lod: int, g: Color, length: float) -> void:
	var hull := Color(0.76, 0.78, 0.82)
	b.box(Vector3(0, -0.05, 0.12), Vector3(0.07, 0.1, 0.52), hull)                          # receiver and stock in one piece
	b.box(Vector3(0, -0.055, 0.17), Vector3(0.074, 0.05, 0.2), DARK)                        # dark side panels
	b.box(Vector3(0, -0.04, -0.24), Vector3(0.064, 0.08, 0.28), hull)                       # handguard
	b.box(Vector3(0, -0.03, -0.25), Vector3(0.068, 0.028, 0.2), DARK)
	b.cyl(Vector3(0, -0.045, -0.34), 0.013, 0.08, STEEL)                                     # barrel
	b.cyl(Vector3(0, -0.045, -0.335), 0.026, 0.016, g, "z", true)                            # emitter ring
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.0365, -0.045, -0.24), Vector3(0.004, 0.014, 0.17), g, true)    # energy strips on the flanks
	b.box(Vector3(0, 0.008, 0.02), Vector3(0.032, 0.016, 0.24), DARK)                       # low sensor rail
	b.box(Vector3(0, 0.014, -0.08), Vector3(0.02, 0.006, 0.05), g, true)                    # sensor lens
	b.box(Vector3(0, -0.1, -0.12), Vector3(0.032, 0.09, 0.04), POLY, false, Basis().rotated(Vector3.RIGHT, 0.2))    # foregrip
	b.box(Vector3(0, -0.14, 0.15), Vector3(0.034, 0.1, 0.042), POLY, false, Basis().rotated(Vector3.RIGHT, -0.3))   # pistol grip
	b.box(Vector3(0, -0.115, 0.27), Vector3(0.05, 0.13, 0.07), DARK, false, Basis().rotated(Vector3.RIGHT, 0.12))   # energy cell (behind the grip)
	b.box(Vector3(0, -0.05, 0.382), Vector3(0.072, 0.1, 0.012), DARK)                       # butt pad
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.0255, -0.115, 0.27), Vector3(0.003, 0.08, 0.02), g, true)   # cell charge strip
			b.box(Vector3(sx * 0.037, -0.03, 0.34), Vector3(0.004, 0.03, 0.08), DARK)         # vents
		b.box(Vector3(0, -0.1, 0.1), Vector3(0.01, 0.012, 0.08), DARK)                        # trigger guard
		b.box(Vector3(0, -0.11, 0.115), Vector3(0.008, 0.03, 0.008), DARK)                    # trigger
	_sights(b, length, DARK, g)

static func _hmg(b: Builder, lod: int, g: Color, length: float) -> void:
	b.box(Vector3(0, -0.06, 0.1), Vector3(0.1, 0.12, 0.5), METAL)                           # receiver
	b.box(Vector3(0, -0.004, 0.1), Vector3(0.03, 0.008, 0.46), LIGHT)                       # top plate
	b.cyl(Vector3(0, -0.06, -0.28), 0.05, 0.34, POLY, "z", false, -1.0, 10)                  # barrel shroud
	b.cyl(Vector3(0, -0.06, -0.462), 0.018, 0.026, STEEL)                                    # barrel
	b.box(Vector3(0, -0.06, -0.462), Vector3(0.07, 0.05, 0.04), DARK)                       # muzzle brake
	b.cyl(Vector3(0, -0.06, -0.482), 0.04, 0.008, g, "z", true)                              # muzzle glow
	for sx in [-1.0, 1.0]:
		for k in 3:
			b.box(Vector3(sx * 0.0515, -0.025, 0.04 + k * 0.05), Vector3(0.003, 0.03, 0.012), g, true)   # heat fin lights
	b.cyl(Vector3(0, -0.185, 0.08), 0.085, 0.1, DARK, "x", false, -1.0, 10)                  # ammo drum
	b.box(Vector3(0, -0.19, 0.24), Vector3(0.04, 0.11, 0.05), POLY, false, Basis().rotated(Vector3.RIGHT, -0.25))   # grip
	b.box(Vector3(0, -0.15, -0.1), Vector3(0.04, 0.1, 0.04), POLY)                          # foregrip
	b.box(Vector3(0, -0.07, 0.42), Vector3(0.06, 0.13, 0.12), POLY)                         # stock
	b.box(Vector3(0, -0.07, 0.48), Vector3(0.062, 0.14, 0.012), DARK)                       # butt pad
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			for z in [-0.2, -0.27, -0.34, -0.41]:
				b.box(Vector3(sx * 0.048, -0.06, z), Vector3(0.006, 0.03, 0.03), DARK)       # shroud vents
			b.cyl(Vector3(sx * 0.052, -0.185, 0.08), 0.034, 0.012, g, "x", true, -1.0, 10)   # glowing drum hubs
		b.box(Vector3(0, -0.12, 0.26), Vector3(0.01, 0.012, 0.08), DARK)                     # trigger guard
	b.box(Vector3(0, -0.007, -length * 0.45), Vector3(0.012, 0.014, 0.02), DARK)             # front sight base
	_sights(b, length, DARK, g)


static func _railgun(b: Builder, lod: int, g: Color) -> void:
	b.box(Vector3(0, -0.05, 0.15), Vector3(0.07, 0.1, 0.38), METAL)                         # receiver
	b.box(Vector3(0, -0.003, 0.15), Vector3(0.02, 0.006, 0.34), LIGHT)                      # top rail
	b.box(Vector3(0, -0.02, -0.3), Vector3(0.03, 0.025, 0.54), STEEL)                       # upper rail
	b.box(Vector3(0, -0.075, -0.3), Vector3(0.03, 0.025, 0.54), STEEL)                      # lower rail
	b.box(Vector3(0, -0.0475, -0.3), Vector3(0.012, 0.03, 0.54), g, true)                   # plasma core between the rails
	for z in [-0.1, -0.2, -0.3, -0.4, -0.5]:
		b.box(Vector3(0, -0.0475, z), Vector3(0.05, 0.07, 0.014), DARK)                      # coil housings
		if lod >= 2:
			for sx in [-1.0, 1.0]:
				b.box(Vector3(sx * 0.026, -0.0475, z), Vector3(0.003, 0.05, 0.016), g, true)  # glowing coil faces
	b.box(Vector3(0, -0.0475, -0.57), Vector3(0.04, 0.08, 0.02), DARK)                      # muzzle
	b.cyl(Vector3(0, 0.032, 0.12), 0.02, 0.22, DARK, "z", false, -1.0, 10)                  # scope tube
	b.cyl(Vector3(0, 0.032, 0.0), 0.018, 0.008, g, "z", true, -1.0, 10)                     # scope lens
	b.cyl(Vector3(0, 0.032, 0.235), 0.024, 0.03, METAL, "z", false, -1.0, 10)              # eyepiece
	b.box(Vector3(0, 0.006, 0.05), Vector3(0.025, 0.02, 0.03), METAL)                       # scope mounts
	b.box(Vector3(0, 0.006, 0.19), Vector3(0.025, 0.02, 0.03), METAL)
	b.box(Vector3(0, -0.03, 0.42), Vector3(0.03, 0.02, 0.16), POLY)                         # skeleton stock
	b.box(Vector3(0, -0.1, 0.42), Vector3(0.03, 0.02, 0.16), POLY)
	b.box(Vector3(0, -0.065, 0.5), Vector3(0.035, 0.1, 0.02), POLY)
	b.box(Vector3(0, -0.065, 0.56), Vector3(0.04, 0.13, 0.025), DARK)                       # butt pad
	b.box(Vector3(0, -0.14, 0.2), Vector3(0.035, 0.1, 0.045), POLY, false, Basis().rotated(Vector3.RIGHT, -0.3))   # grip
	b.box(Vector3(0, -0.13, 0.08), Vector3(0.045, 0.08, 0.09), DARK)                        # battery
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.024, -0.13, 0.08), Vector3(0.003, 0.05, 0.05), g, true)     # battery charge
			b.box(Vector3(sx * 0.012, -0.11, -0.2), Vector3(0.006, 0.03, 0.2), DARK)         # folded bipod legs


## LR-9 long rifle: bolt-action, 1.3 m, heavy fluted barrel with a muzzle brake, a big scope, thumbhole stock, a five-round box
## magazine, a folded bipod. Rust plates like the other invader guns, a thin orange charge line along the receiver.
static func _longrifle(b: Builder, lod: int, g: Color, length: float) -> void:
	var rust := Color(0.5, 0.28, 0.16)
	var h := length * 0.5
	b.box(Vector3(0, -0.05, 0.08), Vector3(0.062, 0.1, 0.4), METAL)                              # receiver
	b.box(Vector3(0, -0.004, 0.08), Vector3(0.02, 0.008, 0.38), LIGHT)                           # top rail
	b.cyl(Vector3(0, -0.045, -0.36), 0.017, 0.7, DARK, "z", false, -1.0, 10)                     # heavy barrel
	b.cyl(Vector3(0, -0.045, -0.2), 0.026, 0.28, METAL, "z", false, -1.0, 10)                    # fluted shroud over its root
	b.box(Vector3(0, -0.045, -h + 0.03), Vector3(0.05, 0.05, 0.1), DARK)                         # muzzle brake
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.026, -0.045, -h + 0.03), Vector3(0.004, 0.03, 0.07), g, true)   # brake slots glow
			b.box(Vector3(sx * 0.032, -0.05, 0.08), Vector3(0.004, 0.012, 0.3), g, true)         # charge line along the receiver
	b.box(Vector3(0.055, -0.03, 0.2), Vector3(0.08, 0.012, 0.014), STEEL)                         # bolt handle...
	b.box(Vector3(0.1, -0.03, 0.2), Vector3(0.02, 0.022, 0.022), DARK)                            # ...and its knob
	b.box(Vector3(0, -0.1, 0.46), Vector3(0.05, 0.05, 0.4), POLY)                                 # thumbhole stock: lower bar...
	b.box(Vector3(0, -0.06, 0.62), Vector3(0.05, 0.13, 0.08), POLY)                               # ...rear block...
	b.box(Vector3(0, -0.03, 0.47), Vector3(0.05, 0.04, 0.3), POLY)                                # ...and the cheek bar over the thumb hole
	b.box(Vector3(0, -0.075, h - 0.01), Vector3(0.05, 0.16, 0.025), DARK)                         # butt pad
	b.box(Vector3(0, -0.15, 0.2), Vector3(0.035, 0.11, 0.045), POLY, false, Basis().rotated(Vector3.RIGHT, -0.3))   # grip
	b.box(Vector3(0, -0.125, 0.05), Vector3(0.04, 0.09, 0.1), DARK)                               # five-round box magazine
	b.box(Vector3(0, -0.045, -0.08), Vector3(0.066, 0.05, 0.05), rust)                            # rust plates on the shroud
	b.box(Vector3(0, -0.085, 0.3), Vector3(0.056, 0.03, 0.07), rust)
	b.cyl(Vector3(0, 0.04, 0.02), 0.026, 0.34, DARK, "z", false, -1.0, 10)                        # scope tube
	b.cyl(Vector3(0, 0.04, -0.17), 0.036, 0.07, METAL, "z", false, -1.0, 10)                      # objective bell
	b.cyl(Vector3(0, 0.04, -0.205), 0.03, 0.006, g, "z", true, -1.0, 10)                          # lens
	b.cyl(Vector3(0, 0.04, 0.215), 0.03, 0.05, METAL, "z", false, -1.0, 10)                       # eyepiece
	b.box(Vector3(0, 0.012, -0.05), Vector3(0.03, 0.03, 0.04), METAL)                             # scope rings
	b.box(Vector3(0, 0.012, 0.13), Vector3(0.03, 0.03, 0.04), METAL)
	if lod >= 2:
		b.box(Vector3(0.032, 0.05, 0.02), Vector3(0.03, 0.03, 0.03), STEEL)                       # windage / elevation turrets
		b.box(Vector3(0, 0.074, 0.02), Vector3(0.03, 0.03, 0.03), STEEL)
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.014, -0.1, -0.3), Vector3(0.006, 0.05, 0.2), DARK, false, Basis().rotated(Vector3.FORWARD, sx * 0.25))   # folded bipod legs


static func _knife(b: Builder, lod: int, g: Color) -> void:
	b.cyl(Vector3(0, 0, 0.065), 0.016, 0.13, DARK)                                           # handle
	b.box(Vector3(0, 0, 0.135), Vector3(0.03, 0.03, 0.014), STEEL)                          # pommel
	b.box(Vector3(0, 0, -0.005), Vector3(0.07, 0.014, 0.016), STEEL)                        # guard
	b.box(Vector3(0, 0.004, -0.12), Vector3(0.007, 0.032, 0.23), STEEL)                     # blade
	b.box(Vector3(0, -0.013, -0.12), Vector3(0.004, 0.006, 0.23), g, true)                  # glowing edge
	b.box(Vector3(0, 0.0, -0.245), Vector3(0.006, 0.026, 0.04), STEEL, false, Basis().rotated(Vector3.RIGHT, 0.5))   # tip
	if lod >= 2:
		for z in [0.03, 0.065, 0.1]:
			b.box(Vector3(0, 0, z), Vector3(0.034, 0.034, 0.008), METAL)                     # grip rings
		b.box(Vector3(0, 0.021, -0.12), Vector3(0.01, 0.004, 0.22), DARK)                    # spine


static func _blade(b: Builder, lod: int, g: Color) -> void:
	b.cyl(Vector3(0, 0, 0.11), 0.018, 0.22, DARK)                                            # hilt
	b.cyl(Vector3(0, 0, 0.225), 0.024, 0.02, STEEL)                                          # pommel
	b.box(Vector3(0, 0, 0.0), Vector3(0.05, 0.05, 0.07), METAL)                             # emitter housing
	b.box(Vector3(0, 0, 0.045), Vector3(0.09, 0.012, 0.02), METAL)                          # crossguard
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.02, 0, -0.045), Vector3(0.01, 0.07, 0.03), g, true)             # emitter prongs
	b.box(Vector3(0, 0, -0.45), Vector3(0.012, 0.06, 0.8), g, true)                         # plasma blade
	b.box(Vector3(0, 0, -0.45), Vector3(0.005, 0.04, 0.78), WHITE, true)                    # hot core
	b.box(Vector3(0, 0, -0.88), Vector3(0.012, 0.04, 0.06), g, true, Basis().rotated(Vector3.RIGHT, 0.5))   # tip
	if lod >= 2:
		for z in [0.05, 0.09, 0.13, 0.17]:
			b.cyl(Vector3(0, 0, z), 0.02, 0.012, METAL)                                      # grip wraps
