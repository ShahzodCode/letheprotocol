class_name Oaks
extends Node3D
## The city's trees: one species, a summer-green oak made in Blender (tools/trees/make_oak.py, 4 variants in models/trees/oak_*.glb).
## CityWar pushes every standing tree into `Scn.oaks` ([Transform3D, variant, tint Color]) and every felled crown into
## `Scn.oak_crowns` (the far mesh lying on its side). Draw calls stay flat: per variant one MultiMesh of the full mesh (lod0,
## only the trees within NEAR_DIST, packed at the front and cut with visible_instance_count) and one of the light mesh (lod1, every
## tree, the near ones collapsed to zero scale), two surfaces each (bark, leaves). The near set is rebuilt every UPDATE_STEP.
## Leaves: alpha-cut cluster cards with outward normals, wind sway from the vertex colour (r weight, g phase, b crown AO).

const VARIANTS := 4
const MODEL := "res://models/trees/oak_%d.glb"
const NEAR_DIST := 42.0          # full mesh inside this distance from the camera
const NEAR_HYST := 4.0           # a near tree goes back to the light mesh only beyond NEAR_DIST + this
const UPDATE_STEP := 0.3
const MODEL_HEIGHT := 10.0       # the Blender tree is 10 m tall
const WIND := 1.0
const CITY_AABB := AABB(Vector3(-400.0, -5.0, -400.0), Vector3(800.0, 60.0, 800.0))

