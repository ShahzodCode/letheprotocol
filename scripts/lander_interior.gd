class_name LanderInterior
extends Node
## Chapter One "X. The Commander": the inside of the landing craft and the Commander on its command deck (the book says it is far larger inside
## than outside, so it is NOT inside the hull model: it is built once, far BELOW the city, and the player is teleported into it).
##
## The plan is a list of floor rectangles in metres (FLOORS); everything else next to them becomes wall (merged into boxes), plus one floor and one
## ceiling slab. Visuals are a few merged meshes (GunModels.Builder, one per 12 m chunk so that the omni lights stay inside the Compatibility
## renderer's per-object limit), colliders one StaticBody3D, navigation one story layer (City.add_story_layer) so the soldiers patrol and hunt
## with their normal A* code. While inside, `Main.world` is hidden and the camera uses its own dark environment.
##
## The route: the ramp hall V -> corridor A -> the crossing (the alarm goes off there) -> corridor NA, or round the west loop (bunk rooms,
## WS, WN) or the east loop (the mess, EN, EC) -> the junction hall -> the stub -> the command deck. Objectives: ship_sneak (reach the
## crossing among five patrols), ship_run (the alarm: five soldiers come up from the ramp hall, the patrols hunt, run for the deck),
## commander (the door shuts; the player empties the pistol into the Commander, who laughs, says his lines and has the player taken;
## white-out, black, the closing lines, "TO BE CONTINUED"). Roles (Main.story_roles): ship_patrol_a/b/c, ship_post_ec, ship_post_hall,
## ship_pursuer, ship_deck, ship_commander (see apply_role).

const DEEP_Y := -400.0                       # the floor of the craft; far below the ground, so nothing of the city can reach it
const ORIGIN := Vector3(0.0, DEEP_Y, 0.0)    # local plan (x, z) in metres -> world (ORIGIN.x + x, DEEP_Y, ORIGIN.z + z)
const MARGIN := 2                            # metres of solid round the plan
const SPAN_X := 52
const SPAN_Z := 54
const WALL_H := 3.2
const CHUNK := 12.0
const NAV_CELL := 0.5
const NAV_WALL_MARGIN := 0.35

# the plan: floor rectangles [x0, z0, x1, z1] in metres (cells x0..x1-1, z0..z1-1). Doors are 2 m gaps between a room and a corridor.
const FLOORS := [
	[16, 40, 32, 49],      # V: the ramp hall (arrival at (24, 46) facing north)
	[22, 29, 25, 40],      # A: the corridor north of it
	[14, 26, 34, 29],      # the crossing (the alarm goes off here)
	[3, 26, 14, 29],       # WC: west corridor
	[3, 12, 6, 26],        # WS: west spine
	[3, 12, 18, 15],       # WN: west-north corridor
	[18, 10, 31, 15],      # the junction hall
	[22, 15, 25, 26],      # NA: the direct corridor between hall and crossing
	[23, 6, 26, 10],       # the stub to the command deck
	[12, 0, 36, 6],        # the command deck
	[34, 26, 36, 29],      # link to the mess
	[36, 20, 46, 30],      # the mess
	[41, 13, 44, 20],      # EN: north out of the mess
	[31, 10, 44, 13],      # EC: east corridor to the hall
	[7, 22, 11, 25], [8, 25, 10, 26],       # bunk room N1 and its door
	[12, 22, 16, 25], [13, 25, 15, 26],     # N2
	[7, 30, 11, 33], [8, 29, 10, 30],       # S1
	[12, 30, 16, 33], [13, 29, 15, 30],     # S2
]
# crates, tables and consoles: [x0, z0, x1, z1, height, kind] (kind 0 crate, 1 table, 2 console). Colliders, nav blocks and a box each.
const PROPS := [
	[17.5, 41.0, 19.5, 43.0, 1.3, 0], [29.5, 44.0, 31.5, 46.0, 1.0, 0], [18.0, 46.0, 20.0, 48.0, 1.7, 0], [26.0, 41.0, 28.0, 42.2, 0.9, 0],
	[38.0, 22.0, 43.0, 23.2, 0.9, 1], [38.0, 26.0, 43.0, 27.2, 0.9, 1], [44.5, 28.0, 46.0, 30.0, 1.2, 0],
	[13.0, 0.2, 22.0, 1.4, 1.0, 2], [27.0, 0.2, 36.0, 1.4, 1.0, 2],
]
const PATROL_A := [Vector2(23.5, 12.5), Vector2(23.5, 20.0), Vector2(23.5, 27.5), Vector2(28.0, 27.5), Vector2(23.5, 20.0)]
const PATROL_B := [Vector2(4.5, 27.5), Vector2(4.5, 14.0), Vector2(12.0, 13.5), Vector2(4.5, 14.0)]
const PATROL_C := [Vector2(38.0, 24.5), Vector2(44.0, 24.5), Vector2(43.5, 28.5), Vector2(38.0, 28.5)]
const ARRIVE := Vector2(24.0, 46.0)
const ALARM_AT := Vector2(24.0, 27.5)
const DECK_DOOR := Vector2(24.5, 5.0)
const DOOR_SEAL := Vector2(24.5, 9.6)          # where the bulkhead falls (the stub's south end)
const COMMANDER_AT := Vector2(24.5, 2.5)
const PURSUER_KINDS := ["soldier", "soldier", "rifleman", "soldier", "blade"]
const DECK_ROWS := [2.9, 4.5]
const DECK_OFFSETS := [5.0, 6.4, 7.8, 9.2, 10.6]       # from the Commander's x, each side
const COMMANDER_SCALE := 1.22                           # on top of the gunner's own scale
const SIREN_DB := -13.0
const FACE_TIMEOUT := 45.0                              # seconds before the Commander laughs even if the pistol is not empty
const FADE_IN := 1.4
const RUSH_TIME := 1.5
const LINE_GAP := 0.3

