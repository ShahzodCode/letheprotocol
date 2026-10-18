class_name CityClimb
## Stage 3 of the war-torn city: ways to move through it. Two phases:
##   plan()  (before CityBuildings.dress) picks the pass-through buildings (a 3 m tunnel from one street to the other), the buildings
##           that get a reachable roof, the pairs of roofs joined by a bridge (their heights are made equal), and the crouch passages
##           (alleys that can only be passed crouched). Everything is plain data in City.tunnels / City.bridges / City.crouch_passages.
##   build() (after dress) turns that into boxes: ladders (City.ladders: the player climbs them), fire escapes and concrete stairs
##           (ramp colliders with step-shaped decor), parapets, solid rooftop units, bridges (open footbridges and glass walkways, some
##           broken), the crouch blockers (pipe, fallen ladder, collapsed slab, low gap) and the lit corridors.
## Heights: STAND 1.8 m, CROUCH 1.1 m; a crouch blocker's underside is at 1.35 m. A step is 0.2-0.3 m (the player steps up 0.55 m).

const STEP_RISE := 3.4
const BLOCKER_BOTTOM := 1.35         # underside of a crouch blocker: above the crouched head (1.1), below the standing head (1.8)
const ESCAPE_RUN := 5.0
const ESCAPE_LANDING := 1.6
const PARAPET_H := 0.9
const STEEL := Color(0.2, 0.22, 0.24)
const STEEL_LIGHT := Color(0.34, 0.36, 0.38)
const CONC := Color(0.62, 0.61, 0.58)

static var tunnel_count := 0
static var bridge_count := 0
static var passage_count := 0
static var escape_count := 0
static var ladder_count := 0


static func _ordinary(b: Dictionary) -> bool:
	return not (b.has("institute") or b.has("home") or b.has("story") or b.get("border", false) or b.get("plug", false) or b.get("no_slab", false)) and float(b["style"]) < 0.97 and not b.has("special")


static func _in_street(p: Vector2) -> bool:
	for st in City.streets:
		if (st["rect"] as Rect2).has_point(p):
			return true
	return false


static func _building_at(p: Vector2) -> bool:
	for b in City.buildings:
		if (b["rect"] as Rect2).has_point(p):
			return true
	return false


# ================================================================== phase 1: plan

