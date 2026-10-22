class_name CityLinks
## Turns the island-like back streets into a network (docs/stealth-layout-plan.md, step 2). The generator cuts every block with
## guillotine cuts, so the alleys of a block form a tree whose only exits are the wide streets round it. After all lots exist this pass
## cuts 3 m passages THROUGH single lots, each from one street to the street on the opposite side of the lot:
##   merge   both ends are narrow streets of different pockets: the pockets become one;
##   cross   one end is a 12 m street and the passage is lined up with an alley mouth on the far side of that street, so the way over is a
##           straight dash instead of a walk along the street;
##   exit    one end is a 12 m street and the pocket it leads into has fewer than MIN_EXITS exits;
##   split   a lot with no street at all on a block (both ends wide, 30 m or more across) gets a passage so the block has an inside.
## It uses its own random stream (seed + 7777) and never touches the generator's, so the rest of the city is generated as before; the new
## halves of a cut lot are made by City._make_lot like every lot. Narrow = streets up to NARROW_MAX wide, wide = WIDE_MIN and more.

const NARROW_MAX := 8.5
const WIDE_MIN := 9.5
const AVENUE_MIN := 18.0            # no passage opens onto a street this wide (avenues are where the soldiers are)
const PASSAGE := 3.0
const HALF_MIN := 6.0               # each half of a cut lot is at least this deep
const MIN_EXITS := 3
const CAPS := {"merge": 30, "cross": 60, "pair": 40, "exit": 24, "split": 12, "loop": 14}

static var done: Dictionary = {}    # type -> count of passages cut in the last run (for the audit / tests)


static func width_of(r: Rect2) -> float:
	return minf(r.size.x, r.size.y)


## The narrowest street rectangle containing `p`, or -1.
static func _street_at(p: Vector2) -> int:
	var best := -1
	var bw := 1.0e9
	for i in City.streets.size():
		var r: Rect2 = City.streets[i]["rect"]
		if r.has_point(p):
			var w := width_of(r)
			if w < bw:
				bw = w
				best = i
	return best


## Union-find over the narrow street rectangles that touch, and the exit count of every pocket (a narrow rectangle touching a wide one).
static func _graph() -> Dictionary:
	var n := City.streets.size()
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	var narrow: Array = []
	var wide: Array = []
	for i in n:
		var w := width_of(City.streets[i]["rect"])
		if w <= NARROW_MAX:
			narrow.append(i)
		elif w >= WIDE_MIN:
			wide.append(i)
	for ai in narrow.size():
		var a: int = narrow[ai]
		var ra: Rect2 = (City.streets[a]["rect"] as Rect2).grow(0.3)
		for bi in range(ai + 1, narrow.size()):
			var b: int = narrow[bi]
			if _contact(ra, (City.streets[b]["rect"] as Rect2).grow(0.3)):
				var pa := _find(parent, a)
				var pb := _find(parent, b)
				if pa != pb:
					parent[pa] = pb
	var exits: Dictionary = {}
	for a in narrow:
		var ra2: Rect2 = (City.streets[a]["rect"] as Rect2).grow(0.3)
		for b in wide:
			if _contact(ra2, (City.streets[b]["rect"] as Rect2).grow(0.3)):
				var root := _find(parent, a)
				exits[root] = int(exits.get(root, 0)) + 1
	# pockets lined up across a wide street (a straight dash over it) form one group
	var group := parent.duplicate()
	for wi in wide:
		var wr: Rect2 = City.streets[wi]["rect"]
		for vertical in [true, false]:
			if (wr.size.y > wr.size.x) != vertical:
				continue
			var before: Array = []
			var after: Array = []
			for a in narrow:
				var sr: Rect2 = City.streets[a]["rect"]
				if vertical and sr.size.x > sr.size.y:
					if absf(sr.end.x - wr.position.x) < 0.8 and sr.end.y > wr.position.y and sr.position.y < wr.end.y:
						before.append(a)
					elif absf(sr.position.x - wr.end.x) < 0.8 and sr.end.y > wr.position.y and sr.position.y < wr.end.y:
						after.append(a)
				elif not vertical and sr.size.y > sr.size.x:
					if absf(sr.end.y - wr.position.y) < 0.8 and sr.end.x > wr.position.x and sr.position.x < wr.end.x:
						before.append(a)
					elif absf(sr.position.y - wr.end.y) < 0.8 and sr.end.x > wr.position.x and sr.position.x < wr.end.x:
						after.append(a)
			for a in before:
				var ra3: Rect2 = City.streets[a]["rect"]
				for b in after:
					var rb3: Rect2 = City.streets[b]["rect"]
					var overlap := minf(ra3.end.y, rb3.end.y) - maxf(ra3.position.y, rb3.position.y) if vertical else minf(ra3.end.x, rb3.end.x) - maxf(ra3.position.x, rb3.position.x)
					if overlap >= 2.0:
						var ga := _find(group, a)
						var gb := _find(group, b)
						if ga != gb:
							group[ga] = gb
	return {"parent": parent, "group": group, "exits": exits}


