class_name CityStory
## Chapter One story dressing for the walk from the Institute to the home (the morning of the invasion): a tram lying on its side
## in the Institute avenue, overturned market stalls with spilled goods along the route, and the places where the dead lie
## (doorways, gutters) plus the two scripted soldiers (the first-lane blade fighter, the lone young soldier near the home).
## `dress()` runs inside City.generate after CityWar.obstacles (static scenery through Scn: MultiMeshes, one box collider each,
## nav blocks). The soldier and body spots need the navigation grid, so they are computed on demand after generation.

const TRAM_LEN := 16.0
const TRAM_W := 3.3                # on its side, its old height is now its width
const TRAM_H := 2.6                # ...and its old width its height
## Candidate places for the tram along the Institute avenue (z = 235, 20 m wide): north lane, south lane, further east / west.
const TRAM_SPOTS := [Vector2(-21.0, 229.0), Vector2(24.0, 241.0), Vector2(-64.0, 229.0), Vector2(42.0, 229.0), Vector2(-64.0, 241.0)]
const STALL_COUNT := 8
const LANE_SEARCH_LEN := 170.0     # the first narrow lane is looked for along the first 170 m of the walk home
const LANE_MAX_OFF := 26.0         # ...within this distance of that walk
const LONE_BEFORE_HOME := 46.0     # the lone soldier waits this far (along the way) before the home door
const BODY_SPACING := 21.0
const BODY_COUNT := 10

static var tram := {}              # {pos: Vector3 (centre, ground), yaw, rect}
static var stalls: Array = []      # [{pos: Vector3, yaw, rect}]
static var _lane := {}
static var _lone := {}
static var _bodies: Array = []


static func reset() -> void:
	CityWar.extra_clear = []
	tram = {}
	stalls = []
	_lane = {}
	_lone = {}
	_bodies = []
	_rest = {}
	_guards = []
	far_landers = []
	_escape = {}


## Static scenery, called from City.generate (needs CityWar.occ).
static func dress(seed_value: int) -> void:
	reset()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 4242
	_tram(rng)
	_stalls(rng)
	_lander_blocks()
	_far_landers(rng)


static func _free(rect: Rect2) -> bool:
	if CityWar.occ == null or CityWar.occ.hits(rect, 0.6) or CityWar._in_clear(rect) or CityWar._hits_building(rect):
		return false
	for c in City.cars:
		var cr: Variant = c.get("rect")
		if cr != null and (cr as Rect2).grow(0.8).intersects(rect):
			return false
	for t in City.trees:
		if rect.grow(1.6).has_point(t["pos"] as Vector2):
			return false
	return true


# ================================================================== the tram

