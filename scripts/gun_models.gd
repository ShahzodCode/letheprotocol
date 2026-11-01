class_name GunModels
## Procedural weapon models: each weapon is a few dozen boxes, chamfered blocks and cylinders (barrels, handguards, magazines,
## grips, stocks, optics, glowing coils) merged into ONE mesh with three surfaces (paint / polymer, bare metal, glow), cached
## per weapon and detail level, so 40 soldiers holding the same gun share it. The same geometry gives the viewmodel (lod 2),
## the gun in an enemy's hands and the pick-up on the ground (lod 1), and the side-on silhouette the HUD draws (profile()).
##
## Surfaces: vertex colours carry the paint; the materials (`_gun_mat`) add a texture in the gun's own space (triplanar, no
## UVs needed): mottled grime on the albedo, worn and polished patches on the roughness and, on the viewmodel, a fine
## hammered normal map. Chamfered blocks (`Builder.pbox`) cut their long edges at 45 degrees in a lighter shade: worn edges.
## Bare metal (STEEL, METAL, LIGHT, GUNMETAL) goes on its own shinier surface.
##
## The viewmodel (`build_viewmodel`) keeps the moving parts apart: the magazine / energy cell ("mag") and the LR-9's bolt
## ("bolt") are nodes of their own, turning about `PIVOTS`, so Weapons can pull the magazine and work the bolt.
##
## Guns are built with the barrel along -z, the top of the receiver at y = 0 and the middle of the gun's length at z = 0,
## the muzzle at z = -length / 2. Everything except the iron sights stays at or below y = 0, so aiming along the sights
## never looks through the gun (see Weapons._ads_pos). Melee weapons are built with the guard at the origin, the blade
## along -z and the grip behind it (+z). `grip()` is where the right hand holds it, `support()` where the left hand goes.

const SIGHT_H := 0.02          # keep equal to Weapons.SIGHT_H
const TEX_SCALE := 4.0         # texture repeats per metre of gun (one tile = 25 cm)

const METAL := Color(0.17, 0.18, 0.21)
const DARK := Color(0.07, 0.07, 0.08)
const POLY := Color(0.11, 0.11, 0.12)
const STEEL := Color(0.62, 0.64, 0.68)
const LIGHT := Color(0.32, 0.34, 0.38)
const GUNMETAL := Color(0.25, 0.26, 0.28)
const TAN := Color(0.42, 0.37, 0.28)
const WHITE := Color(1.0, 1.0, 1.0)
const BONE := Color(0.78, 0.74, 0.66)
const GRAPHITE := Color(0.14, 0.13, 0.14)

