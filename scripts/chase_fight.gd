class_name ChaseFight
extends Node
## "The Lander", part two (IX): the running fight through Noah's neighbourhood, the grenade courtyard and the arm wound.
##   CHASE   (objective ESCAPE INTO THE LANES, then TAKE THE STRAGGLERS' GRENADES) six of the guards of the ramp hunt the player from the balcony.
##           Two of them are stragglers (role "straggler": they drain stamina 2.4 times faster, start half winded, can be knifed from behind while
##           they gasp, and drop two grenades each that stay until taken); the other four are "chaser"s. The lanes are the player's ground: a soldier
##           in a 3 m alley sees only 55% as far and needs 0.7 s to take in what he sees (`Enemy.sight_scale` / `seen_delay`), at a corner of the
##           path he waits for the men behind him (bunching: `Enemy.pace` 0 for 1.4 s), and when they lose him the chasers split up, each to a different
##           search point (`Enemy.last_known`).
##   COURT   (CLEAR THE COURTYARD) the four chasers stop splitting up and walk to the courtyard of the block (City.COURT_RECT): role "courtyard", one
##           Squads record of kind "b2b" (Squads.form_back_to_back): a circle, each guarding a sector, never chasing, shooting on sight, a head over
##           the roof edge included. The player climbs the drainpipe to the low roof over the courtyard and throws grenades. When two or fewer are
##           left (the grenades did their work) they are wounded (28 HP) and the next shot one of them fires at the player hits the right arm:
##           `Weapons.wound_arm()` (rifle dropped, no rifle / knife, pistol in the left hand, wide spread, slow reload, slower walk, blood drips).
##   FINISH  (FINISH THEM) one grenade is guaranteed; thrown with the left hand into the courtyard it kills whoever is left (a scripted death 0.6 s
##           after the blast for anyone alive within 11 m of the centre). Then the objective is the open ramp of the lander.
## Everything is plain Enemy nodes with roles that Main re-applies after a checkpoint restore; `sync()` puts this controller back in step.

enum Phase { IDLE, CHASE, COURT, FINISH, DONE }

const CHASER_COUNT := 6
const STRAGGLER_COUNT := 2
const COURT_SOLDIERS := 4
const TICK := 0.25
const NARROW_WIDTH := 4.5            # an alley this narrow (or narrower) is the player's ground
const NARROW_SIGHT := 0.55
const NARROW_DELAY := 0.7
const OPEN_DELAY := 0.15
const BUNCH_WAIT := 1.4
const BUNCH_COOLDOWN := 4.5
const SPLIT_UNSEEN := 1.2
const SPLIT_COOLDOWN := 12.0
const STRAGGLER_FATIGUE := 2.4
const STRAGGLER_STAMINA := 0.5       # fraction of his stamina he starts with
const STRAGGLER_GRENADES := 2
const GRENADES_NEEDED := 3
const GATHER_AFTER := 30.0           # seconds of chase before the chasers who lost him walk to the courtyard on their own
const WOUND_DAMAGE := 12.0
const WOUNDED_HEALTH := 28.0
const WOUND_MAX_ALIVE := 2           # with this few left the next shot at the player is the wound
const FINISH_RADIUS := 11.0
const FINISH_DELAY := 0.6
const CHASER_ROLES := ["chaser", "straggler"]
const COURT_ROLES := ["courtyard", "courtyard_last"]
const LAST_SCALE := 0.4               # the two "last men" (behind the crates) take 40% of a blast: one grenade rarely kills them, two do

var main
var phase := Phase.IDLE
var wound_ready := false
var _acc := 0.0
var _t := 0.0
var _bunch := {}                     # uid -> {wait, cd}
var _split_cd := {}                  # uid -> seconds until he may be sent off again
var _no_los := {}                    # uid -> seconds a wounded courtyard man has had no line to the player
var _say_cd := 0.0
var _finish_t := -1.0
var _marker_at := Vector3.INF
var _rng := RandomNumberGenerator.new()