const LEAF_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D leaves : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float wind = 1.0;
varying float ao;
varying vec3 tint;
void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	float ph = COLOR.g * 6.283 + wp.x * 0.13 + wp.z * 0.17;
	float w = COLOR.r * wind;
	float t = TIME;
	VERTEX += vec3(sin(t * 1.3 + ph), 0.0, cos(t * 1.1 + ph * 1.3)) * 0.07 * w
		+ vec3(sin(t * 4.7 + ph * 3.0 + VERTEX.y), sin(t * 5.3 + ph * 2.0), cos(t * 4.1 + ph * 2.5 + VERTEX.x)) * 0.03 * w * w;
	ao = COLOR.b;
	tint = INSTANCE_CUSTOM.rgb;
}
void fragment() {
	vec4 c = texture(leaves, UV);
	vec3 col = c.rgb * tint * mix(0.5, 1.0, ao);
	ALBEDO = col;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	BACKLIGHT = col * 0.7;
}
"""

const BARK_SHADER := """
shader_type spatial;
uniform sampler2D bark : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform float wind = 1.0;
varying float ao;
void vertex() {
	vec3 wp = MODEL_MATRIX[3].xyz;
	float ph = COLOR.g * 6.283 + wp.x * 0.13 + wp.z * 0.17;
	float w = COLOR.r * wind;
	VERTEX += vec3(sin(TIME * 1.3 + ph), 0.0, cos(TIME * 1.1 + ph * 1.3)) * 0.07 * w;
	ao = COLOR.b;
}
void fragment() {
	ALBEDO = texture(bark, UV).rgb * mix(0.55, 1.0, ao);
	NORMAL_MAP = texture(bark_normal, UV).rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
"""

var _trees: Array = []            # {pos: Vector3, xf: Transform3D, v: int, lod1_idx: int, near: bool, tint: Color}
var _lod0: Array = []             # per variant: MultiMesh
var _lod1: Array = []             # per variant: MultiMesh
var _zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
var _timer := 0.0


static func build(world: Node3D) -> Oaks:
	if Scn.oaks.is_empty() and Scn.oak_crowns.is_empty():
		return null
	var o := Oaks.new()
	o.name = "Oaks"
	world.add_child(o)
	o._setup()
	return o


## Transform of a standing oak: base at `base`, `height` tall, turned by `yaw`.
static func xf_for(base: Vector3, height: float, yaw: float) -> Transform3D:
	var s := height / MODEL_HEIGHT
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), base)


## A variant and a tint from the position (stable across runs, no random stream used).
static func pick(p: Vector2) -> Array:
	var hsh := fposmod(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453, 1.0)
	var v := int(hsh * VARIANTS) % VARIANTS
	var k := fposmod(hsh * 7.31, 1.0)
	var tint := Color(0.9, 0.95, 0.85).lerp(Color(1.08, 1.06, 0.92), k)
	return [v, tint, hsh * TAU]


func _setup() -> void:
	var leaf_mat := ShaderMaterial.new()
	var ls := Shader.new()
	ls.code = LEAF_SHADER
	leaf_mat.shader = ls
	leaf_mat.set_shader_parameter("leaves", load("res://models/trees/oak_leaves.png"))
	leaf_mat.set_shader_parameter("wind", WIND)
	var bark_mat := ShaderMaterial.new()
	var bs := Shader.new()
	bs.code = BARK_SHADER
	bark_mat.shader = bs
	bark_mat.set_shader_parameter("bark", load("res://models/trees/oak_bark.jpg"))
	bark_mat.set_shader_parameter("bark_normal", load("res://models/trees/oak_bark_normal.jpg"))
	bark_mat.set_shader_parameter("wind", WIND)
	var per_v: Array = []
	for v in VARIANTS:
		per_v.append([])
	for it in Scn.oaks:
		var xf: Transform3D = it[0]
		var t := {"pos": xf.origin, "xf": xf, "v": int(it[1]), "tint": it[2], "near": false, "lod1_idx": 0, "crown": false}
		_trees.append(t)
		(per_v[t["v"]] as Array).append(t)
	for it in Scn.oak_crowns:
		var xf2: Transform3D = it[0]
		var t2 := {"pos": xf2.origin, "xf": xf2, "v": int(it[1]), "tint": it[2], "near": false, "lod1_idx": 0, "crown": true}
		(per_v[t2["v"]] as Array).append(t2)
	for v in VARIANTS:
		var meshes := _load_meshes(v)
		var list: Array = per_v[v]
		var mm0 := _multimesh(meshes[0], maxi(1, list.size()))
		mm0.visible_instance_count = 0
		var mm1 := _multimesh(meshes[1], maxi(1, list.size()))
		for i in list.size():
			var t3: Dictionary = list[i]
			t3["lod1_idx"] = i
			mm1.set_instance_transform(i, t3["xf"])
			mm1.set_instance_custom_data(i, t3["tint"])
		if list.is_empty():
			mm1.visible_instance_count = 0
		_lod0.append(mm0)
		_lod1.append(mm1)
		for mm in [mm0, mm1]:
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = mm
			add_child(inst)
			_apply_mats(inst, mm.mesh, bark_mat, leaf_mat)


func _apply_mats(inst: MultiMeshInstance3D, mesh: Mesh, bark_mat: Material, leaf_mat: Material) -> void:
	# a MultiMeshInstance3D has no per-surface override: the materials go on the mesh surfaces (the mesh is our own copy).
	# The glb comes without material names (exported as placeholders): Blender's order holds, surface 0 bark, surface 1 leaves.
	for s in mesh.get_surface_count():
		var nm := String((mesh as ArrayMesh).surface_get_name(s)) if mesh is ArrayMesh else ""
		var mat_name := ""
		var m := mesh.surface_get_material(s)
		if m != null:
			mat_name = m.resource_name
		var is_leaf := mat_name.begins_with("leaves") or nm.begins_with("leaves") or (mat_name == "" and nm == "" and s == 1)
		mesh.surface_set_material(s, leaf_mat if is_leaf else bark_mat)


func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.custom_aabb = CITY_AABB          # the near set moves: never cull on stale instance bounds
	return mm


## The two meshes of one variant ("lod0", "lod1" nodes of the glb), duplicated so the materials can be set on them.
func _load_meshes(v: int) -> Array:
	var scene := (load(MODEL % v) as PackedScene).instantiate()
	var out: Array = [null, null]
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var idx := 0 if String(mi.name).begins_with("lod0") else 1
		out[idx] = mi.mesh.duplicate()
	scene.free()
	return out


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_STEP
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var changed := false
	for t in _trees:
		var d: float = (t["pos"] as Vector3).distance_to(cp)
		var near: bool = d < NEAR_DIST or (t["near"] and d < NEAR_DIST + NEAR_HYST)
		if near != t["near"]:
			t["near"] = near
			changed = true
			(_lod1[t["v"]] as MultiMesh).set_instance_transform(t["lod1_idx"], _zero if near else t["xf"])
	if not changed:
		return
	var fill: Array = []
	for v in VARIANTS:
		fill.append(0)
	for t in _trees:
		if t["near"]:
			var v2: int = t["v"]
			var mm: MultiMesh = _lod0[v2]
			mm.set_instance_transform(fill[v2], t["xf"])
			mm.set_instance_custom_data(fill[v2], t["tint"])
			fill[v2] += 1
	for v in VARIANTS:
		(_lod0[v] as MultiMesh).visible_instance_count = fill[v]