const FACES := [
	[Vector3.RIGHT, Vector3.UP, Vector3.BACK],
	[Vector3.LEFT, Vector3.BACK, Vector3.UP],
	[Vector3.UP, Vector3.BACK, Vector3.RIGHT],
	[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
	[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
	[Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
]

## Where each moving part of the viewmodel turns (model space): the magazine about the top of its well, the bolt about its axis.
const PIVOTS := {
	"rifle": {"mag": Vector3(0, -0.068, -0.03)},
	"carbine": {"mag": Vector3(0, -0.06, 0.27)},
	"hmg": {"mag": Vector3(0, -0.11, 0.08)},
	"railgun": {"mag": Vector3(0, -0.09, 0.08)},
	"sniper": {"mag": Vector3(0, -0.08, 0.05), "bolt": Vector3(0, -0.03, 0.2)},
}

static var _meshes := {}       # "id:lod" -> ArrayMesh
static var _profiles := {}     # id -> Array of [Rect2, Color, glow]
static var _mats := {}         # "kind:lod" -> StandardMaterial3D (shared by every gun)
static var _tex := {}          # noise kind -> NoiseTexture2D


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

	## A flat triangle facing `nrm` (the winding is chosen so that it is the front face).
	func tri(p0: Vector3, p1: Vector3, p2: Vector3, nrm: Vector3, col: Color) -> void:
		var a := vert(p0, nrm, col)
		var b := vert(p1, nrm, col)
		var e := vert(p2, nrm, col)
		if (p1 - p0).cross(p2 - p0).dot(nrm) < 0.0:
			i.append_array(PackedInt32Array([a, b, e]))
		else:
			i.append_array(PackedInt32Array([a, e, b]))

	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nrm: Vector3, col: Color) -> void:
		tri(p0, p1, p2, nrm, col)
		tri(p0, p2, p3, nrm, col)


## Collects parts, then turns them into one mesh (lit + glowing; style "gun" adds a bare-metal surface and textured materials).
class Builder:
	var lit := Surf.new()
	var metal := Surf.new()    # style "gun": bare metal parts (shinier material)
	var glow := Surf.new()
	var rects: Array = []      # side view: [Rect2 (z, y), Color, glow]
	var style := ""            # "": plain vertex colours (ships, lander rooms); "gun": GunModels._gun_mat materials
	var lod := 1               # style "gun": which material set (2 = viewmodel, with the normal map)
	var split := false         # viewmodel: parts named with part() go into `subs` (moving pieces: magazine, bolt)
	var subs := {}             # part name -> Builder
	var _sub = null            # the Builder that takes the parts while a part() is open

	## Everything added after this goes into the moving part `name` ("" closes it). Without `split` it stays in the one mesh.
	func part(name: String) -> void:
		if not split or name == "":
			_sub = null
			return
		if not subs.has(name):
			var nb = GunModels.Builder.new()
			nb.style = style
			nb.lod = lod
			subs[name] = nb
		_sub = subs[name]

	func _surf(col: Color, glowing: bool) -> Surf:
		if glowing:
			return glow
		if style == "gun" and GunModels.is_metal(col):
			return metal
		return lit

	func box(centre: Vector3, size: Vector3, col: Color, glowing: bool = false, rot: Basis = Basis.IDENTITY) -> void:
		if _sub != null:
			_sub.box(centre, size, col, glowing, rot)
			rects.append(_sub.rects.back())
			return
		var d: Surf = _surf(col, glowing)
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

	## A box whose four long edges (along its own z) are cut at 45 degrees: an octagonal block. The cuts are a lighter shade of
	## `col` and catch the light like worn edges. `ch` is the size of the cut in metres (-1: a third of the smaller half-side).
	func pbox(centre: Vector3, size: Vector3, col: Color, glowing: bool = false, rot: Basis = Basis.IDENTITY, ch: float = -1.0) -> void:
		if _sub != null:
			_sub.pbox(centre, size, col, glowing, rot, ch)
			rects.append(_sub.rects.back())
			return
		var d: Surf = _surf(col, glowing)
		var hx := size.x * 0.5
		var hy := size.y * 0.5
		var hz := size.z * 0.5
		var cut := ch if ch >= 0.0 else minf(hx, hy) * 0.33
		cut = minf(cut, minf(hx, hy) * 0.9)
		var edge := col if glowing else col.lightened(0.16)
		var ring: Array[Vector2] = [Vector2(hx, hy - cut), Vector2(hx - cut, hy), Vector2(-hx + cut, hy), Vector2(-hx, hy - cut),
			Vector2(-hx, -hy + cut), Vector2(-hx + cut, -hy), Vector2(hx - cut, -hy), Vector2(hx, -hy + cut)]
		for k in 8:
			var a2: Vector2 = ring[k]
			var b2: Vector2 = ring[(k + 1) % 8]
			var e := b2 - a2
			if e.length() < 0.00001:
				continue
			var n2 := Vector2(e.y, -e.x).normalized()          # outward (the ring runs anticlockwise)
			var nrm := (rot * Vector3(n2.x, n2.y, 0.0)).normalized()
			d.quad(centre + rot * Vector3(a2.x, a2.y, -hz), centre + rot * Vector3(b2.x, b2.y, -hz),
				centre + rot * Vector3(b2.x, b2.y, hz), centre + rot * Vector3(a2.x, a2.y, hz), nrm, edge if k % 2 == 0 else col)
		for sz in [-1.0, 1.0]:
			var cn := (rot * Vector3(0, 0, sz)).normalized()
			var cc := centre + rot * Vector3(0, 0, sz * hz)
			for k in 8:
				var a3: Vector2 = ring[k]
				var b3: Vector2 = ring[(k + 1) % 8]
				d.tri(cc, centre + rot * Vector3(a3.x, a3.y, sz * hz), centre + rot * Vector3(b3.x, b3.y, sz * hz), cn, col)
		_rect(centre, rot, Vector3(hx, hy, hz), col, glowing)

	## A cylinder (or cone: r2 >= 0 gives the radius at +z) along an axis: "z" (barrel direction), "x" or "y".
	func cyl(centre: Vector3, radius: float, length: float, col: Color, axis: String = "z", glowing: bool = false, r2: float = -1.0, segs: int = 8) -> void:
		if _sub != null:
			_sub.cyl(centre, radius, length, col, axis, glowing, r2, segs)
			rects.append(_sub.rects.back())
			return
		var d: Surf = _surf(col, glowing)
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
		for pair in [[lit, "lit"], [metal, "metal"], [glow, "glow"]]:
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
			var mat: StandardMaterial3D
			if style == "gun":
				mat = GunModels._gun_mat(String(pair[1]), lod)
			else:
				mat = StandardMaterial3D.new()
				mat.vertex_color_use_as_albedo = true
				mat.vertex_color_is_srgb = true
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				if String(pair[1]) == "glow":
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				else:
					mat.roughness = 0.8
					mat.metallic = 0.05
					mat.metallic_specular = 0.3
			m.surface_set_material(m.get_surface_count() - 1, mat)
		return m


# ---------------------------------------------------------------- materials

## Bare metal goes on the shiny surface (style "gun").
static func is_metal(col: Color) -> bool:
	return col == STEEL or col == METAL or col == LIGHT or col == GUNMETAL


## The shared gun materials: "lit" (paint, polymer), "metal" (bare metal) and "glow" (unshaded). All take the vertex colour; the
## lit ones multiply it with a grime texture and vary the roughness (triplanar in the gun's own space, so the texture moves with
## it); lod 2 (the viewmodel, seen up close) adds a fine hammered normal map.
static func _gun_mat(kind: String, lod: int) -> StandardMaterial3D:
	var key := "%s:%d" % [kind, mini(lod, 2)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if kind == "glow":
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		var bare := kind == "metal"
		m.albedo_color = Color(1.12, 1.12, 1.12)          # the grime darkens on average: this keeps the paint near its own colour
		m.albedo_texture = _noise_tex("grime")
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = 3.0
		m.uv1_scale = Vector3.ONE * TEX_SCALE
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		m.roughness = 0.4 if bare else 0.82
		m.metallic = 0.45 if bare else 0.0
		m.metallic_specular = 0.6 if bare else 0.35
		m.roughness_texture = _noise_tex("wear")
		if lod >= 2:
			m.normal_enabled = true
			m.normal_texture = _noise_tex("dents")
			m.normal_scale = 0.35
	_mats[key] = m
	return m


## The textures, made from noise once: "grime" (albedo: dark mottled blotches), "wear" (roughness: polished cells and rough
## patches), "dents" (a fine hammered normal map).
static func _noise_tex(kind: String) -> NoiseTexture2D:
	if _tex.has(kind):
		return _tex[kind]
	var n := FastNoiseLite.new()
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	match kind:
		"grime":
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
			n.frequency = 0.012
			n.fractal_octaves = 5
			n.seed = 7
			var g := Gradient.new()
			g.set_color(0, Color(0.72, 0.7, 0.68))
			g.set_color(1, Color(1.0, 1.0, 1.0))
			t.color_ramp = g
		"wear":
			n.noise_type = FastNoiseLite.TYPE_CELLULAR
			n.frequency = 0.03
			n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
			n.seed = 11
			var g2 := Gradient.new()
			g2.set_color(0, Color(0.55, 0.55, 0.55))
			g2.set_color(1, Color(1.0, 1.0, 1.0))
			t.color_ramp = g2
		_:
			n.noise_type = FastNoiseLite.TYPE_SIMPLEX
			n.frequency = 0.06
			n.fractal_octaves = 3
			n.seed = 3
			t.as_normal_map = true
			t.bump_strength = 4.0
	t.noise = n
	_tex[kind] = t
	return t


# ---------------------------------------------------------------- public API

static func _builder_for(id: String, lod: int, split: bool = false) -> Builder:
	var b := Builder.new()
	b.style = "gun"
	b.lod = lod
	b.split = split
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
	b.part("")
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


## The viewmodel (full detail): a Node3D holding the fixed body ("body") and one node per moving part ("mag", "bolt") placed at
## its pivot (`PIVOTS`), so moving or turning that node moves the part. Same model space as build().
static func build_viewmodel(id: String) -> Node3D:
	var b := _builder_for(id, 2, true)
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "body"
	body.mesh = b.mesh()
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var piv: Dictionary = PIVOTS.get(id, {})
	for nm in b.subs:
		var at: Vector3 = piv.get(nm, Vector3.ZERO)
		var node := Node3D.new()
		node.name = String(nm)
		node.position = at
		var pm := MeshInstance3D.new()
		pm.mesh = (b.subs[nm] as Builder).mesh()
		pm.position = -at
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(pm)
		root.add_child(node)
	return root


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


## Where the other (left) hand holds it: under the handguard or on the foregrip, in model space. Vector3.INF: one-handed (blades).
## A soldier's left hand is pulled there (PoseLayer.grip); a gun longer than his arms can reach gets the hand as far as it goes.
static func support(id: String) -> Vector3:
	match id:
		"pistol":
			return Vector3(-0.01, -0.12, 0.08)       # cups the right hand
		"rifle":
			return Vector3(0, -0.07, -0.19)
		"carbine":
			return Vector3(0, -0.12, -0.12)
		"hmg":
			return Vector3(0, -0.16, -0.1)
		"railgun":
			return Vector3(0, -0.1, -0.14)
		"sniper":
			return Vector3(0, -0.078, -0.12)
	return Vector3.INF


## The muzzle (or blade tip), in model space.
static func muzzle(id: String) -> Vector3:
	match id:
		"pistol":
			return Vector3(0, -0.02, -0.15)
		"rifle":
			return Vector3(0, -0.035, -0.475)
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
	b.box(Vector3(0, 0.003, length * 0.25), Vector3(0.04, 0.006, 0.016), col)                     # rear sight base
	b.box(Vector3(0, SIGHT_H * 0.5, -length * 0.45), Vector3(0.006, SIGHT_H, 0.008), col)
	b.box(Vector3(0, 0.003, -length * 0.45), Vector3(0.016, 0.006, 0.014), col)                   # front sight base
	b.box(Vector3(0, SIGHT_H, -length * 0.45), Vector3(0.003, 0.003, 0.003), g, true)


## The M9 for soldiers and pick-ups (the player's viewmodel is the .glb): slide with serrations, polymer frame with a rail, grip
## with a magazine base, hammer and sights.
static func _pistol(b: Builder, lod: int) -> void:
	b.pbox(Vector3(0, -0.02, 0.0), Vector3(0.03, 0.04, 0.2), GUNMETAL, false, Basis.IDENTITY, 0.006)     # slide
	b.pbox(Vector3(0, -0.055, 0.005), Vector3(0.028, 0.03, 0.17), POLY)                                  # frame
	b.box(Vector3(0, -0.068, -0.06), Vector3(0.022, 0.008, 0.05), DARK)                                 # accessory rail
	b.cyl(Vector3(0, -0.02, -0.105), 0.009, 0.012, STEEL, "z", false, -1.0, 10)                          # barrel tip
	b.pbox(Vector3(0, -0.11, 0.07), Vector3(0.03, 0.095, 0.05), POLY, false, Basis().rotated(Vector3.RIGHT, -0.25), 0.008)   # grip
	b.box(Vector3(0, -0.08, 0.0), Vector3(0.01, 0.015, 0.07), DARK)                                     # trigger guard
	b.box(Vector3(0, -0.16, 0.08), Vector3(0.032, 0.01, 0.054), DARK, false, Basis().rotated(Vector3.RIGHT, -0.25))          # magazine base
	b.box(Vector3(0, 0.007, 0.09), Vector3(0.014, 0.014, 0.01), DARK)                                   # sights
	b.box(Vector3(0, 0.006, -0.09), Vector3(0.006, 0.012, 0.008), DARK)
	b.box(Vector3(0, -0.012, 0.104), Vector3(0.01, 0.018, 0.01), DARK, false, Basis().rotated(Vector3.RIGHT, 0.4))           # hammer
	if lod >= 2:
		for k in 4:
			b.box(Vector3(0.0, -0.016, 0.05 + k * 0.011), Vector3(0.032, 0.026, 0.004), DARK)                # slide serrations
		b.box(Vector3(0, -0.075, 0.02), Vector3(0.006, 0.02, 0.006), DARK)                               # trigger
		for k in 3:
			b.box(Vector3(0, -0.1 - k * 0.02, 0.087 + k * 0.005), Vector3(0.032, 0.006, 0.03), DARK, false, Basis().rotated(Vector3.RIGHT, -0.25))   # grip texture


## PR-1 pulse rifle (the invaders' own rifle, formerly the M4): long, slim and humming. A bone-pale shroud with vent slots over a
## graphite receiver, a white glowing channel down both flanks, an emitter ring and crown at the muzzle, a skeletal stock and a
## charge cell (the magazine) in front of the grip.
static func _rifle(b: Builder, lod: int, g: Color, length: float) -> void:
	var rust := Color(0.34, 0.19, 0.12)
	b.pbox(Vector3(0, -0.04, 0.03), Vector3(0.05, 0.075, 0.44), GRAPHITE, false, Basis.IDENTITY, 0.01)    # graphite receiver
	b.pbox(Vector3(0, -0.03, -0.2), Vector3(0.044, 0.054, 0.34), BONE, false, Basis.IDENTITY, 0.013)      # shroud
	b.pbox(Vector3(0, -0.031, -0.372), Vector3(0.048, 0.058, 0.012), DARK)                               # shroud's front cap
	b.box(Vector3(0, -0.012, -0.2), Vector3(0.02, 0.012, 0.3), DARK)                                     # top spine
	b.cyl(Vector3(0, -0.035, -0.42), 0.012, 0.1, STEEL, "z", false, -1.0, 10)                             # barrel
	b.cyl(Vector3(0, -0.035, -0.459), 0.022, 0.016, g, "z", true, -1.0, 12)                               # emitter ring
	b.cyl(Vector3(0, -0.035, -0.47), 0.016, 0.01, METAL, "z", false, -1.0, 12)                            # muzzle crown
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.0225, -0.03, -0.2), Vector3(0.004, 0.012, 0.32), g, true)                     # glowing channel on the flanks
		b.box(Vector3(sx * 0.0265, -0.04, 0.03), Vector3(0.003, 0.012, 0.3), g, true)
	b.pbox(Vector3(0, -0.04, 0.3), Vector3(0.034, 0.03, 0.18), DARK)                                      # skeletal stock: upper rail
	b.pbox(Vector3(0, -0.085, 0.3), Vector3(0.034, 0.024, 0.18), DARK)                                    # lower rail
	b.box(Vector3(0, -0.062, 0.37), Vector3(0.03, 0.05, 0.02), DARK)                                      # rear strut
	b.pbox(Vector3(0, -0.06, 0.395), Vector3(0.04, 0.09, 0.016), rust)                                    # butt pad
	b.box(Vector3(0, -0.068, -0.03), Vector3(0.04, 0.012, 0.096), GRAPHITE)                               # cell well
	b.pbox(Vector3(0, -0.11, 0.13), Vector3(0.03, 0.09, 0.04), POLY, false, Basis().rotated(Vector3.RIGHT, -0.3), 0.008)   # grip
	b.part("mag")
	b.pbox(Vector3(0, -0.105, -0.03), Vector3(0.036, 0.075, 0.09), DARK, false, Basis.IDENTITY, 0.008)    # charge cell
	b.box(Vector3(0, -0.118, -0.0755), Vector3(0.012, 0.03, 0.002), g, true)                             # its charge window
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.019, -0.105, -0.03), Vector3(0.003, 0.05, 0.05), g, true)                  # cell charge strips
		b.box(Vector3(0, -0.144, -0.03), Vector3(0.04, 0.006, 0.094), GUNMETAL)                          # cell base plate
	b.part("")
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.0255, -0.048, 0.2), Vector3(0.004, 0.036, 0.12), rust)                    # rust side plates
			for z in [-0.12, -0.17, -0.22, -0.27]:
				b.box(Vector3(sx * 0.0222, -0.046, z), Vector3(0.002, 0.01, 0.024), DARK)                  # vent slots in the shroud
			b.box(Vector3(sx * 0.0175, -0.093, 0.39), Vector3(0.004, 0.012, 0.012), STEEL)                 # sling loop
		b.box(Vector3(0, -0.098, 0.115), Vector3(0.008, 0.028, 0.008), DARK)                                # trigger
		b.box(Vector3(0, -0.09, 0.095), Vector3(0.01, 0.012, 0.07), DARK)                                   # trigger guard
		b.box(Vector3(0.027, -0.05, 0.09), Vector3(0.004, 0.008, 0.02), STEEL)                              # selector lever
		b.box(Vector3(0.026, -0.03, 0.15), Vector3(0.004, 0.016, 0.03), DARK)                               # charging port
	_sights(b, length, DARK, g)


