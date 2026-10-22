extends Node3D
## Builds the city, the player, the HUD and the enemies. `-- --selftest` runs the scripted checks in tests/selftest.gd.
## Also: switches the battle sites' detail on and off by distance, and checks whether the player reached the goal house.

const ROAMING_GROUPS := 4        # extra groups placed over the streets by class weight (the rest stand at the battle sites)
const SPAWN_MIN_DIST := 110.0    # nobody starts closer than this to the player (beyond every sight / hearing range)
const RESPAWN_DELAY := 25.0
const CIVILIAN_COUNT := 50          # living civilians at the start of the story (some are children, each with an adult)
const CIVILIAN_CHILDREN := 9
const CIVILIAN_DEAD := 8            # bodies lying near the Institute exit to set the scene (more lie along the way home: CityStory.body_spots)
const SITE_SIZE := [3, 4]        # soldiers per battle site (the first site always holds one of every kind: 5)
## Who stands where: kind weights by street class. Open avenues get the heavy hitters and snipers, alleys only blades.
const KIND_WEIGHTS := {
	"avenue": {"soldier": 35, "rifleman": 25, "gunner": 15, "marksman": 15, "blade": 10},
	"plaza": {"soldier": 35, "rifleman": 25, "gunner": 15, "marksman": 15, "blade": 10},
	"street": {"soldier": 35, "rifleman": 30, "blade": 20, "gunner": 10, "marksman": 5},
	"walk": {"soldier": 35, "blade": 40, "rifleman": 25},
	"alley": {"blade": 60, "soldier": 40},
}
## Group size by class: wide streets hold bigger groups.
const GROUP_SIZE := {"avenue": [1, 3], "plaza": [1, 2], "street": [1, 2], "walk": [1, 1], "alley": [1, 1]}
const SITE_EXTRA_KINDS := {"soldier": 40, "rifleman": 30, "gunner": 15, "blade": 15}
const LANE_TRIGGER := 24.0          # the first-lane blade fighter charges when the player comes this close with a clear line
const STORY_TICK := 0.2
const LOOKOUT_TIME := 6.0           # seconds on the lookout roof (with the landing craft down) before the lookout objective is done
const LOOKOUT_RADIUS := 7.0

var world: World
var player: Player
var hud: HUD
var spawned_total := 0
var site_groups: Array = []       # per battle site: the Enemy nodes spawned there
var _respawns: Array = []        # [seconds left, kind]
var _rng := RandomNumberGenerator.new()
var _site_t := 0.0
var mission: Mission
var squads: Squads
var _crowd: AudioStreamPlayer
var checkpoint: Checkpoint
var enemy_info := {}              # uid -> {kind, group} of every enemy ever spawned (checkpoints rebuild enemies from it)
var _next_uid := 0
var _restoring := false
var story_roles := {}             # uid -> "lane_blade" / "lone_soldier": the two scripted soldiers (re-applied after a checkpoint restore)
var _story_t := 0.0
var _ambience_t := 3.0
var park_fight: ParkFight        # the ten guards at the lander (see ParkFight)
var chase: ChaseFight            # the chase, the courtyard and the arm wound (see ChaseFight)
var _lookout_t := 0.0


