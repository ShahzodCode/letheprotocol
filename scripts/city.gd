class_name City
## The city layout, generated once from a seed. The map is a strip (about 280 x 580 m): you start at the south end in the
## doorway of a building looking out over a wide avenue, the goal house stands at the north end. A solid ring of tall
## buildings closes the map. Inside: avenues for traffic, blocks cut by random binary subdivision into streets, footpaths
## and narrow alleys, a building on every lot, parked cars, battle sites at some junctions, and the navigation grid the
## soldiers use. Everything is plain data (static); World turns it into meshes and colliders.
## Plan view: x is east, z is south; rectangles are Rect2(x, z, width, depth). The player walks north (-z).

const OUT_X := 172.0                       # outer half-extent, including the ring of border buildings
const OUT_Z := 312.0
const RING := 22.0                         # thickness of the border buildings
const IN_X := OUT_X - RING                 # the playable area is |x| < IN_X, |z| < IN_Z
const IN_Z := OUT_Z - RING
const LANE := 8.0                          # width of the lanes that run along the inside of the border ring
const BX := IN_X - LANE                    # the blocks fill |x| < BX, |z| < BZ; the lanes are the strip outside that
const BZ := IN_Z - LANE
## Through streets. Only the central avenue (x = 0), the cross avenue (z = 0) and the start avenue (z = 235) are wide;
## the rest are 12 m streets and 8-10 m footpaths, and the blocks between them are cut up further.
const AVENUE_X := [-108.0, -54.0, 0.0, 54.0, 108.0]                       # lines running along z
const AVENUE_Z := [-258.0, -200.0, -140.0, -80.0, 0.0, 70.0, 130.0, 185.0, 235.0]    # lines running along x
const LINE_WIDTH := {-108.0: 10.0, -54.0: 12.0, 0.0: 24.0, 54.0: 12.0, 108.0: 10.0,
	-258.0: 10.0, -200.0: 12.0, -140.0: 8.0, -80.0: 12.0, 70.0: 12.0, 130.0: 8.0, 185.0: 12.0, 235.0: 20.0}
const MIN_LOT := 12.0
const MAX_LOT := 34.0
## How likely soldiers are to be placed on a street, per square metre, by street class.
const WEIGHTS := {"avenue": 1.6, "plaza": 0.6, "street": 0.5, "walk": 0.3, "alley": 0.15}
## The four street classes of the city (the code names in `streets[i]["cls"]`): width range in metres, cover = planted cover objects per
## 100 m of street (CityWar.street_cover; avenues get only the rings round battle sites and keep x = 0 / z = 0 clear), light = how bright
## it feels 0..1 (street lamps, paving tone, corner signs: avenues are lit and open, alleys dark). The soldier weight is `WEIGHTS[cls]`.
##   avenue "avenue"  20-24 m   street "street" 12 m   side street "walk" 6-8 m (footpaths up to 10 m, border lanes 8 m)   alley "alley" 3-4 m
const STREET_CLASSES := {
	"avenue": {"label": "avenue", "width_min": 18.0, "width_max": 24.0, "cover": 0.0, "light": 1.0},
	"street": {"label": "street", "width_min": 11.0, "width_max": 13.0, "cover": 7.0, "light": 0.75},
	"walk": {"label": "side street", "width_min": 5.0, "width_max": 10.0, "cover": 1.5, "light": 0.5},
	"alley": {"label": "alley / footpath", "width_min": 3.0, "width_max": 4.0, "cover": 0.0, "light": 0.2},
}
## Parked vehicle types: size = width, height, length (metres); w = how common.
const CAR_TYPES := [
	{"name": "hatch", "size": Vector3(1.7, 1.45, 3.6), "w": 3.0},
	{"name": "sedan", "size": Vector3(1.9, 1.45, 4.5), "w": 4.0},
	{"name": "suv", "size": Vector3(2.0, 1.85, 4.8), "w": 3.0},
	{"name": "van", "size": Vector3(2.1, 2.3, 5.4), "w": 2.0},
	{"name": "truck", "size": Vector3(2.4, 3.2, 7.5), "w": 1.2},
	{"name": "bus", "size": Vector3(2.6, 3.3, 11.0), "w": 0.5},
]
## THE INSTITUTE: the tallest tower of the district (about 180 m, pale stone) at the south end. Its lobby (16 x 12 x 5 m)
## opens through a 3 m doorway onto the wide avenue z = 235. The player starts in front of the (unusable) lift.
const INSTITUTE_BLOCK := Rect2(-48.0, 245.0, 36.0, 37.0)
const INSTITUTE_RECT := Rect2(-42.0, 245.0, 24.0, 24.0)            # tower footprint
const LOBBY := Rect2(-38.0, 246.0, 16.0, 12.0)
const LOBBY_H := 5.0
const INSTITUTE_POS := Vector3(-30.0, 0.0, 257.0)                  # centre of the tower
const START_POS := Vector3(-30.0, 0.1, 254.6)
const INSTITUTE_EXIT := Vector3(-30.0, 0.0, 240.5)                 # on the avenue, just outside the doorway
## NOAH'S HOME: a 4-storey apartment block east of the central avenue; only the ground-floor apartment (14 x 10 m, 3 m high)
## can be entered. A door in its hallway leads down a staircase into a 6 x 5 m, 2.4 m high cellar under the yard.
const HOME_BLOCK := Rect2(12.0, -74.0, 36.0, 62.0)
const HOME_RECT := Rect2(16.0, -36.0, 20.4, 14.4)                  # outer footprint (walls 0.4 m)
const HOME_ORIGIN := Vector2(16.4, -35.6)                          # north-west corner of the apartment's inside; u = east, v = south
const HOME_IN := Vector2(19.6, 13.6)                               # the apartment's inside (u, v): the old 14 x 10 flat plus an east wing and a back hall
const HOME_H := 13.2
const APT_H := 3.0
const HOME_POS := Vector3(16.2, 0.0, -30.6)                        # the front door
const CELLAR_DOOR_POS := Vector3(20.2, 0.0, -29.5)                 # hallway side, top of the stairs
const CELLAR_FLOOR_Y := -2.7                                       # floor of the cellar (2.4 m clear height under the 0.3 m ceiling slab)
const CELLAR_CEIL_Y := -0.3
const CELLAR_RECT := Rect2(17.4, -25.6, 6.0, 5.0)
const STAIR_HOLE := Rect2(19.5, -28.9, 1.4, 3.3)                   # opening in the ground above the stairs
const CELLAR_POS := Vector3(20.4, -2.7, -23.1)
## THE PARK: 40 x 40 m, a clear 30 x 15 m landing area in the middle and a building with an open second-floor balcony
## on its south side (outside stair at the west end).
const PARK_BLOCK := Rect2(60.0, -74.0, 43.0, 62.0)
const PARK_RECT := Rect2(61.5, -73.0, 40.0, 40.0)
const PARK_POS := Vector3(81.5, 0.0, -53.0)
const LANDING := Rect2(66.5, -60.5, 30.0, 15.0)
const BALCONY_RECT := Rect2(72.0, -31.6, 22.0, 2.6)
const BALCONY_Y := 3.4
const BALCONY_POS := Vector3(82.0, 3.4, -30.3)
## THE LANDER (ShipModels): a landing craft that comes down on the LANDING area of the park; its ramp faces west, towards the street side.
const LANDER_POS := Vector3(83.0, 0.0, -53.0)
const LANDER_YAW := -PI * 0.5              # model +z (the ramp) -> world -x
const BALCONY_STAIR_FOOT := Vector3(66.8, 0.0, -30.3)      # the outside stair up to the balcony starts here
## NOAH'S NEIGHBOURHOOD ("The Lander", part two): the block south of the cross avenue under the park, hand-built from 3 m alleys, a small
## courtyard (12 x 12 m, two 3 m gates) walled in by low wings, and drainpipes up to the low roof that overlooks it (see CityPlaces.court_block).
const COURT_BLOCK := Rect2(60.0, 12.0, 43.0, 52.0)
const COURT_RECT := Rect2(78.0, 30.0, 12.0, 12.0)
const COURT_POS := Vector3(84.0, 0.0, 36.0)
const COURT_ROOF_Y := 4.6
const SITE_COUNT := 6
const SITE_RADIUS := 13.0
const SITE_KEEP_OUT := 60.0                 # no battle site this close to the Institute or the home
## Between the Institute and the home the back streets are quiet and the avenue busy.
const ROUTE_ZONE := Rect2(-70.0, -60.0, 140.0, 320.0)
const ROUTE_ZONE_MULT := {"avenue": 1.6, "alley": 0.25, "walk": 0.25}

