class_name CityPlaces
## The hand-built places of Chapter One: the Institute with its lobby, Noah's home with its cellar, the park with the
## balcony building, and the trees. They push plain data into City's static arrays (buildings, props, decor, ramps,
## trees, lights...); World turns that into geometry and City builds the navigation layers from it.
## Plan view: x is east, z is south, rectangles are Rect2(x, z, width, depth).

const STONE := Color(0.93, 0.92, 0.88)
const INTERIOR := Color(0.86, 0.83, 0.76)
const PARTITION := Color(0.88, 0.85, 0.78)
const CONCRETE := Color(0.5, 0.5, 0.52)
const STEP_COUNT := 12


static func _bx(rect: Rect2, y0: float, y1: float) -> Dictionary:
	return {"rect": rect, "y0": y0, "y1": y1}


static func _decor(pos: Vector3, size: Vector3, color: Color, glow: bool = false) -> void:
	City.decor.append({"pos": pos, "size": size, "color": color, "glow": glow})


## Thin lining on the inside of a wall (the window shader would paint windows on a bare wall box).
static func _liner(rect: Rect2, y0: float, y1: float, color: Color) -> void:
	_decor(Vector3(rect.get_center().x, (y0 + y1) * 0.5, rect.get_center().y), Vector3(rect.size.x, y1 - y0, rect.size.y), color)


## Solid furniture / partition with a collider. `nav` names the nav grid it blocks ("main", "home", "cellar" or "").
static func _prop(rect: Rect2, y0: float, y1: float, color: Color, nav: String) -> void:
	City.props.append({"rect": rect, "y0": y0, "y1": y1, "color": color, "style": 0.99, "nav": nav})


static func _seg(line: float, s: float, e: float, t: float, along_x: bool, y0: float, y1: float) -> Dictionary:
	return _bx(Rect2(s, line - t * 0.5, e - s, t) if along_x else Rect2(line - t * 0.5, s, t, e - s), y0, y1)


## Wall boxes along x (at z = line) or along z (at x = line) with door gaps [[from, to], ...] given in absolute
## coordinates along the wall; a lintel closes each gap above `door_h`.
static func _wall(line: float, a: float, b: float, t: float, along_x: bool, doors: Array, h: float, door_h: float) -> Array:
	var out: Array = []
	var pos := a
	for d in doors:
		if float(d[0]) > pos + 0.01:
			out.append(_seg(line, pos, d[0], t, along_x, 0.0, h))
		out.append(_seg(line, d[0], d[1], t, along_x, door_h, h))
		pos = d[1]
	if b > pos + 0.01:
		out.append(_seg(line, pos, b, t, along_x, 0.0, h))
	return out


## A rectangle minus some holes, as a few rectangles (coordinate-compressed grid, merged along x).
static func cut(r: Rect2, holes: Array) -> Array:
	var xs: Array = [r.position.x, r.end.x]
	var ys: Array = [r.position.y, r.end.y]
	var hs: Array = []
	for h in holes:
		var c: Rect2 = (h as Rect2).intersection(r)
		if c.size.x <= 0.001 or c.size.y <= 0.001:
			continue
		hs.append(c)
		xs.append(c.position.x)
		xs.append(c.end.x)
		ys.append(c.position.y)
		ys.append(c.end.y)
	xs.sort()
	ys.sort()
	var out: Array = []
	for j in ys.size() - 1:
		var row_start := -1
		for i in xs.size() - 1:
			var cell := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if cell.size.x < 0.001 or cell.size.y < 0.001:
				continue
			var inside := false
			for h in hs:
				if (h as Rect2).has_point(cell.get_center()):
					inside = true
			if inside:
				row_start = -1
				continue
			if row_start >= 0 and absf((out[row_start] as Rect2).end.x - cell.position.x) < 0.001 and absf((out[row_start] as Rect2).position.y - cell.position.y) < 0.001:
				var prev: Rect2 = out[row_start]
				out[row_start] = Rect2(prev.position, Vector2(cell.end.x - prev.position.x, prev.size.y))
			else:
				out.append(cell)
				row_start = out.size() - 1
	return out


## A smooth slope collider (World) with visual steps drawn on it. a = top, b = bottom; the run is along x or z.
static func _stairs(a: Vector3, b: Vector3, width: float, color: Color) -> void:
	City.ramps.append({"a": a, "b": b, "width": width})
	var along_z := absf(b.z - a.z) > absf(b.x - a.x)
	var run := absf(b.z - a.z) if along_z else absf(b.x - a.x)
	for i in STEP_COUNT:
		var p := a.lerp(b, (i + 0.5) / float(STEP_COUNT))
		var size := Vector3(width, 0.5, run / float(STEP_COUNT)) if along_z else Vector3(run / float(STEP_COUNT), 0.5, width)
		_decor(Vector3(p.x, p.y - 0.25, p.z), size, color.lightened(0.12) if i % 2 == 0 else color)