func _ready() -> void:
	Game.reset_stats()
	_rng.randomize()
	if OS.get_environment("LETHE_SEED") != "":        # perf runs: the same soldiers in the same places every launch
		_rng.seed = int(OS.get_environment("LETHE_SEED"))
	world = World.new()
	add_child(world)
	world.build()

	player = Player.new()
	player.position = City.START_POS       # inside the entrance recess of the south building, facing the avenue (yaw 0 = north)
	add_child(player)

	hud = HUD.new()
	add_child(hud)
	hud.setup(player)
	squads = Squads.new()
	add_child(squads)
	squads.setup(player)
	park_fight = ParkFight.new()
	add_child(park_fight)
	park_fight.setup(self)
	chase = ChaseFight.new()
	add_child(chase)
	chase.setup(self)

	Civilian.clock = 0.0
	_crowd = AudioStreamPlayer.new()
	_crowd.stream = Sfx.get_sound("crowd")
	_crowd.volume_db = -60.0
	for sid in ["whip", "hum", "far_gun", "far_boom"]:          # synthesised on first use: build them now, not in the middle of a fight
		Sfx.get_sound(sid)
	add_child(_crowd)
	_spawn_city_enemies()
	Game.enemy_killed.connect(_on_enemy_killed)
	Game.objective_changed.connect(_on_objective_changed)
	Game.checkpoint_requested.connect(_restore_checkpoint)
	_update_sites(true)
	Settings.load_settings()
	Settings.apply(get_tree(), self)
	world.lander.touched_down.connect(_on_lander_touched_down)

	var args := OS.get_cmdline_user_args()
	Game.sandbox = "--sandbox" in args
	mission = Mission.sandbox() if Game.sandbox else Mission.story()
	Game.mission = mission
	if not Game.sandbox:
		_populate_civilians()     # before begin(): the first checkpoint includes them
		_spawn_story_enemies()
	mission.begin()           # saves the first checkpoint through objective_changed
	if "--selftest" in args or "--shots" in args or "--script" in args:
		var path := "res://tests/selftest.gd" if "--selftest" in args else "res://tests/screenshots.gd"
		if "--script" in args:          # `-- --script res://tests/mine.gd`: any script with run(main)
			path = args[args.find("--script") + 1]
		var t = load(path).new()
		add_child(t)
		t.run(self)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pick_weighted(w: Dictionary) -> String:
	var total := 0
	for k in w:
		total += int(w[k])
	var roll := _rng.randi() % total
	for k in w:
		roll -= int(w[k])
		if roll < 0:
			return k
	return "soldier"


## Battle sites get big groups (always at least a blade fighter and a sniper); the rest stand in smaller groups on the
## streets, most of them on the wide ones. The first enemy spawned is a soldier and the first site holds every kind.
func _spawn_city_enemies() -> void:
	for si in City.sites.size():
		var centre: Vector3 = City.sites[si]["center"]
		var kinds: Array = ["soldier", "marksman", "blade"]
		if si == 0:
			kinds.append_array(["rifleman", "gunner"])
		var members: Array = []
		site_groups.append(members)
		var want := _rng.randi_range(SITE_SIZE[0], SITE_SIZE[1])
		while kinds.size() < want:
			kinds.append(_pick_weighted(SITE_EXTRA_KINDS))
		for k in kinds:
			var p := City.random_point_near(_rng, centre, 8.0 if k == "marksman" else 1.5, 12.0 if k == "marksman" else 8.0)
			var member := _spawn_enemy_at(p if p != Vector3.INF else centre, k)
			member.group = si                  # the soldiers around one campfire share a group (see Enemy._alert_group)
			members.append(member)
	if City.sites.is_empty():
		_spawn_enemy_at(City.random_spawn(_rng, player.position, SPAWN_MIN_DIST)["pos"], "soldier")
	for g in ROAMING_GROUPS:
		var spot := City.random_spawn(_rng, player.position, SPAWN_MIN_DIST)
		var cls: String = spot["cls"]
		var gs: Array = GROUP_SIZE[cls]
		var n := _rng.randi_range(gs[0], gs[1])
		for i in n:
			var p2: Vector3 = spot["pos"]
			if i > 0:
				var near := City.random_point_near(_rng, p2, 1.5, 4.5)
				if near != Vector3.INF:
					p2 = near
			var roamer := _spawn_enemy_at(p2, _pick_weighted(KIND_WEIGHTS[cls]))
			roamer.group = 100 + g


func _spawn_enemy_at(p: Vector3, kind: String = "soldier", weapon: String = "") -> Enemy:
	p.x = clampf(p.x, -City.IN_X + 4.0, City.IN_X - 4.0)
	p.z = clampf(p.z, -City.IN_Z + 4.0, City.IN_Z - 4.0)
	p.y = World.height_at(p.x, p.z) + 0.3 if p.y < 1.0 else p.y + 0.3        # a spot with a height (the balcony) keeps it
	var e := Enemy.new()
	e.setup(player, p, kind)
	if weapon != "":
		e.set_weapon(weapon)
	e.uid = _next_uid
	_next_uid += 1
	Game.mark("enemy_spawn")
	enemy_info[e.uid] = {"kind": kind, "group": -1}
	add_child(e)
	spawned_total += 1
	return e