const WALL_COL := Color(0.30, 0.31, 0.34)
const FLOOR_COL := Color(0.15, 0.155, 0.17)
const CEIL_COL := Color(0.24, 0.25, 0.27)
const DARK := Color(0.08, 0.085, 0.095)
const PLATE := Color(0.36, 0.37, 0.39)
const COLD := Color(0.8, 0.9, 1.0)
const TEAL := Color(0.25, 0.75, 0.8)
const AMBER := Color(1.0, 0.55, 0.2)
const BLANKET := Color(0.27, 0.33, 0.42)
const CRATE := Color(0.33, 0.28, 0.2)

enum Scene { NONE, FACE, TALK, RUSH, WHITE, BLACK }

var main
var player: Player
var inside := false                 # the player is in the craft (the world is hidden)
var alarm := false
var scene := Scene.NONE
var _built := false
var _root: Node3D
var _env: Environment
var _layer := -1
var _glow_mats: Array = []
var _lights: Array = []             # [OmniLight3D, base energy, base colour]
var _door_body: StaticBody3D
var _door_vis: MeshInstance3D
var _siren: AudioStreamPlayer
var _alarm_t := 0.0
var _spawned := false
var _deck_spawned := false
var _scene_t := 0.0
var _lines: Array = []              # [time, text]
var _line_i := 0
var _fade_layer: CanvasLayer
var _fade: ColorRect
var _fade_a := 0.0
var _fade_to := 0.0
var _fade_speed := 1.0
var _chunks: Dictionary = {}
var _prop_i := 0


func setup(m) -> void:
	main = m
	player = m.player


# ---------------------------------------------------------------- positions

static func world_at(x: float, z: float) -> Vector3:
	return Vector3(ORIGIN.x + x, DEEP_Y, ORIGIN.z + z)


static func alarm_point() -> Vector3:
	return world_at(ALARM_AT.x, ALARM_AT.y)


static func deck_door() -> Vector3:
	return world_at(DECK_DOOR.x, DECK_DOOR.y)


# ---------------------------------------------------------------- build

func prebuild() -> void:
	if not _built:
		_build()