# ---------------------------------------------------------------- the Institute

static func institute() -> void:
	var fp := City.INSTITUTE_RECT
	var lob := City.LOBBY
	var top := 165.0
	var fl := Rect2(-42.0, 245.0, 10.5, 1.0)       # front wall, left and right of the 3 m doorway
	var fr := Rect2(-28.5, 245.0, 10.5, 1.0)
	var left := Rect2(-42.0, 246.0, 4.0, 12.0)
	var right := Rect2(-22.0, 246.0, 4.0, 12.0)
	var back := Rect2(-42.0, 258.0, 24.0, 11.0)
	var boxes: Array = [
		_bx(fl, 0.0, top), _bx(fr, 0.0, top), _bx(Rect2(-31.5, 245.0, 3.0, 1.0), 4.0, top),      # lintel over the doorway
		_bx(left, 0.0, top), _bx(right, 0.0, top), _bx(back, 0.0, top),
		_bx(lob, City.LOBBY_H, top),                                                              # the lobby ceiling and the tower on it
		_bx(City._shrink(fp, 0.78), top, top + 11.0), _bx(City._shrink(fp, 0.5), top + 11.0, top + 17.0),
		_bx(City._shrink(fp, 0.1), top + 17.0, top + 30.0)]
	City.buildings.append({"rect": fp, "boxes": boxes, "nav_rects": [fl, fr, left, right, back], "style": 0.5, "color": STONE,
		"h": top + 17.0, "institute": true})
	# the inside: linings, floor, ceiling, the lift, the desk and the pillars
	var tall := City.LOBBY_H
	_liner(Rect2(lob.position.x, lob.position.y, 0.1, lob.size.y), 0.0, tall, INTERIOR)
	_liner(Rect2(lob.end.x - 0.1, lob.position.y, 0.1, lob.size.y), 0.0, tall, INTERIOR)
	_liner(Rect2(lob.position.x, lob.end.y - 0.1, lob.size.x, 0.1), 0.0, tall, INTERIOR)
	_liner(Rect2(lob.position.x, lob.position.y, -31.5 - lob.position.x, 0.1), 0.0, tall, INTERIOR)
	_liner(Rect2(-28.5, lob.position.y, lob.end.x + 28.5, 0.1), 0.0, tall, INTERIOR)
	_liner(lob, tall - 0.1, tall, Color(0.92, 0.91, 0.88))
	City.ground_slabs.append([lob, Color(0.4, 0.4, 0.43), 1])
	City.ground_slabs.append([Rect2(-33.0, 246.0, 6.0, 12.0), Color(0.55, 0.3, 0.28), 2])
	_decor(Vector3(-30.0, 1.55, 257.88), Vector3(3.4, 3.1, 0.08), Color(0.18, 0.19, 0.22))                 # lift frame
	_decor(Vector3(-30.0, 1.5, 257.84), Vector3(2.6, 3.0, 0.08), Color(0.7, 0.9, 1.0), true)                # the lift door (glows, not usable)
	_decor(Vector3(-30.0, tall - 0.14, 252.0), Vector3(5.0, 0.06, 3.0), Color(1.0, 0.97, 0.88), true)       # ceiling light panel
	_prop(Rect2(-37.5, 249.5, 5.0, 1.5), 0.0, 1.1, Color(0.62, 0.43, 0.28), "main")                          # reception desk
	_prop(Rect2(-35.5, 252.5, 1.0, 1.0), 0.0, tall, Color(0.9, 0.89, 0.85), "main")                          # two pillars
	_prop(Rect2(-24.5, 252.5, 1.0, 1.0), 0.0, tall, Color(0.9, 0.89, 0.85), "main")
	City.lights.append({"pos": Vector3(-30.0, 4.2, 252.0), "range": 18.0, "energy": 1.2, "color": Color(1.0, 0.95, 0.85)})
	# a lit crown so the tower stands out on the skyline
	_decor(Vector3(-30.0, top + 8.0, 257.0), Vector3(fp.size.x * 0.78 + 0.3, 0.8, fp.size.y * 0.78 + 0.3), Color(0.55, 0.85, 1.0), true)


# ---------------------------------------------------------------- Noah's home