static var streets: Array = []      # {rect: Rect2, cls: "avenue" | "plaza" | "street" | "walk" | "alley"}
static var buildings: Array = []    # {rect: footprint, boxes: [{rect, y0, y1}], style: float, color: Color, h: float, [nav_rects], [border], [no_slab]}
static var backdrop: Array = []     # same, outside the map: pictures only
static var cars: Array = []
static var sites: Array = []        # {center: Vector3, radius: float}: battle sites at junctions
static var decor: Array = []        # {pos: Vector3, size: Vector3, color: Color, glow: bool}: small extras, no collision
static var ground_slabs: Array = [] # [Rect2, Color]: flat coloured ground patches (yards, paths)
static var props: Array = []        # {rect, y0, y1, color, style, nav}: solid furniture / walls with a collider; nav = "main" | "home" | "cellar" | "balcony" | ""
static var ramps: Array = []        # {a: top Vector3, b: bottom Vector3, width}: smooth slope colliders (stairs look like steps, walk like a ramp)
static var trees: Array = []        # {pos: Vector2, h: float, r: float}: trees with a trunk collider and a nav obstacle
static var obstacles: Array = []    # {pos: Vector3, yaw: float, scale: float, half: Vector2, rect: Rect2}: steel hedgehog barricades around the battle sites (collider + nav obstacle)
static var far_trees: Array = []    # unused since the backdrop is all towers (kept so old callers do not break)
static var containers: Array = []   # {pos: Vector3, yaw, top: float, rect}: shipping containers on the kerbs (climbable with a ladder)
static var ladders: Array = []      # {pos: Vector3 (foot, on the wall), n: Vector2 (away from the wall), top: float, kind}: the player climbs these
static var escapes: Array = []      # {rect, side, top, start}: fire escapes and concrete stairs up the side of a building
static var bridges: Array = []      # {a, b (buildings), p0, p1 (Vector3 ends, y = roof), y, kind: open | glass, broken}
static var tunnels: Array = []      # {rect (the 3 m corridor), runs_z, length, a, b (entrance / exit points), building}: pass-through buildings
static var crouch_passages: Array = []   # {pos, rect, along_x, width, kind: pipe | ladder | slab | gap, bottom}: alleys passable only crouched
static var lights: Array = []       # {pos: Vector3, range: float, energy: float, color: Color}
static var layers: Array = []       # nav layers (interior / balcony grids linked to a parent grid at one spot)
static var lots: Array = []         # {b: the building dict, r: the lot rectangle}: every generated lot (not the hand-built places), for CityLinks
static var interiors: Array = []     # CityInteriors plans (one per enterable building; streamed in by Interiors while the player is near)
static var _live: Array = []         # indices of the layers that exist right now (the hand-built ones always, an interior only while it is streamed in)
static var _astar: AStarGrid2D = null
static var _main_grid: Dictionary = {}
static var _cum: PackedFloat32Array = PackedFloat32Array()   # cumulative street weights, for random spawn spots

const GLASS := [Color(0.42, 0.58, 0.66), Color(0.36, 0.5, 0.62), Color(0.5, 0.66, 0.7), Color(0.3, 0.42, 0.5), Color(0.55, 0.62, 0.7)]
const CONCRETE := [Color(0.62, 0.62, 0.6), Color(0.52, 0.53, 0.55), Color(0.72, 0.7, 0.66), Color(0.44, 0.45, 0.47), Color(0.8, 0.8, 0.78)]
const BRICK := [Color(0.55, 0.34, 0.27), Color(0.6, 0.45, 0.35), Color(0.42, 0.3, 0.28)]


## The class table entry of a street class plus its soldier weight; plazas count as avenues for width and light.
static func class_info(cls: String) -> Dictionary:
	var info: Dictionary = (STREET_CLASSES.get(cls, STREET_CLASSES["avenue"]) as Dictionary).duplicate()
	info["weight"] = float(WEIGHTS.get(cls, 0.5))
	return info


static func avenue_width(v: float) -> float:
	return float(LINE_WIDTH.get(v, 12.0))


