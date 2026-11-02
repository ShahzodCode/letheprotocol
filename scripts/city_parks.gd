class_name CityParks
## Open lawn parks (like a city park in summer): a whole block of plain bright grass inside a paved rim, two curving pale paths,
## one low white curving wall (a long seat that is also cover), low hedges, a few big oaks and benches along the paths. No street
## entry (nobody spawns here, the navigation grid is open, roaming soldiers path across); the oaks are park trees (always healthy,
## no planter: CityWar.trees draws them). City.generate still runs the block's subdivision and throws the result away, so the
## random stream (and the rest of the city) stays as it was.

## The blocks that become parks (whole blocks between through streets, off the Chapter One route, no model building on them).
const PARKS := [Rect2(-103.0, 134.0, 43.0, 45.0), Rect2(60.0, -194.0, 43.0, 50.0), Rect2(-103.0, -136.0, 43.0, 50.0)]
const RIM := 2.5                         # paved rim round the lawn
const LAWN := Color(0.33, 0.55, 0.19)
const PAVING := Color(0.62, 0.61, 0.58)
const PATH := Color(0.86, 0.85, 0.81)
const WHITE := Color(0.93, 0.93, 0.91)
const HEDGE := Color(0.13, 0.27, 0.1)
const BENCH := Color(0.45, 0.32, 0.2)
const PATH_W := [3.2, 2.4]
const SEG := 1.6                         # path / wall pieces are this long
const WALL_H := 0.5
const WALL_W := 1.3
const TREES := 5
const TREE_H := [10.5, 14.5]
const OPEN_R := 8.0                      # an open lawn in the middle: no tree within this of the lawn centre


static func is_park(block: Rect2) -> int:
	for i in PARKS.size():
		if (PARKS[i] as Rect2).position.is_equal_approx(block.position) and (PARKS[i] as Rect2).size.is_equal_approx(block.size):
			return i
	return -1