static func _tram(rng: RandomNumberGenerator) -> void:
	for sp in TRAM_SPOTS:
		var p: Vector2 = sp
		var rect := Scn.footprint(p, Vector2(TRAM_LEN * 0.5, TRAM_W * 0.5), 0.0)
		if not _free(rect):
			continue
		CityWar.occ.add(rect)
		var c := Vector3(p.x, 0.0, p.y)
		var cream := Color(0.8, 0.76, 0.64)
		var red := Color(0.55, 0.13, 0.1)
		var dark := Color(0.1, 0.11, 0.13)
		Scn.box(c + Vector3(0, TRAM_H * 0.5, 0), Vector3(TRAM_LEN, TRAM_H, TRAM_W), cream)                   # the body
		Scn.box(c + Vector3(0, 0.25, 0), Vector3(TRAM_LEN + 0.04, 0.5, TRAM_W + 0.04), red)                # red skirt along the bottom edge
		Scn.box(c + Vector3(0, TRAM_H * 0.5, 1.0), Vector3(TRAM_LEN + 0.04, 0.4, TRAM_W + 0.04), red.darkened(0.1))
		for k in 8:                                                                                         # the windows now face the sky
			var wx := -6.6 + float(k) * 1.9
			Scn.box(c + Vector3(wx, TRAM_H + 0.02, -0.3), Vector3(1.4, 0.05, 1.2), dark)
			Scn.box(c + Vector3(wx + 0.95, TRAM_H + 0.02, 1.0), Vector3(0.05, 0.05, 0.9), cream.darkened(0.3))
		Scn.box(c + Vector3(-TRAM_LEN * 0.5 - 0.02, TRAM_H * 0.5, 0), Vector3(0.05, TRAM_H * 0.8, TRAM_W * 0.8), dark)   # cab glass
		Scn.box(c + Vector3(TRAM_LEN * 0.5 + 0.02, TRAM_H * 0.5, 0), Vector3(0.05, TRAM_H * 0.8, TRAM_W * 0.8), dark)
		for bx in [-5.2, 5.2]:                                                                              # the bogies stick out sideways
			Scn.prop(c + Vector3(bx, TRAM_H * 0.5, TRAM_W * 0.5 + 0.35), Vector3(2.6, 1.0, 0.6), dark)
			Scn.between("cyl", c + Vector3(bx - 1.0, TRAM_H * 0.5, TRAM_W * 0.5 + 0.6), c + Vector3(bx - 1.0, TRAM_H * 0.5 + 0.1, TRAM_W * 0.5 + 0.9), 0.7, Color(0.18, 0.18, 0.2))
			Scn.between("cyl", c + Vector3(bx + 1.0, TRAM_H * 0.5, TRAM_W * 0.5 + 0.6), c + Vector3(bx + 1.0, TRAM_H * 0.5 - 0.1, TRAM_W * 0.5 + 0.9), 0.7, Color(0.18, 0.18, 0.2))
		# the pantograph snapped off and lies in the road with the live wire; sparks at its end
		var pa := c + Vector3(3.0, TRAM_H, -TRAM_W * 0.5)
		var pb := c + Vector3(6.2, 0.15, -TRAM_W * 0.5 - 2.4)
		Scn.between("cyl", pa, pb, 0.08, Color(0.2, 0.2, 0.22))
		Scn.between("cyl", pb, pb + Vector3(3.0, 0.0, -1.2), 0.04, Color(0.05, 0.05, 0.05))
		Scn.between("cyl", c + Vector3(-3.0, TRAM_H, 0.0), c + Vector3(-4.5, 0.1, TRAM_W + 2.2), 0.04, Color(0.05, 0.05, 0.05))
		Scn.fire("spark", pb + Vector3(0.6, 0.2, -0.2), 1.0)
		Scn.fire("car", c + Vector3(-5.2, TRAM_H + 0.3, 0.4), 1.6)                                         # the cab end smoulders
		Scn.solid(c + Vector3(0, TRAM_H * 0.5, 0), Vector3(TRAM_LEN, TRAM_H, TRAM_W))
		Scn.block(rect, 0.3)
		tram = {"pos": c, "yaw": 0.0, "rect": rect}
		return


# ================================================================== overturned stalls

static func _stalls(rng: RandomNumberGenerator) -> void:
	var lines: Array = []
	for z in [235.0, 185.0, 130.0, 70.0]:
		lines.append([z, false])
	lines.append([0.0, true])
	var tries := 0
	while stalls.size() < STALL_COUNT and tries < 260:
		tries += 1
		var ln: Array = lines[rng.randi() % lines.size()]
		var line: float = ln[0]
		var along_z: bool = ln[1]
		var w := City.avenue_width(line)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var u: float = side * (w * 0.5 - 2.0 - rng.randf_range(0.0, 1.2))
		var t := rng.randf_range(-62.0, 62.0) if not along_z else rng.randf_range(-40.0, 215.0)
		var p := Vector2(line + u, t) if along_z else Vector2(t, line + u)
		var yaw := (0.0 if along_z else PI * 0.5) + rng.randf_range(-0.5, 0.5)
		var rect := Scn.footprint(p, Vector2(1.8, 1.5), yaw)
		if not _free(rect) or CityWar._reserved(p, 5.0):
			continue
		CityWar.occ.add(rect)
		_stall(Vector3(p.x, 0.0, p.y), yaw, rng)
		stalls.append({"pos": Vector3(p.x, 0.0, p.y), "yaw": yaw, "rect": rect})