func setup(m) -> void:
	main = m
	_rng.randomize()
	Game.enemy_fired.connect(_on_fired)
	Game.exploded.connect(_on_exploded)


# ---------------------------------------------------------------- who is who

func _role(e: Enemy) -> String:
	return String(main.story_roles.get(e.uid, ""))


func members(roles: Array) -> Array:
	var out: Array = []
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and en.state != Enemy.State.DEAD and _role(en) in roles:
			out.append(en)
	return out


func chasers() -> Array:
	return members(CHASER_ROLES)


func court() -> Array:
	return members(COURT_ROLES)


func stragglers() -> Array:
	return members(["straggler"])


# ---------------------------------------------------------------- start of the chase

## ESCAPE INTO THE LANES starts: six of the ramp's guards turn into the chasers (the rest go back into the ship), two grenades lie on the low roof.
func begin() -> void:
	var pp: Vector3 = main.player.global_position
	var guards: Array = main.park_fight.guards()
	guards.sort_custom(func(a, b) -> bool: return a.global_position.distance_squared_to(pp) < b.global_position.distance_squared_to(pp))
	var keep: Array = guards.slice(0, CHASER_COUNT)
	for g in guards.slice(CHASER_COUNT):          # more than six are left: the surplus stays with the ship (gone from the world)
		main.story_roles.erase(g.uid)
		Game.enemies.erase(g)
		g.queue_free()
	var spots := CityStory.guard_spots()
	var k := 0
	while keep.size() < CHASER_COUNT and not spots.is_empty():          # fewer than six left (the player killed many): reinforcements from the ramp
		keep.append(main._spawn_enemy_at(spots[k % spots.size()]["pos"], "soldier"))
		k += 1
	var soldiers: Array = keep.filter(func(e): return (e as Enemy).kind == "soldier")
	soldiers.sort_custom(func(a, b) -> bool: return a.global_position.distance_squared_to(pp) > b.global_position.distance_squared_to(pp))
	var lag: Array = soldiers.slice(0, STRAGGLER_COUNT)
	for e in keep:
		main._assign_role(e, "straggler" if e in lag else "chaser")
		_hunt(e)
	main.park_fight.dismiss()
	for sp in CityStory.court_stash():          # a cache of two grenades on the low roof, so there are always some
		var pk := Pickup.spawn_grenade(main, sp)
		pk.global_position = sp
		pk.keep = true
	phase = Phase.CHASE
	wound_ready = false
	_t = 0.0
	_bunch.clear()
	_split_cd.clear()
	_no_los.clear()
	_say("THEY ARE COMING! AFTER HIM!")


## Hunting the player, right now (also after a checkpoint restore, which rebuilds everybody calm).
func _hunt(e: Enemy) -> void:
	e.post = false
	e.confused = false
	e.noticed_self = true
	e.state = Enemy.State.CHASE
	e.last_known = main.player.global_position
	e.unseen_t = 0.0
	e.alert_t = 0.0
	e.burst_left = 0
	e.nav_goal = Vector3.INF


## After a checkpoint restore: the controller goes back to the phase of the objective the player is on.
func sync() -> void:
	wound_ready = false
	_finish_t = -1.0
	_bunch.clear()
	_split_cd.clear()
	_no_los.clear()
	phase = Phase.IDLE
	if Game.sandbox or main.mission == null:
		return
	var id := String(main.mission.active().get("id", "")) if not main.mission.finished else ""
	match id:
		"escape_lanes", "take_grenades":
			phase = Phase.CHASE
			for e in chasers():
				_hunt(e)
		"clear_courtyard", "finish_them":
			phase = Phase.COURT if id == "clear_courtyard" else Phase.FINISH
			var mem := court()
			if mem.is_empty() and id == "clear_courtyard":
				phase = Phase.CHASE
				gather()
			elif not mem.is_empty():
				main.squads.form_back_to_back(mem, CityStory.court_pos())
			for e2 in stragglers():
				_hunt(e2)
		"ramp":
			phase = Phase.DONE