static func _contact(a: Rect2, b: Rect2) -> bool:
	var i := a.intersection(b)
	return i.size.x > 0.0 and i.size.y > 0.0 and maxf(i.size.x, i.size.y) >= 2.0


static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


## One pass over every lot, in random order. Returns the number of passages cut.
static func link(seed_value: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7777
	done = {"merge": 0, "cross": 0, "pair": 0, "exit": 0, "split": 0, "loop": 0}
	var graph := _graph()
	for sweep in 2:
		var order: Array = City.lots.duplicate()
		for i in range(order.size() - 1, 0, -1):          # Fisher-Yates with our own stream
			var j := rng.randi() % (i + 1)
			var tmp = order[i]
			order[i] = order[j]
			order[j] = tmp
		for lot in order:
			if lot.has("dead"):
				continue                                 # cut earlier in this pass
			var cut := _best_cut(lot["r"], rng, graph)
			if cut.is_empty():
				continue
			var far_lot: Dictionary = {}
			if cut["type"] == "pair":
				far_lot = _mirror_target(bool(cut["along_x"]), int(cut["wide_idx"]), int(cut["wide_end"]), float(cut["t"])).get("lot", {})
			_apply(lot, cut, rng)
			if not far_lot.is_empty():
				_apply(far_lot, {"along_x": cut["along_x"], "t": cut["t"], "type": "cross"}, rng)       # the same passage on the far side: a straight way across
			graph = _graph()
	var total := 0
	for k in done:
		total += int(done[k])
	return total


## The best passage through lot rectangle `r` ({axis, z0, type}), or {} if none is worth it.
static func _best_cut(r: Rect2, rng: RandomNumberGenerator, graph: Dictionary) -> Dictionary:
	var best := {}
	var best_score := 0.0
	for along_x in [true, false]:
		var ext_len: float = r.size.x if along_x else r.size.y         # how long the passage is
		var front: float = r.size.y if along_x else r.size.x           # the frontage it is cut across
		if front < PASSAGE + HALF_MIN * 2.0 or ext_len > 64.0:
			continue
		var f0: float = r.position.y if along_x else r.position.x      # frontage start
		var options: Array = _aligned_options(r, along_x)
		for k in 3:
			options.append({"t": rng.randf_range(f0 + HALF_MIN, f0 + front - HALF_MIN - PASSAGE), "aligned": false})
		for o in options:
			var t: float = clampf(o["t"], f0 + HALF_MIN, f0 + front - HALF_MIN - PASSAGE)
			var mid := t + PASSAGE * 0.5
			var p1 := Vector2(r.position.x - 1.0, mid) if along_x else Vector2(mid, r.position.y - 1.0)
			var p2 := Vector2(r.end.x + 1.0, mid) if along_x else Vector2(mid, r.end.y + 1.0)
			var s1 := _street_at(p1)
			var s2 := _street_at(p2)
			if s1 < 0 or s2 < 0 or s1 == s2:
				continue
			var w1 := width_of(City.streets[s1]["rect"])
			var w2 := width_of(City.streets[s2]["rect"])
			var aven := w1 >= AVENUE_MIN or w2 >= AVENUE_MIN
			var type := ""
			var score := 0.0
			var n1 := w1 <= NARROW_MAX
			var n2 := w2 <= NARROW_MAX
			var parent: PackedInt32Array = graph["parent"]
			var exits: Dictionary = graph["exits"]
			var wide_idx := -1
			var wide_end := 0
			if n1 and n2:
				if _find(parent, s1) != _find(parent, s2):
					type = "merge"
					score = 3.0
				elif ext_len <= 30.0:
					type = "loop"
					score = 1.0
			elif n1 != n2 and not aven:
				var nar := s1 if n1 else s2
				wide_idx = s2 if n1 else s1
				wide_end = 1 if n1 else 0
				var group: PackedInt32Array = graph["group"]
				var m := _mirror_target(along_x, wide_idx, wide_end, t)
				if bool(o["aligned"]):
					# an alley already waits on the far side: worth it if it leads to another group
					var far_s := _far_street(along_x, wide_idx, wide_end, mid)
					if far_s >= 0 and width_of(City.streets[far_s]["rect"]) <= NARROW_MAX and _find(group, far_s) != _find(group, nar):
						type = "cross"
						score = 4.0
				elif not m.is_empty() and width_of(City.streets[int(m["street"])]["rect"]) <= NARROW_MAX and _find(group, int(m["street"])) != _find(group, nar):
					type = "pair"
					score = 3.5
				elif int(exits.get(_find(parent, nar), 0)) < MIN_EXITS:
					type = "exit"
					score = 2.0
			elif not n1 and not n2 and r.size.x >= 30.0 and r.size.y >= 30.0:
				type = "split"
				score = 1.5
			if type == "" or int(done[type]) >= int(CAPS[type]) or (ext_len > 40.0 and type != "split"):
				continue
			if aven and type != "split":
				continue
			score += rng.randf() * 0.5
			if score > best_score:
				best_score = score
				best = {"along_x": along_x, "t": t, "type": type, "wide_idx": wide_idx, "wide_end": wide_end}
	return best


## Positions (along the lot's frontage) that line a passage up with an alley mouth on the far side of a wide street.
static func _aligned_options(r: Rect2, along_x: bool) -> Array:
	var out: Array = []
	var f0: float = r.position.y if along_x else r.position.x
	var f1: float = r.end.y if along_x else r.end.x
	for end in 2:
		var probe := Vector2(r.position.x - 1.0, r.get_center().y) if along_x else Vector2(r.get_center().x, r.position.y - 1.0)
		if end == 1:
			probe = Vector2(r.end.x + 1.0, r.get_center().y) if along_x else Vector2(r.get_center().x, r.end.y + 1.0)
		var wi := _street_at(probe)
		if wi < 0:
			continue
		var wr: Rect2 = City.streets[wi]["rect"]
		var ww := width_of(wr)
		if ww < WIDE_MIN or ww >= AVENUE_MIN:
			continue
		# the wide street must run across the passage (its long side along the other axis)
		if along_x and wr.size.y <= wr.size.x or not along_x and wr.size.x <= wr.size.y:
			continue
		var far: float
		if along_x:
			far = wr.position.x if end == 0 else wr.end.x
		else:
			far = wr.position.y if end == 0 else wr.end.y
		for s in City.streets:
			var sr: Rect2 = s["rect"]
			if width_of(sr) > NARROW_MAX:
				continue
			# an alley whose end sits on the far edge of the wide street and that runs towards it
			if along_x:
				if sr.size.x <= sr.size.y:
					continue
				var edge := sr.end.x if end == 0 else sr.position.x
				if absf(edge - far) > 0.6:
					continue
				var c := sr.position.y + sr.size.y * 0.5
				if c > f0 + HALF_MIN + PASSAGE * 0.5 and c < f1 - HALF_MIN - PASSAGE * 0.5:
					out.append({"t": c - PASSAGE * 0.5, "aligned": true})
			else:
				if sr.size.y <= sr.size.x:
					continue
				var edge2 := sr.end.y if end == 0 else sr.position.y
				if absf(edge2 - far) > 0.6:
					continue
				var c2 := sr.position.x + sr.size.x * 0.5
				if c2 > f0 + HALF_MIN + PASSAGE * 0.5 and c2 < f1 - HALF_MIN - PASSAGE * 0.5:
					out.append({"t": c2 - PASSAGE * 0.5, "aligned": true})
	return out


## The street rectangle just beyond the far edge of wide street `wide_idx` at frontage coordinate `mid`, or -1.
static func _far_street(along_x: bool, wide_idx: int, wide_end: int, mid: float) -> int:
	var wr: Rect2 = City.streets[wide_idx]["rect"]
	var p: Vector2
	if along_x:
		p = Vector2(wr.position.x - 1.0 if wide_end == 0 else wr.end.x + 1.0, mid)
	else:
		p = Vector2(mid, wr.position.y - 1.0 if wide_end == 0 else wr.end.y + 1.0)
	return _street_at(p)


## The lot on the far side of the wide street `wide_idx` from a passage cut at `t` (`wide_end` 0: the wide street is at the start of the
## passage, west / north, so the far lot lies beyond its west / north edge): {lot, street} where `street` is what the far lot's passage
## would open on at its other end, or {} if that lot cannot take an aligned passage (too short, too long, or no street / only an avenue behind it).
static func _mirror_target(along_x: bool, wide_idx: int, wide_end: int, t: float) -> Dictionary:
	var wr: Rect2 = City.streets[wide_idx]["rect"]
	var mid := t + PASSAGE * 0.5
	var far: Vector2
	if along_x:
		far = Vector2(wr.position.x - 1.0 if wide_end == 0 else wr.end.x + 1.0, mid)
	else:
		far = Vector2(mid, wr.position.y - 1.0 if wide_end == 0 else wr.end.y + 1.0)
	for lot2 in City.lots:
		if lot2.has("dead"):
			continue
		var r2: Rect2 = lot2["r"]
		if not r2.has_point(far):
			continue
		var f0: float = r2.position.y if along_x else r2.position.x
		var front: float = r2.size.y if along_x else r2.size.x
		var ext: float = r2.size.x if along_x else r2.size.y
		if front < PASSAGE + HALF_MIN * 2.0 or ext > 40.0 or t < f0 + HALF_MIN or t + PASSAGE > f0 + front - HALF_MIN:
			return {}
		var q := Vector2(r2.position.x - 1.0, mid) if along_x else Vector2(mid, r2.position.y - 1.0)
		if wide_end == 1:
			q = Vector2(r2.end.x + 1.0, mid) if along_x else Vector2(mid, r2.end.y + 1.0)
		var si := _street_at(q)
		if si < 0 or width_of(City.streets[si]["rect"]) >= AVENUE_MIN or si == wide_idx:
			return {}
		return {"lot": lot2, "street": si}
	return {}


## Cut the passage: replace the lot's building by a 3 m street and two new lots.
static func _apply(lot: Dictionary, cut: Dictionary, rng: RandomNumberGenerator) -> void:
	var r: Rect2 = lot["r"]
	var t: float = cut["t"]
	var pass_rect: Rect2
	var ra: Rect2
	var rb: Rect2
	if bool(cut["along_x"]):
		pass_rect = Rect2(r.position.x, t, r.size.x, PASSAGE)
		ra = Rect2(r.position.x, r.position.y, r.size.x, t - r.position.y)
		rb = Rect2(r.position.x, t + PASSAGE, r.size.x, r.end.y - t - PASSAGE)
	else:
		pass_rect = Rect2(t, r.position.y, PASSAGE, r.size.y)
		ra = Rect2(r.position.x, r.position.y, t - r.position.x, r.size.y)
		rb = Rect2(t + PASSAGE, r.position.y, r.end.x - t - PASSAGE, r.size.y)
	City.buildings.erase(lot["b"])
	lot["dead"] = true
	City.lots.erase(lot)
	City.streets.append({"rect": pass_rect, "cls": "alley"})
	City._make_lot(rng, ra)
	City._make_lot(rng, rb)
	done[cut["type"]] = int(done[cut["type"]]) + 1
