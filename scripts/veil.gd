class_name Veil
extends Node3D
## The sky of the invasion morning (Chapter One, "The Streets"): the Veil is a faint pearly dome that flickers in oil-on-water
## colours, with a ragged dark wound above the city centre whose edges crackle, silent flashes far off, black smoke pillars
## over the power stations at the forest edge (south and east) and a handful of landing craft drifting down through the hole.
## Cost: ONE sky shader (it only runs on the sky pixels left between the buildings, no TIME / POSITION built-ins: the uniforms
## `t` and `cam_pos` are set from here, so the sky's radiance map is never re-rendered), two MultiMeshes (hulls, heat shimmer;
## 8 instances each, moved 4 times a second) and one MultiMesh for the pillars. Nothing allocates per frame.
## `LETHE_NOVEIL=1` (environment) builds the plain procedural sky instead, a baseline for frame-time comparisons.

const DOME_H := 480.0              # height of the imagined veil dome the wound is drawn on
const HOLE_C := Vector2(0.0, 0.0)  # the wound hangs over the city centre
const HOLE_R := 320.0
const LANDERS := 8
const LANDER_STEP := 0.25          # seconds between lander transform updates
const LANDER_DIST_MAX := 0.85      # landers are pulled in along the view line (and shrunk) to stay inside this fraction of camera.far
const SHIMMER_H := 3.0             # heat shimmer column length in lander sizes
## Smoke pillars over the power stations at the forest edge: [x, z, width, height, lean x, lean z] (outside the playable ring)
const PILLARS := [
	[-70.0, 430.0, 46.0, 900.0, 0.10, -0.04], [60.0, 470.0, 38.0, 820.0, 0.08, -0.05],
	[400.0, 60.0, 52.0, 900.0, -0.05, 0.1], [440.0, -90.0, 40.0, 780.0, -0.06, 0.09], [420.0, 190.0, 44.0, 840.0, -0.04, 0.08],
]

