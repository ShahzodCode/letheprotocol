class_name InvaderArmour
extends RefCounted
## The shared armour language of the invaders (soldier, rifleman, blade, marksman, gunner): the models differ (a human M4 rig, two
## futuristic rigs), so every kind gets the same kit of rust-eaten plates on its bones and the same helmet: an angular octagonal
## helmet with a dark visor slit, a swept crest and a jaw guard; stacked pauldrons; a chest plate with a gorget and a back pack;
## forearm bracers. `weight` makes the heavy ones bulkier (gunner) and the quick ones lean (blade). The accent colour of the visor
## tells the kinds apart. Visual only (the hit boxes are separate). All the plates of one soldier are ONE skinned, vertex-coloured
## mesh (each plate weighted 100% to its bone, like the model's own skin: no node per plate, no bone attachments to update) plus
## one small unshaded mesh for the visor: 2 draws, hidden beyond SHOW_DIST (`CharModel.show_armour`).

const SHOW_DIST := 55.0          # plates are drawn inside this distance; farther away the tinted model alone reads as the same soldier

const RUST_LIGHT := Color(0.66, 0.31, 0.13)
const RUST := Color(0.47, 0.21, 0.10)
const RUST_DARK := Color(0.27, 0.12, 0.07)
const STEEL := Color(0.14, 0.13, 0.13)

## kind -> [weight, visor colour]
const KINDS := {
	"soldier": [1.0, Color(1.0, 0.45, 0.1)],
	"rifleman": [1.0, Color(1.0, 0.5, 0.12)],
	"blade": [0.85, Color(0.85, 0.35, 1.0)],
	"marksman": [0.95, Color(1.0, 0.1, 0.08)],
	"gunner": [1.3, Color(1.0, 0.75, 0.15)],
}

static var _mat: StandardMaterial3D
static var _visor_mats := {}