## PC-24: a bullpup in pale armour grey (like the rifleman's own gun): the cell sits behind the grip, a low sensor rail on top.
static func _carbine(b: Builder, lod: int, g: Color, length: float) -> void:
	var hull := Color(0.76, 0.78, 0.82)
	b.pbox(Vector3(0, -0.05, 0.12), Vector3(0.07, 0.1, 0.52), hull, false, Basis.IDENTITY, 0.016)         # receiver and stock in one piece
	b.pbox(Vector3(0, -0.055, 0.17), Vector3(0.074, 0.05, 0.2), DARK, false, Basis.IDENTITY, 0.008)       # dark side panels
	b.pbox(Vector3(0, -0.04, -0.24), Vector3(0.064, 0.08, 0.28), hull, false, Basis.IDENTITY, 0.016)      # handguard
	b.pbox(Vector3(0, -0.03, -0.25), Vector3(0.068, 0.028, 0.2), DARK, false, Basis.IDENTITY, 0.006)
	b.cyl(Vector3(0, -0.045, -0.34), 0.013, 0.08, STEEL, "z", false, -1.0, 10)                             # barrel
	b.cyl(Vector3(0, -0.045, -0.33), 0.026, 0.016, g, "z", true, -1.0, 12)                                 # emitter ring
	b.cyl(Vector3(0, -0.045, -0.372), 0.018, 0.012, METAL, "z", false, -1.0, 12)                           # muzzle crown
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.0365, -0.045, -0.24), Vector3(0.004, 0.014, 0.17), g, true)                  # energy strips on the flanks
	b.box(Vector3(0, 0.008, 0.02), Vector3(0.032, 0.016, 0.24), DARK)                                     # low sensor rail
	b.box(Vector3(0, 0.014, -0.08), Vector3(0.02, 0.006, 0.05), g, true)                                  # sensor lens
	b.pbox(Vector3(0, -0.1, -0.12), Vector3(0.032, 0.09, 0.04), POLY, false, Basis().rotated(Vector3.RIGHT, 0.2), 0.008)    # foregrip
	b.pbox(Vector3(0, -0.14, 0.15), Vector3(0.034, 0.1, 0.042), POLY, false, Basis().rotated(Vector3.RIGHT, -0.3), 0.008)   # pistol grip
	b.pbox(Vector3(0, -0.05, 0.382), Vector3(0.072, 0.1, 0.012), DARK)                                    # butt pad
	b.part("mag")
	b.pbox(Vector3(0, -0.115, 0.27), Vector3(0.05, 0.13, 0.07), DARK, false, Basis().rotated(Vector3.RIGHT, 0.12), 0.01)    # energy cell (behind the grip)
	b.box(Vector3(0, -0.15, 0.234), Vector3(0.016, 0.03, 0.002), g, true, Basis().rotated(Vector3.RIGHT, 0.12))             # its charge window
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.0255, -0.115, 0.27), Vector3(0.003, 0.08, 0.02), g, true)                 # cell charge strip
	b.part("")
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.037, -0.03, 0.34), Vector3(0.004, 0.03, 0.08), DARK)                        # vents
			for z in [-0.3, -0.27, -0.24, -0.21, -0.18]:
				b.box(Vector3(sx * 0.0322, -0.06, z), Vector3(0.002, 0.016, 0.012), DARK)                   # handguard slots
		b.box(Vector3(0, -0.1, 0.1), Vector3(0.01, 0.012, 0.08), DARK)                                       # trigger guard
		b.box(Vector3(0, -0.11, 0.115), Vector3(0.008, 0.03, 0.008), DARK)                                   # trigger
		b.box(Vector3(-0.036, -0.03, 0.1), Vector3(0.004, 0.022, 0.05), DARK)                                # ejection port
		for k in 3:
			b.box(Vector3(0, -0.12 - k * 0.022, -0.115 - k * 0.005), Vector3(0.034, 0.006, 0.036), DARK, false, Basis().rotated(Vector3.RIGHT, 0.2))   # foregrip ribs
	_sights(b, length, DARK, g)