const SKY_SHADER := """
shader_type sky;
uniform vec3 cam_pos = vec3(0.0);
uniform float t = 0.0;
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 top_col : source_color = vec3(0.34, 0.5, 0.78);
uniform vec3 horizon_col : source_color = vec3(0.74, 0.72, 0.68);
uniform vec3 ground_horizon_col : source_color = vec3(0.7, 0.67, 0.62);
uniform vec3 ground_bottom_col : source_color = vec3(0.58, 0.56, 0.54);
uniform float dome_h = 480.0;
uniform vec2 hole_c = vec2(0.0);
uniform float hole_r = 320.0;

float h11(float p) {
	return fract(sin(p * 127.1 + 31.7) * 43758.5453);
}
float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	vec3 e = EYEDIR;
	float up = clamp(e.y, 0.0, 1.0);
	vec3 col = mix(horizon_col, top_col, pow(up, 0.45));
	if (e.y < 0.0) {
		col = mix(ground_horizon_col, ground_bottom_col, pow(clamp(-e.y, 0.0, 1.0), 0.5));
	}
	// hazy sun glow (no disc: the veil scatters it)
	float sd = max(dot(e, sun_dir), 0.0);
	col += vec3(1.0, 0.93, 0.78) * (pow(sd, 60.0) * 0.5 + pow(sd, 8.0) * 0.08);

	float above = smoothstep(-0.02, 0.18, e.y);
	// the veil: pearly sheen + oil-on-water colours drifting over the dome, flaring violently at random
	vec2 dome = e.xz / (e.y + 0.35);
	float n = vnoise(dome * 2.2 + vec2(t * 0.05, -t * 0.03)) * 0.6 + vnoise(dome * 5.5 - vec2(t * 0.11, t * 0.07)) * 0.3 + vnoise(dome * 13.0 + t * 0.2) * 0.1;
	float burst = step(0.74, h11(floor(t * 7.0)));
	float burst2 = step(0.86, h11(floor(t * 2.3) + 41.0));
	float flick = (0.18 + 0.82 * max(burst, burst2)) * (0.55 + 0.45 * sin(t * 1.7 + n * 6.0));
	vec3 irid = 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + n * 1.6 + t * 0.07));
	col += (vec3(0.07, 0.065, 0.08) + irid * (0.05 + 0.38 * flick)) * above * (0.45 + n * 0.8);

	// silent flashes far off: a glow in a random direction that dies away quickly
	float rate = 0.8;
	float cell = floor(t * rate);
	float ph = fract(t * rate);
	float on = step(0.45, h11(cell + 7.0));
	vec3 fd = normalize(vec3(h11(cell + 1.0) - 0.5, 0.05 + 0.45 * h11(cell + 2.0), h11(cell + 3.0) - 0.5));
	float fl = pow(max(dot(e, fd), 0.0), 18.0) * on * exp(-ph * 9.0) * step(0.02, ph);
	col += vec3(1.0, 0.82, 0.6) * fl * 1.4;

	// the wound: where the view ray meets the dome, a ragged hole over the city centre with crackling edges
	if (e.y > 0.04) {
		float s = max(dome_h - cam_pos.y, 10.0) / e.y;
		vec2 q = (cam_pos.xz + e.xz * s - hole_c) / hole_r;
		float rag = vnoise(q * 3.3 + vec2(t * 0.25, 0.0)) * 0.34 + vnoise(q * 9.0 - vec2(0.0, t * 0.7)) * 0.12;
		float d = length(q) + rag - 0.24;
		float fade = smoothstep(0.04, 0.22, e.y);
		float hole = (1.0 - smoothstep(0.82, 0.93, d)) * fade;
		float ring = smoothstep(0.74, 0.9, d) * (1.0 - smoothstep(0.93, 1.03, d)) * fade;
		float crack = 0.5 + 0.5 * sin(d * 46.0 + vnoise(q * 14.0) * 14.0 + t * 26.0);
		float spark = step(0.55, h11(floor(t * 14.0 + d * 9.0)));
		vec3 inside = mix(vec3(0.015, 0.012, 0.03), vec3(0.16, 0.035, 0.03), clamp(1.0 - d * 1.2, 0.0, 1.0) * (0.5 + 0.5 * sin(t * 0.8 + q.x * 3.0)));
		col = mix(col, inside, hole);
		col += mix(vec3(0.55, 0.85, 1.0), vec3(1.0, 0.45, 0.9), vnoise(q * 6.0 + t)) * ring * crack * (0.35 + 1.1 * (flick * 0.5 + spark * 0.5));
	}
	COLOR = col;
}
"""

const SHIMMER_SHADER := """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;
varying vec2 uvv;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	vec3 to_cam = vec3(INV_VIEW_MATRIX[3].x - origin.x, 0.0, INV_VIEW_MATRIX[3].z - origin.z);
	to_cam = normalize(to_cam + vec3(0.0001));
	vec3 right = vec3(to_cam.z, 0.0, -to_cam.x);
	vec3 wp = origin + right * VERTEX.x * sx + vec3(0.0, 1.0, 0.0) * VERTEX.y * sy;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	uvv = UV;
}
void fragment() {
	float x = abs(uvv.x - 0.5) * 2.0;
	float across = 1.0 - smoothstep(0.1, 1.0, x);
	float along = smoothstep(0.0, 0.12, uvv.y) * (1.0 - smoothstep(0.35, 1.0, uvv.y));
	float wob = 0.5 + 0.5 * sin(uvv.y * 60.0 - TIME * 5.0 + uvv.x * 17.0 + sin(uvv.y * 21.0 + TIME) * 3.0);
	ALBEDO = vec3(1.0, 0.62, 0.3) * across * along * (0.2 + 0.3 * wob);
}
"""

var clock := 0.0
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var hull_mm: MultiMesh
var shimmer_mm: MultiMesh
var _step_t := 0.0
var _basis_cache: Array = []       # per lander: [yaw0, spin, sway phase, size]
var lander_world: Array[Vector3] = []   # true (uncompressed) positions at the last update, for the tests


