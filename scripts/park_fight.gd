class_name ParkFight
extends Node
## "The Lander", part one: the ten guards at the foot of the landing craft's ramp and what they do when the player shoots from the balcony.
##   CALM    the guards stand at their posts (`post`), facing outwards. They see the player only with their own eyes (a crouched player in
##           the shadow of the rail is not seen at 30 m), like any soldier.
##   SEARCH  the first shot (any shot heard from the balcony: the LR-9 is heard 76 m away) puts all of them into a loose circle round the ramp, a
##           scripted Squads record: HOLD, each sweeping a wide sector, shouting. They are `confused`: they cannot place the shot and see the
##           player only within 12 m. Killing one of them does not break it. Whoever catches the muzzle flash (clear line, inside his wide
##           field of view, 110 m, one chance in two per guard and shot) gives the balcony away.
##   CHARGE  the muzzle flash was seen, or the 20 s of the squad are over (Squads.HOLD_TIME), or a guard noticed the player on his own:
##           the circle breaks (Squads._break: they run to the nearest cover, then CHASE to where the player is) and they flush him out.
## Nothing here is scripted to miss or hit: the shell flies like any other (Weapons.shell_trace); the guards are plain Enemy nodes with
## roles ("park_guard") that Main re-applies after a checkpoint restore (`reset()` then puts this controller back to its calm start).

enum Phase { IDLE, CALM, SEARCH, CHARGE }

const GUARD_GROUP := 200
const GUARD_KINDS := ["soldier", "soldier", "soldier", "soldier", "soldier", "soldier", "soldier", "soldier", "rifleman", "rifleman"]
const FLASH_RANGE := 110.0
const FLASH_CONE := 150.0            # degrees: how wide a guard's attention is when he catches a flash at the edge of his eye
const FLASH_CHANCE := 0.5
const CHARGE_DELAY := 1.0            # shouting, then running: seconds between "the flash was seen" and the circle breaking
const KILLS_TO_CONTINUE := 3         # the objective "THIN OUT THE GUARDS" is done after this many dead guards
const CLOSE_HINT_RANGE := 11.0       # a hunter this close while the long rifle is in hand: a toast says switch to the pistol
const TICK := 0.25
const TRACK_TIME := 14.0             # after the charge begins they keep knowing where the balcony is (the flash gave it away) for this long
const LINES_SEARCH := ["SNIPER! GET DOWN!", "WHERE IS HE?! WHERE IS HE?!", "CHECK THE ROOFS!"]
const LINE_CHARGE := "THE BALCONY! HE IS ON THE BALCONY!"

var main
var phase := Phase.IDLE
var squad: Dictionary = {}
var flash_seen := false
var _charge_in := -1.0
var _charge_t := -1.0                # seconds since the charge began (-1 = not yet)
var _acc := 0.0
var _hint_t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(m) -> void:
	main = m
	_rng.randomize()
	Game.gunshot.connect(_on_gunshot)


## Spawn the ten guards round the foot of the ramp (through Main so they get uids): called when the lander has come down.
func spawn_guards() -> void:
	var spots := CityStory.guard_spots()
	for i in mini(spots.size(), GUARD_KINDS.size()):
		var e: Enemy = main._spawn_enemy_at(spots[i]["pos"], GUARD_KINDS[i])
		main._assign_role(e, "park_guard")
	reset()


## Put the controller back to its calm start (after spawning, and after a checkpoint restore: the guards are rebuilt calm).
func reset() -> void:
	squad = {}
	flash_seen = false
	_charge_in = -1.0
	_charge_t = -1.0
	phase = Phase.CALM if not guards().is_empty() else Phase.IDLE


## The ramp fight is over (the chase takes the guards over: ChaseFight.begin): the controller stands down and the search circle is gone.
func dismiss() -> void:
	if not squad.is_empty() and squad in main.squads.squads:
		main.squads.squads.erase(squad)
	squad = {}
	phase = Phase.IDLE


func guards() -> Array:
	var out: Array = []
	for e in Game.enemies:
		var en := e as Enemy
		if is_instance_valid(en) and en.group == GUARD_GROUP and en.state != Enemy.State.DEAD:
			out.append(en)
	return out


func killed() -> int:
	return CityStory.guard_spots().size() - guards().size() if phase != Phase.IDLE else 0