func _build() -> void:
	_built = true
	_root = Node3D.new()
	add_child(_root)
	var cells := {}
	for r in FLOORS:
		for x in range(int(r[0]), int(r[2])):
			for z in range(int(r[1]), int(r[3])):
				cells[Vector2i(x, z)] = true
	var wall_cells := {}
	for c in cells.keys():
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var n := Vector2i((c as Vector2i).x + dx, (c as Vector2i).y + dz)
				if not cells.has(n):
					wall_cells[n] = true
	var wall_rects := _merge(wall_cells)

	# colliders: one body, floor and ceiling slabs, the merged walls, the props
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	body.collision_mask = 0
	body.position = ORIGIN
	var cx := float(SPAN_X) * 0.5 - MARGIN
	var cz := float(SPAN_Z) * 0.5 - MARGIN
	_shape(body, Vector3(cx, -0.5, cz), Vector3(SPAN_X, 1.0, SPAN_Z))
	_shape(body, Vector3(cx, WALL_H + 0.5, cz), Vector3(SPAN_X, 1.0, SPAN_Z))
	for wr in wall_rects:
		var r: Rect2 = wr
		_shape(body, Vector3(r.position.x + r.size.x * 0.5, WALL_H * 0.5, r.position.y + r.size.y * 0.5), Vector3(r.size.x, WALL_H, r.size.y))
	for p in PROPS:
		_shape(body, Vector3((float(p[0]) + float(p[2])) * 0.5, float(p[4]) * 0.5, (float(p[1]) + float(p[3])) * 0.5),
			Vector3(float(p[2]) - float(p[0]), float(p[4]), float(p[3]) - float(p[1])))
	_root.add_child(body)

	# visuals
	var fi := 0
	for r in FLOORS:
		var w := float(r[2]) - float(r[0])
		var d := float(r[3]) - float(r[1])
		var shade := 0.85 + 0.3 * fposmod(float(fi) * 0.618, 1.0)
		var top := -0.001 * float(fi)
		_vbox(Vector3(float(r[0]) + w * 0.5, top - 0.06, float(r[1]) + d * 0.5), Vector3(w, 0.12, d), FLOOR_COL * shade)
		fi += 1
	for wr in wall_rects:
		var r2: Rect2 = wr
		var wsh := 0.9 + 0.2 * fposmod(r2.position.x * 0.37 + r2.position.y * 0.61, 1.0)
		_vbox(Vector3(r2.position.x + r2.size.x * 0.5, WALL_H * 0.5, r2.position.y + r2.size.y * 0.5), Vector3(r2.size.x, WALL_H, r2.size.y), WALL_COL * wsh)
	_vbox(Vector3(cx, WALL_H + 0.25, cz), Vector3(SPAN_X, 0.5, SPAN_Z), CEIL_COL)
	_dress()
	for p in PROPS:
		_prop_visual(p)

	# one mesh per chunk
	for key in _chunks.keys():
		var b: GunModels.Builder = _chunks[key]
		var mi := MeshInstance3D.new()
		mi.mesh = b.mesh()
		mi.position = ORIGIN
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(mi)
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat != null and mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				_glow_mats.append(mat)
	_chunks.clear()
	_lights_build()

	# the bulkhead that falls behind the player at the command deck (off until the Commander scene)
	_door_body = StaticBody3D.new()
	_door_body.collision_layer = Game.L_WORLD
	_door_body.collision_mask = 0
	_door_body.position = world_at(DOOR_SEAL.x, DOOR_SEAL.y) + Vector3(0, WALL_H * 0.5, 0)
	var dcs := CollisionShape3D.new()
	var dbs := BoxShape3D.new()
	dbs.size = Vector3(3.4, WALL_H, 0.5)
	dcs.shape = dbs
	dcs.disabled = true
	_door_body.add_child(dcs)
	_door_vis = MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(3.2, WALL_H, 0.3)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.12, 0.125, 0.14)
	dmat.roughness = 0.6
	dmat.metallic = 0.3
	dm.material = dmat
	_door_vis.mesh = dm
	_door_vis.visible = false
	_door_body.add_child(_door_vis)
	_root.add_child(_door_body)

	# the environment: black outside, a cold dim ambient, no fog
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color.BLACK
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.5, 0.56, 0.66)
	_env.ambient_light_energy = 0.55
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	# the navigation layer: floors open, walls and props closed with a margin so a body fits
	var rect := Rect2(ORIGIN.x - MARGIN, ORIGIN.z - MARGIN, SPAN_X, SPAN_Z)
	var g := City.story_grid(rect, NAV_CELL)
	for r in FLOORS:
		City.story_set(g, Rect2(ORIGIN.x + float(r[0]), ORIGIN.z + float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1])), 0.0, false)
	for wr in wall_rects:
		var r3: Rect2 = wr
		City.story_set(g, Rect2(ORIGIN.x + r3.position.x, ORIGIN.z + r3.position.y, r3.size.x, r3.size.y), NAV_WALL_MARGIN, true)
	for p in PROPS:
		City.story_set(g, Rect2(ORIGIN.x + float(p[0]), ORIGIN.z + float(p[1]), float(p[2]) - float(p[0]), float(p[3]) - float(p[1])), 0.3, true)
	_layer = City.add_story_layer("lander", rect, DEEP_Y, g)

	_siren = AudioStreamPlayer.new()
	_siren.stream = Sfx.get_sound("alarm")
	_siren.volume_db = SIREN_DB
	add_child(_siren)
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 80
	add_child(_fade_layer)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 0)
	_fade_layer.add_child(_fade)
	Sfx.get_sound("laugh")                 # synthesised now (a fraction of a second), not in the middle of the scene
	Sfx.get_sound("slam")