## A market stall knocked over: the counter on its side, the striped awning slumped across it, the goods scattered.
static func _stall(c: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var b := Basis(Vector3.UP, yaw)
	var wood := Color(0.45, 0.32, 0.2)
	var stripe := Color(0.62, 0.14, 0.1) if rng.randf() < 0.5 else Color(0.18, 0.4, 0.22)
	Scn.prop(c + b * Vector3(0, 0.45, 0), Vector3(2.0, 0.9, 0.8), wood, yaw, Basis(Vector3(0, 0, 1), 1.45))                 # counter on its side (the slumped awning is cloth: no collider)
	Scn.box(c + b * Vector3(0.1, 0.5, 0.6), Vector3(2.4, 0.05, 1.5), stripe, yaw, Basis(Vector3(1, 0, 0), 0.55))           # awning slumped over it
	Scn.box(c + b * Vector3(0.1, 0.25, -0.5), Vector3(2.4, 0.05, 0.9), Color(0.85, 0.82, 0.74), yaw, Basis(Vector3(1, 0, 0), -0.25))
	Scn.between("cyl", c + b * Vector3(-1.1, 0.05, -0.9), c + b * Vector3(-0.2, 0.9, 0.6), 0.05, Color(0.3, 0.3, 0.32))      # a bent pole
	var goods := [Color(0.85, 0.35, 0.1), Color(0.35, 0.6, 0.2), Color(0.8, 0.15, 0.12), Color(0.9, 0.75, 0.2)]
	for i in 12:
		var off := Vector3(rng.randf_range(-1.8, 1.8), 0.0, rng.randf_range(-1.4, 1.4))
		var sz := rng.randf_range(0.12, 0.3)
		Scn.box(c + b * off + Vector3(0, sz * 0.5, 0), Vector3(sz, sz, sz), goods[rng.randi() % goods.size()], rng.randf() * TAU)
	for i in 3:
		var off2 := Vector3(rng.randf_range(-1.8, 1.8), 0.0, rng.randf_range(-1.4, 1.4))
		Scn.prop(c + b * off2 + Vector3(0, 0.15, 0), Vector3(0.6, 0.3, 0.45), wood.lightened(0.1), yaw + rng.randf_range(-0.8, 0.8))   # spilled crates
	Scn.block(Scn.footprint(Vector2(c.x, c.z), Vector2(1.2, 0.7), yaw), 0.3)


# ================================================================== the way home: lane, lone soldier, the dead

static func _way() -> PackedVector3Array:
	return City.path(City.INSTITUTE_EXIT, City.HOME_POS)


## Points along `way` every `step` metres (arc length): [[position, distance from the start], ...].
static func _samples(way: PackedVector3Array, step: float) -> Array:
	var out: Array = []
	var acc := 0.0
	var next := 0.0
	for i in way.size() - 1:
		var a := way[i]
		var b := way[i + 1]
		var seg := a.distance_to(b)
		while next <= acc + seg:
			out.append([a.lerp(b, (next - acc) / maxf(seg, 0.001)), next])
			next += step
		acc += seg
	return out


## The first narrow lane (an alley or footpath) beside the walk home: {rect, pos (about 10 m inside the mouth, where the blade fighter waits),
## near (the mouth towards the Institute), along_x}. Deterministic for the seed; needs the navigation grid.
static func first_lane() -> Dictionary:
	if not _lane.is_empty():
		return _lane
	var way := _way()
	var pts := _samples(way, 4.0)
	var best := {}
	var best_score := INF
	for st in City.streets:
		var cls: String = st["cls"]
		if cls != "alley" and cls != "walk":
			continue
		var r: Rect2 = st["rect"]
		var long_side := maxf(r.size.x, r.size.y)
		if long_side < 14.0 or long_side > 70.0 or not City.ROUTE_ZONE.encloses(r):
			continue
		var along_x := r.size.x > r.size.y
		var mid := r.get_center()
		# how close does the walk home come to this lane, within its first LANE_SEARCH_LEN metres?
		var off := INF
		var at := 0.0
		for sp in pts:
			if float(sp[1]) > LANE_SEARCH_LEN:
				break
			var q := Vector2((sp[0] as Vector3).x, (sp[0] as Vector3).z)
			var d := (q - Vector2(clampf(q.x, r.position.x, r.end.x), clampf(q.y, r.position.y, r.end.y))).length()
			if d < off:
				off = d
				at = float(sp[1])
		if off > LANE_MAX_OFF or at < 35.0:
			continue
		var score := off + at * 0.15 + (0.0 if cls == "alley" else 30.0)          # a real alley (3 m) is preferred to a 6 m footpath
		if score >= best_score:
			continue
		var e1 := Vector3(r.position.x + 0.8, 0.0, mid.y) if along_x else Vector3(mid.x, 0.0, r.position.y + 0.8)
		var e2 := Vector3(r.end.x - 0.8, 0.0, mid.y) if along_x else Vector3(mid.x, 0.0, r.end.y - 0.8)
		var from_end := e1 if e1.distance_to(City.INSTITUTE_EXIT) < e2.distance_to(City.INSTITUTE_EXIT) else e2
		var far_end := e2 if from_end == e1 else e1
		if not City.is_free(far_end) or not City.is_free(from_end):
			continue
		if far_end.lerp(from_end, 0.7).distance_to(City.START_POS) < 65.0:
			continue          # nobody scripted starts within the 60 m the spawn rules keep clear around the start
		best_score = score
		best = {"rect": r, "pos": far_end.lerp(from_end, 0.7), "near": from_end, "along_x": along_x, "off": off, "at": at}
	_lane = best
	return _lane


## Where the lone young soldier waits: on the walk home, LONE_BEFORE_HOME m before the door, facing the way the patrol went
## (towards the home), so the player coming up behind him can take him down silently. {pos, face (yaw)}.
static func lone_soldier_spot() -> Dictionary:
	if not _lone.is_empty():
		return _lone
	var way := _way()
	if way.size() < 2:
		return {}
	var total := 0.0
	for i in way.size() - 1:
		total += way[i].distance_to(way[i + 1])
	var pts := _samples(way, 2.0)
	var want := maxf(total - LONE_BEFORE_HOME, total * 0.5)
	var spot := Vector3.INF
	var ahead := Vector3.INF
	for sp in pts:
		var p: Vector3 = sp[0]
		if float(sp[1]) < want:
			continue
		for off in [0.0, 5.0, -5.0, 8.0, -8.0]:          # the path often runs on the clear band of the avenue: step aside onto the road
			var q := p + Vector3(off, 0.0, 0.0)
			if City.is_free(q) and absf(q.x - City.HOME_POS.x) > 6.0 and not CityWar._in_clear(Rect2(q.x - 0.5, q.z - 0.5, 1.0, 1.0)):
				spot = q
				break
		if spot != Vector3.INF:
			break
	if spot == Vector3.INF:
		return {}
	for sp in pts:
		if float(sp[1]) >= want + 8.0:
			ahead = sp[0]
			break
	if ahead == Vector3.INF:
		ahead = City.HOME_POS
	var d := ahead - spot
	_lone = {"pos": spot, "face": atan2(-d.x, -d.z)}
	return _lone


## Spots for the dead along the walk home: against the nearest wall (doorways) or at the street edge (gutters), one every
## BODY_SPACING m, never within 18 m of the Institute exit or 14 m of the home door, not on the clear band of the main avenues.
static func body_spots(rng: RandomNumberGenerator) -> Array:
	var way := _way()
	var out: Array = []
	if way.size() < 2:
		return out
	var pts := _samples(way, BODY_SPACING)
	for sp in pts:
		if out.size() >= BODY_COUNT:
			break
		var p: Vector3 = sp[0]
		if p.distance_to(City.INSTITUTE_EXIT) < 18.0 or p.distance_to(City.HOME_POS) < 14.0:
			continue
		var dir := Vector3(cos(PI * 0.5 * float(rng.randi() % 4)), 0.0, sin(PI * 0.5 * float(rng.randi() % 4)))
		var q := p + Vector3(rng.randf_range(-2.0, 2.0), 0.0, rng.randf_range(-2.0, 2.0))
		var hit := Vector3.INF
		var d := 0.5
		while d < 14.0:
			var t := q + dir * d
			if not City.is_free(t):
				hit = q + dir * (d - 0.85)       # a body's length from the wall
				break
			d += 0.5
		var spot := hit
		if spot == Vector3.INF or rng.randf() < 0.3:
			spot = _gutter(p, rng)
		if spot != Vector3.INF and City.is_free(spot) and absf(spot.x) > 3.6 and absf(spot.z) > 3.6:
			out.append(spot)
	return out


## A point at the street edge next to `p` (the gutter along the kerb).
static func _gutter(p: Vector3, rng: RandomNumberGenerator) -> Vector3:
	for st in City.streets:
		var r: Rect2 = st["rect"]
		if not r.has_point(Vector2(p.x, p.z)):
			continue
		if r.size.x > r.size.y:
			var edge := r.position.y + 0.9 if absf(p.z - r.position.y) < absf(p.z - r.end.y) else r.end.y - 0.9
			return Vector3(p.x + rng.randf_range(-3.0, 3.0), 0.0, edge)
		var edge_x := r.position.x + 0.9 if absf(p.x - r.position.x) < absf(p.x - r.end.x) else r.end.x - 0.9
		return Vector3(edge_x, 0.0, p.z + rng.randf_range(-3.0, 3.0))
	return Vector3.INF


# ================================================================== the lander in the park

## The landing craft stands on the park's LANDING area (the model is `ShipModels`, built by `World`): soldiers walk round it, not through it.
## The hull's footprint is 21 x 10 m, the engine pods stick out 2.9 m on both sides at the back; the ramp stays open.
static func _lander_blocks() -> void:
	var o := City.LANDER_POS
	Scn.block(Rect2(o.x - 10.5, o.z - 5.2, 21.0, 10.4), 0.2)
	Scn.block(Rect2(o.x - 7.5, o.z - 7.7, 8.0, 3.3), 0.2)
	Scn.block(Rect2(o.x - 7.5, o.z + 4.4, 8.0, 3.3), 0.2)


# ================================================================== the lookout roof

## The roof Noah climbs to look out over the city: `{building, side, foot (Vector3 at the bottom of the way up), roof (Vector3 on the roof,
## about 1.5 m in from the edge), top (roof height), kind "escape" | "ladder"}`; filled by CityClimb when it builds the way up.
static var lookout := {}


## CityClimb._plan_access asks for the building that gets a guaranteed fire escape: an ordinary flat-roofed block 10-24 m high between the
## home and the park (the roof must clear the park's trees so the landing area is in sight), on a street at least 8 m wide.
static func pick_lookout() -> Dictionary:
	lookout = {}
	for b0 in City.buildings:
		if b0.has("lookout_plot") and CityClimb._ordinary(b0) and not b0.has("special"):
			b0["access"] = true
			b0["special"] = true
			b0["lookout"] = true
			return b0
	var best := {}
	var best_score := INF
	for b in City.buildings:
		if not CityClimb._ordinary(b) or b.has("special") or b.has("access") or (b["boxes"] as Array).size() != 1:
			continue
		var h: float = b["h"]
		var r: Rect2 = b["rect"]
		if h < 10.0 or h > 24.0 or minf(r.size.x, r.size.y) < 9.0:
			continue
		var c := r.get_center()
		var d_park := c.distance_to(Vector2(City.LANDER_POS.x, City.LANDER_POS.z))
		var d_home := c.distance_to(Vector2(City.HOME_POS.x, City.HOME_POS.z))
		if d_park < 26.0 or d_park > 70.0 or d_home > 60.0:
			continue
		var wide := false
		for sd in CityBuildings.street_sides(r):
			if float(sd[0]) >= 8.0 and CityBuildings._side_len(r, int(sd[1])) >= 10.5:
				wide = true
		if not wide:
			continue
		var score := absf(d_park - 42.0) + d_home * 0.3 + absf(h - 15.0) * 0.2
		if score < best_score:
			best_score = score
			best = b
	if not best.is_empty():
		best["access"] = true
		best["special"] = true
		best["lookout"] = true
	return best


# ================================================================== the way to the park and the scripted soldiers of "The Lander"

const MARKSMAN_AT := Vector3(77.5, 3.4, -30.7)          # the balcony marksman crouches at the north rail (rifle propped on it), facing the park

const GUARD_COUNT := 10
const GUARD_RING := [4.5, 8.0]                           # radii of the two rows of guards round the foot of the ramp

static var _rest := {}
static var _guards: Array = []
static var _escape := {}


## The ramp's foot in the world (where the ten guards stand round it).
static func ramp_foot() -> Vector3:
	return City.LANDER_POS + Basis(Vector3.UP, City.LANDER_YAW) * ShipModels.ramp_foot_local()


## Where the two gasping soldiers sit: against the west wall of the balcony building (the park block's street side, 7-15 m south of the
## stair foot, in sight of anyone coming to the park along the street), facing the street, 1.5 m apart.
## {a, b (positions), face (yaw, away from the wall), wall (unit vector to the wall)}; needs the navigation grid.
static func rest_spot() -> Dictionary:
	if not _rest.is_empty():
		return _rest
	var wall_x := 62.0                                   # the balcony building's west face (CityPlaces._balcony_building)
	var z := -26.0
	while z <= -16.0:
		var a := Vector3(wall_x - 0.75, 0.0, z)
		var b := Vector3(wall_x - 0.75, 0.0, z + 1.5)
		if City.is_free(a) and City.is_free(b) and City.is_free(a + Vector3(-1.5, 0, 0)) and City.is_free(b + Vector3(-1.5, 0, 0)) and not City.is_free(a + Vector3(1.2, 0, 0)):
			_rest = {"a": a, "b": b, "face": PI * 0.5, "wall": Vector3(1, 0, 0)}
			return _rest
		z += 0.75
	return {}


## Where the two exhausted soldiers drag themselves once the craft has landed: beside the guards' fan, north-west of the ramp foot.
static func exhausted_goal() -> Vector3:
	var foot := ramp_foot()
	for off in [Vector3(-5.0, 0.0, -7.5), Vector3(-9.0, 0.0, -5.0), Vector3(-4.0, 0.0, -10.0), Vector3(-10.0, 0.0, -9.0)]:
		if City.is_free(foot + off):
			return foot + off
	return foot + Vector3(-8.0, 0.0, -6.0)


## The ten guards at the foot of the ramp: two rows of five on an arc round it (the ramp points west, so the arc opens west), facing outwards.
## [{pos, face}]; nudged off props (benches, trees) by the navigation grid.
static func guard_spots() -> Array:
	if not _guards.is_empty():
		return _guards
	var foot := ramp_foot()
	var out: Array = []
	for row in 2:
		var r: float = GUARD_RING[row]
		for i in 5:
			var a := deg_to_rad(-30.0 + 15.0 * float(i) + (7.5 if row == 1 else 0.0))        # a 75 degree fan: nobody faces the balcony
			var dir := Vector3(-cos(a), 0.0, sin(a))               # west of the foot, fanned north-south
			var p := foot + dir * r
			if not City.is_free(p):
				for t in 12:
					var q := foot + dir.rotated(Vector3.UP, 0.12 * float(t + 1) * (1.0 if t % 2 == 0 else -1.0)) * (r + 0.4 * float(t % 3))
					if City.is_free(q):
						p = q
						break
			out.append({"pos": p, "face": atan2(dir.x, dir.z) + PI})
	_guards = out
	return _guards


## The mouth of the west lane of Noah's neighbourhood (City.COURT_BLOCK) where the run after the park fight ends: {pos, rect}.
## The lane is 3 m wide and 52 m long; the chasers get here after him (ChaseFight).
static func escape_lane() -> Dictionary:
	if not _escape.is_empty():
		return _escape
	var p := Vector3(71.5, 0.0, 16.0)
	if City.is_free(p) and City.path(City.BALCONY_STAIR_FOOT, p).size() >= 2:
		_escape = {"pos": p, "rect": Rect2(70.0, 12.0, 3.0, 52.0)}
	return _escape


## The middle of the courtyard (where the squad stands back to back) and its two gates.
static func court_pos() -> Vector3:
	return City.COURT_POS


## The foot of the drainpipe up the north wing's west face (the way to the roof over the courtyard), 0.6 m out into the lane.
static func pipe_foot() -> Vector3:
	var p: Dictionary = CityPlaces.pipes[0] if not CityPlaces.pipes.is_empty() else {}
	if p.is_empty():
		return Vector3(72.0, 0.0, 20.0)
	var b: Vector3 = p["base"]
	var n: Vector2 = p["n"]
	return b + Vector3(n.x, 0.0, n.y) * 0.7


## Two grenades somebody left on the low roof (right where the drainpipe comes up), a guaranteed extra for the courtyard.
static func court_stash() -> Array:
	return [Vector3(75.0, City.COURT_ROOF_Y, 17.5), Vector3(75.0, City.COURT_ROOF_Y, 18.7)]


## Where the four courtyard soldiers can stand when they are put there directly (a circle of 2.2 m round the centre, one per quarter).
static func court_ring(n: int) -> Array:
	var out: Array = []
	for i in n:
		var a := TAU * float(i) / float(maxi(n, 1)) + 0.3
		out.append(City.COURT_POS + Vector3(cos(a), 0.0, sin(a)) * 2.2)
	return out


static func _near_building(p: Vector3, grow: float) -> bool:
	for b in City.buildings:
		if (b["rect"] as Rect2).grow(grow).has_point(Vector2(p.x, p.z)):
			return true
	return false


# ================================================================== the other landing craft

const FAR_LANDERS := 3
static var far_landers: Array = []         # [{pos: Vector3, yaw: float}]: settled craft in far plazas, seen from the lookout roof (drawn by World)

## A few more craft that have settled in the squares of the city, far from the park: the nearest plazas (90 m or more from the park, off the route)
## that have a free spot for the hull (drawn at FAR_SCALE of the model: 16 m long), scanned in 2 m steps because the plazas hold a few trees.
## Static scenery: one MultiMesh of the cheap hull (`World`), a solid box and a nav block each.
const FAR_SCALE := 0.8

static func _far_landers(rng: RandomNumberGenerator) -> void:
	var plazas: Array = []
	for st in City.streets:
		if st["cls"] != "plaza":
			continue
		var r: Rect2 = st["rect"]
		var c := r.get_center()
		var cp := Vector3(c.x, 0.0, c.y)
		if cp.distance_to(City.LANDER_POS) < 90.0 or cp.distance_to(City.HOME_POS) < 50.0 or cp.distance_to(City.INSTITUTE_EXIT) < 60.0:
			continue
		plazas.append([cp.distance_to(City.LANDER_POS), r])
	plazas.sort_custom(func(a, b): return a[0] < b[0])
	for pl in plazas:
		if far_landers.size() >= FAR_LANDERS:
			break
		var r2: Rect2 = pl[1]
		var spot := {}
		for yaw in [0.0, PI * 0.5]:
			if not spot.is_empty():
				break
			var half := Vector2(6.2, 10.0) if yaw == 0.0 else Vector2(10.0, 6.2)
			var x := r2.position.x + half.x
			while x <= r2.end.x - half.x and spot.is_empty():
				var z := r2.position.y + half.y
				while z <= r2.end.y - half.y:
					var fp := Rect2(Vector2(x, z) - half, half * 2.0)
					if _free(fp):
						spot = {"pos": Vector3(x, 0.0, z), "yaw": yaw, "rect": fp}
						break
					z += 2.0
				x += 2.0
		if spot.is_empty():
			continue
		var too_near := false
		for fl in far_landers:
			if (fl["pos"] as Vector3).distance_to(spot["pos"]) < 70.0:
				too_near = true
		if too_near:
			continue
		CityWar.occ.add(spot["rect"])
		Scn.block(spot["rect"], 0.3)
		Scn.solid((spot["pos"] as Vector3) + Vector3(0, 2.4, 0), Vector3(8.0, 4.8, 16.4), float(spot["yaw"]))
		far_landers.append({"pos": spot["pos"], "yaw": spot["yaw"]})