func _on_gunshot(pos: Vector3, loudness: float) -> void:
	if phase != Phase.CALM and phase != Phase.SEARCH:
		return
	var foot := CityStory.ramp_foot()
	if pos.distance_to(foot) > loudness * 0.45 + 6.0:
		return                                  # nobody hears it
	if phase == Phase.CALM:
		_alarm()
	# who catches the flash?
	for g in guards():
		var eye: Vector3 = g._eye_pos()
		var to := pos - eye
		var d := to.length()
		if d > FLASH_RANGE or d < 1.0:
			continue
		var fwd := Vector3(-sin(g.facing), 0.0, -cos(g.facing))
		var flat := Vector3(to.x, 0.0, to.z).normalized()
		if fwd.dot(flat) < cos(deg_to_rad(FLASH_CONE * 0.5)):
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, pos, Game.L_WORLD)
		if not g.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			continue
		if _rng.randf() < FLASH_CHANCE:
			flash_seen = true
			break
	if flash_seen and _charge_in < 0.0 and phase == Phase.SEARCH:
		_charge_in = CHARGE_DELAY


## The first shot: everybody into the confused circle round the ramp (one Squads record that survives deaths).
func _alarm() -> void:
	var members := guards()
	if members.is_empty():
		return
	phase = Phase.SEARCH
	for g in members:
		var en := g as Enemy
		if en.state == Enemy.State.WANDER or en.state == Enemy.State.SUSPICIOUS:
			en.noticed_self = false
			var spot := City.random_point_near(_rng, en.global_position, 2.0, 5.5)         # they scatter a few metres in every direction, then sweep
			en.hold_order(spot if spot != Vector3.INF else en.global_position, en.facing + _rng.randf_range(-1.2, 1.2), deg_to_rad(150.0))
			en.noticed_self = false
			en.confused = true
	squad = {"group": GUARD_GROUP, "members": members, "rally": CityStory.ramp_foot(), "t": 0.0, "line_t": 2.5, "persist": true}
	main.squads.squads.append(squad)
	_say(LINES_SEARCH[_rng.randi() % LINES_SEARCH.size()])


## The circle breaks and they hunt the balcony.
func _charge() -> void:
	phase = Phase.CHARGE
	_charge_t = 0.0
	for g in guards():
		(g as Enemy).confused = false
	if not squad.is_empty() and squad in main.squads.squads:
		main.squads._break(squad)
	for g in guards():
		var en := g as Enemy
		if en.state == Enemy.State.WANDER or en.state == Enemy.State.SUSPICIOUS:
			en._aggravate(false)
	squad = {}
	_say(LINE_CHARGE)


func _say(text: String) -> void:
	Game.radio_line.emit(text)
	Sfx.play(main.player, "radio", -10.0)


func _physics_process(delta: float) -> void:
	if main == null or Game.dead or phase == Phase.IDLE:
		return
	if _charge_in >= 0.0:
		_charge_in -= delta
		if _charge_in < 0.0 and phase == Phase.SEARCH:
			_charge()
	_acc += delta
	if _charge_t >= 0.0:
		_charge_t += delta
	if _acc < TICK:
		return
	_acc = 0.0
	var living := guards()
	if phase == Phase.CHARGE and _charge_t >= 0.0 and _charge_t < TRACK_TIME:
		for g in living:           # the charge keeps its target: they know where the balcony is, whether or not they have a line to him
			var en2 := g as Enemy
			if en2.state == Enemy.State.CHASE or en2.state == Enemy.State.ALERT:
				en2.last_known = main.player.global_position
				en2.unseen_t = 0.0
	if phase == Phase.CALM or phase == Phase.SEARCH:
		for g in living:
			if (g as Enemy).state in [Enemy.State.ALERT, Enemy.State.CHASE, Enemy.State.ATTACK, Enemy.State.SHOOT] and (g as Enemy).noticed_self:
				_charge()                    # one of them found the player with his own eyes
				break
	if phase == Phase.SEARCH and (squad.is_empty() or not (squad in main.squads.squads)):
		phase = Phase.CHARGE                 # the 20 s of the circle are over: they come for the balcony
		_charge_t = 0.0
		for g in living:
			(g as Enemy).confused = false
		_say(LINE_CHARGE)
	# the long rifle is no weapon for a close fight: say so
	_hint_t = maxf(0.0, _hint_t - TICK)
	var w: Weapons = main.player.weapons
	if bool(w.stats().get("heavy", false)) and w.hunter_near(CLOSE_HINT_RANGE) and _hint_t <= 0.0:
		w.notice = "TOO CLOSE - SWITCH TO THE PISTOL (1)"
		w.notice_t = 2.0
		_hint_t = 4.0