static func generate(seed_value: int = 2077) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	streets.clear()
	buildings.clear()
	backdrop.clear()
	cars.clear()
	sites.clear()
	decor.clear()
	ground_slabs.clear()
	props.clear()
	ramps.clear()
	trees.clear()
	obstacles.clear()
	far_trees.clear()
	containers.clear()
	ladders.clear()
	escapes.clear()
	bridges.clear()
	tunnels.clear()
	crouch_passages.clear()
	Scn.reset()
	CityStory.reset()
	lights.clear()
	layers.clear()
	interiors.clear()
	_live.clear()
	lots.clear()
	for x in AVENUE_X:
		var w := avenue_width(x)
		streets.append({"rect": Rect2(x - w * 0.5, -IN_Z, w, IN_Z * 2.0), "cls": _class_of(w)})
	for z in AVENUE_Z:
		var w2 := avenue_width(z)
		streets.append({"rect": Rect2(-IN_X, z - w2 * 0.5, IN_X * 2.0, w2), "cls": _class_of(w2)})
	var xe := _intervals(AVENUE_X, BX)
	var ze := _intervals(AVENUE_Z, BZ)
	for ix in xe.size():
		for iz in ze.size():
			var block := Rect2(xe[ix][0], ze[iz][0], xe[ix][1] - xe[ix][0], ze[iz][1] - ze[iz][0])
			if _same_rect(block, INSTITUTE_BLOCK):
				CityPlaces.institute()
			elif _same_rect(block, HOME_BLOCK):
				CityPlaces.home_block(rng)
			elif _same_rect(block, PARK_BLOCK):
				CityPlaces.park_block()
			elif _same_rect(block, COURT_BLOCK):
				CityPlaces.court_block()
			else:
				_subdivide(rng, block, 0)
	_make_lanes(rng)
	_make_border(rng)
	CityLinks.link(seed_value)                  # cut-throughs and aligned crossings so the back streets form a network (own random stream)
	_make_backdrop(rng)
	CityModels.place()                          # the model buildings take their lots and stretches of the ring (no randomness)
	_pick_sites(rng)
	_make_obstacles(seed_value)
	# LETHE_PLAIN=1 (environment) skips everything the war-torn city added: a baseline for frame-time comparisons
	var plain := OS.get_environment("LETHE_PLAIN") != ""
	if not plain:
		CityWar.trees(seed_value)
	_make_cars(rng)
	if not plain:
		CityWar.wreck_cars(seed_value)
		CityWar.obstacles(seed_value)
		CityStory.dress(seed_value)
		CityWar.street_cover(seed_value)             # after the story dressing (which keeps its places): staggered cover on the 12 m streets
		CityClimb.plan(seed_value)
		CityBuildings.dress(seed_value)
		CityClimb.build(seed_value)
		CityPlaces.lookout_hall()                   # the sniper hall under the lookout roof (needs the fire escape CityClimb just built)
		var road_rng := RandomNumberGenerator.new()
		road_rng.seed = seed_value + 31
		CityRoads.build(road_rng)
	CityPlaces.build_pipes()                    # the drainpipes of the neighbourhood (after CityClimb.build cleared the ladders)
	_build_nav()
	if not plain:
		CityInteriors.plan(seed_value)               # needs the navigation grid (door fronts must be free); adds one inactive layer per enterable building
	_build_width_grid()
	_cum.resize(streets.size())
	var acc := 0.0
	for i in streets.size():
		var r: Rect2 = streets[i]["rect"]
		acc += spawn_weight(String(streets[i]["cls"]), r)
		_cum[i] = acc


static func _same_rect(a: Rect2, b: Rect2) -> bool:
	return a.position.is_equal_approx(b.position) and a.size.is_equal_approx(b.size)


## Spawn weight of a street: area x class weight, scaled up / down by how much of it lies in the zone between the
## Institute and the home (busy avenue, quiet footpaths and alleys).
static func spawn_weight(cls: String, r: Rect2) -> float:
	var w := r.get_area() * float(WEIGHTS[cls])
	if ROUTE_ZONE_MULT.has(cls) and r.get_area() > 0.0:
		var frac := r.intersection(ROUTE_ZONE).get_area() / r.get_area()
		w *= lerpf(1.0, float(ROUTE_ZONE_MULT[cls]), frac)
	return w


## Narrow lanes along the inside of the border ring, so the avenues meet a street instead of a wall. They are NOT one big
## ring road: each lane is cut into sections between the through streets, and some sections are filled with a building.
## Corner sections are always filled and two filled sections never touch, so every lane section ends at a street (you
## turn there, you never walk into a dead end) and every through street can reach a lane on at least one side.
static func _make_lanes(rng: RandomNumberGenerator) -> void:
	_lane_side(rng, AVENUE_X, -IN_X, IN_X, true, -IN_Z)       # north
	_lane_side(rng, AVENUE_X, -IN_X, IN_X, true, BZ)          # south
	_lane_side(rng, AVENUE_Z, -BZ, BZ, false, -IN_X)          # west
	_lane_side(rng, AVENUE_Z, -BZ, BZ, false, BX)             # east


## One lane. `lines` are the through streets crossing it, `lo..hi` the lane's extent along its axis, `along_x` whether
## it runs along x, and `edge` the coordinate of its outer-most side on the other axis.
static func _lane_side(rng: RandomNumberGenerator, lines: Array, lo: float, hi: float, along_x: bool, edge: float) -> void:
	# sections: the gaps between the through streets
	var secs: Array = []
	var prev := lo
	for v in lines:
		secs.append([prev, v - avenue_width(v) * 0.5])
		prev = v + avenue_width(v) * 0.5
	secs.append([prev, hi])
	var plug: Array = []
	for i in secs.size():
		plug.append(i == 0 or i == secs.size() - 1)
	for i in range(1, secs.size() - 1):
		if not plug[i - 1] and i + 1 != secs.size() - 1 and rng.randf() < 0.42:
			plug[i] = true
	for i in secs.size():
		var a: float = secs[i][0]
		var b: float = secs[i][1]
		if b - a < 1.0:
			continue
		var rect := Rect2(a, edge, b - a, LANE) if along_x else Rect2(edge, a, LANE, b - a)
		if plug[i]:
			var h := rng.randf_range(30.0, 75.0)
			var fp := rect.grow(0.2)
			var glass := rng.randf() < 0.4
			buildings.append({"rect": fp, "boxes": [{"rect": fp, "y0": 0.0, "y1": h}], "style": 0.5 if glass else 0.1,
				"color": _pick(rng, GLASS if glass else CONCRETE), "h": h, "plug": true})
		else:
			streets.append({"rect": rect, "cls": "walk"})


## The gaps between consecutive avenues (and to the playable edge).
static func _intervals(lines: Array, half: float) -> Array:
	var out: Array = []
	var prev := -half
	for v in lines:
		out.append([prev, v - avenue_width(v) * 0.5])
		prev = v + avenue_width(v) * 0.5
	out.append([prev, half])
	return out


static func _street_width(rng: RandomNumberGenerator, depth: int) -> float:
	var roll := rng.randf()
	if depth == 0:
		return 12.0 if roll < 0.12 else (6.0 if roll < 0.5 else 3.0)
	if depth == 1:
		return 12.0 if roll < 0.04 else (6.0 if roll < 0.42 else 3.0)
	return 6.0 if roll < 0.25 else 3.0


static func _class_of(width: float) -> String:
	return "avenue" if width >= 18.0 else ("street" if width >= 11.0 else ("walk" if width >= 5.0 else "alley"))