static func plan(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 9091
	for i in City.buildings.size():
		(City.buildings[i] as Dictionary)["bid"] = i
	City.tunnels.clear()
	City.bridges.clear()
	City.crouch_passages.clear()
	City.ladders.clear()
	tunnel_count = 0
	bridge_count = 0
	passage_count = 0
	escape_count = 0
	ladder_count = 0
	_plan_tunnels(rng)
	_plan_bridges(rng)
	_plan_access(rng)
	_plan_passages(rng)


static func _shuffled(list: Array, rng: RandomNumberGenerator) -> Array:
	var a := list.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
	return a


## Buildings with a 3 m corridor through the narrow side: an entrance on one street, an exit on the other.
static func _plan_tunnels(rng: RandomNumberGenerator) -> void:
	var cands: Array = []
	for b in City.buildings:
		if not _ordinary(b) or (b["boxes"] as Array).size() != 1:
			continue
		var r: Rect2 = b["rect"]
		var h: float = b["h"]
		if h < 7.0 or h > 70.0 or minf(r.size.x, r.size.y) < 12.0 or maxf(r.size.x, r.size.y) < 15.0 or minf(r.size.x, r.size.y) > 34.0:
			continue
		cands.append(b)
	for b in _shuffled(cands, rng):
		if City.tunnels.size() >= 11:
			break
		var r: Rect2 = b["rect"]
		var runs_z := r.size.x >= r.size.y            # the corridor crosses the short side
		var span := r.size.x if runs_z else r.size.y
		var length := r.size.y if runs_z else r.size.x
		var c := rng.randf_range(4.5, span - 4.5)
		var tr := Rect2(r.position.x + c - 1.5, r.position.y, 3.0, r.size.y) if runs_z else Rect2(r.position.x, r.position.y + c - 1.5, r.size.x, 3.0)
		var end_a := Vector2(tr.get_center().x, r.position.y - 2.4) if runs_z else Vector2(r.position.x - 2.4, tr.get_center().y)
		var end_b := Vector2(tr.get_center().x, r.end.y + 2.4) if runs_z else Vector2(r.end.x + 2.4, tr.get_center().y)
		if not _in_street(end_a) or not _in_street(end_b) or _building_at(end_a) or _building_at(end_b):
			continue
		if absf(end_a.x) > City.IN_X - 8.0 or absf(end_a.y) > City.IN_Z - 8.0 or absf(end_b.x) > City.IN_X - 8.0 or absf(end_b.y) > City.IN_Z - 8.0:
			continue
		var too_close := false
		for t in City.tunnels:
			if (t["rect"] as Rect2).get_center().distance_to(tr.get_center()) < 40.0:
				too_close = true
		if too_close:
			continue
		# the entrances must be free of parked cars, trees and barricades
		var mouth_a := Rect2(end_a - Vector2(1.6, 1.6), Vector2(3.2, 3.2))
		var mouth_b := Rect2(end_b - Vector2(1.6, 1.6), Vector2(3.2, 3.2))
		if CityWar.occ != null and (CityWar.occ.hits(mouth_a) or CityWar.occ.hits(mouth_b)):
			continue
		var h: float = b["h"]
		var left := Rect2(r.position, Vector2(c - 1.5, r.size.y)) if runs_z else Rect2(r.position, Vector2(r.size.x, c - 1.5))
		var right := Rect2(Vector2(r.position.x + c + 1.5, r.position.y), Vector2(span - c - 1.5, r.size.y)) if runs_z else Rect2(Vector2(r.position.x, r.position.y + c + 1.5), Vector2(r.size.x, span - c - 1.5))
		b["boxes"] = [{"rect": left, "y0": 0.0, "y1": h}, {"rect": right, "y0": 0.0, "y1": h}, {"rect": tr, "y0": 3.4, "y1": h}]
		b["nav_rects"] = [left, right]
		b["slab_holes"] = [tr]
		b["special"] = true
		var info := {"rect": tr, "runs_z": runs_z, "length": length, "a": Vector3(end_a.x, 0.0, end_a.y), "b": Vector3(end_b.x, 0.0, end_b.y), "building": b}
		b["tunnel"] = info
		City.tunnels.append(info)
	tunnel_count = City.tunnels.size()


## Buildings whose roof can be reached, and pairs of roofs joined by a bridge. Heights of a pair are made equal.
static func _plan_bridges(rng: RandomNumberGenerator) -> void:
	var cands: Array = []
	for b in City.buildings:
		if not _ordinary(b) or (b["boxes"] as Array).size() != 1:
			continue
		var h: float = b["h"]
		var r: Rect2 = b["rect"]
		if h < 4.2 or h > 70.0 or minf(r.size.x, r.size.y) < 8.0:
			continue
		cands.append(b)
	var pairs: Array = []
	for i in cands.size():
		for j in range(i + 1, cands.size()):
			var a: Dictionary = cands[i]
			var b: Dictionary = cands[j]
			var ra: Rect2 = a["rect"]
			var rb: Rect2 = b["rect"]
			if ra.get_center().distance_to(rb.get_center()) > 60.0:
				continue
			# facing sides: along x (a left of b) or along z
			var link := _link(ra, rb)
			if link.is_empty():
				continue
			pairs.append([a, b, link])
	var used := {}
	var done := 0
	for pr in _shuffled(pairs, rng):
		if done >= 10:
			break
		var a: Dictionary = pr[0]
		var b: Dictionary = pr[1]
		if used.has(a["bid"]) or used.has(b["bid"]) or a.has("special") or b.has("special"):
			continue
		var link: Dictionary = pr[2]
		# nothing may stand between them (the gap is a street)
		var gap_rect: Rect2 = link["gap"]
		var blocked := false
		for o in City.buildings:
			if int(o["bid"]) != int(a["bid"]) and int(o["bid"]) != int(b["bid"]) and (o["rect"] as Rect2).intersects(gap_rect):
				blocked = true
				break
		if blocked:
			continue
		var min_h := minf(float(a["h"]), float(b["h"]))
		if min_h < 9.5 and maxf(float(a["h"]), float(b["h"])) >= 9.5:
			continue          # do not shave a tower down to a shop roof
		# tall pairs bridge on a storey line, low ones (shops, 4-9 m) just at the lower roof: 3 to 6 m above the street or higher
		var y := minf(floorf(min_h / STEP_RISE) * STEP_RISE, 40.8) if min_h >= 9.5 else snappedf(min_h - 0.05, 0.1)
		if y < 4.0:
			continue
		var close := false
		for br in City.bridges:
			if (br["p0"] as Vector3).distance_to(link["p0"] as Vector3) < 28.0:
				close = true
		if close:
			continue
		for bb in [a, b]:
			bb["boxes"][0]["y1"] = y
			bb["h"] = y
			bb["special"] = true
			bb["access"] = true
			bb["bridge"] = true
			used[bb["bid"]] = true
		var kind := "glass" if rng.randf() < 0.4 else "open"
		var broken := rng.randf() < 0.4
		var p0: Vector3 = link["p0"]
		var p1: Vector3 = link["p1"]
		p0.y = y
		p1.y = y
		City.bridges.append({"a": a, "b": b, "p0": p0, "p1": p1, "y": y, "kind": kind, "broken": broken, "along_x": link["along_x"], "gap": gap_rect})
		done += 1
	# make sure both kinds and a broken one exist (the first bridges are not always lucky)
	if City.bridges.size() >= 3:
		var has_glass := false
		var has_open := false
		var has_broken := false
		for br in City.bridges:
			has_glass = has_glass or br["kind"] == "glass"
			has_open = has_open or br["kind"] == "open"
			has_broken = has_broken or br["broken"]
		if not has_glass:
			City.bridges[0]["kind"] = "glass"
		if not has_open:
			City.bridges[1]["kind"] = "open"
		if not has_broken:
			City.bridges[2]["broken"] = true
		City.bridges[2]["broken"] = true
		City.bridges[1]["broken"] = false
	bridge_count = City.bridges.size()


## Do two footprints face each other across a street 3-12 m wide with at least 7 m of overlap? Returns {gap, p0, p1, along_x}.
static func _link(ra: Rect2, rb: Rect2) -> Dictionary:
	# a left of b
	for swap in [false, true]:
		var a := ra if not swap else rb
		var b := rb if not swap else ra
		var gap_x := b.position.x - a.end.x
		var oz0 := maxf(a.position.y, b.position.y)
		var oz1 := minf(a.end.y, b.end.y)
		if gap_x >= 3.0 and gap_x <= 13.0 and oz1 - oz0 >= 6.0:
			var z := (oz0 + oz1) * 0.5
			var p0 := Vector3(a.end.x - 0.6, 0.0, z)
			var p1 := Vector3(b.position.x + 0.6, 0.0, z)
			if swap:
				var t := p0
				p0 = p1
				p1 = t
			return {"gap": Rect2(a.end.x, oz0, gap_x, oz1 - oz0), "p0": p0, "p1": p1, "along_x": true}
		var gap_z := b.position.y - a.end.y
		var ox0 := maxf(a.position.x, b.position.x)
		var ox1 := minf(a.end.x, b.end.x)
		if gap_z >= 3.0 and gap_z <= 13.0 and ox1 - ox0 >= 6.0:
			var x := (ox0 + ox1) * 0.5
			var p0b := Vector3(x, 0.0, a.end.y - 0.6)
			var p1b := Vector3(x, 0.0, b.position.y + 0.6)
			if swap:
				var t2 := p0b
				p0b = p1b
				p1b = t2
			return {"gap": Rect2(ox0, a.end.y, ox1 - ox0, gap_z), "p0": p0b, "p1": p1b, "along_x": false}
	return {}


## About one building in eight gets a roof you can reach (the others keep their roof units out of reach).
static func _plan_access(rng: RandomNumberGenerator) -> void:
	CityStory.pick_lookout()
	for b in City.buildings:
		if b.has("access"):
			continue
		b["access"] = false
		if not _ordinary(b) or (b["boxes"] as Array).size() != 1:
			continue
		var h: float = b["h"]
		var r: Rect2 = b["rect"]
		if h < 4.0 or h > 42.0 or minf(r.size.x, r.size.y) < 8.0:
			continue
		if rng.randf() < 0.17:
			b["access"] = true
			b["special"] = true


## Alleys and 6 m walks that can only be passed crouched: a blocker spanning wall to wall at 1.35-2.35 m.
static func _plan_passages(rng: RandomNumberGenerator) -> void:
	var cands: Array = []
	for st in City.streets:
		var r: Rect2 = st["rect"]
		var narrow := minf(r.size.x, r.size.y)
		var long_side := maxf(r.size.x, r.size.y)
		if (narrow < 2.9 or narrow > 6.1) or long_side < 14.0 or st["cls"] == "avenue" or st["cls"] == "plaza" or st.get("open", false):
			continue
		cands.append(st)
	var kinds := ["pipe", "ladder", "slab", "gap"]
	for st in _shuffled(cands, rng):
		if City.crouch_passages.size() >= 14:
			break
		var r: Rect2 = st["rect"]
		var along_x := r.size.x > r.size.y
		var w := minf(r.size.x, r.size.y)
		var long_side := maxf(r.size.x, r.size.y)
		if absf(r.position.x) > City.IN_X - 20.0 and not along_x:
			continue
		var t := rng.randf_range(6.0, long_side - 6.0)
		var c := Vector2(r.position.x + t, r.get_center().y) if along_x else Vector2(r.get_center().x, r.position.y + t)
		# real walls on both sides (lots are inset by up to 1.2 m, so the opening can be wider than the street): measure it
		var cross := Vector2(0, 1) if along_x else Vector2(1, 0)
		var alongv := Vector2(1, 0) if along_x else Vector2(0, 1)
		var wl := 0.0
		var wr := 0.0
		for off in [-2.0, 0.0, 2.0]:
			wl = maxf(wl, _wall_dist(c + alongv * off, -cross))
			wr = maxf(wr, _wall_dist(c + alongv * off, cross))
		if wl > 4.5 or wr > 4.5 or wl + wr < 2.4:
			continue
		c += cross * (wr - wl) * 0.5
		var width := wl + wr
		var too_close := false
		for p in City.crouch_passages:
			if (p["pos"] as Vector3).distance_to(Vector3(c.x, 0.0, c.y)) < 30.0:
				too_close = true
		if too_close:
			continue
		var kind: String = kinds[rng.randi() % kinds.size()]
		if kind == "ladder" and width > 6.5:
			kind = "pipe"          # a diagonal ladder lets a standing player slide through a wide gap: only the narrow ones get it
		var depth := 4.0 if kind == "gap" else (2.4 if kind == "slab" else 1.2)
		var rect := Rect2(c.x - depth * 0.5, c.y - width * 0.5, depth, width) if along_x else Rect2(c.x - width * 0.5, c.y - depth * 0.5, width, depth)
		if CityWar.occ != null and CityWar.occ.hits(rect, -0.2):
			continue
		City.crouch_passages.append({"pos": Vector3(c.x, 0.0, c.y), "rect": rect, "along_x": along_x, "width": width, "kind": kind, "bottom": BLOCKER_BOTTOM})
	passage_count = City.crouch_passages.size()


# ================================================================== phase 2: build

static func build(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 9092
	for b in City.buildings:
		if b.has("tunnel"):
			_tunnel(b, rng)
	for b in City.buildings:
		if b["access"] if b.has("access") else false:
			_access(b, rng)
	for br in City.bridges:
		_bridge(br, rng)
	for p in City.crouch_passages:
		_passage(p, rng)
	for c in City.containers:
		_container_ladder(c, rng)
	ladder_count = City.ladders.size()


static func _roof_top(b: Dictionary) -> float:
	var top := 0.0
	for bx in b["boxes"]:
		if float(bx.get("style", 0.0)) < 0.97:
			top = maxf(top, float(bx["y1"]))
	return top


# ---------------------------------------------------------------- ladders

## A ladder up the wall of side `s` at `u` along it: rails and rungs (visual), plus the City.ladders entry the player climbs.
static func _ladder(r: Rect2, s: int, u: float, top: float, kind: String) -> void:
	var n: Vector2 = CityBuildings.SIDE_N[s]
	var base := CityBuildings.facade_pt(r, s, u, 0.0, 0.0)
	var yaw := CityBuildings.side_yaw(s)
	var t := Vector2(-n.y, n.x)
	for sd in [-1.0, 1.0]:
		var rail: Vector3 = base + Vector3(t.x, 0, t.y) * 0.3 * sd + Vector3(n.x, 0, n.y) * 0.1
		Scn.box(rail + Vector3(0, top * 0.5, 0), Vector3(0.07, top, 0.07), STEEL_LIGHT, yaw)
	var y := 0.35
	while y < top:
		Scn.box(base + Vector3(n.x, 0, n.y) * 0.1 + Vector3(0, y, 0), Vector3(0.6, 0.04, 0.05), STEEL_LIGHT, yaw)
		y += 0.32
	City.ladders.append({"pos": base, "n": n, "top": top, "kind": kind, "width": 0.7})


## Container ladders: one on each container, up its long side.
static func _container_ladder(c: Dictionary, rng: RandomNumberGenerator) -> void:
	var yaw: float = c["yaw"]
	var basis := Basis(Vector3.UP, yaw)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var n3 := basis * Vector3(side, 0.0, 0.0)
	var pos: Vector3 = c["pos"]
	var base := pos + n3 * 1.2 + basis * Vector3(0.0, 0.0, rng.randf_range(-1.6, 1.6))
	var n := Vector2(n3.x, n3.z)
	var t := Vector2(-n.y, n.x)
	var top: float = c["top"]
	for sd in [-1.0, 1.0]:
		Scn.box(base + Vector3(t.x, 0, t.y) * 0.3 * sd + Vector3(n.x, 0, n.y) * 0.1 + Vector3(0, top * 0.5, 0), Vector3(0.07, top, 0.07), STEEL_LIGHT, yaw)
	var y := 0.35
	while y < top:
		Scn.box(base + Vector3(n.x, 0, n.y) * 0.1 + Vector3(0, y, 0), Vector3(0.6, 0.04, 0.05), STEEL_LIGHT, yaw + PI * 0.5)
		y += 0.32
	City.ladders.append({"pos": base, "n": n, "top": top, "kind": "container", "width": 0.7})


# ---------------------------------------------------------------- reachable roofs

## An access roof: a way up (fire escape / concrete stairs / ladder), a parapet with gaps, rooftop units with colliders.
static func _access(b: Dictionary, rng: RandomNumberGenerator) -> void:
	var r: Rect2 = b["rect"]
	var top := _roof_top(b)
	if top < 3.5:
		return
	var gaps: Array = []        # [side, u, width]
	var sides := CityBuildings.street_sides(r)
	var did := false
	# a stair for the low roofs and a fire escape for the tall ones, if there is room beside a wide enough street
	if b.has("lookout") or rng.randf() < 0.7 or top <= 8.5:
		for sd in sides:
			var s: int = sd[1]
			var len := CityBuildings._side_len(r, s)
			if float(sd[0]) < 8.0 or len < 10.5:
				continue
			for attempt in (16 if b.has("lookout") else 1):         # the lookout's way up is guaranteed: try several places along the wall
				var u0 := rng.randf_range(ESCAPE_LANDING + 0.6, len - ESCAPE_RUN - ESCAPE_LANDING - 0.6)
				var foot := _escape_footprint(r, s, u0)
				if CityWar.occ != null and CityWar.occ.hits(foot, 0.3):
					continue
				if _building_at_rect(foot, b):
					continue
				_fire_escape(b, s, u0, top, top <= 8.5, gaps)
				CityWar.occ.add(foot)
				did = true
				break
			if did:
				break
	if not did:
		for sd in sides:
			var s2: int = sd[1]
			var len2 := CityBuildings._side_len(r, s2)
			for tries in 6:
				var u := rng.randf_range(2.0, len2 - 2.0)
				var base := CityBuildings.facade_pt(r, s2, u, 0.0, 1.0)
				var foot2 := Rect2(Vector2(base.x, base.z) - Vector2(0.9, 0.9), Vector2(1.8, 1.8))
				if CityWar.occ != null and CityWar.occ.hits(foot2):
					continue
				_ladder(r, s2, u, top, "wall")
				if b.has("lookout"):
					CityStory.lookout = {"building": b, "side": s2, "kind": "ladder", "top": top, "foot": CityBuildings.facade_pt(r, s2, u, 0.0, 0.9), "roof": CityBuildings.facade_pt(r, s2, u, top, -1.6)}
				gaps.append([s2, u, 1.8])
				did = true
				break
			if did:
				break
	# bridges end on this roof: a gap in the parapet where they land
	for br in City.bridges:
		for end in ["a", "b"]:
			if int(br[end]["bid"]) == int(b["bid"]):
				var p: Vector3 = br["p0"] if end == "a" else br["p1"]
				for s3 in 4:
					var along_x: bool = br["along_x"]
					var want := (s3 >= 2) if along_x else (s3 < 2)
					if not want:
						continue
					# the side of this building that faces the other one
					var other: Dictionary = br["b"] if end == "a" else br["a"]
					var oc: Vector2 = (other["rect"] as Rect2).get_center()
					var mc := r.get_center()
					var n3: Vector2 = CityBuildings.SIDE_N[s3]
					if (oc - mc).dot(n3) > 0.0:
						var u_b := (p.z - r.position.y) if along_x else (p.x - r.position.x)
						gaps.append([s3, u_b, 3.2])
	_parapet(b, top, gaps)
	# roof furniture with colliders: AC units, a tank, a bulkhead with a door to nowhere
	var holder := b
	CityBuildings._roof_units(holder, rng, top, true)


static func _building_at_rect(rect: Rect2, except: Dictionary) -> bool:
	for o in City.buildings:
		if int(o["bid"]) != int(except["bid"]) and (o["rect"] as Rect2).intersects(rect):
			return true
	return false


static func _escape_footprint(r: Rect2, s: int, u0: float) -> Rect2:
	return CityBuildings.loc_rect(r, s, u0 - ESCAPE_LANDING, u0 + ESCAPE_RUN + ESCAPE_LANDING, -3.0, 0.0)


## A world point from facade coordinates: u along the wall, y up, out in front of the wall (negative = over the roof).
static func _fp(r: Rect2, s: int, u: float, y: float, out: float) -> Vector3:
	return CityBuildings.facade_pt(r, s, u, y, out)


static func _fire_escape(b: Dictionary, s: int, u0: float, top: float, concrete: bool, gaps: Array) -> void:
	var r: Rect2 = b["rect"]
	var n_fl := int(ceilf(top / STEP_RISE))
	var rise := top / float(n_fl)
	var w := 1.2 if concrete else 1.1
	var inner := 0.4 + w * 0.5            # distance of the inner lane's centre from the wall
	var outer := inner + w + 0.1          # and of the outer lane's
	var plat_out0 := 0.3                  # a landing spans both lanes: from 0.3 m off the wall...
	var plat_w := outer + w * 0.5 + 0.1 - plat_out0       # ...to just past the outer lane
	var plat_c := plat_out0 + plat_w * 0.5
	var col := CONC if concrete else STEEL
	var col2 := CONC.lightened(0.1) if concrete else STEEL_LIGHT
	for i in n_fl:
		var y0 := rise * float(i)
		var y1 := rise * float(i + 1)
		var up_plus := i % 2 == 0           # even flights climb towards +u in the inner lane, odd ones come back in the outer lane
		var lane := inner if up_plus else outer
		var ua := u0 if up_plus else u0 + ESCAPE_RUN
		var ub := u0 + ESCAPE_RUN if up_plus else u0
		# the walkable ramp (a = top, b = bottom) with steps drawn on it (0.28 m each)
		CityPlaces._stairs(_fp(r, s, ub, y1, lane), _fp(r, s, ua, y0, lane), w, col2 if up_plus else col)
		# the landing at the top of the flight: solid, with a railing on its outer edge
		var pu0 := u0 + ESCAPE_RUN if up_plus else u0 - ESCAPE_LANDING
		var pu1 := u0 + ESCAPE_RUN + ESCAPE_LANDING if up_plus else u0
		var pc := _fp(r, s, (pu0 + pu1) * 0.5, y1 - 0.06, plat_c)
		var plat_size := Vector3(pu1 - pu0, 0.12, plat_w) if s < 2 else Vector3(plat_w, 0.12, pu1 - pu0)
		Scn.box(pc, plat_size, col)
		Scn.solid(pc, plat_size)
		var rail_c := _fp(r, s, (pu0 + pu1) * 0.5, y1 + 0.5, plat_out0 + plat_w - 0.04)
		var rail_size := Vector3(pu1 - pu0, 0.9, 0.06) if s < 2 else Vector3(0.06, 0.9, pu1 - pu0)
		Scn.box(rail_c, rail_size, STEEL)
		Scn.solid(rail_c, rail_size)
		# a rail along the flight (visual only: you can step off the side of a flight and fall)
		var ra := _fp(r, s, ua, y0 + 0.95, lane + w * 0.5 - 0.05)
		var rb := _fp(r, s, ub, y1 + 0.95, lane + w * 0.5 - 0.05)
		Scn.between("cyl", ra, rb, 0.05, STEEL)
		for k in 4:
			var tpos := ra.lerp(rb, float(k) / 3.0)
			Scn.between("cyl", Vector3(tpos.x, tpos.y - 0.9, tpos.z), tpos, 0.04, STEEL)
	# the last landing is flush with the roof; a short deck carries it over the roof edge (the parapet is open here)
	var last_up := (n_fl - 1) % 2 == 0
	var lu := u0 + ESCAPE_RUN + ESCAPE_LANDING * 0.5 if last_up else u0 - ESCAPE_LANDING * 0.5
	var deck_c := _fp(r, s, lu, top + 0.06, -0.25)
	var deck_size := Vector3(ESCAPE_LANDING, 0.12, 1.4) if s < 2 else Vector3(1.4, 0.12, ESCAPE_LANDING)
	Scn.box(deck_c, deck_size, col)
	Scn.solid(deck_c, deck_size)
	gaps.append([s, lu, ESCAPE_LANDING + 0.6])
	# the stack blocks the street cells under it for the soldiers
	Scn.block(_escape_footprint(r, s, u0), 0.2)
	City.escapes.append({"rect": _escape_footprint(r, s, u0), "side": s, "top": top, "start": _fp(r, s, u0, 0.0, inner)})
	if b.has("lookout"):
		CityStory.lookout = {"building": b, "side": s, "kind": "escape", "top": top, "foot": _fp(r, s, u0, 0.0, inner), "roof": _fp(r, s, lu, top, -1.6)}
	escape_count += 1


## A low parapet (0.9 m, 0.25 m thick) round the roof edge with gaps; nothing else keeps you from falling off.
static func _parapet(b: Dictionary, top: float, gaps: Array) -> void:
	var boxes: Array = b["boxes"]
	var rect: Rect2 = boxes[0]["rect"]
	var best := -1.0
	for bx in boxes:
		if float(bx.get("style", 0.0)) < 0.97 and float(bx["y1"]) > best:
			best = float(bx["y1"])
			rect = bx["rect"]
	var col := (b["color"] as Color).darkened(0.1)
	for s in 4:
		var len := CityBuildings._side_len(rect, s)
		var cuts: Array = []        # [u0, u1]
		for g in gaps:
			if int(g[0]) == s:
				cuts.append([float(g[1]) - float(g[2]) * 0.5, float(g[1]) + float(g[2]) * 0.5])
		cuts.sort_custom(func(a, c): return a[0] < c[0])
		var pos := 0.0
		for cut in cuts:
			if float(cut[0]) > pos + 0.05:
				_parapet_piece(rect, s, pos, float(cut[0]), top, col)
			pos = maxf(pos, float(cut[1]))
		if len > pos + 0.05:
			_parapet_piece(rect, s, pos, len, top, col)


static func _parapet_piece(rect: Rect2, s: int, u0: float, u1: float, top: float, col: Color) -> void:
	var pr := CityBuildings.loc_rect(rect, s, u0, u1, 0.0, 0.25)
	var c := Vector3(pr.get_center().x, top + PARAPET_H * 0.5, pr.get_center().y)
	var size := Vector3(pr.size.x, PARAPET_H, pr.size.y)
	Scn.box(c, size, col)
	Scn.solid(c, size)


# ---------------------------------------------------------------- bridges

static func _bridge(br: Dictionary, rng: RandomNumberGenerator) -> void:
	var p0: Vector3 = br["p0"]
	var p1: Vector3 = br["p1"]
	var y: float = br["y"]
	var along_x: bool = br["along_x"]
	var kind: String = br["kind"]
	var broken: bool = br["broken"]
	var dir := (p1 - p0)
	var length := dir.length()
	var d := dir / length
	var yaw := atan2(d.x, d.z)
	var mid := (p0 + p1) * 0.5
	var width := 2.4
	var deck_y := y + 0.05
	var gap_len := 2.0 if broken else 0.0
	var gap_t := rng.randf_range(0.35, 0.65)           # where along the span the break is
	var segs: Array = []        # [t0, t1] in metres along the span from p0
	if broken:
		var gs := length * gap_t - gap_len * 0.5
		segs = [[0.0, gs], [gs + gap_len, length]]
	else:
		segs = [[0.0, length]]
	for sg in segs:
		var a: float = sg[0]
		var c: float = sg[1]
		var seg_len := c - a
		if seg_len < 0.3:
			continue
		var centre := p0 + d * (a + seg_len * 0.5)
		var deck := Vector3(centre.x, deck_y - 0.1, centre.z)
		Scn.box(deck, Vector3(width, 0.2, seg_len), STEEL_LIGHT if kind == "open" else CONC, yaw)
		Scn.solid(deck, Vector3(width, 0.2, seg_len), yaw)
		# side rails: solid, 0.95 m (a jump clears them)
		for sd in [-1.0, 1.0]:
			var off := Basis(Vector3.UP, yaw) * Vector3(sd * (width * 0.5 - 0.05), 0.0, 0.0)
			var rc := Vector3(centre.x + off.x, deck_y + 0.475, centre.z + off.z)
			if kind == "open":
				Scn.box(rc + Vector3(0, 0.42, 0), Vector3(0.08, 0.08, seg_len), STEEL, yaw)
				Scn.box(rc, Vector3(0.05, 0.05, seg_len), STEEL, yaw)
				var posts := int(floorf(seg_len / 1.5)) + 1
				for k in posts:
					var pp := p0 + d * (a + (seg_len * float(k) / float(maxi(1, posts - 1))))
					Scn.box(Vector3(pp.x + off.x, deck_y + 0.45, pp.z + off.z), Vector3(0.06, 0.9, 0.06), STEEL, yaw)
				Scn.solid(rc, Vector3(0.1, 0.95, seg_len), yaw)
			else:
				# glass walkway: frame posts, a glass wall, solid
				Scn.part("glass", Scn.box_xf(Vector3(centre.x + off.x, deck_y + 1.2, centre.z + off.z), Vector3(0.05, 2.3, seg_len), yaw), Color(0.55, 0.78, 0.85, 0.35))
				var posts2 := int(floorf(seg_len / 2.0)) + 1
				for k in posts2:
					var pp2 := p0 + d * (a + (seg_len * float(k) / float(maxi(1, posts2 - 1))))
					Scn.box(Vector3(pp2.x + off.x, deck_y + 1.2, pp2.z + off.z), Vector3(0.1, 2.4, 0.1), STEEL, yaw)
				Scn.solid(Vector3(centre.x + off.x, deck_y + 1.2, centre.z + off.z), Vector3(0.1, 2.4, seg_len), yaw)
		if kind == "glass":
			var roof_c := Vector3(centre.x, deck_y + 2.45, centre.z)
			Scn.box(roof_c, Vector3(width + 0.2, 0.12, seg_len), STEEL, yaw)
			Scn.solid(roof_c, Vector3(width + 0.2, 0.12, seg_len), yaw)
		else:
			# a truss under the deck: two diagonals and a bottom chord
			var t0 := p0 + d * a
			var t1 := p0 + d * c
			var tm := (t0 + t1) * 0.5
			Scn.between("cyl", Vector3(t0.x, deck_y - 0.2, t0.z), Vector3(tm.x, deck_y - 1.3, tm.z), 0.1, STEEL)
			Scn.between("cyl", Vector3(t1.x, deck_y - 0.2, t1.z), Vector3(tm.x, deck_y - 1.3, tm.z), 0.1, STEEL)
	if broken:
		# bent beams hanging off the broken ends and rubble in the street far below
		for sd in [-1.0, 1.0]:
			var tb: Vector3 = p0 + d * (length * gap_t + sd * (gap_len * 0.5))
			Scn.box(Vector3(tb.x, deck_y - 0.7, tb.z), Vector3(0.2, 0.2, 1.8), STEEL.darkened(0.2), yaw, Basis(Vector3.RIGHT, 0.7 * sd))
		var g_c := p0 + d * (length * gap_t)
		Scn.box(Vector3(g_c.x + 0.4, 0.5, g_c.z), Vector3(2.0, 0.3, 1.0), Color(0.3, 0.3, 0.3), yaw + 0.5)
	br["length"] = length
	br["gap_t"] = gap_t if broken else -1.0


# ---------------------------------------------------------------- crouch passages

## A blocker from wall to wall with its underside at 1.35 m: pipe, fallen ladder, collapsed slab or a low gap under fallen floors.
static func _passage(p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector3 = p["pos"]
	var w: float = p["width"]
	var along_x: bool = p["along_x"]
	var kind: String = p["kind"]
	# the span runs across the alley: along z if the alley runs along x
	var span_dir := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
	var bottom := BLOCKER_BOTTOM
	match kind:
		"pipe":
			var a := c - span_dir * (w * 0.5 + 0.4) + Vector3(0, bottom + 0.5, 0)
			var b := c + span_dir * (w * 0.5 + 0.4) + Vector3(0, bottom + 0.5, 0)
			Scn.between("cyl", a, b, 1.0, Color(0.36, 0.38, 0.4))
			for k in 3:
				var q := c + span_dir * (-w * 0.5 + (w * float(k) / 2.0)) + Vector3(0, bottom + 0.5, 0)
				Scn.between("cyl", q + Vector3(0, -0.6, 0), q + Vector3(0, 0.1, 0), 0.12, STEEL)
			Scn.solid(c + Vector3(0, bottom + 0.5, 0), Vector3(1.0, 1.0, w + 0.4) if along_x else Vector3(w + 0.4, 1.0, 1.0))
		"ladder":
			# a fallen metal ladder lying diagonally across the alley, resting on both walls
			var ang := 0.7 * (1.0 if rng.randf() < 0.5 else -1.0)
			var dir := (span_dir * cos(ang) + (Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)) * sin(ang)).normalized()
			var len := w / absf(cos(ang)) + 0.8
			var a2 := c - dir * (len * 0.5) + Vector3(0, bottom + 0.25, 0)
			var b2 := c + dir * (len * 0.5) + Vector3(0, bottom + 0.25, 0)
			var perp := Vector3(-dir.z, 0, dir.x)
			for sd in [-1.0, 1.0]:
				Scn.between("cyl", a2 + perp * 0.4 * sd, b2 + perp * 0.4 * sd, 0.1, STEEL_LIGHT)
			var rungs := int(len / 0.35)
			for k in rungs:
				var q2 := a2.lerp(b2, (float(k) + 0.5) / float(rungs))
				Scn.box(q2, Vector3(0.82, 0.06, 0.06), STEEL_LIGHT, atan2(perp.x, perp.z))
			Scn.solid_xf(Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), (a2 + b2) * 0.5 + Vector3(0, 0.05, 0)), Vector3(1.0, 0.5, len))
		"slab":
			# a collapsed concrete slab resting on rubble against both walls
			var col := Color(0.55, 0.54, 0.52)
			var size := Vector3(2.4, 0.4, w + 0.5) if along_x else Vector3(w + 0.5, 0.4, 2.4)
			var centre := c + Vector3(0, bottom + 0.2, 0)
			Scn.box(centre, size, col)
			Scn.solid(centre, size)
			for k in 5:
				var q3 := c + span_dir * rng.randf_range(-w * 0.45, w * 0.45) + Vector3(rng.randf_range(-0.6, 0.6) * (0.0 if along_x else 1.0), 0, rng.randf_range(-0.6, 0.6) * (1.0 if along_x else 0.0))
				Scn.box(Vector3(q3.x, 0.4, q3.z), Vector3(0.7, 0.8, 0.6), Color(0.45, 0.44, 0.42), rng.randf() * TAU, Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4)))
			Scn.between("cyl", centre + Vector3(0, 0.2, 0), centre + Vector3(0.3, -0.6, 0.3), 0.05, Color(0.3, 0.2, 0.15))
		_:
			# a low gap under partly collapsed floors: a slab of masonry bridging the alley, 4 m deep
			var size2 := Vector3(4.0, 2.6, w + 0.5) if along_x else Vector3(w + 0.5, 2.6, 4.0)
			var centre2 := c + Vector3(0, bottom + 1.3, 0)
			Scn.box(centre2, size2, Color(0.5, 0.48, 0.45))
			Scn.solid(centre2, size2)
			for k in 4:
				var q4 := c + span_dir * rng.randf_range(-w * 0.4, w * 0.4)
				Scn.between("cyl", Vector3(q4.x, bottom + 0.2, q4.z) , Vector3(q4.x + rng.randf_range(-0.3, 0.3), bottom - 0.5, q4.z + rng.randf_range(-0.3, 0.3)), 0.05, Color(0.3, 0.2, 0.15))
			# rubble heaped at one end
			Scn.box(c + Vector3(0, 0.3, 0) + (Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)) * 2.4, Vector3(1.4, 0.6, w * 0.8) if along_x else Vector3(w * 0.8, 0.6, 1.4), Color(0.4, 0.39, 0.37), rng.randf() * 0.4)
	# enemies cannot path through it
	Scn.block(Rect2((p["rect"] as Rect2).position - Vector2(0.1, 0.1), (p["rect"] as Rect2).size + Vector2(0.2, 0.2)), 0.35)