## HG-60: a squat heavy gun. Receiver with a top plate, a thick vented barrel shroud and a muzzle brake, a big drum (the magazine)
## under a feed chute, heat-fin lights, foregrip, stock and a folded bipod.
static func _hmg(b: Builder, lod: int, g: Color, length: float) -> void:
	var segs := 14 if lod >= 2 else 10
	b.pbox(Vector3(0, -0.06, 0.1), Vector3(0.1, 0.12, 0.5), METAL, false, Basis.IDENTITY, 0.018)          # receiver
	b.box(Vector3(0, -0.004, 0.1), Vector3(0.03, 0.008, 0.46), LIGHT)                                     # top plate
	b.cyl(Vector3(0, -0.06, -0.28), 0.05, 0.34, POLY, "z", false, -1.0, segs)                              # barrel shroud
	b.cyl(Vector3(0, -0.06, -0.11), 0.056, 0.03, DARK, "z", false, -1.0, segs)                             # shroud's collar
	b.cyl(Vector3(0, -0.06, -0.462), 0.018, 0.026, STEEL, "z", false, -1.0, 10)                            # barrel
	b.pbox(Vector3(0, -0.06, -0.462), Vector3(0.07, 0.05, 0.04), DARK, false, Basis.IDENTITY, 0.01)       # muzzle brake
	b.cyl(Vector3(0, -0.06, -0.482), 0.04, 0.008, g, "z", true, -1.0, segs)                                # muzzle glow
	for sx in [-1.0, 1.0]:
		for k in 3:
			b.box(Vector3(sx * 0.0515, -0.025, 0.04 + k * 0.05), Vector3(0.003, 0.03, 0.012), g, true)   # heat fin lights
	b.box(Vector3(0, -0.115, 0.08), Vector3(0.05, 0.03, 0.07), DARK)                                      # feed chute
	b.pbox(Vector3(0, -0.19, 0.24), Vector3(0.04, 0.11, 0.05), POLY, false, Basis().rotated(Vector3.RIGHT, -0.25), 0.01)    # grip
	b.pbox(Vector3(0, -0.15, -0.1), Vector3(0.04, 0.1, 0.04), POLY, false, Basis.IDENTITY, 0.01)          # foregrip
	b.pbox(Vector3(0, -0.07, 0.42), Vector3(0.06, 0.13, 0.12), POLY, false, Basis.IDENTITY, 0.014)        # stock
	b.box(Vector3(0, -0.07, 0.48), Vector3(0.062, 0.14, 0.012), DARK)                                     # butt pad
	b.part("mag")
	b.cyl(Vector3(0, -0.185, 0.08), 0.085, 0.1, DARK, "x", false, -1.0, segs)                              # ammo drum
	b.cyl(Vector3(0, -0.185, 0.08), 0.088, 0.016, GUNMETAL, "x", false, -1.0, segs)                        # its middle band
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.cyl(Vector3(sx * 0.052, -0.185, 0.08), 0.034, 0.012, g, "x", true, -1.0, 10)                 # glowing drum hubs
			b.cyl(Vector3(sx * 0.051, -0.185, 0.08), 0.07, 0.006, METAL, "x", false, -1.0, segs)           # drum rims
	b.part("")
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			for z in [-0.2, -0.27, -0.34, -0.41]:
				b.box(Vector3(sx * 0.048, -0.06, z), Vector3(0.006, 0.03, 0.03), DARK)                       # shroud vents
			b.box(Vector3(sx * 0.014, -0.11, -0.3), Vector3(0.008, 0.012, 0.22), DARK, false, Basis().rotated(Vector3.FORWARD, sx * 0.2))   # folded bipod
			b.box(Vector3(sx * 0.051, -0.08, 0.3), Vector3(0.004, 0.04, 0.06), DARK)                         # receiver bolts plate
		b.box(Vector3(0, -0.12, 0.26), Vector3(0.01, 0.012, 0.08), DARK)                                     # trigger guard
		b.box(Vector3(0, -0.13, 0.245), Vector3(0.008, 0.028, 0.008), DARK)                                  # trigger
		b.box(Vector3(0.052, -0.05, 0.18), Vector3(0.006, 0.02, 0.05), STEEL)                                # charging handle
	b.box(Vector3(0, -0.007, -length * 0.45), Vector3(0.012, 0.014, 0.02), DARK)                             # front sight base
	_sights(b, length, DARK, g)


