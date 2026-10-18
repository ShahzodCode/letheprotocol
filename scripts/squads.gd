class_name Squads
extends Node
## Squad regrouping. Every enemy has a `group` (campfire / roaming group). When an alerted group has lost at least 40% of the
## members it had when it became alerted and at least 3 survive, the survivors regroup: they run to a rally point (an open
## spot near their middle, at least 3 m from any wall), stand back to back facing outwards (the circle split evenly between
## them) and hold for 20 s, turning slowly inside their sector and shooting at the player on sight, but not chasing.
## The formation breaks when a grenade lands within 8 m of the rally point, when a member is killed, or when the 20 s are up:
## everybody runs to the nearest cover point and then the normal hunt goes on. While they hold, they talk over the radio
## (subtitles, a crackle) if the player is within 25 m.

const LOSS_FRACTION := 0.4
const MIN_SURVIVORS := 3
const HOLD_TIME := 20.0
const BREAK_GRENADE_DIST := 8.0
const WALL_CLEARANCE := 3.0
const RADIO_RANGE := 25.0
const CALM_RESET := 6.0              # seconds with nobody hunting before a group forgets it was alerted
const TICK := 0.25
const LINES := ["Close up! Watch the corners!", "Back to back! He is close!", "Eyes open, check your sector!", "Hold the line, don't let him flank us!",
	"Stay tight! Shoot anything that moves!", "He's picking us off, keep together!"]
const B2B_LINES := ["Watch the roofs!", "Eyes up! Check the roof edges!", "Nobody leaves this circle!", "He is up there somewhere, hold!", "Cover your sector, shoot anything that shows!"]
const HUNTING := [Enemy.State.ALERT, Enemy.State.CHASE, Enemy.State.ATTACK, Enemy.State.SHOOT, Enemy.State.HOLD]

var player: Player
var records := {}          # group id -> {initial, alerted, calm, cool}
var squads: Array = []     # active: {group, members, rally, t, line_t}
var _rng := RandomNumberGenerator.new()
var _acc := 0.0


func setup(p: Player) -> void:
	player = p
	_rng.randomize()
	Game.grenade_landed.connect(_on_grenade_landed)


func reset() -> void:
	records.clear()
	squads.clear()


func is_holding(e: Enemy) -> bool:
	for sq in squads:
		if e in sq["members"]:
			return true
	return false


func _physics_process(delta: float) -> void:
	if player == null or Game.dead:
		return
	_acc += delta
	if _acc >= TICK:
		var dt := _acc
		_acc = 0.0
		_watch_groups(dt)
	for sq in squads.duplicate():
		sq["t"] += delta
		var broken: bool = float(sq["t"]) >= HOLD_TIME and sq.get("kind", "") != "b2b"        # the courtyard variant holds until its members are dead
		var persist: bool = sq.get("persist", false)         # a scripted squad (the park guards) keeps going when one of them dies
		var alive: Array = []
		for m in sq["members"]:
			if not is_instance_valid(m) or (m as Enemy).state == Enemy.State.DEAD:
				if not persist:
					broken = true         # one of them was killed
			else:
				alive.append(m)
		if persist:
			sq["members"] = alive
			if alive.is_empty():
				broken = true
		if broken:
			_break(sq)
			continue
		_radio(sq, delta)


func _watch_groups(dt: float) -> void:
	var groups := {}
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and en.state != Enemy.State.DEAD and en.group >= 0:
			if not groups.has(en.group):
				groups[en.group] = []
			groups[en.group].append(en)
	for gid in groups:
		var members: Array = groups[gid]
		var rec: Dictionary = records.get(gid, {"initial": 0, "alerted": false, "calm": 0.0, "cool": false})
		var hunting := false
		for m in members:
			if (m as Enemy).state in HUNTING:
				hunting = true
		if hunting:
			rec["calm"] = 0.0
			if not rec["alerted"]:
				rec["alerted"] = true
				rec["initial"] = members.size()       # how many it had when it became alerted
		else:
			rec["calm"] += dt
			if rec["calm"] > CALM_RESET:
				rec["alerted"] = false
				rec["cool"] = false
		records[gid] = rec
		if rec["alerted"] and not rec["cool"] and not _squad_of(gid) and members.size() >= MIN_SURVIVORS:
			var lost: int = int(rec["initial"]) - members.size()
			if float(lost) >= LOSS_FRACTION * float(rec["initial"]) - 0.001:
				_form(gid, members)


func _squad_of(gid: int) -> Dictionary:
	for sq in squads:
		if sq["group"] == gid:
			return sq
	return {}


## An open point near the middle of the survivors, at least 3 m from walls (every point on a 3 m ring is walkable too).
func find_rally(members: Array) -> Vector3:
	var c := Vector3.ZERO
	for m in members:
		c += (m as Enemy).global_position
	c /= float(members.size())
	c.y = 0.0
	var cands: Array = [c]
	for i in 50:
		var p := City.random_point_near(_rng, c, 1.0, 14.0)
		if p != Vector3.INF:
			cands.append(p)
	for p2 in cands:
		if _open(p2):
			return p2
	return Vector3.INF


