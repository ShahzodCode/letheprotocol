class_name CityBuildings
## Stage 2 of the war-torn city: every ordinary building gets a design (apartment blocks with balconies, shops with awnings, offices
## with pale piers, old houses with pitched roofs, roof gardens, rooftop units) in the pale colours of Verdance, and a DAMAGE value:
## about 20% of the buildings are heavily damaged (a missing corner, collapsed top floors, a hole through the facade, rubble in the
## street, some of them burning), about 40% lightly, the rest intact. The shader (BuildingShader) draws the broken windows, soot and
## fire from that value. The border ring is damaged the same way. All geometry is boxes; colliders follow (World makes one per box).
##   building["damage"]  0..1        building["burning"]  bool      building["seed"]  random 0..1 for the shader
##   building["arch"]    String      building["chunk"]    {rect, y0, y1} the missing corner volume (if any)
##   building["access"]  a flat roof the player may reach (stage 3 gives it a parapet, a ladder or a fire escape)

const STONE := [Color(0.86, 0.84, 0.78), Color(0.93, 0.92, 0.9), Color(0.66, 0.64, 0.6), Color(0.84, 0.72, 0.5), Color(0.78, 0.75, 0.68)]
const BRICKS := [Color(0.58, 0.4, 0.32), Color(0.62, 0.48, 0.38)]
const AWNINGS := [Color(0.72, 0.14, 0.12), Color(0.14, 0.34, 0.6), Color(0.86, 0.7, 0.2), Color(0.2, 0.5, 0.3), Color(0.9, 0.9, 0.85)]
const ROOFS := [Color(0.58, 0.28, 0.18), Color(0.3, 0.32, 0.36), Color(0.5, 0.3, 0.22)]
const SIDE_N := [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]       # north (-z), south (+z), west (-x), east (+x)
const FLOOR_H := 3.4
## Decoration that costs triangles but cannot be read from the street is trimmed (city pass, phase 2): roof units only on one-floor roofs
## (and on the roofs the player can reach, CityClimb), no roof gardens, balconies only on the lowest floors.
const ROOF_UNITS_MAX_H := 8.0
const ROOF_GARDENS := false
const BALCONY_TOP_FLOOR := 5

static var heavy_count := 0
static var light_count := 0
static var intact_count := 0
static var burning_count := 0
static var access_count := 0


# ---------------------------------------------------------------- side geometry

static func _side_len(r: Rect2, s: int) -> float:
	return r.size.x if s < 2 else r.size.y


static func _side_depth(r: Rect2, s: int) -> float:
	return r.size.y if s < 2 else r.size.x


## The world rectangle for u0..u1 along side `s` and d0..d1 inwards from its facade.
static func loc_rect(r: Rect2, s: int, u0: float, u1: float, d0: float, d1: float) -> Rect2:
	match s:
		0:
			return Rect2(r.position.x + u0, r.position.y + d0, u1 - u0, d1 - d0)
		1:
			return Rect2(r.position.x + u0, r.end.y - d1, u1 - u0, d1 - d0)
		2:
			return Rect2(r.position.x + d0, r.position.y + u0, d1 - d0, u1 - u0)
	return Rect2(r.end.x - d1, r.position.y + u0, d1 - d0, u1 - u0)


## A point on the facade of side `s`, `u` along it, `y` up, `out` metres in front of the wall.
static func facade_pt(r: Rect2, s: int, u: float, y: float, out: float) -> Vector3:
	var n: Vector2 = SIDE_N[s]
	var p := Vector2.ZERO
	match s:
		0:
			p = Vector2(r.position.x + u, r.position.y)
		1:
			p = Vector2(r.position.x + u, r.end.y)
		2:
			p = Vector2(r.position.x, r.position.y + u)
		_:
			p = Vector2(r.end.x, r.position.y + u)
	return Vector3(p.x + n.x * out, y, p.y + n.y * out)


static func side_yaw(s: int) -> float:
	var n: Vector2 = SIDE_N[s]
	return atan2(n.x, n.y)