## RG-5 rail rifle: twin steel rails with the plasma core between them, coil housings, muzzle prongs, a scope, a skeletal stock and a
## battery (the magazine) in front of the grip.
static func _railgun(b: Builder, lod: int, g: Color) -> void:
	b.pbox(Vector3(0, -0.05, 0.15), Vector3(0.07, 0.1, 0.38), METAL, false, Basis.IDENTITY, 0.014)        # receiver
	b.box(Vector3(0, -0.003, 0.15), Vector3(0.02, 0.006, 0.34), LIGHT)                                    # top rail
	b.pbox(Vector3(0, -0.02, -0.3), Vector3(0.03, 0.025, 0.54), STEEL, false, Basis.IDENTITY, 0.006)      # upper rail
	b.pbox(Vector3(0, -0.075, -0.3), Vector3(0.03, 0.025, 0.54), STEEL, false, Basis.IDENTITY, 0.006)     # lower rail
	b.box(Vector3(0, -0.0475, -0.3), Vector3(0.012, 0.03, 0.54), g, true)                                 # plasma core between the rails
	for z in [-0.1, -0.2, -0.3, -0.4, -0.5]:
		b.pbox(Vector3(0, -0.0475, z), Vector3(0.05, 0.07, 0.014), DARK, false, Basis.IDENTITY, 0.01)      # coil housings
		if lod >= 2:
			for sx in [-1.0, 1.0]:
				b.box(Vector3(sx * 0.026, -0.0475, z), Vector3(0.003, 0.05, 0.016), g, true)                # glowing coil faces
	b.pbox(Vector3(0, -0.0475, -0.565), Vector3(0.04, 0.08, 0.02), DARK)                                  # muzzle
	for sy in [-1.0, 1.0]:
		b.box(Vector3(0, -0.0475 + sy * 0.03, -0.578), Vector3(0.03, 0.01, 0.01), METAL)                   # muzzle prongs
	b.cyl(Vector3(0, 0.032, 0.12), 0.02, 0.22, DARK, "z", false, -1.0, 10)                                 # scope tube
	b.cyl(Vector3(0, 0.032, 0.0), 0.018, 0.008, g, "z", true, -1.0, 10)                                    # scope lens
	b.cyl(Vector3(0, 0.032, 0.235), 0.024, 0.03, METAL, "z", false, -1.0, 10)                              # eyepiece
	b.box(Vector3(0, 0.006, 0.05), Vector3(0.025, 0.02, 0.03), METAL)                                     # scope mounts
	b.box(Vector3(0, 0.006, 0.19), Vector3(0.025, 0.02, 0.03), METAL)
	b.pbox(Vector3(0, -0.03, 0.42), Vector3(0.03, 0.02, 0.16), POLY)                                      # skeleton stock
	b.pbox(Vector3(0, -0.1, 0.42), Vector3(0.03, 0.02, 0.16), POLY)
	b.box(Vector3(0, -0.065, 0.5), Vector3(0.035, 0.1, 0.02), POLY)
	b.pbox(Vector3(0, -0.065, 0.56), Vector3(0.04, 0.13, 0.025), DARK)                                    # butt pad
	b.pbox(Vector3(0, -0.14, 0.2), Vector3(0.035, 0.1, 0.045), POLY, false, Basis().rotated(Vector3.RIGHT, -0.3), 0.008)    # grip
	b.part("mag")
	b.pbox(Vector3(0, -0.13, 0.08), Vector3(0.045, 0.08, 0.09), DARK, false, Basis.IDENTITY, 0.01)        # battery
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.024, -0.13, 0.08), Vector3(0.003, 0.05, 0.05), g, true)                    # battery charge
	b.part("")
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.012, -0.11, -0.2), Vector3(0.006, 0.03, 0.2), DARK)                        # folded bipod legs
		b.cyl(Vector3(0.026, 0.032, 0.12), 0.008, 0.012, METAL, "x", false, -1.0, 8)                        # scope turret
		b.box(Vector3(0, -0.11, 0.21), Vector3(0.008, 0.028, 0.008), DARK)                                   # trigger