## Rebuild an enemy from a checkpoint record: same uid, kind, group, place and health; calm (wandering) again.
func spawn_enemy_from(info: Dictionary) -> Enemy:
	Game.mark("enemy_spawn")
	var e := Enemy.new()
	e.setup(player, info["pos"], info["kind"])
	if String(story_roles.get(int(info["uid"]), "")) == "balcony_marksman":
		e.set_weapon("sniper")
	e.uid = int(info["uid"])
	e.group = int(info["group"])
	e.health = float(info["health"])
	e.ammo = int(info["ammo"])
	e.sidearm_ammo = int(info["sidearm_ammo"])
	add_child(e)
	e.home = info["home"]
	e.facing = float(info["facing"])
	enemy_info[e.uid] = {"kind": info["kind"], "group": e.group}
	if story_roles.has(e.uid):
		_apply_role(e)
	return e


func reset_respawns() -> void:
	_respawns.clear()


## After a restore: the per-campfire member lists point at the new enemy nodes.
func rebuild_site_groups() -> void:
	for si in site_groups.size():
		site_groups[si] = []
	for e in Game.enemies:
		if e.group >= 0 and e.group < site_groups.size():
			site_groups[e.group].append(e)


## The two scripted soldiers of Chapter One (story only, before the first checkpoint): the blade fighter with no gun who waits at the
## end of the first narrow lane and charges the player, and the lone young soldier who fell behind a patrol near the home, idly
## spinning his rifle (the player can take him down silently from behind or shoot him; his rifle is the first pulse rifle).
func _spawn_story_enemies() -> void:
	var lane := CityStory.first_lane()
	if not lane.is_empty():
		var b := _spawn_enemy_at(lane["pos"], "blade")
		_assign_role(b, "lane_blade")
	var lone := CityStory.lone_soldier_spot()
	if not lone.is_empty():
		var s := _spawn_enemy_at(lone["pos"], "soldier")
		_assign_role(s, "lone_soldier")
	# "The Lander": the marksman on the balcony (his rifle is the LR-9) and two soldiers gasping against a wall on the way to the park
	var mk := _spawn_enemy_at(CityStory.MARKSMAN_AT, "marksman", "sniper")
	_assign_role(mk, "balcony_marksman")
	var rest := CityStory.rest_spot()
	if not rest.is_empty():
		_assign_role(_spawn_enemy_at(rest["a"], "soldier"), "exhausted")
		_assign_role(_spawn_enemy_at(rest["b"], "soldier"), "exhausted")


func _assign_role(e: Enemy, role: String) -> void:
	story_roles[e.uid] = role
	_apply_role(e)


