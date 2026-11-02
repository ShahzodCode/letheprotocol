class_name CityGreen
## Green buildings: about one ordinary lot building in GREEN_SHARE is redesigned so that greenery is part of its architecture.
##   * its footprint is pulled in from the lot (INSET), and the freed ring is a garden: lawn, a paved apron on the street sides,
##     low hedges with gaps, and oaks in the corners (park trees: always healthy, no planter);
##   * a mid-rise (MID_H) is rebuilt as stepped terraces (2-4 tiers, each set back on its street sides) and every terrace is planted:
##     a lawn bed, a hedge along its edge and small oaks (drawn by Oaks, no collider, out of reach);
##   * a tower keeps its tiers, but its setbacks are planted the same way, and its podium roof becomes a garden;
##   * hanging greenery (ivy) grows down the upper facade above the shop floor.
## Runs in City.generate after CityModels.place (so the model lots are taken) and before CityWar.trees, CityClimb, CityBuildings and
## the navigation grid (they all see the new footprint and boxes). Own random stream.

const GREEN_SHARE := 3           # one in this many candidate buildings
const MIN_SIDE := 14.0           # the footprint must be this wide on both sides before the inset
const MIN_H := 12.0
const INSET := 4.5               # the building pulls in this far from its lot on every side
const MIN_LEFT := 10.0           # ... but keeps at least this much footprint
const MIN_INSET := 2.0           # a lot too small for a garden this wide is left alone
const MID_H := [15.0, 75.0]      # rebuilt as terraces
const TIER_SET := 2.6            # each terrace is set back this far on the sides that step
const LAWN := Color(0.31, 0.52, 0.18)
const BED := Color(0.27, 0.46, 0.16)
const HEDGE := Color(0.13, 0.27, 0.1)
const IVY := Color(0.17, 0.32, 0.12)
const APRON := Color(0.6, 0.59, 0.56)
const PLANTER := Color(0.82, 0.81, 0.77)
const BAND_STEP := 3.4           # a planted balcony band every floor
const BAND_TOP := 70.0
const BAND_OUT := 0.8            # how far a band sticks out of the wall
const BAND_H := 0.7
const ROOF_TREE_H := [3.8, 5.2]
const GARDEN_TREE_H := [7.5, 10.0]
const HAND_PAD := 8.0

static var count := 0