## Adds the kit to `model`'s skeleton; returns the MeshInstance3Ds (the enemy shows / hides them by distance).
## Needs the model inside the scene tree (the fitted scale is read from the skeleton).
static func build(model: CharModel, kind: String) -> Array:
	var out := []
	if not KINDS.has(kind) or model.skeleton == null:
		return out
	var wt: float = KINDS[kind][0]
	var acc: Color = KINDS[kind][1]
	var sk := model.skeleton
	var p := {}
	var bones := {}
	for a in ["chest", "neck", "head", "arm_l", "arm_r", "fore_l", "fore_r", "hand_l", "hand_r"]:
		if model.anchor_bone(a) < 0:
			return out
		p[a] = model.anchor_pos(a)
		bones[a] = model.anchor_bone(a)
	var k := model.rest_k()
	var sw := absf(p["arm_l"].x - p["arm_r"].x)                    # shoulder width in metres
	var head_top: Vector3 = model.anchor_pos("headtop") if model.anchor_bone("headtop") >= 0 else p["head"] + Vector3.UP * 0.22
	var hh := clampf(head_top.y - p["head"].y, 0.16, 0.3)          # head height in metres
	var head_c: Vector3 = (p["head"] as Vector3).lerp(head_top, 0.5)
	var hx := hh * 0.46
	var hz := hh * 0.52
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var m := _Mesh.new(rng, 1.0 / k)

	# ---- head: helmet, crest, jaw guard (+ the visor slit as its own unshaded mesh)
	var hb: int = bones["head"]
	m.box(hb, head_c, Vector3(hx, hh * 0.5, hz), Basis.IDENTITY, RUST)
	m.box(hb, head_c, Vector3(hx, hh * 0.5, hz), Basis(Vector3.UP, PI * 0.25), RUST_DARK)           # the same block turned 45 degrees: an octagon from above
	m.box(hb, head_c + Vector3(0, hh * 0.5, -0.01), Vector3(hx * 0.7, 0.02, hz * 0.85), Basis.IDENTITY, RUST_LIGHT)   # the cap
	m.box(hb, head_c + Vector3(0, hh * 0.62, -0.02), Vector3(0.01, 0.04 * wt, hz * 0.9), Basis(Vector3.RIGHT, -0.18), STEEL)   # swept crest
	m.box(hb, head_c + Vector3(0, -hh * 0.45, hz * 0.55), Vector3(hx * 0.7, 0.035, hz * 0.4), Basis.IDENTITY, STEEL)       # jaw guard
	m.box(hb, head_c + Vector3(hx * 1.02, -0.01, 0.0), Vector3(0.01, hh * 0.22, hz * 0.45), Basis.IDENTITY, STEEL)     # ear plates
	m.box(hb, head_c + Vector3(-hx * 1.02, -0.01, 0.0), Vector3(0.01, hh * 0.22, hz * 0.45), Basis.IDENTITY, STEEL)
	var visor := _Mesh.new(rng, 1.0 / k)
	visor.box(hb, head_c + Vector3(0, hh * 0.05, hz * 0.78), Vector3(hx * 0.85, 0.014, hz * 0.3), Basis.IDENTITY, acc)

	# ---- torso: chest plate, gorget, back pack
	var cb: int = bones["chest"]
	var tc: Vector3 = (p["chest"] as Vector3).lerp(p["neck"], 0.45)
	var cw := sw * 0.36 * lerpf(wt, 1.0, 0.5)
	m.box(cb, tc + Vector3(0, 0.0, 0.12), Vector3(cw, 0.13 * lerpf(wt, 1.0, 0.6), 0.04), Basis.IDENTITY, RUST)
	m.box(cb, tc + Vector3(0, -0.02, 0.145), Vector3(cw * 0.55, 0.075, 0.02), Basis.IDENTITY, RUST_LIGHT)
	m.box(cb, tc + Vector3(0, 0.145, 0.015), Vector3(cw * 0.55, 0.035, 0.1), Basis.IDENTITY, STEEL)
	m.box(cb, tc + Vector3(0, 0.0, -0.15), Vector3(0.12 * wt, 0.16 * wt, 0.065 * wt), Basis.IDENTITY, STEEL)
	m.box(cb, tc + Vector3(0, 0.02, -0.22 * wt), Vector3(0.09 * wt, 0.12 * wt, 0.02), Basis.IDENTITY, RUST_DARK)
	if kind == "gunner":
		m.box(cb, tc + Vector3(0.0, -0.12, -0.12), Vector3(0.16, 0.05, 0.09), Basis.IDENTITY, RUST)        # an extra ammo belt block

	# ---- pauldrons (outward is +x on the left arm, -x on the right)
	for side in [1.0, -1.0]:
		var arm_name := "arm_l" if side > 0.0 else "arm_r"
		var ab: int = bones[arm_name]
		var c: Vector3 = p[arm_name] + Vector3(side * 0.015, 0.02, 0.0)
		m.box(ab, c, Vector3(0.085, 0.032, 0.1) * wt, Basis.IDENTITY, RUST)
		m.box(ab, c + Vector3(side * 0.025, 0.045 * wt, 0.0), Vector3(0.065, 0.026, 0.082) * wt, Basis(Vector3.BACK, side * -0.28), RUST_LIGHT)
		m.box(ab, c + Vector3(0.0, -0.03, 0.0), Vector3(0.078, 0.01, 0.092) * wt, Basis.IDENTITY, STEEL)

	# ---- forearm bracers (a block round the middle of the forearm, along it)
	for side in [1.0, -1.0]:
		var fname := "fore_l" if side > 0.0 else "fore_r"
		var hname := "hand_l" if side > 0.0 else "hand_r"
		var fb: int = bones[fname]
		var a: Vector3 = p[fname]
		var h: Vector3 = p[hname]
		var d := (h - a).normalized()
		var ln := a.distance_to(h)
		m.box(fb, a.lerp(h, 0.5), Vector3(0.05 * wt, 0.05 * wt, ln * 0.28), _along(d), RUST_DARK)
		m.box(fb, a.lerp(h, 0.5) + Vector3(0, 0.035, 0), Vector3(0.035 * wt, 0.012, ln * 0.2), _along(d), RUST_LIGHT)

	out.append(_instance(sk, m, _material()))
	out.append(_instance(sk, visor, _visor_material(acc)))
	return out