## Cut a block in two with a street across the whole of it, then do the same to both halves until they are lots.
static func _subdivide(rng: RandomNumberGenerator, r: Rect2, depth: int) -> void:
	var w := r.size.x
	var d := r.size.y
	var can_x := w >= MIN_LOT * 2.0 + 3.0
	var can_z := d >= MIN_LOT * 2.0 + 3.0
	var small := w <= MAX_LOT and d <= MAX_LOT
	if (not can_x and not can_z) or (small and rng.randf() < 0.25):
		_make_lot(rng, r)
		return
	var cut_x: bool
	if can_x and can_z:
		cut_x = (w > d) if rng.randf() < 0.8 else (w <= d)
	else:
		cut_x = can_x
	var sw := _street_width(rng, depth)
	var length := w if cut_x else d
	var first := roundf(length * rng.randf_range(0.35, 0.65) - sw * 0.5)
	var second := length - first - sw
	if first < MIN_LOT or second < MIN_LOT:
		_make_lot(rng, r)
		return
	var ra: Rect2
	var rs: Rect2
	var rb: Rect2
	if cut_x:
		ra = Rect2(r.position.x, r.position.y, first, d)
		rs = Rect2(r.position.x + first, r.position.y, sw, d)
		rb = Rect2(r.position.x + first + sw, r.position.y, second, d)
	else:
		ra = Rect2(r.position.x, r.position.y, w, first)
		rs = Rect2(r.position.x, r.position.y + first, w, sw)
		rb = Rect2(r.position.x, r.position.y + first + sw, w, second)
	streets.append({"rect": rs, "cls": _class_of(sw)})
	_subdivide(rng, ra, depth + 1)
	_subdivide(rng, rb, depth + 1)


static func _pick(rng: RandomNumberGenerator, palette: Array) -> Color:
	return (palette[rng.randi() % palette.size()] as Color).lerp(Color.WHITE, rng.randf_range(0.0, 0.12)).darkened(rng.randf_range(0.0, 0.12))


static func _shrink(r: Rect2, k: float) -> Rect2:
	var c := r.get_center()
	var s := r.size * k
	return Rect2(c - s * 0.5, s)


## A tall tower: stepped crown above 110 m, a spire above 200 m.
static func _tower_boxes(fp: Rect2, h: float) -> Array:
	var boxes: Array = []
	if h > 110.0:
		boxes.append({"rect": fp, "y0": 0.0, "y1": h * 0.62})
		boxes.append({"rect": _shrink(fp, 0.78), "y0": h * 0.62, "y1": h * 0.84})
		boxes.append({"rect": _shrink(fp, 0.52), "y0": h * 0.84, "y1": h})
		if h > 200.0:
			boxes.append({"rect": _shrink(fp, 0.08), "y0": h, "y1": h * 1.12})
	else:
		boxes.append({"rect": fp, "y0": 0.0, "y1": h})
	return boxes


const MAX_SQUARES := 4
const SQUARE_MIN := 22.0

static func _wants_square(rng: RandomNumberGenerator, r: Rect2) -> bool:
	if minf(r.size.x, r.size.y) < SQUARE_MIN:
		return false
	var n := 0
	for st in streets:
		if st["cls"] == "plaza":
			n += 1
	return n < MAX_SQUARES and rng.randf() < 0.3


static func _make_lot(rng: RandomNumberGenerator, r: Rect2) -> void:
	var fp := r.grow_individual(-rng.randf_range(0.0, 1.2), -rng.randf_range(0.0, 1.2), -rng.randf_range(0.0, 1.2), -rng.randf_range(0.0, 1.2))
	var c := r.get_center()
	var downtown := 1.0 - clampf(c.length() / 330.0, 0.0, 1.0)
	var tall_p := lerpf(0.18, 0.5, downtown)
	var roll := rng.randf()
	var low_side := minf(fp.size.x, fp.size.y)
	var h := 0.0
	var style := 0.1
	var col := _pick(rng, CONCRETE)
	var boxes: Array = []
	if roll < tall_p and low_side >= 18.0:
		# skyscraper; one in eight is absurdly tall
		h = rng.randf_range(220.0, 380.0) if rng.randf() < 0.125 else rng.randf_range(80.0, 190.0)
		var sr := rng.randf()
		style = 0.85 if sr < 0.6 else (0.5 if sr < 0.85 else 0.1)
		col = _pick(rng, GLASS if style > 0.7 else CONCRETE)
		boxes = _tower_boxes(fp, h)
	elif roll < tall_p + 0.28 and low_side >= 12.0:
		h = rng.randf_range(20.0, 70.0)
		style = 0.1 if rng.randf() < 0.5 else 0.5
		col = _pick(rng, BRICK if rng.randf() < 0.3 else CONCRETE)
		boxes.append({"rect": fp, "y0": 0.0, "y1": h * 0.8})
		if rng.randf() < 0.4:
			boxes.append({"rect": _shrink(fp, 0.7), "y0": h * 0.8, "y1": h})
	elif roll < tall_p + 0.28 + 0.36 or not _wants_square(rng, r):        # open squares have no cover: only a few big lots stay empty (the other landing craft settle there)
		h = rng.randf_range(4.2, 6.5)             # one floor: shops, garages, depots
		style = 0.1
		col = _pick(rng, BRICK if rng.randf() < 0.35 else CONCRETE)
		boxes.append({"rect": fp, "y0": 0.0, "y1": h})
	else:
		streets.append({"rect": r, "cls": "plaza"})   # an empty lot: small square
		return
	var b := {"rect": fp, "boxes": boxes, "style": style, "color": col, "h": h}
	buildings.append(b)
	lots.append({"b": b, "r": r})


## Buildings shoulder to shoulder around the whole map: nobody can leave, and avenues end in towers, not in a wall.
static func _make_border(rng: RandomNumberGenerator) -> void:
	var strips := [
		[Rect2(-OUT_X, -OUT_Z, OUT_X * 2.0, RING), true],
		[Rect2(-OUT_X, IN_Z, OUT_X * 2.0, RING), true],
		[Rect2(-OUT_X, -IN_Z, RING, IN_Z * 2.0), false],
		[Rect2(IN_X, -IN_Z, RING, IN_Z * 2.0), false],
	]
	for s in strips:
		var strip: Rect2 = s[0]
		var along_x: bool = s[1]
		var total := strip.size.x if along_x else strip.size.y
		var t := 0.0
		while t < total - 0.5:
			var seg := minf(rng.randf_range(24.0, 46.0), total - t)
			if total - t - seg < 20.0:
				seg = total - t         # no sliver at the end
			var fp: Rect2
			if along_x:
				fp = Rect2(strip.position.x + t - 0.2, strip.position.y, seg + 0.4, strip.size.y)
			else:
				fp = Rect2(strip.position.x, strip.position.y + t - 0.2, strip.size.x, seg + 0.4)
			var h := rng.randf_range(220.0, 340.0) if rng.randf() < 0.12 else rng.randf_range(55.0, 190.0)
			var glass := rng.randf() < 0.55
			buildings.append({"rect": fp, "boxes": _tower_boxes(fp, h), "style": 0.85 if glass else (0.5 if rng.randf() < 0.5 else 0.1),
				"color": _pick(rng, GLASS if glass else CONCRETE), "h": h, "border": true})
			t += seg