# ---------------------------------------------------------------- the courtyard

## The chasers who are left walk to the courtyard and stand back to back; missing ones are made up to four (they step out of the gates).
func gather() -> void:
	if phase == Phase.COURT or phase == Phase.FINISH or phase == Phase.DONE:
		return
	var mem: Array = members(["chaser"])
	var ring := CityStory.court_ring(COURT_SOLDIERS)
	var k := 0
	while mem.size() < COURT_SOLDIERS:
		var e: Enemy = main._spawn_enemy_at(ring[k % ring.size()] + Vector3(0.0, 0.0, 0.0), "soldier")
		mem.append(e)
		k += 1
	for i2 in mem.size():
		var e2: Enemy = mem[i2]
		main._assign_role(e2, "courtyard_last" if i2 >= mem.size() - 2 else "courtyard")          # the last two are the ones the first grenade leaves alive
		e2.pace = 1.0
		e2.seen_delay = 0.0
		e2.sight_scale = 1.0
	main.squads.form_back_to_back(mem, CityStory.court_pos())
	phase = Phase.COURT
	wound_ready = false
	_say("FALL BACK! THE COURTYARD! BACK TO BACK!")


## FINISH THEM starts: make sure there is a grenade to throw.
func on_finish_start() -> void:
	if Game.grenades <= 0:
		var fwd: Vector3 = -main.player.global_transform.basis.z
		fwd.y = 0.0
		var at: Vector3 = main.player.global_position + fwd.normalized() * 1.2
		var pk := Pickup.spawn_grenade(main, at)
		pk.global_position = Vector3(at.x, main.player.global_position.y + 0.05, at.z)        # on the roof the player stands on, not on the ground below
		pk.keep = true
		main.player.weapons.notice = "ONE GRENADE LEFT, JUST AHEAD"
		main.player.weapons.notice_t = 3.0
	phase = Phase.FINISH


func _say(text: String) -> void:
	Game.radio_line.emit(text)
	Sfx.play(main.player, "radio", -10.0)


# ---------------------------------------------------------------- the tick

func _physics_process(delta: float) -> void:
	if main == null or Game.dead or phase == Phase.IDLE or phase == Phase.DONE:
		return
	if _finish_t >= 0.0:
		_finish_t -= delta
		if _finish_t < 0.0:
			_finish_now()
	_acc += delta
	if _acc < TICK:
		return
	var dt := _acc
	_acc = 0.0
	_t += dt
	_say_cd = maxf(0.0, _say_cd - dt)
	match phase:
		Phase.CHASE:
			_tick_chase(dt)
		Phase.COURT:
			_tick_court()
		Phase.FINISH:
			_tick_finish()
	_marker()


func _tick_chase(dt: float) -> void:
	var list := chasers()
	for uid in _split_cd.keys():
		_split_cd[uid] = maxf(0.0, float(_split_cd[uid]) - dt)
	for e in list:
		var narrow := is_narrow(e.global_position)
		e.sight_scale = NARROW_SIGHT if narrow else 1.0
		e.seen_delay = NARROW_DELAY if narrow else OPEN_DELAY
		_bunch_step(e, narrow, list, dt)
	_split(list)
	# when they have lost him for good (and the first half minute is over) the four walk to the courtyard on their own
	var id := String(main.mission.active().get("id", "")) if main.mission != null and not main.mission.finished else ""
	if id == "clear_courtyard":
		gather()
	elif id == "take_grenades" and _t > GATHER_AFTER:
		var lost := true
		var n := 0
		for e2 in members(["chaser"]):
			n += 1
			if e2.state == Enemy.State.CHASE and e2.unseen_t < 6.0 or e2.state in [Enemy.State.SHOOT, Enemy.State.ATTACK, Enemy.State.ALERT]:
				lost = false
		if n >= 2 and lost:
			gather()