static func home_block(rng: RandomNumberGenerator) -> void:
	# a footpath splits the block: the home plot in the south, ordinary lots in the north
	City.streets.append({"rect": Rect2(12.0, -59.0, 36.0, 6.0), "cls": "walk"})
	City._subdivide(rng, Rect2(12.0, -74.0, 36.0, 15.0), 1)
	City.ground_slabs.append([Rect2(12.6, -52.4, 34.8, 39.8), Color(0.24, 0.42, 0.2)])      # the yard
	City.ground_slabs.append([Rect2(12.0, -31.6, 4.2, 2.0), Color(0.62, 0.6, 0.55), 2])        # path to the front door
	_home()
	_cellar()
	_old_block()


static func _home() -> void:
	var o := City.HOME_ORIGIN
	var hr := City.HOME_RECT
	var ah := City.APT_H
	var door_a := o.y + 4.4
	var door_b := o.y + 5.6
	var boxes: Array = _wall(hr.position.x + 0.2, hr.position.y, hr.end.y, 0.4, false, [[door_a, door_b]], ah, 2.2)   # west wall with the front door
	boxes.append(_bx(Rect2(o.x + 14.0, hr.position.y, 0.4, hr.size.y), 0.0, ah))
	boxes.append(_bx(Rect2(o.x, hr.position.y, 14.0, 0.4), 0.0, ah))
	boxes.append(_bx(Rect2(o.x, o.y + 10.0, 14.0, 0.4), 0.0, ah))
	boxes.append(_bx(hr, ah, City.HOME_H))                                       # the three floors above are one solid block
	City.buildings.append({"rect": hr, "boxes": boxes, "nav_rects": [hr], "style": 0.1, "color": Color(0.78, 0.6, 0.48),
		"h": City.HOME_H, "no_slab": true, "home": true})
	# linings on the inside of the outer walls, the ceiling and the floors
	_liner(Rect2(o.x, o.y, 14.0, 0.1), 0.0, ah, INTERIOR)
	_liner(Rect2(o.x, o.y + 9.9, 14.0, 0.1), 0.0, ah, INTERIOR)
	_liner(Rect2(o.x + 13.9, o.y, 0.1, 10.0), 0.0, ah, INTERIOR)
	_liner(Rect2(o.x, o.y, 0.1, door_a - o.y), 0.0, ah, INTERIOR)
	_liner(Rect2(o.x, door_b, 0.1, o.y + 10.0 - door_b), 0.0, ah, INTERIOR)
	_liner(Rect2(o.x, o.y, 14.0, 10.0), ah - 0.1, ah, Color(0.93, 0.92, 0.89))
	for piece in cut(Rect2(o, Vector2(14.0, 10.0)), [City.STAIR_HOLE]):
		City.ground_slabs.append([piece, Color(0.55, 0.4, 0.27), 2])
	City.ground_slabs.append([Rect2(o, Vector2(6.0, 3.4)), Color(0.78, 0.74, 0.66), 3])                 # kitchen tiles
	City.ground_slabs.append([Rect2(o.x, o.y + 6.6, 3.0, 3.4), Color(0.7, 0.78, 0.8), 3])               # bathroom tiles
	# partition walls (0.2 m thick, doorways 1.2 m wide, doors 2.2 m high)
	var walls: Array = []
	walls.append_array(_wall(o.y + 3.4, o.x, o.x + 6.0, 0.2, true, [[o.x + 2.0, o.x + 3.2]], ah, 2.2))                                   # kitchen | hallway
	walls.append_array(_wall(o.x + 6.0, o.y, o.y + 6.6, 0.2, false, [[o.y + 4.5, o.y + 5.7]], ah, 2.2))                                  # kitchen + hallway | living room
	walls.append_array(_wall(o.y + 6.6, o.x, o.x + 14.0, 0.2, true, [[o.x + 0.9, o.x + 2.1], [o.x + 3.2, o.x + 4.4], [o.x + 9.0, o.x + 10.2]], ah, 2.2))   # bathroom, stairs, bedroom
	walls.append_array(_wall(o.x + 3.0, o.y + 6.6, o.y + 10.0, 0.2, false, [], ah, 2.2))
	walls.append_array(_wall(o.x + 4.6, o.y + 6.6, o.y + 10.0, 0.2, false, [], ah, 2.2))
	for w in walls:
		_prop(w["rect"], w["y0"], w["y1"], PARTITION, "home")
	# furniture: the kitchen counter (cover!), sofa, table, bed, bathtub
	_prop(Rect2(o.x + 0.4, o.y + 0.15, 4.2, 0.7), 0.0, 1.0, Color(0.5, 0.5, 0.52), "home")
	_prop(Rect2(o.x + 0.15, o.y + 0.85, 0.7, 2.0), 0.0, 1.0, Color(0.5, 0.5, 0.52), "home")
	_prop(Rect2(o.x + 8.0, o.y + 0.3, 3.2, 0.9), 0.0, 0.8, Color(0.3, 0.38, 0.5), "home")
	_prop(Rect2(o.x + 9.0, o.y + 3.0, 1.6, 1.0), 0.0, 0.55, Color(0.45, 0.32, 0.2), "home")
	_prop(Rect2(o.x + 11.4, o.y + 7.1, 2.4, 2.3), 0.0, 0.6, Color(0.7, 0.35, 0.35), "home")
	_prop(Rect2(o.x + 0.2, o.y + 8.9, 2.6, 0.9), 0.0, 0.6, Color(0.9, 0.92, 0.94), "home")
	City.lights.append({"pos": Vector3(o.x + 7.0, 2.6, o.y + 5.0), "range": 14.0, "energy": 1.3, "color": Color(1.0, 0.92, 0.75)})
	# warm lights on the street side so the house reads from the avenue
	_decor(Vector3(hr.position.x - 0.05, 2.55, o.y + 5.0), Vector3(0.15, 0.25, 1.8), Color(1.0, 0.8, 0.4), true)
	for wz in [o.y + 1.8, o.y + 8.4]:
		_decor(Vector3(hr.position.x - 0.03, 1.5, wz), Vector3(0.08, 1.2, 1.8), Color(1.0, 0.85, 0.5), true)