## The sides of a footprint ordered by the width of the street in front of them (widest first): [[width, side], ...].
static func street_sides(r: Rect2) -> Array:
	var out: Array = []
	for s in 4:
		var mid := facade_pt(r, s, _side_len(r, s) * 0.5, 0.0, 2.5)
		var best := 0.0
		for st in City.streets:
			var sr: Rect2 = st["rect"]
			if sr.has_point(Vector2(mid.x, mid.z)):
				best = maxf(best, minf(sr.size.x, sr.size.y))
		out.append([best, s])
	out.sort_custom(func(a, b): return a[0] > b[0])
	return out


# ---------------------------------------------------------------- the entry point

static func dress(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 2024
	heavy_count = 0
	light_count = 0
	intact_count = 0
	burning_count = 0
	access_count = 0
	var inner: Array = []
	var border: Array = []
	var special: Array = []      # tunnels, bridge ends and reachable roofs (stage 3): never heavily damaged
	for b in City.buildings:
		if b.has("institute") or b.has("home") or b.has("story") or b.has("model") or float(b["style"]) >= 0.97 or float(b["h"]) < 3.0:
			continue
		b["damage"] = 0.0
		b["burning"] = false
		b["seed"] = rng.randf()
		b["arch"] = ""
		b["access"] = bool(b.get("access", false))
		if b.has("special"):
			special.append(b)
		else:
			(border if b.get("border", false) else inner).append(b)
	_assign_damage(inner, rng, 0.2, 0.4)
	_assign_damage(border, rng, 0.34, 0.4)
	for b in special:
		b["damage"] = rng.randf_range(0.0, 0.5)
	for b in special:
		_dress_one(b, rng)
	for b in inner:
		_dress_one(b, rng)
	for b in border:
		_dress_one(b, rng)
	for b in inner + border + special:
		var d: float = b["damage"]
		if d >= 0.66:
			heavy_count += 1
		elif d >= 0.2:
			light_count += 1
		else:
			intact_count += 1
		if b["burning"]:
			burning_count += 1
		if b["access"]:
			access_count += 1


## Rank the buildings by how close they are to the fighting and the central avenues (plus luck): the top `heavy_f` are heavily
## damaged, the next `light_f` lightly, the rest intact.
static func _assign_damage(list: Array, rng: RandomNumberGenerator, heavy_f: float, light_f: float) -> void:
	var scored: Array = []
	for b in list:
		var c: Vector2 = (b["rect"] as Rect2).get_center()
		var near_site := 0.0
		for s in City.sites:
			var sc: Vector3 = s["center"]
			near_site = maxf(near_site, 1.0 - c.distance_to(Vector2(sc.x, sc.z)) / 160.0)
		var near_avenue := 1.0 - clampf(minf(absf(c.x), absf(c.y)) / 55.0, 0.0, 1.0)
		scored.append([0.5 * clampf(near_site, 0.0, 1.0) + 0.28 * near_avenue + 0.22 * rng.randf(), b])
	scored.sort_custom(func(a, b2): return a[0] > b2[0])
	var n := scored.size()
	for i in n:
		var b3: Dictionary = scored[i][1]
		var rank := float(i) / maxf(1.0, float(n))
		if rank < heavy_f:
			b3["damage"] = rng.randf_range(0.72, 1.0)
			b3["burning"] = rng.randf() < 0.38
		elif rank < heavy_f + light_f:
			b3["damage"] = rng.randf_range(0.28, 0.6)
		else:
			b3["damage"] = rng.randf_range(0.0, 0.12)


# ---------------------------------------------------------------- one building

static func _dress_one(b: Dictionary, rng: RandomNumberGenerator) -> void:
	var boxes: Array = b["boxes"]
	var r: Rect2 = b["rect"]
	var h: float = b["h"]
	var dmg: float = b["damage"]
	var border: bool = b.get("border", false)
	var plug: bool = b.get("plug", false)
	var style: float = b["style"]
	var glass := style > 0.7
	var tall := h >= 80.0
	# colour: Verdance's pale stone, white, warm grey, light ochre (some brick on the low old ones); glass stays glass
	var col: Color = b["color"]
	if glass:
		col = col.lerp(Color(0.5, 0.58, 0.62), 0.2)
	else:
		col = (BRICKS[rng.randi() % BRICKS.size()] if (h < 24.0 and rng.randf() < 0.22) else STONE[rng.randi() % STONE.size()]).darkened(rng.randf_range(0.0, 0.1))
	b["color"] = col
	for bx in boxes:
		bx["color"] = col
		bx["style"] = style
	var low := h <= 7.0
	var flat_top := boxes.size() == 1
	var roof_y: float = boxes[0]["y1"]
	# --- the design
	if b.has("tunnel"):
		b["arch"] = "passage"            # a pass-through building: only awnings, the corridor itself is CityClimb's
		_awnings(b, rng, 2)
	elif border:
		b["arch"] = "tower"
		if glass and rng.randf() < 0.5:
			_set_style(boxes, 0.8)
	elif low:
		if r.size.x >= 8.0 and r.size.y >= 8.0 and maxf(r.size.x, r.size.y) <= 36.0 and rng.randf() < 0.5 and not b["access"]:
			b["arch"] = "house"
			_set_style(boxes, 0.2)
			if rng.randf() < 0.5:
				for bx in boxes:
					bx["color"] = (BRICKS[rng.randi() % BRICKS.size()] as Color)
				b["color"] = boxes[0]["color"]
			_pitched_roof(b, rng)
			flat_top = false
		else:
			b["arch"] = "shop"
			_set_style(boxes, 0.14)
			_awnings(b, rng, 2)
			if dmg < 0.66 and not b["access"]:
				_roof_units(b, rng, roof_y)
	elif h <= 42.0 and not plug:
		b["arch"] = "apartments"
		var shops := rng.randf() < 0.7
		if shops:
			_ground_floor(b, rng)
		if rng.randf() < 0.5:
			_balconies(b, rng, dmg)
		if shops:
			_awnings(b, rng, 1)
		# a roof the player may reach gets its furniture (with colliders) from CityClimb
		if b["access"]:
			pass
		elif flat_top and dmg < 0.66:
			if rng.randf() < 0.16:
				_roof_garden(b, rng, roof_y)
			else:
				_roof_units(b, rng, float(boxes[boxes.size() - 1]["y1"]))
		elif dmg < 0.66:
			_roof_units(b, rng, float(boxes[boxes.size() - 1]["y1"]))
	elif not tall:
		b["arch"] = "office"
		_set_style(boxes, 0.8 if rng.randf() < 0.55 else (0.5 if style < 0.6 else style))
		_ground_floor(b, rng)
		if dmg < 0.66 and h < 70.0:
			_roof_units(b, rng, float(boxes[boxes.size() - 1]["y1"]))
	else:
		b["arch"] = "tower"
		if glass and rng.randf() < 0.45:
			_set_style(boxes, 0.8)
	b["flat_top"] = flat_top and b["arch"] != "house"
	# --- the damage
	if dmg >= 0.66 and float(boxes[0]["y1"]) >= 10.0:
		_wreck(b, rng)
	# a burning building: flames and smoke come out of a broken window on its front side (Fires shows them near the player)
	if b["burning"]:
		var top := 8.0
		for bx in boxes:
			if float(bx.get("style", 0.0)) < 0.97:
				top = maxf(top, float(bx["y1"]))
		var sides := street_sides(r)
		var s: int = sides[0][1]
		var fy := rng.randf_range(5.0, minf(top * 0.6, 40.0))
		var p := facade_pt(r, s, _side_len(r, s) * rng.randf_range(0.25, 0.75), fy, 0.4)
		Scn.fire("build", p, 1.0)
	# the new height after the damage (the tallest solid box)
	var nh := 0.0
	for bx in boxes:
		if float(bx.get("style", 0.0)) < 0.97:
			nh = maxf(nh, float(bx["y1"]))
	b["h"] = nh


static func _set_style(boxes: Array, style: float) -> void:
	for bx in boxes:
		if float(bx.get("style", 0.0)) < 0.97:
			bx["style"] = style


## The ground floor of the first box becomes its own box (a darker colour and the shop-front style).
static func _ground_floor(b: Dictionary, rng: RandomNumberGenerator) -> void:
	var boxes: Array = b["boxes"]
	var first: Dictionary = boxes[0]
	if float(first["y0"]) != 0.0 or float(first["y1"]) < 9.0:
		return
	var upper_col: Color = first["color"]
	var gcol := upper_col.darkened(0.12).lerp(Color(0.55, 0.5, 0.45), 0.25)
	var ground := {"rect": first["rect"], "y0": 0.0, "y1": 4.6, "color": gcol, "style": 0.14}
	first["y0"] = 4.6
	boxes.insert(0, ground)
	b["ground_box"] = true


## Rows of balconies (slab + railing) on the front facade of an apartment block; broken ones where the building is damaged.
static func _balconies(b: Dictionary, rng: RandomNumberGenerator, dmg: float) -> void:
	var boxes: Array = b["boxes"]
	var main: Dictionary = boxes[1] if b.get("ground_box", false) else boxes[0]
	var r: Rect2 = main["rect"]
	var top: float = main["y1"]
	var sides := street_sides(r)
	var s: int = sides[0][1]
	var len := _side_len(r, s)
	var n := int(floorf((len - 2.0) / 5.6))
	if n < 1:
		return
	var floors := int(floorf(top / 3.3))
	var yaw := side_yaw(s)
	var col := Color(0.72, 0.71, 0.68)
	var rail := Color(0.16, 0.18, 0.2)
	b["balconies"] = true
	for f in range(2, mini(floors, BALCONY_TOP_FLOOR)):
		var y := float(f) * 3.3 + 0.2
		for i in n:
			if rng.randf() < dmg * 0.55:
				continue          # shaken off
			var u := (float(i) + 0.5) * len / float(n)
			var p := facade_pt(r, s, u, y, 0.62)
			Scn.box(p, Vector3(2.4, 0.16, 1.24), col, yaw)
			Scn.box(facade_pt(r, s, u, y + 0.58, 1.2), Vector3(2.4, 0.95, 0.06), rail, yaw)
			if rng.randf() < 0.3:
				Scn.box(facade_pt(r, s, u + 0.5, y + 0.4, 0.5), Vector3(0.5, 0.5, 0.35), Color(0.2, 0.4, 0.16), yaw)           # a plant box


## Shop awnings (and a few hanging signs) over the pavement on the best street sides.
static func _awnings(b: Dictionary, rng: RandomNumberGenerator, max_sides: int) -> void:
	var r: Rect2 = b["rect"]
	var sides := street_sides(r)
	var done := 0
	for sd in sides:
		if done >= max_sides or float(sd[0]) < 5.5:
			break
		var s: int = sd[1]
		var len := _side_len(r, s)
		var n := int(floorf((len - 1.0) / 5.6))
		var yaw := side_yaw(s)
		for i in n:
			if rng.randf() < 0.25:
				continue
			var u := (float(i) + 0.5) * len / float(n)
			var col: Color = AWNINGS[rng.randi() % AWNINGS.size()]
			Scn.box(facade_pt(r, s, u, 3.3, 0.75), Vector3(3.2, 0.07, 1.5), col, yaw, Basis(Vector3.RIGHT, 0.26))
			Scn.box(facade_pt(r, s, u, 3.05, 1.42), Vector3(3.2, 0.3, 0.05), col.darkened(0.15), yaw)
			if rng.randf() < 0.3:
				Scn.part("glow", Scn.box_xf(facade_pt(r, s, u + 1.8, 4.1, 0.5), Vector3(0.12, 0.9, 0.7), yaw), Color(1.0, 0.8, 0.3) if rng.randf() < 0.5 else Color(0.4, 0.9, 1.0))
		done += 1


## AC units, a water tank, a stair bulkhead and an aerial on a roof at height `y`.
static func _roof_units(b: Dictionary, rng: RandomNumberGenerator, y: float, solid: bool = false) -> void:
	if not solid and y > ROOF_UNITS_MAX_H:
		return
	var boxes: Array = b["boxes"]
	var top_box: Dictionary = boxes[boxes.size() - 1]
	var r: Rect2 = (top_box["rect"] as Rect2).grow(-1.4)
	if r.size.x < 3.0 or r.size.y < 3.0:
		return
	var placed: Array = []
	var n := rng.randi_range(2, 4)
	for i in n:
		var kind := rng.randi() % 4
		var half := Vector2(0.9, 0.7) if kind < 2 else (Vector2(1.3, 1.3) if kind == 2 else Vector2(1.6, 1.5))
		var p := Vector2(rng.randf_range(r.position.x + half.x, r.end.x - half.x), rng.randf_range(r.position.y + half.y, r.end.y - half.y))
		var rect := Rect2(p - half, half * 2.0)
		var clash := false
		for q in placed:
			if (q as Rect2).intersects(rect.grow(0.4)):
				clash = true
		if clash:
			continue
		placed.append(rect)
		if b.has("keep_clear") and rect.grow(0.4).intersects(b["keep_clear"]):          # a roof hatch lies here (the lookout's hall)
			continue
		match kind:
			0, 1:
				Scn.box(Vector3(p.x, y + 0.5, p.y), Vector3(1.6, 1.0, 1.2), Color(0.62, 0.64, 0.66))
				Scn.box(Vector3(p.x, y + 1.04, p.y), Vector3(1.0, 0.1, 0.8), Color(0.22, 0.23, 0.25))
				if solid:
					Scn.solid(Vector3(p.x, y + 0.5, p.y), Vector3(1.6, 1.0, 1.2))
			2:
				Scn.between("cyl", Vector3(p.x, y + 1.2, p.y), Vector3(p.x, y + 3.6, p.y), 2.3, Color(0.42, 0.36, 0.3))
				for lx in [-0.8, 0.8]:
					for lz in [-0.8, 0.8]:
						Scn.box(Vector3(p.x + lx, y + 0.6, p.y + lz), Vector3(0.14, 1.2, 0.14), Color(0.25, 0.25, 0.27))
				if solid:
					Scn.solid(Vector3(p.x, y + 1.8, p.y), Vector3(2.4, 3.6, 2.4))
			3:
				Scn.box(Vector3(p.x, y + 1.3, p.y), Vector3(3.0, 2.6, 2.8), top_box["color"] as Color)
				Scn.box(Vector3(p.x - 1.52, y + 1.0, p.y), Vector3(0.06, 2.0, 1.0), Color(0.3, 0.26, 0.2))          # a door that leads nowhere
				if solid:
					Scn.solid(Vector3(p.x, y + 1.3, p.y), Vector3(3.0, 2.6, 2.8))
	if rng.randf() < 0.6:
		var ap := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
		if b.has("keep_clear") and (b["keep_clear"] as Rect2).has_point(ap):
			return
		Scn.between("cyl", Vector3(ap.x, y, ap.y), Vector3(ap.x, y + rng.randf_range(5.0, 8.0), ap.y), 0.12, Color(0.3, 0.3, 0.32))


## A green roof: a layer of soil and grass, planters and a few small trees.
static func _roof_garden(b: Dictionary, rng: RandomNumberGenerator, y: float) -> void:
	if not ROOF_GARDENS:
		return
	var r: Rect2 = (b["rect"] as Rect2).grow(-0.9)
	Scn.box(Vector3(r.get_center().x, y + 0.14, r.get_center().y), Vector3(r.size.x, 0.28, r.size.y), Color(0.2, 0.36, 0.16))
	b["green_roof"] = true
	for i in 4:
		var p := Vector2(rng.randf_range(r.position.x + 1.5, r.end.x - 1.5), rng.randf_range(r.position.y + 1.5, r.end.y - 1.5))
		Scn.prop(Vector3(p.x, y + 0.5, p.y), Vector3(1.6, 0.5, 1.6), Color(0.78, 0.76, 0.72))
		Scn.cyl_solid(Vector3(p.x, y + 0.75, p.y), 0.15, 1.4)          # the trunk (the crown is above head height)
		Scn.between("cyl", Vector3(p.x, y + 0.7, p.y), Vector3(p.x, y + 2.2, p.y), 0.3, Color(0.32, 0.22, 0.14))
		Scn.part("sphere", Transform3D(Basis.from_scale(Vector3(2.4, 1.9, 2.4)), Vector3(p.x, y + 2.9, p.y)), Color(0.18, 0.36, 0.14).lightened(rng.randf_range(0.0, 0.15)))


## An old house: a low attic and two tilted roof slabs (with colliders) over the ridge, along the longer side.
static func _pitched_roof(b: Dictionary, rng: RandomNumberGenerator) -> void:
	var boxes: Array = b["boxes"]
	var r: Rect2 = b["rect"]
	var h: float = boxes[0]["y1"]
	var along_x := r.size.x >= r.size.y
	var long_len := r.size.x if along_x else r.size.y
	var width := r.size.y if along_x else r.size.x
	var half := width * 0.5
	var ang := 0.5
	var rise := half * tan(ang)
	var he := h + 0.4
	boxes.append({"rect": r, "y0": h, "y1": he, "color": boxes[0]["color"], "style": boxes[0]["style"]})
	var roof_col: Color = ROOFS[rng.randi() % ROOFS.size()]
	var slope := (half + 0.45) / cos(ang)
	var yaw := 0.0 if along_x else PI * 0.5
	for sd in [-1.0, 1.0]:
		var centre_off := (half * 0.5 + 0.12) * float(sd)
		var c := Vector3(r.get_center().x, he + rise * 0.5 + 0.03, r.get_center().y)
		var across := Vector3(0.0, 0.0, centre_off) if along_x else Vector3(centre_off, 0.0, 0.0)
		var extra := Basis(Vector3.RIGHT, ang * float(sd))
		var size := Vector3(long_len + 0.9, 0.14, slope)
		Scn.part("box", Scn.box_xf(c + across, size, yaw, extra), roof_col)
		Scn.solid_xf(Transform3D(Basis(Vector3.UP, yaw) * extra, c + across), size)
	# the gable ends: a pale triangle approximated by one box each
	for end in [-1.0, 1.0]:
		var ec := Vector3(r.get_center().x + (long_len * 0.5 - 0.1) * float(end), he + rise * 0.28, r.get_center().y) if along_x else Vector3(r.get_center().x, he + rise * 0.28, r.get_center().y + (long_len * 0.5 - 0.1) * float(end))
		var esz := Vector3(0.2, rise * 0.56, width * 0.7) if along_x else Vector3(width * 0.7, rise * 0.56, 0.2)
		Scn.box(ec, esz, boxes[0]["color"] as Color)
	b["roof_pitched"] = true


# ---------------------------------------------------------------- the damage

static func _wreck(b: Dictionary, rng: RandomNumberGenerator) -> void:
	var picks := rng.randi() % 4
	var did := false
	if picks == 0 or picks == 3:
		did = _corner_chunk(b, rng) or did
	if picks == 1 or picks == 3:
		did = _facade_hole(b, rng) or did
	if picks == 2 or (picks == 3 and rng.randf() < 0.5) or not did:
		_collapse_top(b, rng)


static func _main_box(b: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for bx in b["boxes"]:
		if float(bx.get("style", 0.0)) >= 0.97:
			continue
		if best.is_empty() or float(bx["y1"]) - float(bx["y0"]) > float(best["y1"]) - float(best["y0"]):
			best = bx
	return best


## A missing corner: everything above `yc` in one corner is gone; exposed floor slabs and bent beams hang out of the break.
static func _corner_chunk(b: Dictionary, rng: RandomNumberGenerator) -> bool:
	var main := _main_box(b)
	if main.is_empty():
		return false
	var rect: Rect2 = main["rect"]
	var y0: float = main["y0"]
	var y1: float = main["y1"]
	if y1 - y0 < 14.0 or rect.size.x < 10.0 or rect.size.y < 10.0:
		return false
	var yc := y0 + snappedf((y1 - y0) * rng.randf_range(0.4, 0.68), FLOOR_H)
	var cx := rect.size.x * rng.randf_range(0.3, 0.45)
	var cz := rect.size.y * rng.randf_range(0.3, 0.45)
	var west := rng.randf() < 0.5
	var north := rng.randf() < 0.5
	var chunk := Rect2(rect.position.x if west else rect.end.x - cx, rect.position.y if north else rect.end.y - cz, cx, cz)
	# the part below stays whole, above it two boxes make an L
	var color: Color = main["color"]
	var style: float = main["style"]
	main["y1"] = yc
	var strip1 := Rect2(rect.position.x + (cx if west else 0.0), rect.position.y, rect.size.x - cx, rect.size.y)
	var strip2 := Rect2(chunk.position.x, rect.position.y + (cz if north else 0.0), cx, rect.size.y - cz)
	(b["boxes"] as Array).append({"rect": strip1, "y0": yc, "y1": y1, "color": color, "style": style})
	(b["boxes"] as Array).append({"rect": strip2, "y0": yc, "y1": y1, "color": color, "style": style})
	b["chunk"] = {"rect": chunk, "y0": yc, "y1": y1}
	b["arch_damage"] = "corner"
	# floor slabs still sticking out of the break (fewer and shorter higher up) and bent beams
	var k := 0
	var y := yc
	while y < y1 - 1.0 and k < 14:
		var cover := clampf(rng.randf_range(0.45, 0.95) - float(k) * 0.045, 0.15, 0.95)
		var sw := chunk.size.x * rng.randf_range(0.5, 1.0) * cover
		var sd := chunk.size.y * rng.randf_range(0.5, 1.0) * cover
		var slab := Rect2(chunk.position.x if west else chunk.end.x - sw, chunk.position.y if north else chunk.end.y - sd, sw, sd)
		(b["boxes"] as Array).append({"rect": slab, "y0": y, "y1": y + 0.3, "color": Color(0.6, 0.59, 0.57), "style": 0.99})
		y += FLOOR_H
		k += 1
	for i in 4:
		var bp := Vector3(chunk.position.x + chunk.size.x * rng.randf_range(0.1, 0.9), yc + rng.randf_range(0.5, minf(y1 - yc, 10.0)), chunk.position.y + chunk.size.y * rng.randf_range(0.1, 0.9))
		Scn.box(bp, Vector3(0.22, 0.22, rng.randf_range(2.5, 5.0)), Color(0.28, 0.24, 0.22), rng.randf() * TAU, Basis(Vector3.RIGHT, rng.randf_range(-0.6, 0.6)))
	# the debris in the street below the break
	var c2 := chunk.get_center()
	var out := Vector2(-1.0 if west else 1.0, -1.0 if north else 1.0).normalized()
	CityWar.try_rubble(c2 + out * (maxf(chunk.size.x, chunk.size.y) * 0.5 + 3.0), rng)
	CityWar.try_rubble(c2 + Vector2(out.x, 0.0) * (chunk.size.x * 0.5 + 3.2) + Vector2(0.0, out.y * 4.0), rng)
	return true


## The top floors collapsed: a ragged skyline of broken walls, bare floor slabs and bent beams.
static func _collapse_top(b: Dictionary, rng: RandomNumberGenerator) -> void:
	var main := _main_box(b)
	if main.is_empty():
		return
	var rect: Rect2 = main["rect"]
	var y1: float = main["y1"]
	var y0: float = main["y0"]
	var lost := rng.randi_range(2, 4)
	var y_cut := maxf(y0 + 6.0, y1 - float(lost) * FLOOR_H)
	if y_cut >= y1 - 1.0:
		return
	main["y1"] = y_cut
	var color: Color = main["color"]
	var style: float = main["style"]
	b["arch_damage"] = "collapse"
	# three ragged columns of what is left standing
	var cols := 3
	var along_x := rect.size.x >= rect.size.y
	for i in cols:
		var piece: Rect2
		if along_x:
			piece = Rect2(rect.position.x + rect.size.x * float(i) / float(cols), rect.position.y, rect.size.x / float(cols), rect.size.y)
		else:
			piece = Rect2(rect.position.x, rect.position.y + rect.size.y * float(i) / float(cols), rect.size.x, rect.size.y / float(cols))
		var extra := rng.randf_range(0.0, float(lost) * FLOOR_H * 0.9)
		if extra > 1.2:
			var thin := piece.grow(-rng.randf_range(0.0, 1.5))
			(b["boxes"] as Array).append({"rect": thin, "y0": y_cut, "y1": y_cut + extra, "color": color, "style": style})
	# bare floor slabs over the break (coverage shrinks upwards) and bent beams
	var y := y_cut
	for k in lost:
		y += FLOOR_H
		var cover := rng.randf_range(0.35, 0.85)
		var slab := Rect2(rect.position + rect.size * (1.0 - cover) * Vector2(rng.randf(), rng.randf()), rect.size * cover)
		(b["boxes"] as Array).append({"rect": slab, "y0": y_cut + FLOOR_H * float(k) + 0.1, "y1": y_cut + FLOOR_H * float(k) + 0.4, "color": Color(0.6, 0.59, 0.57), "style": 0.99})
	for i in 6:
		var bp := Vector3(rect.position.x + rect.size.x * rng.randf_range(0.1, 0.9), y_cut + rng.randf_range(0.2, float(lost) * FLOOR_H), rect.position.y + rect.size.y * rng.randf_range(0.1, 0.9))
		Scn.box(bp, Vector3(0.2, 0.2, rng.randf_range(2.5, 6.0)), Color(0.28, 0.24, 0.22), rng.randf() * TAU, Basis(Vector3.RIGHT, rng.randf_range(-0.7, 0.7)))
	# debris round the foot
	var sides := street_sides(rect)
	var s: int = sides[0][1]
	var mid := facade_pt(rect, s, _side_len(rect, s) * rng.randf_range(0.25, 0.75), 0.0, 3.0)
	CityWar.try_rubble(Vector2(mid.x, mid.z), rng)


## A large hole through the facade: a cavity (dark inside) 4-8 m wide; on the ground it is a way in, higher up a black wound.
static func _facade_hole(b: Dictionary, rng: RandomNumberGenerator) -> bool:
	var main := _main_box(b)
	if main.is_empty():
		return false
	var rect: Rect2 = main["rect"]
	var y0: float = main["y0"]
	var y1: float = main["y1"]
	if y1 - y0 < 16.0 or b.has("chunk"):
		return false
	var sides := street_sides(rect)
	var s: int = sides[0][1]
	var len := _side_len(rect, s)
	var depth_total := _side_depth(rect, s)
	var w := minf(rng.randf_range(4.5, 7.5), len * 0.6)
	var cd := minf(rng.randf_range(3.5, 5.5), depth_total * 0.55)
	var ground := rng.randf() < 0.45 and y0 < 0.5
	var hh := 4.2 if ground else rng.randf_range(6.0, 9.0)
	var lo := y0 if ground else y0 + rng.randf_range(5.0, minf(maxf(6.0, (y1 - y0) * 0.5), 34.0))
	var hi := lo + hh
	if hi > y1 - 3.0:
		return false
	var u0 := rng.randf_range(len * 0.15, maxf(len * 0.15 + 0.1, len * 0.85 - w))
	var color: Color = main["color"]
	var style: float = main["style"]
	# replace the main box by the pieces round the cavity
	var boxes: Array = b["boxes"]
	boxes.erase(main)
	if lo > y0 + 0.05:
		boxes.append({"rect": rect, "y0": y0, "y1": lo, "color": color, "style": style})
	boxes.append({"rect": rect, "y0": hi, "y1": y1, "color": color, "style": style})
	boxes.append({"rect": loc_rect(rect, s, 0.0, len, cd, depth_total), "y0": lo, "y1": hi, "color": color, "style": style})        # behind the cavity
	if u0 > 0.05:
		boxes.append({"rect": loc_rect(rect, s, 0.0, u0, 0.0, cd), "y0": lo, "y1": hi, "color": color, "style": style})
	if u0 + w < len - 0.05:
		boxes.append({"rect": loc_rect(rect, s, u0 + w, len, 0.0, cd), "y0": lo, "y1": hi, "color": color, "style": style})
	# dark linings inside (the shader would paint windows on the cut faces)
	var dark := Color(0.04, 0.038, 0.036)
	boxes.append({"rect": loc_rect(rect, s, u0 + 0.02, u0 + w - 0.02, cd - 0.08, cd), "y0": lo, "y1": hi, "color": dark, "style": 0.99, "decor": true})
	b["hole"] = {"rect": loc_rect(rect, s, u0, u0 + w, 0.0, cd), "y0": lo, "y1": hi, "side": s, "ground": ground}
	b["arch_damage"] = "hole"
	# a bent slab and rebar at the lip, and the debris on the street
	var lip := facade_pt(rect, s, u0 + w * 0.5, lo + 0.1, 0.3)
	Scn.box(lip, Vector3(w * 0.7, 0.3, 1.6), Color(0.58, 0.57, 0.55), side_yaw(s), Basis(Vector3.RIGHT, 0.18))
	var rub := facade_pt(rect, s, u0 + w * 0.5, 0.0, 3.0)
	CityWar.try_rubble(Vector2(rub.x, rub.z), rng)
	return true