static func plan(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 6060
	count = 0
	var hand: Array = []
	for hb in [City.INSTITUTE_BLOCK, City.HOME_BLOCK, City.PARK_BLOCK, City.COURT_BLOCK]:
		hand.append((hb as Rect2).grow(HAND_PAD))
	for lot in City.lots:
		var b: Dictionary = lot["b"]
		var r: Rect2 = lot["r"]
		if not _plain(b) or float(b["h"]) < MIN_H:
			continue
		var fp: Rect2 = b["rect"]
		if minf(fp.size.x, fp.size.y) < MIN_SIDE:
			continue
		var bad := false
		for h in hand:
			if (h as Rect2).intersects(r):
				bad = true
		if bad or not City.buildings.has(b):
			continue
		if rng.randi() % GREEN_SHARE != 0:
			continue
		if _make_green(b, r, rng):
			count += 1


## An ordinary generated box building (nothing but its basic keys: no story role, passage, model...).
static func _plain(b: Dictionary) -> bool:
	for k in b:
		if not String(k) in ["rect", "boxes", "style", "color", "h", "bid"]:
			return false
	return true


static func _make_green(b: Dictionary, lot: Rect2, rng: RandomNumberGenerator) -> bool:
	var old: Rect2 = b["rect"]
	var ins := minf(INSET, (minf(lot.size.x, lot.size.y) - MIN_LEFT) * 0.5)
	if ins < MIN_INSET:
		return false
	var fp := lot.grow(-ins)
	var h: float = b["h"]
	# [width, side] per side, best first; CityBuildings numbers the sides -z, +z, -x, +x, here they are -x, +x, -z, +z
	var sides: Array = []
	for sd in CityBuildings.street_sides(old):
		sides.append([sd[0], [2, 3, 0, 1][int(sd[1])]])
	var boxes: Array = []
	if h <= MID_H[1]:
		boxes = _terraces(fp, h, sides, rng)
	else:
		# a tower: its tiers mapped from the old footprint onto the new one
		for bx in b["boxes"]:
			boxes.append({"rect": _remap(bx["rect"], old, fp), "y0": bx["y0"], "y1": bx["y1"]})
		# a podium (two floors) under the tower on the full footprint, its roof planted
		var tower: Rect2 = boxes[0]["rect"]
		var shaft := tower.grow(-minf(5.0, minf(tower.size.x, tower.size.y) * 0.18))
		boxes[0]["rect"] = shaft
		boxes.insert(0, {"rect": tower, "y0": 0.0, "y1": 8.0})
		boxes[1]["y0"] = 8.0
	b["rect"] = fp
	b["boxes"] = boxes
	b["green"] = true
	_garden(lot, fp, sides, rng)
	# every box top that is not covered by the box above it is planted
	for i in boxes.size():
		var bx: Dictionary = boxes[i]
		var above: Rect2 = Rect2()
		for j in boxes.size():
			if j != i and is_equal_approx(float(boxes[j]["y0"]), float(bx["y1"])):
				above = boxes[j]["rect"]
		_terrace_planting(bx["rect"], float(bx["y1"]), above, rng, i == boxes.size() - 1 and h > 60.0)
	_ivy(fp, boxes, rng)
	_bands(boxes, rng)
	return true


## Planted balconies: a green planter band round every box each BAND_STEP up the facade (above the shop floor, up to BAND_TOP),
## broken into 2-3 pieces per side so it reads as planting, not as a stripe; now and then a shrub sticks up out of it.
static func _bands(boxes: Array, rng: RandomNumberGenerator) -> void:
	for bx in boxes:
		var r: Rect2 = bx["rect"]
		var y := maxf(float(bx["y0"]), 4.6) + BAND_STEP * 0.5
		while y < minf(float(bx["y1"]) - 1.0, BAND_TOP):
			for s in 4:
				var along_x := s >= 2
				var length := r.size.x if along_x else r.size.y
				var t := rng.randf_range(0.0, 1.5)
				while t < length - 1.0:
					var piece := minf(rng.randf_range(2.5, 6.5), length - t)
					var mid := t + piece * 0.5
					var c: Vector3
					var size: Vector3
					match s:
						0:
							c = Vector3(r.position.x - BAND_OUT * 0.5, y, r.position.y + mid)
							size = Vector3(BAND_OUT, BAND_H, piece)
						1:
							c = Vector3(r.end.x + BAND_OUT * 0.5, y, r.position.y + mid)
							size = Vector3(BAND_OUT, BAND_H, piece)
						2:
							c = Vector3(r.position.x + mid, y, r.position.y - BAND_OUT * 0.5)
							size = Vector3(piece, BAND_H, BAND_OUT)
						_:
							c = Vector3(r.position.x + mid, y, r.end.y + BAND_OUT * 0.5)
							size = Vector3(piece, BAND_H, BAND_OUT)
					Scn.box(c - Vector3(0, BAND_H * 0.4, 0), Vector3(size.x, BAND_H * 0.25, size.z), PLANTER)
					Scn.box(c + Vector3(0, BAND_H * 0.1, 0), size * Vector3(1.0, 1.05, 1.15), HEDGE.lerp(LAWN, rng.randf() * 0.6))
					if rng.randf() < 0.6:
						Scn.box(c + Vector3(0, BAND_H * 0.8, 0), Vector3(minf(size.x, 1.5), 1.1, minf(size.z, 1.3)), HEDGE.lerp(IVY, rng.randf()), rng.randf() * TAU)
					t += piece + rng.randf_range(0.8, 2.5)
			y += BAND_STEP


## Stepped terraces: 2-4 tiers, each set back on the street sides (the back stays a straight wall).
static func _terraces(fp: Rect2, h: float, sides: Array, rng: RandomNumberGenerator) -> Array:
	var n := clampi(int(h / 13.0), 2, 4)
	var step_sides: Array = []
	for s in sides:
		if float(s[0]) > 0.0 and step_sides.size() < 2:
			step_sides.append(int(s[1]))
	if step_sides.is_empty():
		step_sides = [rng.randi_range(0, 3)]
	var boxes: Array = []
	var r := fp
	var y := 0.0
	var tier_h := h / n
	for i in n:
		var y1 := h if i == n - 1 else y + tier_h * rng.randf_range(0.9, 1.1)
		boxes.append({"rect": r, "y0": y, "y1": y1})
		y = y1
		var nr := r
		for s in step_sides:
			nr = _pull(nr, int(s), TIER_SET)
		if minf(nr.size.x, nr.size.y) < 9.0:
			boxes[boxes.size() - 1]["y1"] = h
			break
		r = nr
	return boxes


## Rect r pulled in by d on side s (0 = -x, 1 = +x, 2 = -z, 3 = +z).
static func _pull(r: Rect2, s: int, d: float) -> Rect2:
	match s:
		0:
			return Rect2(r.position.x + d, r.position.y, r.size.x - d, r.size.y)
		1:
			return Rect2(r.position.x, r.position.y, r.size.x - d, r.size.y)
		2:
			return Rect2(r.position.x, r.position.y + d, r.size.x, r.size.y - d)
		_:
			return Rect2(r.position.x, r.position.y, r.size.x, r.size.y - d)


static func _remap(r: Rect2, a: Rect2, b: Rect2) -> Rect2:
	var k := b.size / a.size
	return Rect2(b.position + (r.position - a.position) * k, r.size * k)


## The ground garden in the ring between the lot and the new footprint.
static func _garden(lot: Rect2, fp: Rect2, sides: Array, rng: RandomNumberGenerator) -> void:
	City.ground_slabs.append([lot, LAWN, 1])
	# a paved apron along the lot edge on the street sides (the hedges stand behind it), and a path to the door on the best side
	var best := int(sides[0][1]) if not sides.is_empty() else 3
	for s in sides:
		if float(s[0]) <= 0.0:
			continue
		var apron := _edge(lot, int(s[1]), 1.2)
		City.ground_slabs.append([apron, APRON, 2])
		# a hedge just inside the apron, broken in the middle (the way in) and at the corners
		var hr := _edge(_edge_inner(lot, int(s[1]), 1.2), int(s[1]), 0.9)
		for piece in _split_hedge(hr, int(s[1])):
			var c := (piece as Rect2).get_center()
			Scn.box(Vector3(c.x, 0.45, c.y), Vector3(piece.size.x, 0.9, piece.size.y), HEDGE)
			Scn.solid(Vector3(c.x, 0.45, c.y), Vector3(piece.size.x, 0.9, piece.size.y))
			Scn.block(piece, 0.2)
	var door_path := _path_to(lot, fp, best)
	City.ground_slabs.append([door_path, APRON, 2])
	# oaks in the garden corners (where the ring is wide enough), never on the door path
	var gap := minf(minf(fp.position.x - lot.position.x, lot.end.x - fp.end.x), minf(fp.position.y - lot.position.y, lot.end.y - fp.end.y))
	if gap < 3.0:
		return
	var corners := [Vector2(lot.position.x, lot.position.y), Vector2(lot.end.x, lot.position.y), Vector2(lot.position.x, lot.end.y), Vector2(lot.end.x, lot.end.y)]
	for c in corners:
		if rng.randf() < 0.3:
			continue
		var into := (fp.get_center() - (c as Vector2)).normalized()
		var p: Vector2 = (c as Vector2) + Vector2(signf(into.x), signf(into.y)) * (gap * 0.5 + 0.6)
		if door_path.grow(2.0).has_point(p):
			continue
		City.trees.append({"pos": p, "h": rng.randf_range(GARDEN_TREE_H[0], GARDEN_TREE_H[1]), "r": 0.3})


static func _edge(r: Rect2, s: int, w: float) -> Rect2:
	match s:
		0:
			return Rect2(r.position.x, r.position.y, w, r.size.y)
		1:
			return Rect2(r.end.x - w, r.position.y, w, r.size.y)
		2:
			return Rect2(r.position.x, r.position.y, r.size.x, w)
		_:
			return Rect2(r.position.x, r.end.y - w, r.size.x, w)


static func _edge_inner(r: Rect2, s: int, w: float) -> Rect2:
	return _pull(r, s, w)


## A hedge strip cut into two pieces: a 3 m gap in the middle and 1.5 m free at each end.
static func _split_hedge(hr: Rect2, s: int) -> Array:
	var along_x := s >= 2
	var length := hr.size.x if along_x else hr.size.y
	if length < 9.0:
		return []
	var half := (length - 3.0) * 0.5 - 1.5
	var out: Array = []
	for k in 2:
		var start := 1.5 if k == 0 else 1.5 + half + 3.0
		if along_x:
			out.append(Rect2(hr.position.x + start, hr.position.y, half, hr.size.y))
		else:
			out.append(Rect2(hr.position.x, hr.position.y + start, hr.size.x, half))
	return out


## The path from the middle of the best street side to the building.
static func _path_to(lot: Rect2, fp: Rect2, s: int) -> Rect2:
	var c := fp.get_center()
	match s:
		0:
			return Rect2(lot.position.x, c.y - 1.5, fp.position.x - lot.position.x, 3.0)
		1:
			return Rect2(fp.end.x, c.y - 1.5, lot.end.x - fp.end.x, 3.0)
		2:
			return Rect2(c.x - 1.5, lot.position.y, 3.0, fp.position.y - lot.position.y)
		_:
			return Rect2(c.x - 1.5, fp.end.y, 3.0, lot.end.y - fp.end.y)


## Planting on the exposed top of a box (the part not under `above`): lawn beds, a hedge on the open edges, small oaks.
static func _terrace_planting(r: Rect2, y: float, above: Rect2, rng: RandomNumberGenerator, high: bool) -> void:
	var pieces: Array = CityPlaces.cut(r.grow(-0.3), [above] if above.has_area() else [])
	for piece in pieces:
		var pr: Rect2 = piece
		if minf(pr.size.x, pr.size.y) < 1.5:
			continue
		var c := pr.get_center()
		Scn.box(Vector3(c.x, y + 0.2, c.y), Vector3(pr.size.x, 0.4, pr.size.y), BED if rng.randf() < 0.5 else LAWN)
		# a hedge ring on the outer edge of the terrace (a parapet of green)
		for s in 4:
			var e := _edge(pr, s, 0.6)
			if above.has_area() and above.grow(0.4).intersects(e):
				continue
			var ec := e.get_center()
			Scn.box(Vector3(ec.x, y + 0.75, ec.y), Vector3(e.size.x, 0.7, e.size.y), HEDGE)
		# small oaks along the terrace, every 6-8 m where it is deep enough
		if minf(pr.size.x, pr.size.y) < 2.4 or high:
			continue
		var along_x := pr.size.x >= pr.size.y
		var length := pr.size.x if along_x else pr.size.y
		var t := rng.randf_range(2.0, 4.0)
		while t < length - 1.5:
			var p := Vector2(pr.position.x + t, c.y) if along_x else Vector2(c.x, pr.position.y + t)
			var pk := Oaks.pick(p)
			Scn.oaks.append([Oaks.xf_for(Vector3(p.x, y + 0.35, p.y), rng.randf_range(ROOF_TREE_H[0], ROOF_TREE_H[1]), pk[2]), pk[0], pk[1]])
			t += rng.randf_range(6.0, 8.5)


## Hanging greenery down the upper facade: a few strips on each long side, above the shop floor.
static func _ivy(fp: Rect2, boxes: Array, rng: RandomNumberGenerator) -> void:
	var base: Dictionary = boxes[0]
	var r: Rect2 = base["rect"]
	var top: float = base["y1"]
	if top < 9.0:
		return
	for s in 4:
		var along_x := s >= 2
		var length := r.size.x if along_x else r.size.y
		var n := int(length / 9.0)
		for i in n:
			if rng.randf() < 0.4:
				continue
			var w := rng.randf_range(2.0, 3.6)
			var t := (i + 0.5) * length / n + rng.randf_range(-1.0, 1.0)
			var y1 := top - rng.randf_range(0.0, 1.0)
			var y0 := maxf(4.6, y1 - rng.randf_range(4.0, 12.0))
			var c: Vector3
			var size: Vector3
			match s:
				0:
					c = Vector3(r.position.x - 0.08, (y0 + y1) * 0.5, r.position.y + t)
					size = Vector3(0.16, y1 - y0, w)
				1:
					c = Vector3(r.end.x + 0.08, (y0 + y1) * 0.5, r.position.y + t)
					size = Vector3(0.16, y1 - y0, w)
				2:
					c = Vector3(r.position.x + t, (y0 + y1) * 0.5, r.position.y - 0.08)
					size = Vector3(w, y1 - y0, 0.16)
				_:
					c = Vector3(r.position.x + t, (y0 + y1) * 0.5, r.end.y + 0.08)
					size = Vector3(w, y1 - y0, 0.16)
			Scn.box(c, size, IVY.lerp(HEDGE, rng.randf() * 0.6))