static func _cellar() -> void:
	var cr := City.CELLAR_RECT
	var hole := City.STAIR_HOLE
	var fy := City.CELLAR_FLOOR_Y
	var cy := City.CELLAR_CEIL_Y
	# the stairs: a smooth slope to walk on, steps drawn on it
	_stairs(Vector3(hole.get_center().x, 0.0, hole.position.y), Vector3(hole.get_center().x, fy, hole.end.y), hole.size.x, CONCRETE)
	# linings: the ground is cut open here and its sides are not drawn
	_liner(Rect2(cr.position.x, cr.position.y, cr.size.x, cr.size.y), fy - 0.06, fy, Color(0.36, 0.36, 0.38))                  # floor
	_liner(Rect2(cr.position.x, cr.position.y, cr.size.x, cr.size.y), cy - 0.06, cy, Color(0.55, 0.55, 0.57))                  # ceiling
	_liner(Rect2(cr.position.x, cr.position.y, 0.06, cr.size.y), fy, cy, CONCRETE)
	_liner(Rect2(cr.end.x - 0.06, cr.position.y, 0.06, cr.size.y), fy, cy, CONCRETE)
	_liner(Rect2(cr.position.x, cr.end.y - 0.06, cr.size.x, 0.06), fy, cy, CONCRETE)
	_liner(Rect2(cr.position.x, cr.position.y, hole.position.x - cr.position.x, 0.06), fy, cy, CONCRETE)
	_liner(Rect2(hole.end.x, cr.position.y, cr.end.x - hole.end.x, 0.06), fy, cy, CONCRETE)
	_liner(Rect2(hole.position.x, hole.position.y, 0.06, hole.size.y), fy, 0.0, CONCRETE)          # the stairwell's side walls
	_liner(Rect2(hole.end.x - 0.06, hole.position.y, 0.06, hole.size.y), fy, 0.0, CONCRETE)
	# storage shelves along the walls and a few crates
	_prop(Rect2(cr.position.x + 0.1, cr.position.y + 0.6, 0.5, cr.size.y - 0.8), fy, fy + 1.9, Color(0.45, 0.32, 0.2), "cellar")
	_prop(Rect2(cr.end.x - 0.6, cr.position.y + 0.6, 0.5, cr.size.y - 0.8), fy, fy + 1.9, Color(0.45, 0.32, 0.2), "cellar")
	_prop(Rect2(cr.position.x + 0.8, cr.end.y - 0.6, cr.size.x - 1.6, 0.5), fy, fy + 1.9, Color(0.45, 0.32, 0.2), "cellar")
	_prop(Rect2(cr.position.x + 0.8, cr.position.y + 2.4, 0.7, 0.7), fy, fy + 0.7, Color(0.6, 0.5, 0.32), "cellar")
	_prop(Rect2(cr.end.x - 1.5, cr.position.y + 2.8, 0.8, 0.8), fy, fy + 0.8, Color(0.55, 0.45, 0.3), "cellar")
	City.lights.append({"pos": Vector3(cr.get_center().x, cy - 0.5, cr.get_center().y), "range": 8.0, "energy": 0.6, "color": Color(1.0, 0.9, 0.7)})


# ---------------------------------------------------------------- the park