## A basis whose z axis runs along `d`.
static func _along(d: Vector3) -> Basis:
	var z := d.normalized()
	var x := Vector3.UP.cross(z)
	if x.length() < 0.1:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x), z)


## A skinned MeshInstance3D under the skeleton: every vertex is weighted 100% to the bone it was built for, and the skin's bind
## pose is that bone's rest pose, so the plates stand where they were drawn at rest and then follow the bones.
static func _instance(sk: Skeleton3D, m: _Mesh, mat: Material) -> MeshInstance3D:
	var skin := Skin.new()
	skin.set_bind_count(m.bone_ids.size())
	for j in m.bone_ids.size():
		var bi: int = m.bone_ids[j]
		skin.set_bind_bone(j, bi)
		skin.set_bind_pose(j, sk.get_bone_global_rest(bi).affine_inverse())
	var mi := MeshInstance3D.new()
	mi.mesh = m.finish(mat)
	mi.skin = skin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	return mi


static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.88
		_mat.metallic = 0.2
	return _mat


static func _visor_material(acc: Color) -> StandardMaterial3D:
	if not _visor_mats.has(acc):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_visor_mats[acc] = m
	return _visor_mats[acc]


## Vertex-coloured, skinned box batcher (flat normals, per-face shading + a little random wear so no two plates are the same).
## Boxes are given in model-space metres; `unit` turns them into skeleton units.
class _Mesh:
	var st := SurfaceTool.new()
	var rng: RandomNumberGenerator
	var unit: float
	var bone_ids: Array = []           # skeleton bone of every skin bind

	func _init(r: RandomNumberGenerator, u: float) -> void:
		rng = r
		unit = u
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func box(bone: int, centre: Vector3, half: Vector3, basis: Basis, col: Color) -> void:
		var bind := bone_ids.find(bone)
		if bind < 0:
			bind = bone_ids.size()
			bone_ids.append(bone)
		var bones := PackedInt32Array([bind, 0, 0, 0])
		var weights := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
		var wear := rng.randf_range(0.82, 1.12)
		for f in 6:
			var axis := f / 2
			var sgn := 1.0 if f % 2 == 0 else -1.0
			var n_local := Vector3.ZERO
			n_local[axis] = sgn
			var u_ax := (axis + 1) % 3
			var v_ax := (axis + 2) % 3
			var shade := 1.0
			if axis == 1:
				shade = 1.18 if sgn > 0.0 else 0.62        # tops catch the light, undersides sink
			elif axis == 0:
				shade = 0.88
			var c := Color(col.r * shade * wear, col.g * shade * wear, col.b * shade * wear, 1.0)
			var corners := []
			for q in [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]:
				var su: float = q[0]
				var sv: float = q[1]
				var lp := Vector3.ZERO
				lp[axis] = sgn * half[axis]
				lp[u_ax] = su * half[u_ax]
				lp[v_ax] = sv * half[v_ax]
				corners.append((centre + basis * lp) * unit)
			var nrm := (basis * n_local).normalized()
			var order := [0, 1, 2, 0, 2, 3]
			var tri_n := ((corners[1] - corners[0]) as Vector3).cross(corners[2] - corners[0])
			if tri_n.dot(nrm) < 0.0:
				order = [0, 2, 1, 0, 3, 2]
			for i in order:
				st.set_color(c)
				st.set_normal(nrm)
				st.set_bones(bones)
				st.set_weights(weights)
				st.add_vertex(corners[i])

	func finish(mat: Material) -> ArrayMesh:
		var m := st.commit()
		m.surface_set_material(0, mat)
		return m