## Decorative towers beyond the border so the skyline continues.
static func _make_backdrop(rng: RandomNumberGenerator) -> void:
	for i in 130:
		var along_z := i % 2 == 0
		var out := rng.randf_range(34.0, 170.0)
		var pos: Vector2
		if along_z:
			pos = Vector2(rng.randf_range(-OUT_X - 150.0, OUT_X + 150.0), OUT_Z + out)
		else:
			pos = Vector2(OUT_X + out, rng.randf_range(-OUT_Z - 150.0, OUT_Z + 150.0))
		if i % 4 >= 2:
			pos = -pos
		var w := rng.randf_range(26.0, 70.0)
		var d := rng.randf_range(26.0, 70.0)
		var h := rng.randf_range(60.0, 220.0) if rng.randf() < 0.85 else rng.randf_range(250.0, 420.0)
		var rect := Rect2(pos.x - w * 0.5, pos.y - d * 0.5, w, d)
		var glass := rng.randf() < 0.6
		backdrop.append({"rect": rect, "boxes": [{"rect": rect, "y0": 0.0, "y1": h}], "style": 0.85 if glass else 0.1,
			"color": _pick(rng, GLASS if glass else CONCRETE), "h": h})


## Battle sites at some junctions far from the start, the origin and the goal.
static func _pick_sites(rng: RandomNumberGenerator) -> void:
	# one site always stands on the central avenue, the direct way home; the others are drawn from the open junctions
	for p in [Vector3(0.0, 0.0, 70.0)]:
		sites.append({"center": p, "radius": SITE_RADIUS})
	var cand: Array = []
	for x in AVENUE_X:
		for z in AVENUE_Z:
			if avenue_width(x) < 12.0 or avenue_width(z) < 12.0:
				continue          # need an open junction
			var p2 := Vector3(x, 0.0, z)
			if Vector2(p2.x, p2.z).length() < 1.0:
				continue          # the central junction stays quiet (the tests and the first screenshot use it)
			if p2.distance_to(START_POS) < 120.0 or p2.distance_to(HOME_POS) < 70.0 or p2.distance_to(PARK_POS) < 50.0 or p2.distance_to(COURT_POS) < 75.0:
				continue
			cand.append(p2)
	for i in range(cand.size() - 1, 0, -1):         # shuffle
		var j := rng.randi() % (i + 1)
		var tmp = cand[i]
		cand[i] = cand[j]
		cand[j] = tmp
	for p3 in cand:
		if sites.size() >= SITE_COUNT:
			break
		var far_enough := true
		for s in sites:
			if (s["center"] as Vector3).distance_to(p3) < 50.0:
				far_enough = false
		if far_enough:
			sites.append({"center": p3, "radius": SITE_RADIUS})


const OBSTACLE_COUNT := 3                  # hedgehog barricades around each battle site
const OBSTACLE_HALF := Vector2(2.4, 1.0)   # half size of one barricade's footprint at scale 1 (x along its length)

## Steel hedgehog barricades at the battle sites: a few arcs around the fire, tangent to a circle, never in the junction's
## middle (the soldiers stand there). Own random stream, so the rest of the city does not change.
static func _make_obstacles(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 4242
	for s in sites:
		var c: Vector3 = s["center"]
		var open := minf(minf(avenue_width(c.x), avenue_width(c.z)), 30.0) * 0.5      # the junction's half width
		var radius := clampf(open * 0.62, 4.0, 8.0)
		var a0 := rng.randf() * TAU
		for i in OBSTACLE_COUNT:
			var a := a0 + TAU * float(i) / float(OBSTACLE_COUNT) + rng.randf_range(-0.25, 0.25)
			var sc := rng.randf_range(0.85, 1.1)
			var p := Vector3(c.x + cos(a) * radius, 0.0, c.z + sin(a) * radius)
			var yaw := -a + PI * 0.5            # the long side runs along the circle
			var half := OBSTACLE_HALF * sc
			var bb := Basis().rotated(Vector3.UP, yaw)
			var ext := Vector2(absf(bb.x.x) * half.x + absf(bb.z.x) * half.y, absf(bb.x.z) * half.x + absf(bb.z.z) * half.y)
			obstacles.append({"pos": p, "yaw": yaw, "scale": sc, "half": half,
				"rect": Rect2(p.x - ext.x, p.z - ext.y, ext.x * 2.0, ext.y * 2.0)})

## Parked and abandoned vehicles along the avenue kerbs (never at junctions, battle sites, the start door or near the origin).
static func _make_cars(rng: RandomNumberGenerator) -> void:
	var palette := [Color(0.1, 0.1, 0.12), Color(0.75, 0.75, 0.78), Color(0.55, 0.1, 0.1), Color(0.15, 0.25, 0.45), Color(0.8, 0.7, 0.2),
		Color(0.3, 0.32, 0.34), Color(0.9, 0.9, 0.9), Color(0.12, 0.35, 0.25), Color(0.85, 0.4, 0.1), Color(0.35, 0.2, 0.45), Color(0.6, 0.6, 0.64)]
	var total_w := 0.0
	for ct in CAR_TYPES:
		total_w += float(ct["w"])
	for along_z in [true, false]:
		var lines: Array = AVENUE_X if along_z else AVENUE_Z
		var cross: Array = AVENUE_Z if along_z else AVENUE_X
		var lim := IN_Z if along_z else IN_X
		for line in lines:
			var w := avenue_width(line)
			if w < 12.0:
				continue        # footpaths stay free of cars
			for side in [-1.0, 1.0]:
				var t := -lim + rng.randf_range(10.0, 25.0)
				while t < lim - 10.0:
					var roll := rng.randf() * total_w
					var ct: Dictionary = CAR_TYPES[0]
					for c in CAR_TYPES:
						roll -= float(c["w"])
						ct = c
						if roll <= 0.0:
							break
					var size: Vector3 = ct["size"] * Vector3(rng.randf_range(0.95, 1.06), rng.randf_range(0.95, 1.06), rng.randf_range(0.95, 1.06))
					t += size.z * 0.5 + rng.randf_range(5.0, 26.0)
					var ok := true
					for cl in cross:
						if absf(t - cl) < avenue_width(cl) * 0.5 + 8.0 + size.z * 0.5:
							ok = false
					var off: float = side * (w * 0.5 - 1.25 - size.x * 0.5)
					var p := Vector2(line + off, t) if along_z else Vector2(t, line + off)
					for s in sites:
						var sc: Vector3 = s["center"]
						if Vector2(p.x - sc.x, p.y - sc.z).length() < float(s["radius"]) + 8.0:
							ok = false
					if Vector2(p.x - START_POS.x, p.y - 235.0).length() < 24.0 or Vector2(p.x - HOME_POS.x, p.y - HOME_POS.z).length() < 26.0:
						ok = false
					for ec in CityWar.extra_clear:          # the lookout's fire escape (and anything else planned by hand) keeps its ground free
						if (ec as Rect2).grow(3.0).has_point(p):
							ok = false
					if ok and p.length() > 30.0 and t < lim - 10.0 and rng.randf() < 0.75:
						var body: Color = palette[rng.randi() % palette.size()]
						var accent: Color = palette[rng.randi() % palette.size()]
						var car := {"pos": Vector3(p.x, 0.0, p.y), "type": ct["name"], "size": size,
							"yaw": (0.0 if along_z else PI * 0.5) + rng.randf_range(-0.05, 0.05) + (PI if rng.randf() < 0.5 else 0.0),
							"color": body, "accent": accent, "cargo": palette[rng.randi() % palette.size()].lerp(Color.WHITE, 0.3),
							"stripe": rng.randf() < 0.4, "two_tone": rng.randf() < 0.35, "along_z": along_z,
							"dmg": "", "roll": 0.0, "crush": 0.0, "doors": false, "burnt": false, "fire": false}
						CityWar.finish_car(car)
						cars.append(car)
					t += size.z * 0.5


# ---------------------------------------------------------------- navigation
## A grid is a Dictionary {a: AStarGrid2D, o: Vector2 (north-west corner), c: cell size, nx, nz}. Grid "main" covers the whole
## map with 1 m cells. LAYERS (the apartment, the cellar, the balcony) are finer grids stacked over / under it: each has a
## parent grid, a link point on the parent (`outer`), waypoints along the way in (`via`) and an entry point on the layer
## (`inner`). City.path() joins the pieces, so enemies can walk into the home and down the stairs although the map itself is flat.

static func _new_grid(rect: Rect2, cell: float, solid: bool = false) -> Dictionary:
	var nx := int(ceil(rect.size.x / cell - 0.001))
	var nz := int(ceil(rect.size.y / cell - 0.001))
	var a := AStarGrid2D.new()
	a.region = Rect2i(0, 0, nx, nz)
	a.cell_size = Vector2(cell, cell)
	a.offset = rect.position + Vector2(cell, cell) * 0.5       # points sit on cell centres
	a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	a.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	a.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	a.update()
	if solid:
		a.fill_solid_region(Rect2i(0, 0, nx, nz), true)
	return {"a": a, "o": rect.position, "c": cell, "nx": nx, "nz": nz}


## Mark the cells whose centre lies inside `r` grown by `margin` (negative = shrunk) as solid / free.
static func _g_set(g: Dictionary, r: Rect2, margin: float, solid: bool) -> void:
	var c: float = g["c"]
	var o: Vector2 = g["o"]
	var x0 := floori((r.position.x - margin - o.x) / c - 0.5) + 1
	var x1 := ceili((r.end.x + margin - o.x) / c - 0.5) - 1
	var z0 := floori((r.position.y - margin - o.y) / c - 0.5) + 1
	var z1 := ceili((r.end.y + margin - o.y) / c - 0.5) - 1
	x0 = maxi(x0, 0)
	z0 = maxi(z0, 0)
	x1 = mini(x1, int(g["nx"]) - 1)
	z1 = mini(z1, int(g["nz"]) - 1)
	if x1 >= x0 and z1 >= z0:
		(g["a"] as AStarGrid2D).fill_solid_region(Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1), solid)