## Is this spot in a narrow lane (an alley of at most NARROW_WIDTH metres)?
func is_narrow(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	for st in City.streets:
		var r: Rect2 = st["rect"]
		if r.has_point(q):
			return st["cls"] == "alley" and minf(r.size.x, r.size.y) <= NARROW_WIDTH
	return false


## Bunching: a chaser who is out of sight of the player, in an alley, at a bend of his path with a man well behind him, waits for BUNCH_WAIT seconds.
func _bunch_step(e: Enemy, narrow: bool, list: Array, dt: float) -> void:
	var st: Dictionary = _bunch.get(e.uid, {"wait": 0.0, "cd": 0.0})
	st["cd"] = maxf(0.0, float(st["cd"]) - dt)
	if e.state != Enemy.State.CHASE or e.seen_now or e.straggler:
		st["wait"] = 0.0
		e.pace = 1.0
	elif float(st["wait"]) > 0.0:
		st["wait"] = float(st["wait"]) - dt
		e.pace = 0.0
		if float(st["wait"]) <= 0.0:
			e.pace = 1.0
			st["cd"] = BUNCH_COOLDOWN
	elif narrow and float(st["cd"]) <= 0.0 and _at_corner(e) and _man_behind(e, list):
		st["wait"] = BUNCH_WAIT
		e.pace = 0.0
	else:
		e.pace = 1.0
	_bunch[e.uid] = st


func _at_corner(e: Enemy) -> bool:
	var path := e.nav_path
	var i := e.nav_i
	if i >= path.size() - 1:
		return false
	var pos := e.global_position
	var a := Vector2(path[i].x - pos.x, path[i].z - pos.z)
	var b := Vector2(path[i + 1].x - path[i].x, path[i + 1].z - path[i].z)
	if a.length() > 3.5 or a.length() < 0.01 or b.length() < 0.01:
		return false
	return absf(a.angle_to(b)) > 0.9


func _man_behind(e: Enemy, list: Array) -> bool:
	var goal_d := e.global_position.distance_to(e.last_known)
	for o in list:
		var oe := o as Enemy
		if oe == e or oe.straggler:
			continue
		var d := oe.global_position.distance_to(e.global_position)
		if d > 6.0 and d < 30.0 and oe.global_position.distance_to(e.last_known) > goal_d:
			return true
	return false


## They lost him: each of them goes to a different place to look (the next search point is far from the points the others got).
func _split(list: Array) -> void:
	var cands: Array = []
	for e in list:
		var en := e as Enemy
		if not en.straggler and en.state == Enemy.State.CHASE and en.unseen_t > SPLIT_UNSEEN and float(_split_cd.get(en.uid, 0.0)) <= 0.0:
			cands.append(en)
	if cands.size() < 2:
		return
	var assigned: Array = []
	for en2 in cands:
		var best := Vector3.INF
		var best_score := -1.0
		for k in 10:
			var p := City.random_point_near(_rng, en2.global_position, 12.0, 36.0)
			if p == Vector3.INF:
				continue
			var score := 100.0
			for a in assigned:
				score = minf(score, p.distance_to(a))
			if score > best_score:
				best_score = score
				best = p
		if best != Vector3.INF:
			en2.last_known = best
			en2.unseen_t = 0.0
			en2.nav_goal = Vector3.INF
			assigned.append(best)
			_split_cd[en2.uid] = SPLIT_COOLDOWN
	if not assigned.is_empty() and _say_cd <= 0.0:
		_say_cd = 10.0
		_say("SPLIT UP! CHECK THE ALLEYS!")


func _tick_court() -> void:
	var alive := court()
	if not Game.arm_injured:
		if not wound_ready and alive.size() <= WOUND_MAX_ALIVE:
			wound_ready = true                      # the grenades did their work: the ones who are left are hurt
			for e in alive:
				(e as Enemy).health = minf((e as Enemy).health, WOUNDED_HEALTH)
				(e as Enemy).damage_scale = 1.0
		if wound_ready and alive.is_empty():
			_wound(null)                           # the last man falls with a burst that catches the arm anyway
		elif wound_ready:
			# a wounded man the blast threw against the wall under the roof edge cannot see the roof: after 2.5 s without a line he drags himself
			# back to the middle of the courtyard, facing the roof the player is on
			for e2 in alive:
				var en := e2 as Enemy
				var t := float(_no_los.get(en.uid, 0.0))
				t = 0.0 if en._los_to_player() else t + TICK
				if t >= 2.5 and en.state == Enemy.State.HOLD:
					var spot := CityStory.court_pos() + Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
					var d: Vector3 = main.player.global_position - spot
					en.hold_walk_max = 60.0
					en.hold_order(spot, atan2(-d.x, -d.z), TAU / 3.0)
					t = -4.0
				_no_los[en.uid] = t


func _tick_finish() -> void:
	if court().is_empty():
		Mission.complete("finish_them")
		phase = Phase.DONE


func _on_fired(e) -> void:
	if phase != Phase.COURT or not wound_ready or Game.arm_injured:
		return
	var en := e as Enemy
	if not is_instance_valid(en) or not (_role(en) in COURT_ROLES):
		return
	if en.global_position.distance_to(main.player.global_position) > 45.0:
		return
	_wound(en)


## The story wound: the right arm is hit.
func _wound(shooter: Enemy) -> void:
	wound_ready = false
	phase = Phase.FINISH
	var pl: Player = main.player
	var from: Vector3 = shooter.global_position if shooter != null else CityStory.court_pos()
	pl.weapons.wound_arm()
	pl.take_damage(clampf(WOUND_DAMAGE, 0.0, maxf(pl.health - 1.0, 0.0)), from)
	pl.add_shake(18.0)
	Sfx.play(pl, "pain", -2.0)
	pl.place_drip(pl.global_position)
	Game.arm_wounded.emit()
	Mission.complete("clear_courtyard")


## A grenade went off: if it was in the courtyard during FINISH THEM, nobody who is left there survives it.
func _on_exploded(pos: Vector3) -> void:
	if phase == Phase.FINISH and Game.arm_injured and Vector2(pos.x - City.COURT_POS.x, pos.z - City.COURT_POS.z).length() < FINISH_RADIUS:
		_finish_t = FINISH_DELAY


func _finish_now() -> void:
	for e in court():
		var en := e as Enemy
		var away := en.global_position - City.COURT_POS
		away.y = 0.0
		en.take_hit(999.0, "body", (away.normalized() if away.length() > 0.1 else Vector3.FORWARD) * 6.0, en.takedown_point())


## The marker over TAKE THE STRAGGLERS' GRENADES follows the nearest straggler, else the nearest grenade lying on the ground.
func _marker() -> void:
	if main.mission == null or main.mission.finished or String(main.mission.active().get("id", "")) != "take_grenades":
		return
	var pp: Vector3 = main.player.global_position
	var best := Vector3.INF
	var best_d := INF
	for e in stragglers():
		var d: float = e.global_position.distance_squared_to(pp)
		if d < best_d:
			best_d = d
			best = e.global_position
	if best == Vector3.INF:
		for pk in Game.pickups:
			if is_instance_valid(pk) and (pk as Pickup).is_grenade:
				var d2 := (pk as Pickup).global_position.distance_squared_to(pp)
				if d2 < best_d:
					best_d = d2
					best = (pk as Pickup).global_position
	if best == Vector3.INF:
		best = CityStory.pipe_foot()
	if _marker_at == Vector3.INF or best.distance_to(_marker_at) > 4.0:
		_marker_at = best
		main.world.set_marker_target(best)
