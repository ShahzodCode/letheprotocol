class_name Fires
extends Node3D
## Everything that burns or sparks in the city (Scn.fires: trees, cars, buildings, broken wires). The fires are data; only the ones
## near the player get real nodes (flames, a puff of smoke particles), and only the few nearest of each kind get a light.
## Far away the burning things are drawn by WorldWar as flickering canopies, glowing windows and tall dark smoke columns.
## Main calls `update(player_position)` a few times a second and `animate(time)` every frame.

const RANGE := {"tree": 85.0, "car": 85.0, "build": 190.0, "spark": 40.0, "tunnel": 45.0}
const MAX_ACTIVE := 16
const LIGHTS := {"tree": 4, "build": 3, "car": 2, "tunnel": 2}
const LIGHT_RANGE := {"tree": 9.0, "build": 16.0, "car": 8.0, "tunnel": 9.0}
const LIGHT_DIST := 60.0

var entries: Array = []          # {kind, pos, s, node, phase}
var _lights := {}                # kind -> Array[OmniLight3D]
var active_count := 0


func setup(list: Array) -> void:
	for f in list:
		entries.append({"id": entries.size(), "kind": f["kind"], "pos": f["pos"], "s": float(f["s"]), "node": null, "phase": fposmod(float((f["pos"] as Vector3).x * 0.37 + (f["pos"] as Vector3).z * 0.19), 6.28)})
	for k in LIGHTS:
		var arr: Array = []
		for i in int(LIGHTS[k]):
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.92, 0.75) if k == "tunnel" else Color(1.0, 0.55, 0.22)
			l.omni_range = float(LIGHT_RANGE[k])
			l.light_energy = 1.4
			l.shadow_enabled = false
			l.visible = false
			add_child(l)
			arr.append(l)
		_lights[k] = arr


func update(pp: Vector3) -> void:
	var near: Array = []             # fires and sparks near the player: [distance, entry]
	var lamps: Array = []            # corridor lamps ("tunnel"): only a light, no nodes
	for e in entries:
		var d := Vector2((e["pos"] as Vector3).x - pp.x, (e["pos"] as Vector3).z - pp.z).length()
		if d < float(RANGE[e["kind"]]):
			if e["kind"] == "tunnel":
				lamps.append([d, e])
			else:
				near.append([d, e])
		elif e["node"] != null:
			_drop(e)
	near.sort_custom(func(a, b): return a[0] < b[0])
	lamps.sort_custom(func(a, b): return a[0] < b[0])
	var keep := {}
	for i in mini(near.size(), MAX_ACTIVE):
		var e2: Dictionary = near[i][1]
		keep[e2["id"]] = true
		if e2["node"] == null:
			_make(e2)
	for i in range(MAX_ACTIVE, near.size()):
		if near[i][1]["node"] != null:
			_drop(near[i][1])
	active_count = mini(near.size(), MAX_ACTIVE)
	for it in lamps:
		keep[(it[1] as Dictionary)["id"]] = true
	near.append_array(lamps)
	# lights: the nearest few of each kind
	for k in LIGHTS:
		var arr: Array = _lights[k]
		var chosen: Array = []
		for it in near:
			var e3: Dictionary = it[1]
			if e3["kind"] == k and float(it[0]) < LIGHT_DIST and keep.has(e3["id"]):
				chosen.append(e3)
				if chosen.size() >= arr.size():
					break
		for i in arr.size():
			var l := arr[i] as OmniLight3D
			if i < chosen.size():
				l.visible = true
				l.position = (chosen[i]["pos"] as Vector3) + (Vector3(0, 0.2, 0) if k == "tunnel" else Vector3(0, 1.0, 0))
			else:
				l.visible = false


func _drop(e: Dictionary) -> void:
	if e["node"] != null:
		(e["node"] as Node).queue_free()
		e["node"] = null