## Role behaviour that is not part of the checkpoint record (calm again after a restore).
func _apply_role(e: Enemy) -> void:
	var role := String(story_roles[e.uid])
	if role == "chaser" or role == "straggler" or role == "courtyard" or role == "courtyard_last":
		# "The Lander" part two (ChaseFight): they hunt (or hold the courtyard), no post; the two stragglers tire fast and drop two grenades each
		e.group = -1
		e.post = false
		if role == "courtyard_last":
			e.damage_scale = ChaseFight.LAST_SCALE
		if role == "straggler":
			e.straggler = true
			e.fatigue = ChaseFight.STRAGGLER_FATIGUE
			e.grenade_drop = ChaseFight.STRAGGLER_GRENADES
			e.stamina = minf(e.stamina, e.max_stamina * ChaseFight.STRAGGLER_STAMINA)
		return
	e.group = -1                  # alone: nobody shares anything with him
	e.post = true
	match String(story_roles[e.uid]):
		"lane_blade":
			var lane := CityStory.first_lane()
			var to: Vector3 = (lane["near"] as Vector3) - e.home if not lane.is_empty() else Vector3.FORWARD
			e.post_facing = atan2(-to.x, -to.z)
		"lone_soldier":
			var lone := CityStory.lone_soldier_spot()
			e.post_facing = float(lone.get("face", 0.0))
			e.spin_rifle = true
			e.lazy_alert = 1.0           # he grins and raises the rifle without hurry
			e.max_health = 60.0          # young, and without his patrol he is weak
			e.health = minf(e.health, e.max_health)
		"balcony_marksman":
			e.group = 201                # his own group: the objective "TAKE OUT THE MARKSMAN" is kill_group 201
			e.post_facing = 0.0          # north: his back is to the stair end of the balcony, he watches the park
			e.sight_fov = 70.0           # a rifle on the rail: he looks hard at the park and does not see what comes up the stair behind him
		"exhausted":
			var rest := CityStory.rest_spot()
			e.group = 202
			e.sit_down(float(rest["face"]) if not rest.is_empty() else e.facing)
			e.remove_helmet()
			e.lazy_alert = 0.7           # when he finally gets up he is slow about it
		"park_guard":
			e.group = ParkFight.GUARD_GROUP
			var best_d := INF
			for g in CityStory.guard_spots():
				var d := ((g["pos"] as Vector3) - e.home).length_squared()
				if d < best_d:
					best_d = d
					e.post_facing = float(g["face"])
	e.facing = e.post_facing
	e.rig.rotation.y = e.facing


## Every STORY_TICK: the lane blade fighter charges the player as soon as he comes close in a clear line (calm soldiers only: once
## he hunts, his own senses take over).
func _update_story(delta: float) -> void:
	_story_t -= delta
	if _story_t > 0.0 or story_roles.is_empty():
		return
	_story_t = STORY_TICK
	_update_lander_objectives()
	for e in Game.enemies:
		var en := e as Enemy
		if not is_instance_valid(en) or en.state != Enemy.State.WANDER or String(story_roles.get(en.uid, "")) != "lane_blade":
			continue
		var d := en.global_position - player.global_position
		if Vector2(d.x, d.z).length() < LANE_TRIGGER and absf(d.y) < 3.0 and en._los_to_player():
			en._aggravate(true)
			en.alert_t = 0.3
			en.last_known = player.global_position


## Closeness (0..1) to a wide avenue (the through avenues x = 0 and z = 0 and the Institute avenue): the crowd and the distant
## fighting get louder the nearer the player is to one.
func avenue_closeness() -> float:
	var p := player.global_position
	var d := minf(minf(absf(p.x) - City.avenue_width(0.0) * 0.5, absf(p.z) - City.avenue_width(0.0) * 0.5), absf(p.z - 235.0) - City.avenue_width(235.0) * 0.5)
	return clampf(1.0 - maxf(d, 0.0) / 45.0, 0.0, 1.0)


## Far-off gunfire and explosions from a random direction every few seconds (more often and louder near the main avenue).
func _update_ambience(delta: float) -> void:
	_ambience_t -= delta
	if _ambience_t > 0.0 or Game.sandbox:
		return
	var k := avenue_closeness()
	_ambience_t = lerpf(7.0, 2.2, k) * _rng.randf_range(0.6, 1.4)
	var a := _rng.randf() * TAU
	var dist := _rng.randf_range(110.0, 280.0)
	var pos := player.global_position + Vector3(cos(a) * dist, 6.0, sin(a) * dist)
	var id := "far_gun" if _rng.randf() < 0.62 else "far_boom"
	Sfx.play_at(self, pos, id, 12.0 + k * 7.0 + _rng.randf_range(-3.0, 2.0), _rng.randf_range(0.85, 1.15), 450.0, 70.0)