## LR-9 long rifle: bolt-action, 1.3 m, heavy fluted barrel with a muzzle brake, a big scope, thumbhole stock, a five-round box
## magazine, a folded bipod. Rust plates like the other invader guns, a thin orange charge line along the receiver.
static func _longrifle(b: Builder, lod: int, g: Color, length: float) -> void:
	var rust := Color(0.5, 0.28, 0.16)
	var h := length * 0.5
	var segs := 12 if lod >= 2 else 10
	b.pbox(Vector3(0, -0.05, 0.08), Vector3(0.062, 0.1, 0.4), METAL, false, Basis.IDENTITY, 0.014)         # receiver
	b.box(Vector3(0, -0.004, 0.08), Vector3(0.02, 0.008, 0.38), LIGHT)                                     # top rail
	b.cyl(Vector3(0, -0.045, -0.36), 0.017, 0.7, DARK, "z", false, -1.0, segs)                              # heavy barrel
	b.cyl(Vector3(0, -0.045, -0.2), 0.026, 0.28, METAL, "z", false, -1.0, segs)                             # fluted shroud over its root
	b.pbox(Vector3(0, -0.045, -h + 0.03), Vector3(0.05, 0.05, 0.1), DARK, false, Basis.IDENTITY, 0.012)    # muzzle brake
	if lod >= 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.026, -0.045, -h + 0.03), Vector3(0.004, 0.03, 0.07), g, true)            # brake slots glow
			b.box(Vector3(sx * 0.032, -0.05, 0.08), Vector3(0.004, 0.012, 0.3), g, true)                  # charge line along the receiver
		for k in 6:
			var a := TAU * float(k) / 6.0
			b.box(Vector3(cos(a) * 0.026, -0.045 + sin(a) * 0.026, -0.2), Vector3(0.004, 0.004, 0.26), DARK, false, Basis().rotated(Vector3.BACK, a))   # flutes
	b.pbox(Vector3(0, -0.1, 0.46), Vector3(0.05, 0.05, 0.4), POLY, false, Basis.IDENTITY, 0.012)           # thumbhole stock: lower bar...
	b.pbox(Vector3(0, -0.06, 0.62), Vector3(0.05, 0.13, 0.08), POLY, false, Basis.IDENTITY, 0.012)         # ...rear block...
	b.pbox(Vector3(0, -0.03, 0.47), Vector3(0.05, 0.04, 0.3), POLY, false, Basis.IDENTITY, 0.01)           # ...and the cheek bar over the thumb hole
	b.pbox(Vector3(0, -0.075, h - 0.01), Vector3(0.05, 0.16, 0.025), DARK)                                 # butt pad
	b.pbox(Vector3(0, -0.15, 0.2), Vector3(0.035, 0.11, 0.045), POLY, false, Basis().rotated(Vector3.RIGHT, -0.3), 0.008)   # grip
	b.pbox(Vector3(0, -0.045, -0.08), Vector3(0.066, 0.05, 0.05), rust)                                    # rust plates on the shroud
	b.pbox(Vector3(0, -0.085, 0.3), Vector3(0.056, 0.03, 0.07), rust)
	b.cyl(Vector3(0, 0.04, 0.02), 0.026, 0.34, DARK, "z", false, -1.0, segs)                                # scope tube
	b.cyl(Vector3(0, 0.04, -0.17), 0.036, 0.07, METAL, "z", false, -1.0, segs)                              # objective bell
	b.cyl(Vector3(0, 0.04, -0.205), 0.03, 0.006, g, "z", true, -1.0, segs)                                  # lens
	b.cyl(Vector3(0, 0.04, 0.215), 0.03, 0.05, METAL, "z", false, -1.0, segs)                               # eyepiece
	b.box(Vector3(0, 0.012, -0.05), Vector3(0.03, 0.03, 0.04), METAL)                                      # scope rings
	b.box(Vector3(0, 0.012, 0.13), Vector3(0.03, 0.03, 0.04), METAL)
	b.part("mag")
	b.pbox(Vector3(0, -0.125, 0.05), Vector3(0.04, 0.09, 0.1), DARK, false, Basis.IDENTITY, 0.008)         # five-round box magazine
	b.box(Vector3(0, -0.172, 0.05), Vector3(0.044, 0.008, 0.104), GUNMETAL)                                # its floor plate
	b.part("bolt")
	b.box(Vector3(0.055, -0.03, 0.2), Vector3(0.08, 0.012, 0.014), STEEL)                                  # bolt handle...
	b.cyl(Vector3(0.1, -0.03, 0.2), 0.013, 0.022, DARK, "x", false, -1.0, 10)                               # ...and its knob
	b.part("")
	if lod >= 2:
		b.box(Vector3(0.032, 0.05, 0.02), Vector3(0.03, 0.03, 0.03), STEEL)                                # windage / elevation turrets
		b.box(Vector3(0, 0.074, 0.02), Vector3(0.03, 0.03, 0.03), STEEL)
		for sx in [-1.0, 1.0]:
			b.box(Vector3(sx * 0.014, -0.1, -0.3), Vector3(0.006, 0.05, 0.2), DARK, false, Basis().rotated(Vector3.FORWARD, sx * 0.25))   # folded bipod legs
		b.box(Vector3(0, -0.11, 0.2), Vector3(0.008, 0.028, 0.008), DARK)                                   # trigger
		b.box(Vector3(0, -0.105, 0.18), Vector3(0.01, 0.01, 0.07), DARK)                                    # trigger guard
		b.box(Vector3(0.032, -0.03, 0.14), Vector3(0.002, 0.03, 0.06), DARK)                                # ejection port