static func park_block() -> void:
	var pr := City.PARK_RECT
	City.ground_slabs.append([pr, Color(0.2, 0.42, 0.17)])
	City.ground_slabs.append([Rect2(pr.position.x, -54.5, pr.size.x, 3.0), Color(0.6, 0.55, 0.46), 2])             # east-west path
	City.ground_slabs.append([Rect2(80.0, pr.position.y, 3.0, 44.0), Color(0.6, 0.55, 0.46), 2])                  # north-south path down to the balcony building
	_prop(Rect2(64.0, -71.0, 9.0, 6.0), 0.0, 0.1, Color(0.3, 0.6, 0.95), "main")                                # the pond (flat, water-blue)
	for bp in [Vector2(76.0, -66.0), Vector2(87.0, -66.0), Vector2(76.0, -40.0), Vector2(87.0, -40.0), Vector2(63.0, -57.0), Vector2(99.0, -43.0)]:
		_prop(Rect2(bp.x - 0.8, bp.y - 0.25, 1.6, 0.5), 0.0, 0.5, Color(0.45, 0.32, 0.2), "main")                # bench seat
		_prop(Rect2(bp.x - 0.8, bp.y + 0.2, 1.6, 0.1), 0.5, 0.95, Color(0.45, 0.32, 0.2), "")                    # bench back
	for tp in [Vector2(78, -70), Vector2(90, -70), Vector2(98, -70), Vector2(63, -63), Vector2(63, -45), Vector2(63, -37),
			Vector2(100.5, -68), Vector2(100.5, -58), Vector2(100.5, -48), Vector2(100.5, -37), Vector2(96, -38), Vector2(98.5, -35)]:
		City.trees.append({"pos": tp, "h": 7.0 + fposmod(tp.x * 0.37 + tp.y * 0.61, 4.0), "r": 0.35})
	_balcony_building()


## A 3-storey building on the south side of the park with an open balcony on the second floor (railing on the park side),
## reached by an outside stair at its west end.
static func _balcony_building() -> void:
	var fp := Rect2(62.0, -29.0, 40.0, 15.0)
	var h := 10.4
	var ledge := City.BALCONY_RECT
	var boxes: Array = _hall_boxes(fp, h)
	boxes.append(_bx(ledge, City.BALCONY_Y - 0.3, City.BALCONY_Y))
	City.buildings.append({"rect": fp, "boxes": boxes, "nav_rects": [fp], "style": 0.1, "color": Color(0.64, 0.42, 0.34), "h": h, "story": true})
	_hall_inside()
	var rail: Array = []
	var y_top := City.BALCONY_Y + 1.1
	rail.append(_bx(Rect2(ledge.position.x, ledge.position.y, ledge.size.x, 0.1), y_top - 0.1, y_top))                    # north rail, top
	rail.append(_bx(Rect2(ledge.position.x, ledge.position.y, ledge.size.x, 0.1), City.BALCONY_Y + 0.5, City.BALCONY_Y + 0.58))
	rail.append(_bx(Rect2(ledge.end.x - 0.1, ledge.position.y, 0.1, ledge.size.y), y_top - 0.1, y_top))                   # east end
	rail.append(_bx(Rect2(ledge.end.x - 0.1, ledge.position.y, 0.1, ledge.size.y), City.BALCONY_Y + 0.5, City.BALCONY_Y + 0.58))
	var n := 8
	for i in n + 1:
		var px := ledge.position.x + (ledge.size.x - 0.1) * float(i) / float(n)
		rail.append(_bx(Rect2(px, ledge.position.y, 0.1, 0.1), City.BALCONY_Y, y_top))
	rail.append(_bx(Rect2(ledge.end.x - 0.1, ledge.end.y - 0.1, 0.1, 0.1), City.BALCONY_Y, y_top))
	City.buildings.append({"rect": ledge, "boxes": rail, "nav_rects": [], "style": 0.99, "color": Color(0.2, 0.22, 0.25), "h": y_top, "no_slab": true})
	_stairs(Vector3(ledge.position.x, City.BALCONY_Y, City.BALCONY_POS.z), Vector3(66.8, 0.0, City.BALCONY_POS.z), 1.6, CONCRETE)



## Wall boxes along x (at z = line) or along z (at x = line) from a to b with openings [[from, to], ...]: each opening keeps a sill up to
## `sill` and a lintel from `head` (a door has sill 0), so shots and people pass through the gap only.
static func _pierced(line: float, a: float, b: float, t: float, along_x: bool, gaps: Array, y0: float, y1: float, sill: float, head: float) -> Array:
	var out: Array = []
	var pos := a
	for g in gaps:
		if float(g[0]) > pos + 0.01:
			out.append(_seg(line, pos, g[0], t, along_x, y0, y1))
		if sill > 0.01:
			out.append(_seg(line, g[0], g[1], t, along_x, y0, y0 + sill))
		out.append(_seg(line, g[0], g[1], t, along_x, y0 + head, y1))
		pos = g[1]
	if b > pos + 0.01:
		out.append(_seg(line, pos, b, t, along_x, y0, y1))
	return out



