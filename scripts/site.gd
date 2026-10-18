class_name Site
extends Node3D
## A battle site: asphalt smashed by heavy weapons, churned to mud, with craters, cracks, rubble and a few small fires.
## All the static damage is two MultiMeshes (one draw call each, no collision). The fires, their particles and the light
## only run while the player is near: `set_lod()` is driven by Main from the distance, so with several sites on the map
## only the one(s) around the player cost anything.
##   lod 0 = far (nothing drawn), 1 = ground damage only, 2 = flames + smoke + sparks, 3 = also the firelight.

const FAR := 230.0
const MID := 120.0
const NEAR := 55.0

var radius := 13.0
var lod := -1
var _fires: Array = []          # [{root: Node3D, flames: Array[MeshInstance3D], smoke: CPUParticles3D, sparks: CPUParticles3D, phase: float}]
var _light: OmniLight3D


## Distance -> level of detail, with a little hysteresis so a player standing on a boundary does not flip it every tick.
static func lod_for(dist: float, current: int) -> int:
	var slack := 8.0
	var far_d := FAR + (slack if current >= 1 else 0.0)
	var mid_d := MID + (slack if current >= 2 else 0.0)
	var near_d := NEAR + (slack if current >= 3 else 0.0)
	if dist > far_d:
		return 0
	if dist > mid_d:
		return 1
	if dist > near_d:
		return 2
	return 3


func build(center: Vector3, r: float, seed_value: int) -> void:
	position = Vector3(center.x, 0.0, center.z)
	radius = r
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var discs: Array = []       # [Transform3D, Color]  (cylinders: mud, craters)
	var boxes: Array = []       # [Transform3D, Color]  (chunks of asphalt, cracks, planks)

	# craters: a mud disc, a darker pit, a rim of broken asphalt and cracks running out of it
	var crater_pos: Array = []
	for i in 3:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, r * 0.6)
		var cp := Vector3(cos(a) * d, 0.0, sin(a) * d)
		crater_pos.append(cp)
		var cr := rng.randf_range(2.4, 4.4)
		discs.append([_disc(cp, cr * 1.5, cr * 1.35, 0.045, rng.randf() * TAU), Color(0.2, 0.14, 0.09)])      # blast scorch / mud
		discs.append([_disc(cp, cr, cr * 0.92, 0.058, rng.randf() * TAU), Color(0.13, 0.09, 0.06)])
		discs.append([_disc(cp, cr * 0.55, cr * 0.5, 0.07, rng.randf() * TAU), Color(0.06, 0.045, 0.035)])
		for k in 10:
			var ra := TAU * float(k) / 10.0 + rng.randf_range(-0.2, 0.2)
			var rr := cr * rng.randf_range(1.05, 1.4)
			var sz := Vector3(rng.randf_range(0.5, 1.4), rng.randf_range(0.12, 0.4), rng.randf_range(0.4, 1.1))
			var pos := cp + Vector3(cos(ra) * rr, sz.y * 0.35, sin(ra) * rr)
			boxes.append([_tilted(pos, sz, rng), _asphalt(rng)])
		for k in 3:
			var ca := rng.randf() * TAU
			var cl := rng.randf_range(4.0, 9.0)
			var from := cp + Vector3(cos(ca), 0, sin(ca)) * (cr * 1.2)
			var mid := from + Vector3(cos(ca), 0, sin(ca)) * cl * 0.5
			var cb := Basis().rotated(Vector3.UP, -ca + PI * 0.5).scaled(Vector3(rng.randf_range(0.1, 0.2), 0.02, cl))
			boxes.append([Transform3D(cb, Vector3(mid.x, 0.08, mid.z)), Color(0.05, 0.05, 0.06)])

	# churned mud around the fighting
	for i in 11:
		var a2 := rng.randf() * TAU
		var d2 := rng.randf_range(0.0, r * 0.95)
		var p2 := Vector3(cos(a2) * d2, 0.0, sin(a2) * d2)
		var mr := rng.randf_range(1.4, 4.2)
		var mud := Color(0.3, 0.22, 0.14).lerp(Color(0.22, 0.16, 0.1), rng.randf())
		discs.append([_disc(p2, mr, mr * rng.randf_range(0.6, 1.0), 0.04 + rng.randf() * 0.004, rng.randf() * TAU), mud])
	# loose rubble and charred planks
	for i in 24:
		var a3 := rng.randf() * TAU
		var d3 := rng.randf_range(1.0, r)
		var sz2 := Vector3(rng.randf_range(0.25, 0.9), rng.randf_range(0.08, 0.3), rng.randf_range(0.25, 0.8))
		boxes.append([_tilted(Vector3(cos(a3) * d3, sz2.y * 0.35, sin(a3) * d3), sz2, rng), _asphalt(rng)])
	for i in 5:
		var a4 := rng.randf() * TAU
		var d4 := rng.randf_range(2.0, r * 0.9)
		var pl := Basis().rotated(Vector3.UP, rng.randf() * TAU).scaled(Vector3(0.18, 0.08, rng.randf_range(1.2, 2.4)))
		boxes.append([Transform3D(pl, Vector3(cos(a4) * d4, 0.07, sin(a4) * d4)), Color(0.13, 0.09, 0.06)])

	add_child(_multimesh(CylinderMesh.new(), discs, true))
	add_child(_multimesh(BoxMesh.new(), boxes, false))

	# small fires: a burnt-out barrel or crate with flames on top, spread around the craters
	for i in 4:
		var base: Vector3 = crater_pos[i % crater_pos.size()]
		var a5 := rng.randf() * TAU
		var fp := base + Vector3(cos(a5), 0, sin(a5)) * rng.randf_range(2.5, 5.5)
		if fp.length() > r:
			fp = fp.normalized() * r * 0.9
		_add_fire(fp, rng, i)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.light_energy = 1.5
	_light.omni_range = 24.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 2.6, 0)
	_light.visible = false
	add_child(_light)
	set_lod(0)