static func _knife(b: Builder, lod: int, g: Color) -> void:
	b.cyl(Vector3(0, 0, 0.065), 0.016, 0.13, DARK, "z", false, -1.0, 10)                                   # handle
	b.pbox(Vector3(0, 0, 0.135), Vector3(0.03, 0.03, 0.014), STEEL)                                        # pommel
	b.pbox(Vector3(0, 0, -0.005), Vector3(0.07, 0.014, 0.016), STEEL, false, Basis.IDENTITY, 0.004)       # guard
	b.pbox(Vector3(0, 0.004, -0.12), Vector3(0.007, 0.032, 0.23), STEEL, false, Basis.IDENTITY, 0.003)    # blade
	b.box(Vector3(0, -0.013, -0.12), Vector3(0.004, 0.006, 0.23), g, true)                                 # glowing edge
	b.box(Vector3(0, 0.0, -0.245), Vector3(0.006, 0.026, 0.04), STEEL, false, Basis().rotated(Vector3.RIGHT, 0.5))   # tip
	if lod >= 2:
		for z in [0.03, 0.065, 0.1]:
			b.cyl(Vector3(0, 0, z), 0.018, 0.008, METAL, "z", false, -1.0, 10)                              # grip rings
		b.box(Vector3(0, 0.021, -0.12), Vector3(0.01, 0.004, 0.22), DARK)                                   # spine
		b.box(Vector3(0, 0.008, -0.11), Vector3(0.0075, 0.006, 0.17), METAL)                                # fuller