## The sniper's galleries inside the balcony building: two storeys of one long hall (39 x 8 m) along the park side, the lower one level with the
## balcony (a doorway from it), the upper one 3.4 m higher, joined by a stair along the south wall. The north wall has real open windows exactly where
## the facade shader paints its windows (cells of 2.8 m, 1.08 - 3.06 m above each 3.6 m storey line), so the facade looks the same from outside.
## Lower windows sit above the balcony (x 72 - 94) so nobody can step out of them.
const HALL := Rect2(62.4, -28.6, 39.2, 8.0)
const HALL_UP := 6.8
const LOW_WINDOWS := [[73.36, 75.04], [78.96, 80.64], [84.56, 86.24], [90.16, 91.84]]
const HIGH_WINDOWS := [[67.76, 69.44], [73.36, 75.04], [78.96, 80.64], [84.56, 86.24], [90.16, 91.84], [95.76, 97.44]]
const DOOR := [76.2, 78.2]
const STAIR_HOLE_HALL := Rect2(69.5, -22.6, 6.5, 2.0)


static func _north_wall() -> Array:
	var y0 := City.BALCONY_Y
	var line := -28.8
	var out: Array = []
	out.append_array(_pierced(line, 62.0, DOOR[0], 0.4, true, [LOW_WINDOWS[0]], y0, HALL_UP, 1.28, 3.26))
	out.append(_seg(line, DOOR[0], DOOR[1], 0.4, true, y0 + 2.4, HALL_UP))                       # the lintel over the doorway
	out.append_array(_pierced(line, DOOR[1], 102.0, 0.4, true, [LOW_WINDOWS[1], LOW_WINDOWS[2], LOW_WINDOWS[3]], y0, HALL_UP, 1.28, 3.26))
	out.append_array(_pierced(line, 62.0, 102.0, 0.4, true, HIGH_WINDOWS, HALL_UP, 10.4, 1.48, 3.46))
	return out


static func _hall_boxes(fp: Rect2, h: float) -> Array:
	var y0 := City.BALCONY_Y
	var boxes: Array = [_bx(fp, 0.0, y0)]                                                           # the ground storey stays solid
	boxes.append(_bx(Rect2(62.0, -20.6, 40.0, 6.6), y0, h))                                         # the south block behind the hall
	boxes.append(_bx(Rect2(62.0, -29.0, 0.4, 8.4), y0, h))                                          # west and east walls
	boxes.append(_bx(Rect2(101.6, -29.0, 0.4, 8.4), y0, h))
	boxes.append_array(_north_wall())
	for piece in cut(HALL, [STAIR_HOLE_HALL]):                                                      # the upper floor, open over the stair
		boxes.append(_bx(piece, HALL_UP - 0.2, HALL_UP))
	boxes.append(_bx(HALL, 10.26, h))                                                               # the roof over the hall
	return boxes


static func _hall_inside() -> void:
	var y0 := City.BALCONY_Y
	var top := 10.26
	_liner(Rect2(HALL.position.x, HALL.position.y, 0.06, HALL.size.y), y0, top, INTERIOR)           # west, east and south linings
	_liner(Rect2(HALL.end.x - 0.06, HALL.position.y, 0.06, HALL.size.y), y0, top, INTERIOR)
	_liner(Rect2(HALL.position.x, HALL.end.y - 0.06, HALL.size.x, 0.06), y0, top, INTERIOR)
	for b in _north_wall():                                                                         # the north lining, with the window openings
		var r: Rect2 = b["rect"]
		_liner(Rect2(r.position.x, HALL.position.y, r.size.x, 0.06), float(b["y0"]), float(b["y1"]), INTERIOR)
	_liner(HALL, y0, y0 + 0.03, Color(0.5, 0.42, 0.35))                                             # floor
	_stairs(Vector3(76.0, HALL_UP, -21.6), Vector3(69.0, y0, -21.6), 2.0, CONCRETE)
	_liner(Rect2(STAIR_HOLE_HALL.position.x, STAIR_HOLE_HALL.position.y, STAIR_HOLE_HALL.size.x, 0.06), HALL_UP - 0.2, HALL_UP, CONCRETE)
	# desks to rest a rifle on, under some of the windows
	for dx in [74.2, 85.4]:
		_prop(Rect2(dx - 1.2, -28.0, 2.4, 0.7), y0, y0 + 0.9, Color(0.5, 0.42, 0.3), "")
	for dx in [68.6, 79.8, 91.0, 96.6]:
		_prop(Rect2(dx - 1.2, -28.0, 2.4, 0.7), HALL_UP, HALL_UP + 0.9, Color(0.5, 0.42, 0.3), "")
	City.lights.append({"pos": Vector3(78.0, y0 + 2.8, -24.6), "range": 22.0, "energy": 0.8, "color": Color(1.0, 0.93, 0.78)})
	City.lights.append({"pos": Vector3(90.0, HALL_UP + 2.8, -24.6), "range": 22.0, "energy": 0.8, "color": Color(1.0, 0.93, 0.78)})
	City.lights.append({"pos": Vector3(68.0, HALL_UP + 2.8, -24.6), "range": 22.0, "energy": 0.8, "color": Color(1.0, 0.93, 0.78)})