static func enabled() -> bool:
	return OS.get_environment("LETHE_NOVEIL") == ""


## The sky shader material with the same palette as the old procedural sky.
static func make_sky_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = SKY_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("dome_h", DOME_H)
	m.set_shader_parameter("hole_c", HOLE_C)
	m.set_shader_parameter("hole_r", HOLE_R)
	return m


## Where lander `i` is `t` seconds into the story: an analytic path (hull, shimmer and the tests all use it). The first two
## are already on the way down at t = 0, the others follow every 14 s; each sinks about 3-4 m/s to its own resting height and
## then drifts outwards over the districts.
static func lander_pos(i: int, t: float) -> Vector3:
	var a := float(i) * TAU / float(LANDERS) + 0.5 * sin(float(i) * 7.3)
	var r0 := HOLE_R * (0.15 + 0.5 * fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0))
	var delay := float(i) * 14.0 - 30.0
	var tt := maxf(0.0, t - delay)
	var y0 := DOME_H - 40.0 + 30.0 * float(i % 3)
	var rest := 150.0 + 25.0 * float((i * 5) % 7)
	var fall := 3.0 + 0.25 * float(i % 4)
	var y := maxf(rest, y0 - fall * tt)
	var drift := 1.1 + 0.15 * float(i % 3)
	var r := r0 + drift * tt
	var ang := a + 0.0015 * tt
	return Vector3(HOLE_C.x + cos(ang) * r, y, HOLE_C.y + sin(ang) * r)


static func lander_size(i: int) -> float:
	return 34.0 + 4.0 * float(i % 4)


func setup(sun_light: DirectionalLight3D, material: ShaderMaterial) -> void:
	sun = sun_light
	sky_mat = material
	if sun != null:
		sky_mat.set_shader_parameter("sun_dir", sun.global_transform.basis.z)
	_build_landers()
	_build_pillars()
	_update_landers()


func _build_landers() -> void:
	hull_mm = MultiMesh.new()
	hull_mm.transform_format = MultiMesh.TRANSFORM_3D
	hull_mm.mesh = _hull_mesh()
	hull_mm.instance_count = LANDERS
	var hull := MultiMeshInstance3D.new()
	hull.multimesh = hull_mm
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hull.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.vertex_color_use_as_albedo = true
	hm.vertex_color_is_srgb = true
	hm.disable_fog = true
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hull.material_override = hm
	add_child(hull)

	shimmer_mm = MultiMesh.new()
	shimmer_mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0, 0.5, 0)          # the column grows upwards from the origin; instances hang it below the hull
	shimmer_mm.mesh = quad
	shimmer_mm.instance_count = LANDERS
	var sh := MultiMeshInstance3D.new()
	sh.multimesh = shimmer_mm
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
	var shader := Shader.new()
	shader.code = SHIMMER_SHADER
	var smat := ShaderMaterial.new()
	smat.shader = shader
	sh.material_override = smat
	add_child(sh)
	for i in LANDERS:
		_basis_cache.append([float(i) * 1.7, 0.04 + 0.01 * float(i % 3), float(i) * 2.3, lander_size(i)])
		lander_world.append(Vector3.ZERO)


## Black smoke pillars from the power stations: tilted tapered cylinders, unshaded, not fogged (they must read as black
## columns through the haze). One MultiMesh.
func _build_pillars() -> void:
	var items: Array = []
	for p in PILLARS:
		var w: float = p[2]
		var h: float = p[3]
		var lean := Vector3(float(p[4]), 0.0, float(p[5]))
		var up := (Vector3.UP + lean).normalized()
		var base := Vector3(float(p[0]), 0.0, float(p[1]))
		var x := up.cross(Vector3.RIGHT).normalized()
		var z := x.cross(up)
		var xf := Transform3D(Basis(x * w, up * h, z * w), base + up * h * 0.5)
		items.append([xf, Color(0.05, 0.045, 0.045, 0.82)])
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.16
	cyl.height = 1.0
	cyl.radial_segments = 10
	cyl.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.disable_fog = true
	WorldWar._mm(self, cyl, items, m, false, 0.0, 2000.0)