func _shape(body: StaticBody3D, centre: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = centre
	body.add_child(cs)


func _vbox(centre: Vector3, size: Vector3, col: Color, glow: bool = false) -> void:
	var key := Vector2i(floori(centre.x / CHUNK), floori(centre.z / CHUNK))
	if not _chunks.has(key):
		_chunks[key] = GunModels.Builder.new()
	(_chunks[key] as GunModels.Builder).box(centre, size, col, glow)


## Runs of cells per row, then equal runs of consecutive rows joined: the rectangles (in metres) that cover a set of cells.
func _merge(cellset: Dictionary) -> Array:
	var rows := {}
	var zmin := 1000000
	var zmax := -1000000
	for c in cellset.keys():
		var v: Vector2i = c
		if not rows.has(v.y):
			rows[v.y] = []
		(rows[v.y] as Array).append(v.x)
		zmin = mini(zmin, v.y)
		zmax = maxi(zmax, v.y)
	var out: Array = []
	var open := {}
	for z in range(zmin, zmax + 2):
		var runs := {}
		if rows.has(z):
			var xs: Array = rows[z]
			xs.sort()
			var start: int = xs[0]
			var prev: int = xs[0]
			for i in range(1, xs.size() + 1):
				if i < xs.size() and int(xs[i]) == prev + 1:
					prev = int(xs[i])
					continue
				runs["%d:%d" % [start, prev + 1]] = [start, prev + 1]
				if i < xs.size():
					start = int(xs[i])
					prev = start
		for k in open.keys():
			if not runs.has(k):
				var o: Array = open[k]
				out.append(Rect2(float(o[0]), float(o[2]), float(o[1] - o[0]), float(z - int(o[2]))))
				open.erase(k)
		for k in runs.keys():
			if not open.has(k):
				var rr: Array = runs[k]
				open[k] = [rr[0], rr[1], z]
	return out


## Ceiling light strips, the bright opening of the ramp, bunks and lockers in the four rooms, the command deck's window, screens and mullions.
func _dress() -> void:
	for r in FLOORS:
		var w := float(r[2]) - float(r[0])
		var d := float(r[3]) - float(r[1])
		if minf(w, d) < 2.5:
			continue
		var c := Vector3(float(r[0]) + w * 0.5, WALL_H - 0.04, float(r[1]) + d * 0.5)
		if w >= d:
			_vbox(c, Vector3(maxf(w - 3.0, 1.0), 0.06, 0.28), COLD, true)
			if d >= 8.0:
				_vbox(c + Vector3(0, 0, d * 0.28), Vector3(maxf(w - 3.0, 1.0), 0.06, 0.28), COLD, true)
				_vbox(c - Vector3(0, 0, d * 0.28), Vector3(maxf(w - 3.0, 1.0), 0.06, 0.28), COLD, true)
		else:
			_vbox(c, Vector3(0.28, 0.06, maxf(d - 3.0, 1.0)), COLD, true)
	# the way back: the ramp opening, white-hot daylight
	_vbox(Vector3(24.0, 1.3, 48.92), Vector3(4.6, 2.6, 0.1), Color(1.0, 0.9, 0.7), true)
	_vbox(Vector3(24.0, 0.06, 48.6), Vector3(4.6, 0.12, 0.8), PLATE)
	# bunk rooms: a bed along the west wall, a locker in the far east corner
	for rm in [[7, 22, 11, 25, true], [12, 22, 16, 25, true], [7, 30, 11, 33, false], [12, 30, 16, 33, false]]:
		var x0 := float(rm[0])
		var z0 := float(rm[1])
		var x1 := float(rm[2])
		var z1 := float(rm[3])
		var far_north: bool = rm[4]
		var zf := z0 + 0.15 if far_north else z1 - 0.15
		var sgn := 1.0 if far_north else -1.0
		_vbox(Vector3(x0 + 0.6, 0.35, zf + sgn * 1.1), Vector3(0.95, 0.7, 2.2), DARK)
		_vbox(Vector3(x0 + 0.6, 0.74, zf + sgn * 1.2), Vector3(0.9, 0.12, 2.0), BLANKET)
		_vbox(Vector3(x0 + 0.6, 0.84, zf + sgn * 0.25), Vector3(0.7, 0.12, 0.35), Color(0.6, 0.6, 0.62))
		_vbox(Vector3(x1 - 0.45, 0.95, zf + sgn * 0.3), Vector3(0.6, 1.9, 0.6), PLATE)
	# the command deck: the forward window, a burning skyline in it, mullions, side screens
	_vbox(Vector3(24.0, 2.15, 0.03), Vector3(22.0, 1.7, 0.06), Color(0.95, 0.45, 0.18), true)
	_vbox(Vector3(24.0, 2.75, 0.045), Vector3(22.0, 0.5, 0.05), Color(0.45, 0.2, 0.12), true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4500
	var sx := 13.2
	while sx < 34.8:
		var bw := rng.randf_range(0.6, 1.8)
		_vbox(Vector3(sx + bw * 0.5, 1.3 + rng.randf_range(0.2, 0.7), 0.075), Vector3(bw, rng.randf_range(0.4, 1.3), 0.05), Color(0.03, 0.025, 0.025))
		sx += bw + rng.randf_range(0.0, 0.5)
	for mx in [13.0, 17.5, 22.0, 26.0, 30.5, 35.0]:
		_vbox(Vector3(mx, 2.15, 0.12), Vector3(0.18, 1.7, 0.2), DARK)
	_vbox(Vector3(24.0, 3.0, 0.12), Vector3(23.0, 0.25, 0.22), DARK)
	for sxx in [12.1, 35.9]:
		for k in 3:
			var col := TEAL if k != 1 else AMBER
			_vbox(Vector3(sxx + (0.05 if sxx < 20.0 else -0.05), 1.7, 1.3 + float(k) * 1.7), Vector3(0.06, 0.9, 1.3), col, true)
	for k in 4:
		_vbox(Vector3(14.5 + float(k) * 2.0, 1.15, 0.8), Vector3(1.4, 0.05, 0.4), TEAL, true)
		_vbox(Vector3(27.5 + float(k) * 2.0, 1.15, 0.8), Vector3(1.4, 0.05, 0.4), AMBER if k == 2 else TEAL, true)


func _prop_visual(p: Array) -> void:
	var cx := (float(p[0]) + float(p[2])) * 0.5
	var cz := (float(p[1]) + float(p[3])) * 0.5
	var h := float(p[4])
	var col := CRATE
	match int(p[5]):
		1:
			col = PLATE
		2:
			col = DARK
	_vbox(Vector3(cx, h * 0.5, cz), Vector3(float(p[2]) - float(p[0]), h, float(p[3]) - float(p[1])), col)
	if int(p[5]) == 0:
		_vbox(Vector3(cx, h + 0.02, cz), Vector3(float(p[2]) - float(p[0]) - 0.2, 0.05, float(p[3]) - float(p[1]) - 0.2), Color(0.45, 0.38, 0.26))


func _lights_build() -> void:
	for r in FLOORS:
		var w := float(r[2]) - float(r[0])
		var d := float(r[3]) - float(r[1])
		if minf(w, d) < 2.5:
			continue
		var long_x := w >= d
		var length := w if long_x else d
		var n := maxi(1, roundi(length / 11.0))
		for i in n:
			var t := (float(i) + 0.5) / float(n)
			var pos := Vector3(float(r[0]) + w * (t if long_x else 0.5), WALL_H - 0.5, float(r[1]) + d * (0.5 if long_x else t))
			var deck := float(r[1]) < 1.0 and float(r[3]) <= 6.0
			var l := OmniLight3D.new()
			l.light_color = Color(0.55, 0.85, 0.9) if deck else Color(0.8, 0.9, 1.0)
			l.light_energy = 1.1
			l.omni_range = 8.5
			l.shadow_enabled = false
			l.position = ORIGIN + pos
			_root.add_child(l)
			_lights.append([l, 1.1, l.light_color])


# ---------------------------------------------------------------- entering and leaving

func _enter_world() -> void:
	inside = true
	main.world.visible = false
	player.camera.environment = _env


func _exit_world() -> void:
	inside = false
	if main.world != null:
		main.world.visible = true
	if player != null and player.camera != null:
		player.camera.environment = null
	alarm = false
	scene = Scene.NONE
	Game.frozen = false
	Game.invulnerable = false
	if _siren != null:
		_siren.stop()
	_set_alarm_look(false)
	if _door_body != null:
		_set_door(false)
	_fade_a = 0.0
	_fade_to = 0.0
	if _fade != null:
		_fade.color = Color(0, 0, 0, 0)


## The "ramp" objective is done: the player steps through the doorway into the ship (the teleport is instant so that the checkpoint of the next
## objective is already inside; the screen fades up from black).
func enter() -> void:
	prebuild()
	_enter_world()
	var pos := world_at(ARRIVE.x, ARRIVE.y) + Vector3(0, 0.1, 0)
	_place_player(pos)
	_spawn_patrols()
	_set_fade(1.0, 0.0, 1.0 / FADE_IN, Color(0, 0, 0))
	Sfx.play(self, "slam", -8.0, 0.7)


func _place_player(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.pitch = 0.0
	player.rotation.y = 0.0
	player.head.rotation = Vector3.ZERO
	player.fall_speed = 0.0
	_settle(pos)


func _settle(pos: Vector3) -> void:
	await get_tree().physics_frame
	player.global_position = pos
	player.velocity = Vector3.ZERO


## After a checkpoint restore: the craft matches the objective the player is back on.
func sync() -> void:
	if main.mission == null:
		return
	var first: int = main._objective_index("ship_sneak")
	if first < 0:
		return
	if main.mission.index < first:
		if inside:
			_exit_world()
		_spawned = false
		_deck_spawned = false
		_fade_a = 0.0
		return
	prebuild()
	if not inside:
		_enter_world()
	_spawned = true
	var run_i: int = main._objective_index("ship_run")
	var cmd_i: int = main._objective_index("commander")
	_deck_spawned = true
	Game.frozen = false
	Game.invulnerable = false
	scene = Scene.NONE
	_fade_a = 0.0
	_fade.color = Color(0, 0, 0, 0)
	alarm = main.mission.index == run_i
	_set_alarm_look(alarm)
	if alarm:
		_siren.play()
	else:
		_siren.stop()
	_set_door(main.mission.index >= cmd_i)
	if main.mission.index >= cmd_i:
		_start_face()


func _in_alarm_phase() -> bool:
	return main.mission != null and main.mission.index >= main._objective_index("ship_run") and main._objective_index("ship_run") >= 0


func _in_scene_phase() -> bool:
	return main.mission != null and main.mission.index >= main._objective_index("commander") and main._objective_index("commander") >= 0


# ---------------------------------------------------------------- soldiers

func _spawn_at(xz: Vector2, kind: String, role: String) -> Enemy:
	var e: Enemy = main._spawn_enemy_at(world_at(xz.x, xz.y), kind)
	main._assign_role(e, role)
	return e


func _spawn_patrols() -> void:
	if _spawned:
		return
	_spawned = true
	_spawn_at(Vector2(23.5, 21.0), "soldier", "ship_patrol_a")
	_spawn_at(Vector2(4.5, 20.0), "soldier", "ship_patrol_b")
	_spawn_at(Vector2(40.0, 24.5), "rifleman", "ship_patrol_c")
	_spawn_at(Vector2(42.5, 11.5), "soldier", "ship_post_ec")
	_spawn_at(Vector2(28.0, 12.0), "rifleman", "ship_post_hall")
	_spawn_deck()                          # the Commander and his twenty wait on the deck from the start (the black fade hides the spawning)


func _spawn_deck() -> void:
	if _deck_spawned:
		return
	_deck_spawned = true
	_spawn_at(COMMANDER_AT, "gunner", "ship_commander")
	for row in DECK_ROWS:
		for off in DECK_OFFSETS:
			_spawn_at(Vector2(COMMANDER_AT.x - float(off), float(row)), "soldier", "ship_deck")
			_spawn_at(Vector2(COMMANDER_AT.x + float(off), float(row)), "soldier", "ship_deck")


func _route(pts: Array) -> Array:
	var out: Array = []
	for p in pts:
		out.append(world_at((p as Vector2).x, (p as Vector2).y))
	return out


func _hunt(e: Enemy) -> void:
	e.post = false
	e.patrol = []
	e.knows_player = true
	e._aggravate(true)
	e.alert_t = 0.3
	e.last_known = player.global_position


## Called by Main._apply_role for every "ship_*" role (also after a checkpoint restore).
func apply_role(e: Enemy, role: String) -> void:
	e.group = -1
	e.post = false
	match role:
		"ship_patrol_a":
			e.patrol = _route(PATROL_A)
		"ship_patrol_b":
			e.patrol = _route(PATROL_B)
		"ship_patrol_c":
			e.patrol = _route(PATROL_C)
		"ship_post_ec":
			e.post = true
			e.post_facing = PI * 0.5
		"ship_post_hall":
			e.post = true
			e.post_facing = PI * 0.5
		"ship_pursuer":
			_hunt(e)
		"ship_deck":
			e.post = true
			e.passive = true
			e.damage_scale = 0.0
			e.state = Enemy.State.ALERT
			e.alert_t = 99.0
		"ship_commander":
			e.post = true
			e.passive = true
			e.damage_scale = 0.0
			e.rig.scale = Vector3.ONE * e.body_scale * COMMANDER_SCALE
	if role.begins_with("ship_patrol") or role.begins_with("ship_post"):
		if _in_scene_phase():
			e.passive = true
		elif _in_alarm_phase():
			_hunt(e)
	if e.post:
		e.facing = e.post_facing
		e.rig.rotation.y = e.facing


# ---------------------------------------------------------------- the alarm

func begin_alarm() -> void:
	alarm = true
	_alarm_t = 0.0
	_siren.play()
	Sfx.play(self, "slam", -4.0, 0.9)
	for i in PURSUER_KINDS.size():
		_spawn_at(Vector2(19.0 + float(i) * 2.4, 45.0), String(PURSUER_KINDS[i]), "ship_pursuer")
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and en.state != Enemy.State.DEAD and en.passive == false:
			var role := String(main.story_roles.get(en.uid, ""))
			if role.begins_with("ship_patrol") or role.begins_with("ship_post"):
				_hunt(en)


func _set_alarm_look(on: bool) -> void:
	for gm in _glow_mats:
		(gm as StandardMaterial3D).albedo_color = Color(1.0, 0.18, 0.12) if on else Color.WHITE
	for l in _lights:
		var light: OmniLight3D = l[0]
		light.light_color = Color(1.0, 0.2, 0.14) if on else (l[2] as Color)
		light.light_energy = float(l[1])


func _set_door(shut: bool) -> void:
	for c in _door_body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = not shut
	_door_vis.visible = shut


# ---------------------------------------------------------------- the Commander scene

func begin_confrontation() -> void:
	_set_door(true)
	Sfx.play_at(self, world_at(DOOR_SEAL.x, DOOR_SEAL.y) + Vector3(0, 1.5, 0), "slam", 4.0, 0.8, 60.0, 12.0)
	_start_face()


func _start_face() -> void:
	scene = Scene.FACE
	_scene_t = 0.0
	alarm = false
	_siren.stop()
	_set_alarm_look(false)
	Game.invulnerable = true
	for e in Game.enemies:
		var en := e as Enemy
		if not is_instance_valid(en) or en.state == Enemy.State.DEAD:
			continue
		var role := String(main.story_roles.get(en.uid, ""))
		if role.begins_with("ship_") and role != "ship_deck" and role != "ship_commander":
			en.passive = true             # whoever was hunting stops at the sealed door
			en.knows_player = false
			en.state = Enemy.State.WANDER
	var w: Weapons = player.weapons
	if w.current == "pistol":
		w.state["pistol"]["ammo"] = int(WeaponsDB.WEAPONS["pistol"]["mag"])
		w.reloading = false
	Game.radio_line.emit("@THE COMMANDER. THE ONE WHO GAVE THE ORDER. EMPTY THE PISTOL INTO HIM.")


func _line_time(text: String) -> float:
	var read := clampf(2.0 + float(text.length()) * 0.04, 3.0, 6.0)
	var spoken: float = main.voice.count_duration(Game.kills) if text.contains("OF MY SOLDIERS") else main.voice.duration(text)
	return maxf(read, spoken + 0.4) + LINE_GAP


func _schedule(texts: Array, t0: float) -> Array:
	var out: Array = []
	var t := t0
	for tx in texts:
		out.append([t, String(tx)])
		t += _line_time(String(tx))
	out.append([t, ""])               # the end marker
	return out


func _commander() -> Enemy:
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and String(main.story_roles.get(en.uid, "")) == "ship_commander":
			return en
	return null


func _start_talk() -> void:
	scene = Scene.TALK
	_scene_t = 0.0
	Game.frozen = true
	var cm := _commander()
	if cm != null:
		Sfx.play_at(self, cm.global_position + Vector3(0, 2.2, 0), "laugh", 6.0, 0.85, 80.0, 14.0)
	var count := "SO MANY" if Game.kills <= 0 else str(Game.kills)
	_lines = _schedule([
		"@COMMANDER: %s OF MY SOLDIERS, IN A SINGLE MORNING. KILLED BY A BOY WITH ONE GOOD ARM." % count,
		"@COMMANDER: NO. YOU ARE FAR TOO INTERESTING TO WASTE.",
		"@COMMANDER: TAKE HIM ALIVE. PUT HIM IN A CELL.",
	], 2.0)
	_line_i = 0


func _start_rush() -> void:
	scene = Scene.RUSH
	_scene_t = 0.0
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and String(main.story_roles.get(en.uid, "")) == "ship_deck":
			en.passive = false
			en.knows_player = true
			en.state = Enemy.State.CHASE
			en.last_known = player.global_position


func _start_white() -> void:
	scene = Scene.WHITE
	_scene_t = 0.0
	player.add_shake(1.0)
	Sfx.play(self, "hurt", 0.0, 0.7)
	_set_fade(0.0, 1.0, 9.0, Color(1, 1, 1))


func _start_black() -> void:
	scene = Scene.BLACK
	_scene_t = 0.0
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and en.state != Enemy.State.DEAD and String(main.story_roles.get(en.uid, "")).begins_with("ship_"):
			en.passive = true
	_lines = _schedule([
		"@THE LAST THING I SAW WAS THE BURNING CITY, AND THE BROKEN VEIL FLICKERING ABOVE IT.",
		"@SOMEWHERE OUT THERE, MY SISTER WAS HIDING ALONE BEHIND A LOCKED CELLAR DOOR.",
		"@MY FATHER WAS SOMEWHERE HE SHOULD NOT BE. MY MOTHER LAY BENEATH HER BLANKET IN OUR EMPTY HOME.",
		"@AND I WAS BEING TAKEN TO A PRISON.",
	], 1.8)
	_line_i = 0


func _run_lines() -> bool:
	while _line_i < _lines.size() and _scene_t >= float((_lines[_line_i] as Array)[0]):
		var tx := String((_lines[_line_i] as Array)[1])
		_line_i += 1
		if tx == "":
			return true
		Game.radio_line.emit(tx)
		if tx.contains("OF MY SOLDIERS"):
			main.voice.say_count(Game.kills)          # "Twenty-seven ... of my soldiers" (the other lines have their own clips)
	return false


func _set_fade(from_a: float, to_a: float, speed: float, rgb: Color) -> void:
	_fade_a = from_a
	_fade_to = to_a
	_fade_speed = speed
	_fade.color = Color(rgb.r, rgb.g, rgb.b, from_a)


func _process(delta: float) -> void:
	if not _built:
		return
	if _fade != null and not is_equal_approx(_fade_a, _fade_to):
		_fade_a = move_toward(_fade_a, _fade_to, _fade_speed * delta)
		_fade.color.a = _fade_a
	if alarm:
		_alarm_t += delta
		var k := 0.5 + 0.5 * sin(_alarm_t * 5.0)
		for l in _lights:
			(l[0] as OmniLight3D).light_energy = float(l[1]) * (0.35 + 0.9 * k)
	match scene:
		Scene.FACE:
			_scene_t += delta
			var w: Weapons = player.weapons
			var empty := w.current == "pistol" and w.ammo() == 0
			if _scene_t > 1.5 and (empty or _scene_t > FACE_TIMEOUT):
				_start_talk()
		Scene.TALK:
			_scene_t += delta
			if _run_lines():
				_start_rush()
		Scene.RUSH:
			_scene_t += delta
			if _scene_t >= RUSH_TIME:
				_start_white()
		Scene.WHITE:
			_scene_t += delta
			if _scene_t >= 0.7:
				scene = Scene.BLACK
				_start_black()
				_set_fade(1.0, 1.0, 1.0, Color(0, 0, 0))
		Scene.BLACK:
			_scene_t += delta
			if _run_lines():
				_finish()


func _finish() -> void:
	scene = Scene.NONE
	_fade_a = 0.0
	_fade_to = 0.0
	_fade.color = Color(0, 0, 0, 0)
	Game.frozen = false
	main.voice.hush()
	Mission.complete("commander")          # the last objective: the end-of-slice screen