# ---------------------------------------------------------------- Noah's neighbourhood: the alleys, the courtyard and the drainpipes

static var pipes: Array = []        # [{base (Vector3 on the wall, ground), n (Vector2 away from the wall), top}]: built by `build_pipes()` after CityClimb cleared the ladders
static var court_gates: Array = []  # the two 3 m gates of the courtyard (Vector3 centres)
const PIPE_STEEL := Color(0.3, 0.3, 0.32)


## The block south of the cross avenue below the park (City.COURT_BLOCK, 43 x 52 m): 3 m alleys (west, east and a cross alley in the south),
## a 12 x 12 m courtyard in the middle with a 3 m gate west and east, walled by low wings (the north wing's roof is 4.6 m: it overlooks
## the courtyard and has no parapet), tall and short houses round the edges and drainpipes up to the low roofs from the alleys.
## Plan: x 60..103, z 12..64. Everything here is a story building (no random damage, no random roof access, no passages in the alleys).
static func court_block() -> void:
	pipes = []
	court_gates = []
	var wall := Color(0.8, 0.7, 0.56)
	var wall2 := Color(0.72, 0.6, 0.5)
	var wall3 := Color(0.62, 0.62, 0.58)
	# the lanes and the courtyard (street entries so the roads / spawn / sound code know them; "open" = never blocked by a crouch passage)
	for lane in [Rect2(70.0, 12.0, 3.0, 52.0), Rect2(96.0, 12.0, 3.0, 52.0), Rect2(73.0, 54.0, 23.0, 3.0), Rect2(73.0, 34.5, 5.0, 3.0), Rect2(90.0, 34.5, 6.0, 3.0)]:
		City.streets.append({"rect": lane, "cls": "alley", "open": true})
	City.streets.append({"rect": City.COURT_RECT, "cls": "walk", "open": true})
	court_gates = [Vector3(75.5, 0.0, 36.0), Vector3(93.0, 0.0, 36.0)]
	# the buildings: [rect, height, colour]
	var wings: Array = [
		[Rect2(60.0, 12.0, 10.0, 52.0), 11.6, wall2],          # west block, fronts the street x = 54
		[Rect2(73.0, 12.0, 23.0, 18.0), City.COURT_ROOF_Y, wall],           # NORTH WING: the low roof over the courtyard
		[Rect2(73.0, 30.0, 5.0, 4.5), 4.6, wall3], [Rect2(73.0, 37.5, 5.0, 4.5), 4.6, wall3],          # the gate piers (west)
		[Rect2(90.0, 30.0, 6.0, 4.5), 4.6, wall3], [Rect2(90.0, 37.5, 6.0, 4.5), 4.6, wall3],          # (east)
		[Rect2(73.0, 42.0, 23.0, 12.0), 8.6, wall2],            # the south wing: the tall wall opposite the roof
		[Rect2(73.0, 57.0, 23.0, 7.0), 5.2, wall],              # low shops on the south street
		[Rect2(99.0, 12.0, 4.0, 52.0), 5.5, wall3]]             # the strip on the east street
	for w in wings:
		var fp: Rect2 = w[0]
		City.buildings.append({"rect": fp, "boxes": [_bx(fp, 0.0, float(w[1]))], "nav_rects": [fp], "style": 0.1, "color": w[2], "h": float(w[1]), "story": true})
	City.ground_slabs.append([City.COURT_RECT, Color(0.5, 0.47, 0.42), 2])                      # the paved courtyard
	_prop(Rect2(79.2, 30.8, 1.2, 1.2), 0.0, 1.0, Color(0.55, 0.42, 0.28), "main")               # two crates in the corners
	_prop(Rect2(87.6, 40.0, 1.2, 1.2), 0.0, 0.9, Color(0.5, 0.4, 0.3), "main")
	City.lights.append({"pos": Vector3(84.0, 3.4, 36.0), "range": 15.0, "energy": 0.7, "color": Color(1.0, 0.85, 0.6)})
	# the drainpipes: from the alleys to the low roofs (base on the wall, n = into the alley)
	pipes = [
		{"base": Vector3(73.0, 0.0, 20.0), "n": Vector2(-1, 0), "top": City.COURT_ROOF_Y},       # north wing, west face (the way up to the courtyard roof)
		{"base": Vector3(96.0, 0.0, 25.0), "n": Vector2(1, 0), "top": City.COURT_ROOF_Y},        # north wing, east face
		{"base": Vector3(73.0, 0.0, 60.5), "n": Vector2(-1, 0), "top": 5.2},                     # the south shops
		{"base": Vector3(99.0, 0.0, 40.0), "n": Vector2(-1, 0), "top": 5.5}]                     # the east strip