## Landing craft silhouette: a lens-shaped hull with an engine bell and three landing legs (unit radius), vertex coloured:
## dark rust on top, darker underneath, a hot orange bell. Flat shaded, 56 triangles.
static func _hull_mesh() -> ArrayMesh:
	var v: Array = []
	var c: Array = []
	var n: Array = []
	var tri := func(a: Vector3, b: Vector3, d: Vector3, col: Color) -> void:
		var nn := (b - a).cross(d - a).normalized()
		for p in [a, b, d]:
			v.append(p)
			n.append(nn)
			c.append(col)
	var top := Vector3(0, 0.3, 0)
	var bottom := Vector3(0, -0.42, 0)
	var k := 8
	for i in k:
		var a0 := TAU * float(i) / float(k)
		var a1 := TAU * float(i + 1) / float(k)
		var p0 := Vector3(cos(a0), 0.0, sin(a0))
		var p1 := Vector3(cos(a1), 0.0, sin(a1))
		var shade := 0.85 + 0.3 * float(i % 2)
		tri.call(top, p1, p0, Color(0.24, 0.15, 0.11) * shade)
		tri.call(bottom, p0, p1, Color(0.1, 0.075, 0.07) * shade)
		var q0 := Vector3(cos(a0) * 0.34, -0.42, sin(a0) * 0.34)
		var q1 := Vector3(cos(a1) * 0.34, -0.42, sin(a1) * 0.34)
		var tip := Vector3(0, -0.8, 0)
		tri.call(tip, q0, q1, Color(1.0, 0.58, 0.22))
	for l in 3:
		var al := TAU * (float(l) + 0.25) / 3.0
		var dir := Vector3(cos(al), 0.0, sin(al))
		var side := Vector3(-dir.z, 0.0, dir.x) * 0.05
		var foot := dir * 1.12 + Vector3(0, -0.72, 0)
		tri.call(dir * 0.7 + Vector3(0, -0.12, 0) - side, foot, dir * 0.7 + Vector3(0, -0.12, 0) + side, Color(0.08, 0.07, 0.07))
		tri.call(dir * 0.7 + Vector3(0, -0.12, 0) + side, foot, dir * 0.7 + Vector3(0, -0.12, 0) - side, Color(0.08, 0.07, 0.07))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(v)
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(n)
	arr[Mesh.ARRAY_COLOR] = PackedColorArray(c)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _process(delta: float) -> void:
	clock += delta
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		sky_mat.set_shader_parameter("cam_pos", cam.global_position)
	sky_mat.set_shader_parameter("t", clock)
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = LANDER_STEP
		_update_landers()


## Moves the 8 hulls and their heat shimmer. A lander farther than LANDER_DIST_MAX x camera.far is pulled in along the view line
## and shrunk by the same factor, so it keeps its place and size on screen whatever the view distance setting is.
func _update_landers() -> void:
	if hull_mm == null:
		return
	var cam := get_viewport().get_camera_3d()
	var cp := cam.global_position if cam != null else Vector3.ZERO
	var dmax := (cam.far if cam != null else 700.0) * LANDER_DIST_MAX
	for i in LANDERS:
		var p := lander_pos(i, clock)
		lander_world[i] = p
		var info: Array = _basis_cache[i]
		var size: float = info[3]
		var off := p - cp
		var d := off.length()
		if d > dmax:
			var k := dmax / d
			p = cp + off * k
			size *= k
		var yaw: float = info[0] + info[1] * clock
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.07 * sin(clock * 0.35 + float(info[2]))) * Basis(Vector3.FORWARD, 0.06 * sin(clock * 0.27 + float(info[2]) * 1.3))
		b = b.scaled(Vector3(size, size * 0.8, size))
		hull_mm.set_instance_transform(i, Transform3D(b, p))
		var sh_h := size * SHIMMER_H
		shimmer_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(size * 0.75, sh_h, 1.0)), p - Vector3(0, size * 0.62 + sh_h, 0)))