## The story's crowd: about 56 civilians (children with an adult) between the Institute and the home, 8 bodies near the
## Institute exit and about 16 more along the way home. Nobody is added later: the crowd only thins out (see Civilian).
func _populate_civilians() -> void:
	var zone := City.ROUTE_ZONE
	var adults: Array = []
	var n_civ := int(OS.get_environment("LETHE_CIVILIANS")) if OS.get_environment("LETHE_CIVILIANS") != "" else CIVILIAN_COUNT      # perf runs: LETHE_CIVILIANS=40 gives the old crowd
	for i in maxi(n_civ - CIVILIAN_CHILDREN, 0):
		var pos := Vector3.INF
		for t in 150:
			var spot := City.random_spawn(_rng, player.position, 10.0)
			var p: Vector3 = spot["pos"]
			if zone.has_point(Vector2(p.x, p.z)):
				pos = p
				break
		if pos != Vector3.INF:
			adults.append(Civilian.spawn(self, player, pos, _rng.randi(), false))
	for i in mini(CIVILIAN_CHILDREN, adults.size()):
		var a: Civilian = adults[i]
		var cp := City.random_point_near(_rng, a.global_position, 0.9, 1.8)
		Civilian.spawn(self, player, cp if cp != Vector3.INF else a.global_position, _rng.randi(), true, a)
	for i in CIVILIAN_DEAD:
		var bp := City.random_point_near(_rng, City.INSTITUTE_EXIT, 3.0, 30.0)
		if bp != Vector3.INF:
			Civilian.spawn(self, player, bp, _rng.randi(), false).lie_down()
	# the dead of the walk home: against the walls (doorways) and in the gutters along the way
	var brng := RandomNumberGenerator.new()
	brng.seed = 7117
	for spot in (CityStory.body_spots(brng) if OS.get_environment("LETHE_NOROUTEDEAD") == "" else []):          # LETHE_NOROUTEDEAD=1: perf runs without them
		Civilian.spawn(self, player, spot, brng.randi(), false).lie_down()


## Quiet crowd panic ambience: louder with more panicking civilians near the player, fading out as they leave.
func _update_crowd(delta: float) -> void:
	var near := 0
	for c in Game.civilians:
		var cv := c as Civilian
		if is_instance_valid(cv) and cv.state != Civilian.State.DEAD and cv.global_position.distance_to(player.global_position) < 45.0:
			near += 1
	var k := avenue_closeness()
	var civ_db := lerpf(-46.0, -19.0, clampf(float(near) / 10.0, 0.0, 1.0)) if near > 0 else -60.0
	var far_db := lerpf(-60.0, -27.0, k) if k > 0.0 else -60.0      # the whole avenue screams: heard even with nobody close
	var fade := clampf(1.0 - Civilian.clock / 420.0, 0.35, 1.0)      # the crowd thins out with the minutes
	var target_db := maxf(civ_db + 5.0 * k, far_db * (1.0 + (1.0 - fade) * 0.3) if far_db > -60.0 else -60.0)
	_crowd.volume_db = lerpf(_crowd.volume_db, target_db, 1.0 - exp(-1.5 * delta))
	if _crowd.volume_db > -52.0 and not _crowd.playing:
		_crowd.play()
	elif _crowd.volume_db <= -56.0 and _crowd.playing:
		_crowd.stop()


func _on_enemy_killed(e) -> void:
	if mission != null and mission.respawn_enemies:
		_respawns.append([RESPAWN_DELAY, (e as Enemy).kind])


## A new objective starts: show the marker over it and save a checkpoint.
func _on_objective_changed(_id: String) -> void:
	world.set_marker_target(mission.marker_pos() if mission != null and not mission.finished else null)
	if not _restoring and mission != null and not mission.finished:
		checkpoint = Checkpoint.capture(self)
		Game.has_checkpoint = true


func _restore_checkpoint() -> void:
	if checkpoint == null or _restoring:
		return
	_restoring = true
	await checkpoint.restore(self)
	_restoring = false
	_sync_story_world()
	hud.on_restored()


## Distance-based detail for the battle sites: far ones are not drawn at all, only the nearest burn.
func _update_sites(force: bool) -> void:
	if force:
		_site_t = 0.0
	if _site_t > 0.0:
		return
	_site_t = 0.35
	var pp := player.global_position
	for s in world.sites:
		var site := s as Site
		var d := Vector2(pp.x - site.position.x, pp.z - site.position.z).length()
		site.set_lod(Site.lod_for(d, site.lod))
	if world.lander != null and world.lander.visible:
		world.lander.update_lod(pp.distance_to(City.LANDER_POS))
	if world.fires != null:
		world.fires.update(pp)