## The drainpipes as climbable things: a City.ladders entry (the player attaches, climbs at 2.5 m/s and steps onto the roof) and a pipe drawn
## with brackets. Called after CityClimb.build (which clears the ladder list).
static func build_pipes() -> void:
	for p in pipes:
		var base: Vector3 = p["base"]
		var n: Vector2 = p["n"]
		var top: float = p["top"]
		var yaw := atan2(n.x, n.y)
		var t := Vector2(-n.y, n.x)
		Scn.box(base + Vector3(n.x, 0, n.y) * 0.1 + Vector3(0, top * 0.5, 0), Vector3(0.16, top, 0.16), PIPE_STEEL, yaw)          # the pipe
		var y := 0.6
		while y < top:
			Scn.box(base + Vector3(n.x, 0, n.y) * 0.06 + Vector3(0, y, 0), Vector3(0.3, 0.08, 0.1), PIPE_STEEL.lightened(0.15), yaw)   # brackets = foot-holds
			y += 1.2
		Scn.box(base + Vector3(n.x, 0, n.y) * 0.1 + Vector3(t.x, top - 0.1, t.y) * 0.0 + Vector3(0, top - 0.05, 0), Vector3(0.24, 0.12, 0.24), PIPE_STEEL.darkened(0.2), yaw)   # the gutter at the top
		City.ladders.append({"pos": base, "n": n, "top": top, "kind": "pipe", "width": 0.5})


# ---------------------------------------------------------------- trees

## Street trees in a line along the kerbs of the wide avenues (never at junctions, doors or battle sites).
static func street_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for along_z in [true, false]:
		var lines: Array = City.AVENUE_X if along_z else City.AVENUE_Z
		var cross: Array = City.AVENUE_Z if along_z else City.AVENUE_X
		var lim := City.IN_Z if along_z else City.IN_X
		for line in lines:
			var w := City.avenue_width(line)
			if w < 18.0:
				continue
			for side in [-1.0, 1.0]:
				var t := -lim + 14.0
				while t < lim - 14.0:
					var off: float = side * (w * 0.5 - 0.8)
					var p := Vector2(line + off, t) if along_z else Vector2(t, line + off)
					var ok := true
					for cl in cross:
						if absf(t - cl) < City.avenue_width(cl) * 0.5 + 4.0:
							ok = false
					if p.distance_to(Vector2(City.INSTITUTE_EXIT.x, 245.0)) < 9.0 or p.distance_to(Vector2(City.HOME_POS.x - 4.0, City.HOME_POS.z)) < 8.0:
						ok = false
					for s in City.sites:
						var sc: Vector3 = s["center"]
						if p.distance_to(Vector2(sc.x, sc.z)) < float(s["radius"]) + 6.0:
							ok = false
					var h := rng.randf_range(8.0, 13.0)
					if ok:
						City.trees.append({"pos": p, "h": h, "r": 0.3})
					t += 18.0


## The "old block" at the end of the street, east of Noah's home in the yard: an ordinary 4-storey apartment house (14 m). CityClimb gives it a
## guaranteed fire escape on the side facing the park street (`CityStory.pick_lookout`): Noah climbs it to look out over the city.
static func _old_block() -> void:
	var fp := Rect2(37.0, -47.0, 9.5, 13.0)
	CityWar.extra_clear.append(Rect2(46.0, -48.5, 5.0, 16.0))      # the fire escape stands on the street side: no tree, car or barricade there
	City.buildings.append({"rect": fp, "boxes": [_bx(fp, 0.0, 14.0)], "nav_rects": [fp], "style": 0.1, "color": Color(0.82, 0.74, 0.6), "h": 14.0, "lookout_plot": true})