func _open(p: Vector3) -> bool:
	if not City.is_free(p):
		return false
	for i in 8:
		var a := TAU * float(i) / 8.0
		if not City.is_free(p + Vector3(cos(a), 0, sin(a)) * WALL_CLEARANCE):
			return false
	return true


func _form(gid: int, members: Array) -> void:
	var rally := find_rally(members)
	if rally == Vector3.INF:
		return
	var n := members.size()
	# survivors take their places in the circle in the order they stand around the rally point: nobody crosses over
	var sorted := members.duplicate()
	sorted.sort_custom(func(a, b) -> bool:
		var da: Vector3 = (a as Enemy).global_position - rally
		var db: Vector3 = (b as Enemy).global_position - rally
		return atan2(da.z, da.x) < atan2(db.z, db.x))
	var base := _rng.randf() * TAU
	var radius := maxf(1.0, float(n) * 0.75 / TAU)
	for i in n:
		var a := base + TAU * float(i) / float(n)
		var o := Vector3(cos(a), 0, sin(a))
		var face := atan2(-o.x, -o.z)        # yaw whose forward vector (-sin, -cos) is the outward direction
		(sorted[i] as Enemy).hold_order(rally + o * radius, face, TAU / float(n))
	squads.append({"group": gid, "members": sorted, "rally": rally, "t": 0.0, "line_t": 0.5})


## BACK_TO_BACK, the courtyard variant ("The Lander", part two): `members` stand in a circle of radius `radius` round `centre`, each facing outwards and
## guarding his own sector, and HOLD there for good: no 20 s limit, no breaking when one of them dies, no break for a grenade landing near (the
## player's grenades are the whole point of the place). They never chase; they shoot (or strike) at anyone they see, which includes a head over a
## roof edge. Persistent: the record keeps going until nobody is left. Walking in takes as long as it takes (`hold_walk_max`).
func form_back_to_back(members: Array, centre: Vector3, radius: float = 2.2) -> Dictionary:
	var n := members.size()
	if n == 0:
		return {}
	var sorted := members.duplicate()
	sorted.sort_custom(func(a, b) -> bool:
		var da: Vector3 = (a as Enemy).global_position - centre
		var db: Vector3 = (b as Enemy).global_position - centre
		return atan2(da.z, da.x) < atan2(db.z, db.x))
	var base := 0.3
	for i in n:
		var a := base + TAU * float(i) / float(n)
		var o := Vector3(cos(a), 0, sin(a))
		var en := sorted[i] as Enemy
		en.hold_walk_max = 60.0
		en.confused = false
		en.hold_order(centre + o * radius, atan2(-o.x, -o.z), TAU / float(n))
	var sq := {"group": -2, "members": sorted, "rally": centre, "t": 0.0, "line_t": 1.5, "persist": true, "kind": "b2b"}
	squads.append(sq)
	return sq


func back_to_back_of(e: Enemy) -> Dictionary:
	for sq in squads:
		if sq.get("kind", "") == "b2b" and e in sq["members"]:
			return sq
	return {}


func _break(sq: Dictionary) -> void:
	squads.erase(sq)
	var rec: Dictionary = records.get(sq["group"], {})
	if not rec.is_empty():
		rec["cool"] = true
	for m in sq["members"]:
		var en := m as Enemy
		if is_instance_valid(en) and en.state == Enemy.State.HOLD:
			en.hold_scatter(cover_point(en, sq["rally"]))


## The nearest spot that the player cannot see (a ray from his eyes to it is blocked), 3 - 12 m from the soldier;
## failing that a point straight away from the rally point.
func cover_point(en: Enemy, rally: Vector3) -> Vector3:
	var space := en.get_world_3d().direct_space_state
	var eye := player.camera.global_position
	var best := Vector3.INF
	var best_d := 1.0e9
	for i in 24:
		var p := City.random_point_near(_rng, en.global_position, 3.0, 12.0)
		if p == Vector3.INF:
			continue
		var d := en.global_position.distance_to(p)
		if d >= best_d:
			continue
		var hidden := not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, p + Vector3(0, 1.2, 0), Game.L_WORLD)).is_empty()
		if hidden:
			best = p
			best_d = d
	if best != Vector3.INF:
		return best
	var away := en.global_position - rally
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.RIGHT
	var fallback := en.global_position + away * 10.0
	return fallback if City.is_free(fallback) else en.global_position


func _on_grenade_landed(pos: Vector3) -> void:
	for sq in squads.duplicate():
		if sq.get("kind", "") != "b2b" and Vector2(pos.x - sq["rally"].x, pos.z - sq["rally"].z).length() < BREAK_GRENADE_DIST:
			_break(sq)


func _radio(sq: Dictionary, delta: float) -> void:
	var rally: Vector3 = sq["rally"]
	if Vector2(player.global_position.x - rally.x, player.global_position.z - rally.z).length() > RADIO_RANGE:
		return
	sq["line_t"] -= delta
	if sq["line_t"] <= 0.0:
		sq["line_t"] = _rng.randf_range(3.5, 5.5)
		var pool: Array = B2B_LINES if sq.get("kind", "") == "b2b" else LINES
		Game.radio_line.emit(pool[_rng.randi() % pool.size()])
		Sfx.play(player, "radio", -10.0)