# ---------------------------------------------------------------- pass-through corridors

## The inside of a pass-through building: dark floor and walls, a lit ceiling strip, crates, a broken door, one cheap light.
static func _tunnel(b: Dictionary, rng: RandomNumberGenerator) -> void:
	var info: Dictionary = b["tunnel"]
	var tr: Rect2 = info["rect"]
	var runs_z: bool = info["runs_z"]
	var r: Rect2 = b["rect"]
	var wall := Color(0.34, 0.33, 0.32)
	var h := 3.4
	# floor
	City.ground_slabs.append([tr, Color(0.22, 0.22, 0.23), 2])
	# wall liners (the shader would paint windows on the cut faces)
	if runs_z:
		for sd in [0, 1]:
			var x := tr.position.x + 0.03 if sd == 0 else tr.end.x - 0.03
			Scn.box(Vector3(x, h * 0.5, tr.get_center().y), Vector3(0.06, h, tr.size.y), wall)
		Scn.part("glow", Scn.box_xf(Vector3(tr.get_center().x, h - 0.08, tr.get_center().y), Vector3(0.3, 0.05, tr.size.y - 1.0), 0.0), Color(1.0, 0.95, 0.8))
	else:
		for sd in [0, 1]:
			var z := tr.position.y + 0.03 if sd == 0 else tr.end.y - 0.03
			Scn.box(Vector3(tr.get_center().x, h * 0.5, z), Vector3(tr.size.x, h, 0.06), wall)
		Scn.part("glow", Scn.box_xf(Vector3(tr.get_center().x, h - 0.08, tr.get_center().y), Vector3(tr.size.x - 1.0, 0.05, 0.3), 0.0), Color(1.0, 0.95, 0.8))
	# a few boxes and a broken door leaning on the wall
	var along := tr.size.y if runs_z else tr.size.x
	for k in 3:
		var t := rng.randf_range(-along * 0.35, along * 0.35)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var cp := Vector2(tr.get_center().x + side * 1.0, tr.get_center().y + t) if runs_z else Vector2(tr.get_center().x + t, tr.get_center().y + side * 1.0)
		var sz := Vector3(0.8, rng.randf_range(0.5, 1.0), 0.8)
		Scn.box(Vector3(cp.x, sz.y * 0.5, cp.y), sz, Color(0.45, 0.33, 0.2), rng.randf() * TAU)
		Scn.solid(Vector3(cp.x, sz.y * 0.5, cp.y), sz, 0.0)
		Scn.block(Rect2(cp - Vector2(0.45, 0.45), Vector2(0.9, 0.9)), 0.0)
	var door_t := along * 0.5 - 1.2
	var dcp := Vector2(tr.get_center().x - 1.25, tr.get_center().y - door_t) if runs_z else Vector2(tr.get_center().x - door_t, tr.get_center().y - 1.25)
	Scn.box(Vector3(dcp.x, 1.0, dcp.y), Vector3(0.05, 2.0, 0.9) if runs_z else Vector3(0.9, 2.0, 0.05), Color(0.55, 0.5, 0.42), 0.0, Basis(Vector3(0, 0, 1) if runs_z else Vector3(1, 0, 0), 0.3))
	# lit by one cheap light (a pool of two moves to the nearest corridor)
	Scn.fire("tunnel", Vector3(tr.get_center().x, h - 0.4, tr.get_center().y), 1.0)


## Distance from `p` along `dir` to the first building wall (99 if none within 5 m).
static func _wall_dist(p: Vector2, dir: Vector2) -> float:
	for k in 51:
		if _building_at(p + dir * (float(k) * 0.1)):
			return float(k) * 0.1
	return 99.0
