class_name CityInteriors
## Enterable buildings (city pass, phase 3). PLAN ONLY: this class decides, from the seed, which ground-floor shops can be entered and what
## they look like inside (plain data in `City.interiors`); `Interiors` (a node) builds the geometry, colliders, light and navigation layer
## while the player is near and frees them again. Every other building stays a closed box.
##   - about FRACTION of the playable buildings, fixed by the seed, never on a street 18 m or wider, never near the hand-built places
##   - one entrance door on the widest street, one escape door on another side (the narrowest street: an alley if there is one)
##   - a hall along the long axis with 2 to 4 rooms on both sides (a doorway each, no door leaves), 3 m high, ground floor only
##   - a few props as cover (crates, tables, a shelf), one dim light
## Layout is worked out in a canonical frame (u along the long axis, v across) and mapped to the world, so it works either way round.

const FRACTION := 0.10               # share of the playable buildings that can be entered (8-12% asked for)
const MIN_GAP := 14.0                # two enterable buildings are at least this far apart
const MIN_SIDE := 7.0                # footprints under this are too small for a hall and rooms
const MAX_SIDE := 40.0
const MIN_H := 4.2
const HAND_PAD := 8.0                # no interiors this close to the hand-built places
const WALL := 0.4                    # outer wall thickness
const PART := 0.2                    # partition thickness
const HEIGHT := 3.0                  # room height
const CEIL := 0.2                    # ceiling slab
const HALL_W := 2.2                    # (2.0 in the narrow buildings)
const DOOR_W := 1.6                  # outer doors
const DOORWAY := 1.4                 # doorways inside
const NAV_MARGIN := 0.25
const AVENUE_W := 18.0               # no entrance on a street this wide (the main avenues)
const MIN_STREET := 2.9
const SOLDIER_CHANCE := 0.0          # chance that an interior holds one lone soldier (0 = none: the soldier count must not rise)

static var stats: Dictionary = {}          # why buildings were left out (for the probe)

const SIDE_N := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]       # north (-z), south (+z), west (-x), east (+x)