func _process(delta: float) -> void:
	_site_t -= delta
	_update_sites(false)
	var t := Time.get_ticks_msec() * 0.001
	for s in world.sites:
		if (s as Site).lod >= 2:
			(s as Site).animate(t)
	if world.fires != null:
		world.fires.animate(t)
	if Game.dead or Game.won:
		return
	Civilian.clock += delta
	_update_crowd(delta)
	_update_story(delta)
	_update_ambience(delta)
	if mission != null and not _restoring:
		mission.update(player, delta)
	for i in range(_respawns.size() - 1, -1, -1):
		_respawns[i][0] -= delta
		if _respawns[i][0] <= 0.0:
			var kind: String = _respawns[i][1]
			_respawns.remove_at(i)
			# a replacement turns up somewhere far from where the player stands
			var spot := City.random_spawn(_rng, player.global_position, 90.0)
			_spawn_enemy_at(spot["pos"], kind)


# ---------------------------------------------------------------- "The Lander": the objectives' world

func _objective_index(oid: String) -> int:
	if mission == null:
		return -1
	for i in mission.objectives.size():
		if String(mission.objectives[i]["id"]) == oid:
			return i
	return -1


## The lookout objective starts (ChapterOne hook): the landing craft comes down over the park. The ten guards appear when it touches down.
func begin_lookout() -> void:
	_lookout_t = 0.0
	world.lander.begin_landing()
	if world.far_landers_node != null:
		world.far_landers_node.visible = true          # the other ships have settled in the squares: the lookout sees them


func _on_lander_touched_down() -> void:
	if mission != null and not mission.finished and String(mission.active().get("id", "")) == "lookout":
		park_fight.spawn_guards()


## After a checkpoint restore the craft and the guards' controller match the objective the player is back on.
func _sync_story_world() -> void:
	if mission == null or Game.sandbox or world.lander == null:
		return
	var li := _objective_index("lookout")
	if li < 0:
		return
	_lookout_t = 0.0
	if mission.index > li:
		world.lander.land_now()
	else:
		world.lander.hide_ship()
		if mission.index == li:
			world.lander.begin_landing()
	if world.far_landers_node != null:
		world.far_landers_node.visible = mission.index >= li
	park_fight.reset()
	chase.sync()
	if String(mission.active().get("id", "")) == "balcony_marksman":
		alert_marksman()


## The marksman on the balcony knows exactly where the player is (the lookout is over): he turns on him at once and keeps him in his
## sights, so the player has to deal with him instead of creeping up the stair past the guards. Called when the objective starts.
func alert_marksman() -> void:
	for e in Game.enemies:
		var en := e as Enemy
		if not is_instance_valid(en) or en.state == Enemy.State.DEAD or String(story_roles.get(en.uid, "")) != "balcony_marksman":
			continue
		en.knows_player = true
		en.post = false
		en.lazy_alert = 0.0
		en._aggravate(true)
		en.alert_t = 0.3


## Every STORY_TICK: the objectives that watch the world (the lookout, the rifle, the guards).
func _update_lander_objectives() -> void:
	if mission == null or mission.finished or Game.sandbox:
		return
	match String(mission.active().get("id", "")):
		"lookout":
			var lk := CityStory.lookout
			if not lk.is_empty():
				var roof: Vector3 = lk["roof"]
				var d := Vector2(player.global_position.x - roof.x, player.global_position.z - roof.z).length()
				if d < LOOKOUT_RADIUS and absf(player.global_position.y - roof.y) < 3.0:
					_lookout_t += STORY_TICK
				else:
					_lookout_t = maxf(0.0, _lookout_t - STORY_TICK * 0.5)
				if _lookout_t >= LOOKOUT_TIME and world.lander.landed:
					Mission.complete("lookout")
		"park_fight":
			if park_fight.killed() >= ParkFight.KILLS_TO_CONTINUE:
				Mission.complete("park_fight")
		"take_grenades":
			if Game.grenades >= ChaseFight.GRENADES_NEEDED:
				Mission.complete("take_grenades")