func _make(e: Dictionary) -> void:
	Game.mark("fire_nodes")
	var kind: String = e["kind"]
	var s: float = e["s"]
	var root := Node3D.new()
	root.position = e["pos"]
	add_child(root)
	e["node"] = root
	e["flames"] = []
	if kind == "spark":
		var sp := _particles(10, 0.8, 0.07, Color(1.0, 0.85, 0.4, 1.0), false, false)
		sp.direction = Vector3.UP
		sp.spread = 70.0
		sp.initial_velocity_min = 1.5
		sp.initial_velocity_max = 4.5
		sp.gravity = Vector3(0, -9.0, 0)
		root.add_child(sp)
		sp.emitting = true
		return
	var big := kind == "build"
	if kind == "car":
		_flame(root, e, 0.55 * s, 1.4, 0.0, Color(1.0, 0.4, 0.06))
		_flame(root, e, 0.35 * s, 1.0, 0.1, Color(1.0, 0.68, 0.15))
	elif kind == "tree":
		_flame(root, e, 0.8 * s, 1.5, -0.4, Color(1.0, 0.45, 0.08))
		_flame(root, e, 0.45 * s, 1.1, -0.2, Color(1.0, 0.72, 0.2))
	else:
		_flame(root, e, 1.4 * s, 3.0, 0.0, Color(1.0, 0.4, 0.06))
		_flame(root, e, 0.8 * s, 2.0, 0.2, Color(1.0, 0.7, 0.18))
	var smoke := _particles(14 if big else 7, 7.0 if big else 3.6, 1.0, Color(0.1, 0.1, 0.11, 0.7), true, true)
	smoke.position = Vector3(0, 0.6, 0)
	smoke.direction = Vector3.UP
	smoke.spread = 9.0
	smoke.initial_velocity_min = 2.2 if big else 1.2
	smoke.initial_velocity_max = 3.6 if big else 2.0
	smoke.gravity = Vector3(0.35, 0.2, 0.1)
	smoke.scale_amount_min = 3.0 if big else 1.2
	smoke.scale_amount_max = 7.0 if big else 2.6
	root.add_child(smoke)
	smoke.emitting = true


func _flame(parent: Node3D, e: Dictionary, r: float, h: float, y: float, color: Color) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 5
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	cm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.position = Vector3(0, y + h * 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	(e["flames"] as Array).append(mi)


func _particles(amount: int, life: float, size: float, color: Color, fade: bool, quad: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	if fade:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if quad:
		var qm := QuadMesh.new()
		qm.size = Vector2(size, size)
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		qm.material = m
		p.mesh = qm
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(size, size, size)
		bm.material = m
		p.mesh = bm
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = g
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Flicker the flames and the lights (cheap: only the active few).
func animate(t: float) -> void:
	for e in entries:
		if e["node"] == null or not e.has("flames"):
			continue
		var ph: float = e["phase"]
		var k := 0.8 + 0.25 * sin(t * 11.0 + ph) + 0.15 * sin(t * 23.0 + ph * 2.0)
		var fl: Array = e["flames"]
		for i in fl.size():
			var mi := fl[i] as MeshInstance3D
			mi.scale = Vector3(1.0 + 0.1 * sin(t * 17.0 + ph + i), k + 0.1 * i, 1.0 + 0.1 * cos(t * 13.0 + ph))
			mi.rotation.y = t * (1.5 + i) + ph
	for kind in _lights:
		for l in _lights[kind]:
			if (l as OmniLight3D).visible:
				(l as OmniLight3D).light_energy = (1.0 + 0.04 * sin(t * 40.0)) if kind == "tunnel" else 1.2 + 0.4 * sin(t * 9.0 + (l as OmniLight3D).position.x) + 0.2 * sin(t * 21.0)


## Standing in a flame hurts: BURN_DPS per second in small ticks, only for the fires that have real nodes (the ones near the player).
const BURN_RADIUS := {"tree": 1.5, "car": 1.7, "build": 2.4}
const BURN_DPS := 10.0
const BURN_TICK := 0.5
var _burn_t := 0.0


func burn(player: Player, delta: float) -> void:
	_burn_t = maxf(0.0, _burn_t - delta)
	if _burn_t > 0.0 or Game.dead:
		return
	var pp := player.global_position
	for e in entries:
		if e["node"] == null or not BURN_RADIUS.has(e["kind"]):
			continue
		var fp: Vector3 = e["pos"]
		var r: float = float(BURN_RADIUS[e["kind"]]) * clampf(float(e["s"]), 0.7, 1.5)
		if Vector2(fp.x - pp.x, fp.z - pp.z).length() < r and pp.y > fp.y - 0.6 and pp.y < fp.y + 2.2:
			_burn_t = BURN_TICK
			player.take_damage(BURN_DPS * BURN_TICK, fp)
			return