static func plan(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5150
	var hand: Array = []
	for hb in [City.INSTITUTE_BLOCK, City.HOME_BLOCK, City.PARK_BLOCK, City.COURT_BLOCK]:
		hand.append((hb as Rect2).grow(HAND_PAD))
	var cands: Array = []
	var playable := 0
	stats = {}
	for b in City.buildings:
		if b.get("border", false) or b.get("plug", false):
			continue
		playable += 1
		if _eligible(b, hand):
			cands.append(b)
	for i in range(cands.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = cands[i]
		cands[i] = cands[j]
		cands[j] = tmp
	var want := roundi(FRACTION * float(playable))
	var centres: Array = []
	for b in cands:
		if City.interiors.size() >= want:
			break
		var c: Vector2 = (b["rect"] as Rect2).get_center()
		var near := false
		for q in centres:
			if (q as Vector2).distance_to(c) < MIN_GAP:
				near = true
		if near:
			continue
		var p := _make(b, City.interiors.size(), rng)
		if p.is_empty():
			continue
		City.interiors.append(p)
		centres.append(c)


static func _eligible(b: Dictionary, hand: Array) -> bool:
	for k in ["access", "tunnel", "arch_damage", "special", "story", "institute", "home", "bridge", "nav_rects", "slab_holes", "no_slab", "roof_pitched", "chunk", "hole", "model"]:
		if b.has(k) and (k != "access" or bool(b[k])):
			return _no("flag " + k)
	if String(b.get("arch", "")) != "shop":
		return _no("not a shop")
	if (b["boxes"] as Array).size() != 1 or float(b["h"]) < MIN_H:
		return _no("boxes/height")
	var r: Rect2 = b["rect"]
	if minf(r.size.x, r.size.y) < MIN_SIDE:
		return _no("too small")
	if maxf(r.size.x, r.size.y) > MAX_SIDE:
		return _no("too big")
	for h in hand:
		if (h as Rect2).intersects(r):
			return _no("near hand-built")
	return true


## The plan of one building, or {} if its doors cannot be put on free street.
static func _make(b: Dictionary, iid: int, rng: RandomNumberGenerator) -> Dictionary:
	var r: Rect2 = b["rect"]
	var sides := CityBuildings.street_sides(r)            # [[street width, side], ...] widest first
	if float(sides[0][0]) >= AVENUE_W or float(sides[0][0]) < MIN_STREET:
		_no("on an avenue or no street"); return {}
	var inner := r.grow(-WALL)
	var along_x := inner.size.x >= inner.size.y
	var L := inner.size.x if along_x else inner.size.y
	var W := inner.size.y if along_x else inner.size.x
	var n_rooms := 2 if L >= 14.0 else 1
	var hall_w := HALL_W if W >= 7.6 else 2.0
	var hv0 := W * 0.5 - hall_w * 0.5
	var hv1 := hv0 + hall_w
	var room_len := L / float(n_rooms)
	# the entrance: the widest street whose door front is free; the escape: another side, the narrowest street first (an alley if there is one)
	var ent: Dictionary = {}
	var esc: Dictionary = {}
	for es in sides:
		if float(es[0]) < MIN_STREET:
			continue
		ent = _door_any(r, inner, along_x, L, W, room_len, int(es[1]))
		if ent.is_empty():
			continue
		var others: Array = []
		for os in sides:
			if int(os[1]) != int(es[1]) and float(os[0]) >= MIN_STREET:
				others.append(os)
		others.sort_custom(func(a, c): return a[0] < c[0])
		for ch in others:
			esc = _door_any(r, inner, along_x, L, W, room_len, int(ch[1]))
			if not esc.is_empty():
				break
		if not esc.is_empty():
			break
		ent = {}
	if ent.is_empty() or esc.is_empty():
		_no("no two free doors"); return {}
	# ---- walls: the shell with the two door openings, the hall walls with a doorway per room, a divider between two rooms of a strip
	var shell: Array = []
	var strips := [
		[Rect2(r.position.x, r.position.y, r.size.x, WALL), true, 0],
		[Rect2(r.position.x, r.end.y - WALL, r.size.x, WALL), true, 1],
		[Rect2(r.position.x, r.position.y + WALL, WALL, r.size.y - WALL * 2.0), false, 2],
		[Rect2(r.end.x - WALL, r.position.y + WALL, WALL, r.size.y - WALL * 2.0), false, 3],
	]
	for st in strips:
		var openings: Array = []
		for d in [ent, esc]:
			if int(d["side"]) == int(st[2]):
				var c: float = float(d["centre"].x) if bool(st[1]) else float(d["centre"].y)
				openings.append([c - DOOR_W * 0.5, c + DOOR_W * 0.5])
		shell.append_array(_cut(st[0], bool(st[1]), openings))
	var walls: Array = []
	for s in 2:
		var v_line := hv0 if s == 0 else hv1
		var openings2: Array = []
		for i in n_rooms:
			var uc := (float(i) + 0.5) * room_len
			openings2.append([uc - DOORWAY * 0.5, uc + DOORWAY * 0.5])
		var u := 0.0
		for o in openings2:
			if float(o[0]) > u + 0.05:
				walls.append(_cr(inner, along_x, u, v_line - PART * 0.5, float(o[0]) - u, PART))
			u = float(o[1])
		if L > u + 0.05:
			walls.append(_cr(inner, along_x, u, v_line - PART * 0.5, L - u, PART))
		if n_rooms == 2:
			var v0 := 0.0 if s == 0 else hv1
			var vd := hv0 if s == 0 else W - hv1
			walls.append(_cr(inner, along_x, L * 0.5 - PART * 0.5, v0, PART, vd))
	# ---- props: in the back corners of the rooms, never on the line from a door to the hall
	var props: Array = []
	for s in 2:
		for i in n_rooms:
			if room_len < 5.0:
				continue
			var u0 := float(i) * room_len
			for k in 2:
				var kind := rng.randi() % 3
				var du := 1.0 if kind == 0 else (1.6 if kind == 1 else 2.0)
				var dv := 0.9 if kind == 0 else (0.8 if kind == 1 else 0.5)
				var ph := 0.9 if kind == 0 else (0.85 if kind == 1 else 1.9)
				var pu := u0 + 0.5 if k == 0 else u0 + room_len - 0.5 - du
				var pv := 0.15 if s == 0 else W - dv - 0.15
				var col := Color(0.42, 0.3, 0.19) if kind != 2 else Color(0.34, 0.33, 0.31)
				props.append({"rect": _cr(inner, along_x, pu, pv, du, dv), "h": ph, "color": col})
	var solids: Array = []
	solids.append_array(shell)
	solids.append_array(walls)
	for p in props:
		solids.append(p["rect"])
	var cc := _cp(inner, along_x, L * 0.5, W * 0.5)
	var layers_idx := City.layers.size()
	City.layers.append({"name": "interior%d" % iid, "rect": r, "ymin": -0.6, "ymax": HEIGHT + 0.3, "y": 0.0, "parent": -1,
		"outer": ent["outer"], "via": [ent["via"]], "inner": ent["in"], "grid": {}})
	b["iid"] = iid
	return {"iid": iid, "b": b, "rect": r, "inner": inner, "shell": shell, "walls": walls, "props": props, "solids": solids,
		"light": Vector3(cc.x, 2.4, cc.y), "range": maxf(L, W) * 0.9, "slot": layers_idx, "entrance": ent, "escape": esc,
		"color": b["color"], "style": float(b["boxes"][0].get("style", b["style"])), "h": float(b["h"]), "lone": rng.randf() < SOLDIER_CHANCE}


## The door on world side `side`: its centre on the outer wall line, the outward normal, and the three link points. {} if the street
## in front of it is not free in the navigation grid.
static func _door_any(r: Rect2, inner: Rect2, along_x: bool, L: float, W: float, room_len: float, side: int) -> Dictionary:
	for ri in maxi(1, roundi(L / room_len)):
		var d := _door(r, inner, along_x, L, W, room_len, side, ri)
		if not d.is_empty():
			return d
	return {}


static func _door(r: Rect2, inner: Rect2, along_x: bool, L: float, W: float, room_len: float, side: int, ri: int = 0) -> Dictionary:
	var is_end := (side == 2 or side == 3) if along_x else (side == 0 or side == 1)
	var u := 0.0
	var v := 0.0
	if is_end:
		v = W * 0.5
		u = 0.0 if (side == 2 or side == 0) else L
	else:
		u = room_len * (float(ri) + 0.5)
		if along_x:
			v = 0.0 if side == 0 else W
		else:
			v = 0.0 if side == 2 else W
	var pin := _cp(inner, along_x, u, v)                     # on the inner face of the wall
	var n: Vector2 = SIDE_N[side]
	var wall_pt := pin + n * WALL                           # on the outer face
	var outer := wall_pt + n * 1.6
	var via := wall_pt + n * 0.5
	var inside := pin - n * 1.2
	if not City._g_free(City._main_grid, Vector3(outer.x, 0.0, outer.y)) or not City._g_free(City._main_grid, Vector3(via.x, 0.0, via.y)):
		_no("door front not free"); return {}
	return {"side": side, "centre": pin, "n": n, "wall_pt": wall_pt, "outer": Vector3(outer.x, 0.0, outer.y), "via": Vector3(via.x, 0.0, via.y),
		"in": Vector3(inside.x, 0.0, inside.y)}


## Canonical (u along the long axis, v across) -> world.
static func _cp(inner: Rect2, along_x: bool, u: float, v: float) -> Vector2:
	return Vector2(inner.position.x + u, inner.position.y + v) if along_x else Vector2(inner.position.x + v, inner.position.y + u)


static func _cr(inner: Rect2, along_x: bool, u: float, v: float, du: float, dv: float) -> Rect2:
	return Rect2(inner.position.x + u, inner.position.y + v, du, dv) if along_x else Rect2(inner.position.x + v, inner.position.y + u, dv, du)


## A wall strip cut by openings (coordinates along the strip's long axis): the pieces left over.
static func _cut(strip: Rect2, horizontal: bool, openings: Array) -> Array:
	openings.sort_custom(func(a, c): return a[0] < c[0])
	var out: Array = []
	var a0 := strip.position.x if horizontal else strip.position.y
	var a1 := strip.end.x if horizontal else strip.end.y
	var cur := a0
	for o in openings:
		if float(o[0]) > cur + 0.05:
			out.append(Rect2(cur, strip.position.y, float(o[0]) - cur, strip.size.y) if horizontal else Rect2(strip.position.x, cur, strip.size.x, float(o[0]) - cur))
		cur = maxf(cur, float(o[1]))
	if a1 > cur + 0.05:
		out.append(Rect2(cur, strip.position.y, a1 - cur, strip.size.y) if horizontal else Rect2(strip.position.x, cur, strip.size.x, a1 - cur))
	return out


static func _no(reason: String) -> bool:
	stats[reason] = int(stats.get(reason, 0)) + 1
	return false