static func build(block: Rect2, idx: int, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 4040 + idx * 17
	City.ground_slabs.append([block.grow(-0.4), PAVING, 1])
	var lawn := block.grow(-RIM)
	City.ground_slabs.append([lawn, LAWN, 2])
	var flip_u := idx % 2 == 1
	var flip_v := idx == 2
	var to_w := func(u: float, v: float) -> Vector2:
		var uu := 1.0 - u if flip_u else u
		var vv := 1.0 - v if flip_v else v
		return Vector2(lawn.position.x + uu * lawn.size.x, lawn.position.y + vv * lawn.size.y)
	# two paths: a long S across the lawn and a gentle curve crossing it
	var paths: Array = []
	var p1: Array = []
	var p2: Array = []
	for i in 41:
		var t := i / 40.0
		p1.append(to_w.call(-0.04 + t * 1.08, 0.22 + 0.56 * smoothstep(0.0, 1.0, t) + 0.07 * sin(TAU * t)))
		p2.append(to_w.call(0.28 + 0.3 * t + 0.1 * sin(PI * t), 1.04 - t * 1.08))
	paths.append(p1)
	paths.append(p2)
	for k in 2:
		_strip(paths[k], float(PATH_W[k]), PATH)
	# the low white wall: an arc round a hollow of lawn, on the side away from the long path's start
	var wall: Array = []
	var wc: Vector2 = to_w.call(0.72, 0.28)
	var wr := minf(lawn.size.x, lawn.size.y) * 0.2
	var a0 := deg_to_rad(205.0 + rng.randf_range(-10.0, 10.0))
	var a1 := deg_to_rad(330.0 + rng.randf_range(-10.0, 10.0))
	var steps := int((a1 - a0) * wr / SEG)
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps)
		var sgn := -1.0 if flip_v else 1.0
		wall.append(wc + Vector2(cos(a) * (-1.0 if flip_u else 1.0), sin(a) * sgn) * wr)
	for i in wall.size() - 1:
		var a: Vector2 = wall[i]
		var b: Vector2 = wall[i + 1]
		var c := (a + b) * 0.5
		var yaw := atan2((b - a).x, (b - a).y)
		var size := Vector3(WALL_W, WALL_H, a.distance_to(b) + 0.15)
		Scn.box(Vector3(c.x, WALL_H * 0.5, c.y), size, WHITE, yaw)
		Scn.solid(Vector3(c.x, WALL_H * 0.5, c.y), size, yaw)
		Scn.block(Scn.footprint(c, Vector2(WALL_W * 0.5, size.z * 0.5), yaw), 0.2)
	# low hedges along two edges of the lawn (cover for a crouching player)
	for h in 2:
		var along_x := h == 0
		var length := rng.randf_range(9.0, 13.0)
		var u := rng.randf_range(0.15, 0.55)
		var hc: Vector2
		var hs: Vector2
		if along_x:
			hc = to_w.call(u, 0.94)
			hs = Vector2(length, 1.1)
		else:
			hc = to_w.call(0.05, u + 0.25)
			hs = Vector2(1.1, length)
		var hr := Rect2(hc - hs * 0.5, hs)
		if _near_line(hc, paths, 3.5 + length * 0.5):
			continue
		Scn.box(Vector3(hc.x, 0.48, hc.y), Vector3(hs.x, 0.95, hs.y), HEDGE)
		Scn.solid(Vector3(hc.x, 0.48, hc.y), Vector3(hs.x, 0.95, hs.y))
		Scn.block(hr, 0.3)
	# big oaks: away from the paths, the wall and each other, the middle of the lawn left open
	var placed: Array = []
	var centre := lawn.get_center()
	for tries in 200:
		if placed.size() >= TREES:
			break
		var p := Vector2(rng.randf_range(lawn.position.x + 2.0, lawn.end.x - 2.0), rng.randf_range(lawn.position.y + 2.0, lawn.end.y - 2.0))
		if p.distance_to(centre) < OPEN_R or _near_line(p, paths, 3.6) or _near_pts(p, wall, 4.0) or _near_pts(p, placed, 9.0):
			continue
		placed.append(p)
		City.trees.append({"pos": p, "h": rng.randf_range(TREE_H[0], TREE_H[1]), "r": 0.4})
	# benches beside the paths, facing them (props are axis-aligned: the seat faces the path's nearer axis)
	for k in 2:
		var pts: Array = paths[k]
		for t in ([0.18, 0.42, 0.68] if k == 0 else [0.3, 0.7]):
			var i := int(t * (pts.size() - 1))
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var d := (b - a).normalized()
			var n := Vector2(-d.y, d.x) * (1.0 if (i % 2 == 0) else -1.0)
			var ax := Vector2(signf(n.x), 0.0) if absf(n.x) > absf(n.y) else Vector2(0.0, signf(n.y))
			var sc := a + ax * (float(PATH_W[k]) * 0.5 + 0.9)
			if not lawn.grow(-0.5).has_point(sc) or _near_pts(sc, wall, 2.0):
				continue
			_bench(sc, -ax)


## A pale strip along a polyline (short flat pieces, slightly overlapping, so the curve has no gaps).
static func _strip(pts: Array, width: float, color: Color) -> void:
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var yaw := atan2((b - a).x, (b - a).y)
		Scn.decal("paint", (a + b) * 0.5, Vector2(width, a.distance_to(b) + 0.35), yaw, color, 0.105)


## A park bench at `c`, its front towards `face` (unit axis vector): a seat and a back rest on the far side.
static func _bench(c: Vector2, face: Vector2) -> void:
	var across := absf(face.x) > 0.5            # the bench runs along z when it faces x
	var seat := Rect2(c.x - 0.25, c.y - 0.8, 0.5, 1.6) if across else Rect2(c.x - 0.8, c.y - 0.25, 1.6, 0.5)
	CityPlaces._prop(seat, 0.0, 0.5, BENCH, "main")
	var bc := c - face * 0.3
	var back := Rect2(bc.x - 0.05, bc.y - 0.8, 0.1, 1.6) if across else Rect2(bc.x - 0.8, bc.y - 0.05, 1.6, 0.1)
	CityPlaces._prop(back, 0.5, 0.95, BENCH, "")


static func _near_line(p: Vector2, paths: Array, dist: float) -> bool:
	for pts in paths:
		if _near_pts(p, pts, dist):
			return true
	return false


static func _near_pts(p: Vector2, pts: Array, dist: float) -> bool:
	for q in pts:
		if (q as Vector2).distance_to(p) < dist:
			return true
	return false