static func _block(r: Rect2, margin: float) -> void:
	_g_set(_main_grid, r, margin, true)


static func _g_cell_raw(g: Dictionary, p: Vector3) -> Vector2i:
	var c: float = g["c"]
	var o: Vector2 = g["o"]
	return Vector2i(floori((p.x - o.x) / c), floori((p.z - o.y) / c))


static func _g_free(g: Dictionary, p: Vector3) -> bool:
	var a: AStarGrid2D = g["a"]
	var cell := _g_cell_raw(g, p)
	return a.is_in_boundsv(cell) and not a.is_point_solid(cell)


## The walkable cell nearest to p (p's own cell if it is free), or (-1, -1).
static func _g_free_cell(g: Dictionary, p: Vector3) -> Vector2i:
	var a: AStarGrid2D = g["a"]
	var c0 := _g_cell_raw(g, p)
	c0 = Vector2i(clampi(c0.x, 0, int(g["nx"]) - 1), clampi(c0.y, 0, int(g["nz"]) - 1))
	if not a.is_point_solid(c0):
		return c0
	var rmax := maxi(7, int(ceil(3.0 / float(g["c"]))))
	for r in range(1, rmax + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var q := c0 + Vector2i(dx, dz)
				if a.is_in_boundsv(q) and not a.is_point_solid(q):
					return q
	return Vector2i(-1, -1)


## Waypoints (cell centres, collinear ones dropped) from a to b inside one grid; null if there is no way (empty = same cell).
static func _g_path(g: Dictionary, from: Vector3, to: Vector3, y: float) -> Variant:
	var a := _g_free_cell(g, from)
	var b := _g_free_cell(g, to)
	if a.x < 0 or b.x < 0:
		return null
	var out := PackedVector3Array()
	if a == b:
		return out
	var ids: Array[Vector2i] = (g["a"] as AStarGrid2D).get_id_path(a, b)
	if ids.size() < 2:
		return null
	var c: float = g["c"]
	var o: Vector2 = g["o"]
	for i in range(1, ids.size()):
		var keep := i == ids.size() - 1
		if not keep:
			var d1: Vector2i = ids[i] - ids[i - 1]
			var d2: Vector2i = ids[i + 1] - ids[i]
			keep = d1 != d2
		if keep:
			out.append(Vector3(o.x + (ids[i].x + 0.5) * c, y, o.y + (ids[i].y + 0.5) * c))
	return out


static func _build_nav() -> void:
	_main_grid = _new_grid(Rect2(-OUT_X, -OUT_Z, OUT_X * 2.0, OUT_Z * 2.0), 1.0)
	_astar = _main_grid["a"]
	for b in buildings:
		for r in b.get("nav_rects", [b["rect"]]):
			_block(r, 0.5)
	for c in cars:
		_block(c["rect"], 0.4)
	for t in trees:
		var tp: Vector2 = t["pos"]
		_block(Rect2(tp.x - float(t["r"]), tp.y - float(t["r"]), float(t["r"]) * 2.0, float(t["r"]) * 2.0), 0.4)
	for ob in obstacles:
		_block(ob["rect"], 0.3)
	for bl in Scn.blocks:
		_block(bl["rect"], float(bl["margin"]))
	for pr in props:
		if String(pr["nav"]) == "main":
			_block(pr["rect"], 0.4)
	_build_layers()


static func _add_layer(lname: String, rect: Rect2, cell: float, ymin: float, ymax: float, y: float, parent: int,
		outer: Vector3, via: Array, inner: Vector3, open: Array, margin: float) -> int:
	var g := _new_grid(rect, cell, true)
	for fr in open:
		_g_set(g, fr, -margin, false)
	for pr in props:
		if String(pr["nav"]) == lname and float(pr["y0"]) < 0.5 and float(pr["y1"]) > 0.3:
			_g_set(g, pr["rect"], margin, true)
	layers.append({"name": lname, "rect": rect, "ymin": ymin, "ymax": ymax, "y": y, "parent": parent, "outer": outer,
		"via": via, "inner": inner, "grid": g})
	return layers.size() - 1


static func _build_layers() -> void:
	var o := HOME_ORIGIN
	# the apartment: finer cells so 1.2 m doorways stay open (margin 0.35 leaves 0.5 m for a body 0.7 m wide)
	var home := _add_layer("home", Rect2(15.8, o.y, HOME_IN.x + 0.6, HOME_IN.y), 0.25, -0.6, 2.8, 0.0, -1,
		Vector3(15.5, 0.0, o.y + 5.0 - 0.1), [Vector3(16.2, 0.0, o.y + 5.0)], Vector3(17.1, 0.0, o.y + 5.0),
		[Rect2(o, HOME_IN)], 0.35)
	# the cellar and the stairs down to it, linked at the top of the stairs
	_add_layer("cellar", Rect2(17.4, STAIR_HOLE.position.y, 6.0, CELLAR_RECT.end.y - STAIR_HOLE.position.y), 0.25, -4.0, -0.6, CELLAR_FLOOR_Y, home,
		CELLAR_DOOR_POS, [Vector3(20.2, -0.5, STAIR_HOLE.position.y + 0.4), Vector3(20.2, -1.6, STAIR_HOLE.position.y + 1.7), Vector3(20.2, -2.5, STAIR_HOLE.end.y - 0.5)],
		Vector3(20.2, CELLAR_FLOOR_Y, CELLAR_RECT.position.y + 0.5), [CELLAR_RECT, STAIR_HOLE.grow_individual(0.0, 0.0, 0.0, 0.0)], 0.25)
	# the balcony over the park, linked at the foot of the outside stairs
	_add_layer("balcony", BALCONY_RECT, 0.5, 2.5, 8.0, BALCONY_Y, -1,
		Vector3(66.5, 0.0, BALCONY_POS.z - 0.2), [Vector3(68.5, 1.1, BALCONY_POS.z), Vector3(70.5, 2.4, BALCONY_POS.z)],
		Vector3(72.7, BALCONY_Y, BALCONY_POS.z), [BALCONY_RECT], 0.4)
	_live = []
	for li in layers.size():
		_live.append(li)


## Which layer a point belongs to (-1 = the main grid).
static func layer_of(p: Vector3) -> int:
	for i in _live:
		var l: Dictionary = layers[i]
		if (l["rect"] as Rect2).has_point(Vector2(p.x, p.z)) and p.y >= float(l["ymin"]) and p.y <= float(l["ymax"]):
			return i
	return -1


## An interior's navigation grid: `rect` (the whole footprint, solid) with `inner` opened and `solids` (wall / prop rectangles) closed
## again with a margin, 0.5 m cells. Used by Interiors when the building is streamed in.
static func interior_grid(rect: Rect2, inner: Rect2, solids: Array, margin: float) -> Dictionary:
	var g := _new_grid(rect, 0.5, true)
	_g_set(g, inner, 0.0, false)
	for s in solids:
		_g_set(g, s as Rect2, margin, true)
	return g


## Switch an interior layer on (grid built) or off (grid freed). Layer indices never move, so nothing that stores one breaks.
static func interior_layer(i: int, grid: Dictionary) -> void:
	layers[i]["grid"] = grid
	if grid.is_empty():
		_live.erase(i)
	elif not _live.has(i):
		_live.append(i)


## A stand-alone navigation layer that is not joined to the street grid (the lander's inside, built far below the city by LanderInterior):
## `rect` in plan, `y_floor` the floor height. Returns its index; remove_story_layer() takes it out again.
static func add_story_layer(lname: String, rect: Rect2, y_floor: float, grid: Dictionary) -> int:
	layers.append({"name": lname, "rect": rect, "ymin": y_floor - 2.0, "ymax": y_floor + 6.0, "y": y_floor, "parent": -1,
		"outer": Vector3(1.0e6, 0.0, 1.0e6), "via": [], "inner": Vector3(1.0e6, 0.0, 1.0e6), "grid": grid})
	_live.append(layers.size() - 1)
	return layers.size() - 1


static func remove_story_layer(i: int) -> void:
	if i >= 0 and i < layers.size():
		_live.erase(i)
		layers[i]["grid"] = {}


## The nav-grid helpers LanderInterior needs (the grid functions are static and private to City by name only).
static func story_grid(rect: Rect2, cell: float) -> Dictionary:
	return _new_grid(rect, cell, true)


static func story_set(g: Dictionary, r: Rect2, margin: float, solid: bool) -> void:
	_g_set(g, r, margin, solid)


static func _grid_of(l: int) -> Dictionary:
	return _main_grid if l < 0 else layers[l]["grid"]


static func _y_of(l: int) -> float:
	return 0.0 if l < 0 else float(layers[l]["y"])


## Is layer a the same as b or one of b's ancestors?
static func _is_ancestor(a: int, b: int) -> bool:
	var cur := b
	while true:
		if cur == a:
			return true
		if cur < 0:
			return false
		cur = int(layers[cur]["parent"])
	return false


static func is_free(p: Vector3) -> bool:
	if _astar == null:
		return true
	return _g_free(_grid_of(layer_of(p)), p)


## Waypoints (cell centres, collinear ones dropped) from `from` to `to` around buildings, through doors and down stairs.
## Empty if there is no way.
static func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if _astar == null:
		return PackedVector3Array()
	var res: Variant = _route(from, to)
	return PackedVector3Array() if res == null else res


static func _route(from: Vector3, to: Vector3) -> Variant:
	var la := layer_of(from)
	var lb := layer_of(to)
	if la == lb:
		return _g_path(_grid_of(la), from, to, _y_of(la))
	var out := PackedVector3Array()
	if not _is_ancestor(la, lb):
		# walk to the layer's exit, step out, carry on from the parent's link point
		var l: Dictionary = layers[la]
		var up: Variant = _g_path(l["grid"], from, l["inner"], l["y"])
		if up == null:
			return null
		out.append_array(up)
		out.append(l["inner"])
		var via: Array = l["via"]
		for i in range(via.size() - 1, -1, -1):
			out.append(via[i])
		out.append(l["outer"])
		var rest: Variant = _route(l["outer"], to)
		if rest == null:
			return null
		out.append_array(rest)
		return out
	# la is an ancestor of lb: get to the link point on lb's parent, step in, walk on inside
	var lay: Dictionary = layers[lb]
	var down: Variant = _route(from, lay["outer"])
	if down == null:
		return null
	out.append_array(down)
	out.append(lay["outer"])
	for v in lay["via"]:
		out.append(v)
	out.append(lay["inner"])
	var inside: Variant = _g_path(lay["grid"], lay["inner"], to, lay["y"])
	if inside == null:
		return null
	out.append_array(inside)
	return out


## A free point at a random distance and direction around `center`, or Vector3.INF.
static func random_point_near(rng: RandomNumberGenerator, center: Vector3, rmin: float, rmax: float) -> Vector3:
	for i in 12:
		var a := rng.randf() * TAU
		var r := rng.randf_range(rmin, rmax)
		var p := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
		if absf(p.x) < IN_X - 3.0 and absf(p.z) < IN_Z - 3.0 and is_free(p):
			return p
	return Vector3.INF


## A random walkable spot at least `min_dist` from `avoid`; streets are picked by area x class weight,
## so wide avenues get most of the soldiers and alleys very few. Returns {pos, cls}.
## `only` limits the street classes ("avenue", "street", "walk", "alley", "plaza"); the result also names the street (`idx`).
static func random_spawn(rng: RandomNumberGenerator, avoid: Vector3, min_dist: float, only: Array = []) -> Dictionary:
	var total := _cum[_cum.size() - 1]
	for tries in (400 if not only.is_empty() else 80):
		var roll := rng.randf() * total
		var idx := 0
		while idx < _cum.size() - 1 and _cum[idx] < roll:
			idx += 1
		if not only.is_empty() and not only.has(String(streets[idx]["cls"])):
			continue
		var r: Rect2 = streets[idx]["rect"]
		var p := Vector3(rng.randf_range(r.position.x + 0.8, r.end.x - 0.8) if r.size.x > 1.6 else r.get_center().x, 0.0,
			rng.randf_range(r.position.y + 0.8, r.end.y - 0.8) if r.size.y > 1.6 else r.get_center().y)
		if absf(p.x) > IN_X - 6.0 or absf(p.z) > IN_Z - 6.0:
			continue
		if not is_free(p) or Vector2(p.x - avoid.x, p.z - avoid.z).length() < min_dist:
			continue
		return {"pos": p, "cls": streets[idx]["cls"], "idx": idx}
	return {"pos": Vector3(0.0, 0.0, -60.0), "cls": "avenue", "idx": -1}


## Share of the walkable ground inside the playable area that can be reached on foot from `from` (4-neighbour flood fill
## over the main grid). Anything below ~1 means walled-in pockets.
static func reachable_fraction(from: Vector3) -> float:
	var nx := int(OUT_X * 2.0)
	var nz := int(OUT_Z * 2.0)
	var start := _g_free_cell(_main_grid, from)
	if start.x < 0:
		return 0.0
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var stack: Array[Vector2i] = [start]
	seen[start.y * nx + start.x] = 1
	var reached := 0
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		reached += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + d
			if q.x < 0 or q.y < 0 or q.x >= nx or q.y >= nz:
				continue
			if seen[q.y * nx + q.x] == 1 or _astar.is_point_solid(q):
				continue
			seen[q.y * nx + q.x] = 1
			stack.append(q)
	var total := 0
	for z in range(int(OUT_Z - IN_Z), int(OUT_Z + IN_Z)):
		for x in range(int(OUT_X - IN_X), int(OUT_X + IN_X)):
			if not _astar.is_point_solid(Vector2i(x, z)):
				total += 1
	return float(reached) / maxf(1.0, float(total))


# ---------------------------------------------------------------- street width, alley mouths, patrol segments (soldier placement, hunter tuning)

static var _wgrid: PackedByteArray = PackedByteArray()      # 1 m cells over the whole map: the width in metres of the narrowest street rectangle there (0 = none)
static var _mouths: Array = []


static func _build_width_grid() -> void:
	var nx := int(OUT_X * 2.0)
	var nz := int(OUT_Z * 2.0)
	_wgrid.resize(nx * nz)
	_wgrid.fill(0)
	for st in streets:
		var r: Rect2 = st["rect"]
		var w := mini(255, int(roundf(minf(r.size.x, r.size.y))))
		for z in range(maxi(0, floori(r.position.y + OUT_Z)), mini(nz, ceili(r.end.y + OUT_Z))):
			for x in range(maxi(0, floori(r.position.x + OUT_X)), mini(nx, ceili(r.end.x + OUT_X))):
				var i := z * nx + x
				if _wgrid[i] == 0 or w < _wgrid[i]:
					_wgrid[i] = w
	_mouths = []


## The width (m) of the narrowest street at p, 0 when p is on no street rectangle (hand-built places, inside a building).
static func street_width_at(p: Vector3) -> float:
	var x := floori(p.x + OUT_X)
	var z := floori(p.z + OUT_Z)
	var nx := int(OUT_X * 2.0)
	if _wgrid.is_empty() or x < 0 or z < 0 or x >= nx or z >= int(OUT_Z * 2.0):
		return 0.0
	return float(_wgrid[z * nx + x])


## Where side streets and alleys (8.5 m or less) open onto a wider street: [{pos: Vector2 on the street's edge, out: Vector2 (into the wide street), width}].
static func alley_mouths() -> Array:
	if not _mouths.is_empty():
		return _mouths
	for st in streets:
		var r: Rect2 = st["rect"]
		var w := minf(r.size.x, r.size.y)
		if w > 8.5 or maxf(r.size.x, r.size.y) < 8.0:
			continue
		var along_x := r.size.x > r.size.y
		for end in 2:
			var d := Vector2(1.0 if end == 1 else -1.0, 0.0) if along_x else Vector2(0.0, 1.0 if end == 1 else -1.0)
			var edge := Vector2((r.end.x if end == 1 else r.position.x) if along_x else r.get_center().x, r.get_center().y if along_x else (r.end.y if end == 1 else r.position.y))
			var wide_w := 0.0
			for o in streets:
				var orr: Rect2 = o["rect"]
				if orr != r and orr.has_point(edge + d * 1.5):
					wide_w = maxf(wide_w, minf(orr.size.x, orr.size.y))
			if wide_w >= w + 2.5 and absf(edge.x) < IN_X - 4.0 and absf(edge.y) < IN_Z - 4.0:
				_mouths.append({"pos": edge, "out": d, "width": wide_w, "cls": st["cls"]})
	return _mouths


## Which stretch of street a point belongs to: the street rectangle plus the interval between two crossing through streets
## ("one patrol per 12 m street segment between two avenues").
static func segment_key(idx: int, p: Vector3) -> String:
	if idx < 0:
		return "-1"
	var r: Rect2 = streets[idx]["rect"]
	var az := r.size.y > r.size.x
	var lines: Array = AVENUE_Z if az else AVENUE_X
	var along := p.z if az else p.x
	var seg := 0
	for l in lines:
		if float(l) < along:
			seg += 1
	return "%d:%d" % [idx, seg]


## Is `p` within 2.5 m of a door or stair link (where a layer joins the street)? Paths there are followed closely.
static func near_link(p: Vector3) -> bool:
	for i in _live:
		var l: Dictionary = layers[i]
		for k in ["outer", "inner"]:
			var q: Vector3 = l[k]
			if absf(q.x - p.x) < 2.5 and absf(q.z - p.z) < 2.5:
				return true
	return false