static func _blade(b: Builder, lod: int, g: Color) -> void:
	b.cyl(Vector3(0, 0, 0.11), 0.018, 0.22, DARK, "z", false, -1.0, 10)                                    # hilt
	b.cyl(Vector3(0, 0, 0.225), 0.024, 0.02, STEEL, "z", false, -1.0, 10)                                  # pommel
	b.pbox(Vector3(0, 0, 0.0), Vector3(0.05, 0.05, 0.07), METAL, false, Basis.IDENTITY, 0.01)             # emitter housing
	b.pbox(Vector3(0, 0, 0.045), Vector3(0.09, 0.012, 0.02), METAL, false, Basis.IDENTITY, 0.004)         # crossguard
	for sx in [-1.0, 1.0]:
		b.box(Vector3(sx * 0.02, 0, -0.045), Vector3(0.01, 0.07, 0.03), g, true)                           # emitter prongs
	b.box(Vector3(0, 0, -0.45), Vector3(0.012, 0.06, 0.8), g, true)                                       # plasma blade
	b.box(Vector3(0, 0, -0.45), Vector3(0.005, 0.04, 0.78), WHITE, true)                                  # hot core
	b.box(Vector3(0, 0, -0.88), Vector3(0.012, 0.04, 0.06), g, true, Basis().rotated(Vector3.RIGHT, 0.5)) # tip
	if lod >= 2:
		for z in [0.05, 0.09, 0.13, 0.17]:
			b.cyl(Vector3(0, 0, z), 0.02, 0.012, METAL, "z", false, -1.0, 10)                               # grip wraps
		b.box(Vector3(0, 0.026, 0.0), Vector3(0.012, 0.004, 0.05), g, true)                                 # emitter charge light