func _disc(pos: Vector3, rx: float, rz: float, top: float, yaw: float) -> Transform3D:
	var b := Basis().rotated(Vector3.UP, yaw).scaled(Vector3(rx, 0.03, rz))
	return Transform3D(b, Vector3(pos.x, top - 0.015, pos.z))


func _tilted(pos: Vector3, size: Vector3, rng: RandomNumberGenerator) -> Transform3D:
	var b := Basis().rotated(Vector3.UP, rng.randf() * TAU)
	b = b.rotated(b.x, rng.randf_range(-0.3, 0.3)).rotated(b.z, rng.randf_range(-0.3, 0.3)).scaled(size)
	return Transform3D(b, pos)


func _asphalt(rng: RandomNumberGenerator) -> Color:
	var g := rng.randf_range(0.14, 0.34)
	return Color(g, g * 0.98, g * 1.02) if rng.randf() < 0.8 else Color(0.25, 0.18, 0.11)


func _multimesh(mesh: Mesh, items: Array, is_cylinder: bool) -> MultiMeshInstance3D:
	if is_cylinder:
		var cm: CylinderMesh = mesh
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 12
		cm.rings = 1
	else:
		(mesh as BoxMesh).size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


func _flame(parent: Node3D, radius_b: float, height: float, y: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = radius_b
	cm.height = height
	cm.radial_segments = 5
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	cm.material = m
	mi.mesh = cm
	mi.position = Vector3(0, y + height * 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _particles(amount: int, life: float, size: float, color: Color, fade: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	var bm := BoxMesh.new()
	bm.size = Vector3(size, size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	if fade:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = m
	p.mesh = bm
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _add_fire(pos: Vector3, rng: RandomNumberGenerator, idx: int) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	# the burnt-out thing that is burning
	var body := MeshInstance3D.new()
	var bm: Mesh
	var top := 0.9
	if idx % 2 == 0:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.38
		cyl.bottom_radius = 0.4
		cyl.height = 0.9
		cyl.radial_segments = 8
		bm = cyl
	else:
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 0.7, 0.9)
		bm = box
		top = 0.7
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.07, 0.06, 0.055)
	bmat.roughness = 1.0
	bm.material = bmat
	body.mesh = bm
	body.position = Vector3(0, top * 0.5, 0)
	body.rotation.y = rng.randf() * TAU
	root.add_child(body)
	var flames: Array = []
	flames.append(_flame(root, 0.34, 1.2, top - 0.05, Color(1.0, 0.4, 0.06)))
	flames.append(_flame(root, 0.23, 0.9, top - 0.02, Color(1.0, 0.68, 0.15)))
	flames.append(_flame(root, 0.12, 0.55, top, Color(1.0, 0.95, 0.6)))
	var smoke := _particles(7, 3.0, 0.5, Color(0.18, 0.18, 0.19, 0.75), true)
	smoke.position = Vector3(0, top + 0.9, 0)
	smoke.direction = Vector3.UP
	smoke.spread = 14.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 1.8
	smoke.gravity = Vector3(0, 0.3, 0)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 2.0
	root.add_child(smoke)
	var sparks := _particles(5, 1.0, 0.06, Color(1.0, 0.8, 0.3, 1.0), false)
	sparks.position = Vector3(0, top + 0.5, 0)
	sparks.direction = Vector3.UP
	sparks.spread = 35.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 4.0
	sparks.gravity = Vector3(0, -6.0, 0)
	root.add_child(sparks)
	_fires.append({"root": root, "flames": flames, "smoke": smoke, "sparks": sparks, "phase": rng.randf() * 10.0})


func set_lod(l: int) -> void:
	if l == lod:
		return
	Game.mark("site_lod")
	lod = l
	visible = l >= 1
	for f in _fires:
		var root: Node3D = f["root"]
		root.visible = l >= 2
		root.process_mode = Node.PROCESS_MODE_INHERIT if l >= 2 else Node.PROCESS_MODE_DISABLED
		(f["smoke"] as CPUParticles3D).emitting = l >= 2
		(f["sparks"] as CPUParticles3D).emitting = l >= 2
	_light.visible = l >= 3


## Flicker the flames and the firelight; called only while lod >= 2.
func animate(t: float) -> void:
	for f in _fires:
		var ph: float = f["phase"]
		var k := 0.8 + 0.25 * sin(t * 11.0 + ph) + 0.15 * sin(t * 23.0 + ph * 2.0)
		var flames: Array = f["flames"]
		for i in flames.size():
			var fl := flames[i] as MeshInstance3D
			fl.scale = Vector3(1.0 + 0.1 * sin(t * 17.0 + ph + i), k + 0.1 * i, 1.0 + 0.1 * cos(t * 13.0 + ph))
			fl.rotation.y = t * (1.5 + i) + ph
	if _light.visible:
		_light.light_energy = 1.3 + 0.35 * sin(t * 9.0) + 0.2 * sin(t * 21.0)
