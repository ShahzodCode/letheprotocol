extends Node
## Headless checks. Run:  godot --headless --path . -- --selftest
## Prints PASS / FAIL per check and exits non-zero if anything failed.

var main
var player: Player
var fails := 0
var passes := 0
var all: Array = []


## A dead soldier lies down: the clip models end with the head near the ground, the procedural ones tip over (tilt).
func corpse_lying(e: Enemy) -> bool:
	if e.model.has_anim("death"):
		return e.model.head_node.global_position.y - e.global_position.y < 0.7
	return absf(e.tilt.rotation.x) > 1.2

func check(name: String, cond: bool, detail: String = "") -> void:
	var stamp := "  [%ds]" % int(Time.get_ticks_msec() / 1000)
	if cond:
		passes += 1
		print("PASS  ", name, "  ", detail, stamp)
	else:
		fails += 1
		print("FAIL  ", name, "  ", detail, stamp)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func secs(t: float) -> void:
	await frames(int(t * 120.0))


func aim_at(target: Vector3) -> void:
	var d := target - player.camera.global_position
	player.yaw = atan2(-d.x, -d.z)
	player.pitch = asin(d.y / d.length())
	player.rotation.y = player.yaw
	player.recoil_pitch = 0.0
	player.recoil_yaw = 0.0
	player.head.rotation = Vector3(player.pitch, 0, 0)
	player.camera.force_update_transform()


## Parking spot for enemies that must stay out of a test: a grid on the ground beyond the east border buildings.
func park_pos(e: Enemy) -> Vector3:
	var i := all.find(e)
	return Vector3(200.0 + 3.0 * (i % 15), 0, 3.0 * (i / 15))


func place(e: Enemy, p: Vector3, freeze: bool) -> void:
	e.global_position = Vector3(p.x, World.height_at(p.x, p.z) + 0.1, p.z)
	e.velocity = Vector3.ZERO
	e.home = e.global_position
	e.stun = 999.0 if freeze else 0.0
	e.state = Enemy.State.WANDER


func run(m) -> void:
	main = m
	player = m.player
	Game.force_input = true
	all = Game.enemies.duplicate()
	await frames(5)
	print("--- spawn ---")
	await secs(0.5)
	check("player stands on the ground", player.is_on_floor(), "y=%.2f dead=%s hp=%.0f paused=%s" % [player.global_position.y, Game.dead, player.health, get_tree().paused])
	var spawn_off := Vector2(player.global_position.x - City.START_POS.x, player.global_position.z - City.START_POS.z).length()
	check("the player starts in front of the lift inside the Institute lobby", spawn_off < 1.5 and City.LOBBY.has_point(Vector2(player.global_position.x, player.global_position.z)), "%.1f m from the start spot" % spawn_off)
	var up_ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 1.6, 0), player.global_position + Vector3(0, 12.0, 0), Game.L_WORLD)
	var up_hit := player.get_world_3d().direct_space_state.intersect_ray(up_ray)
	check("the lobby has a 5 m ceiling", not up_hit.is_empty() and absf((up_hit["position"] as Vector3).y - City.LOBBY_H) < 0.1, str(up_hit.get("position")))
	var look := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 1.6, 0), player.global_position + Vector3(0, 1.6, -60), Game.L_WORLD)
	var look_hit := player.get_world_3d().direct_space_state.intersect_ray(look)
	var look_d := 60.0 if look_hit.is_empty() else (look_hit["position"] as Vector3).distance_to(player.global_position + Vector3(0, 1.6, 0))
	check("the start faces the doorway and the wide avenue beyond", look_d > 20.0 and absf(player.yaw) < 0.05, "clear for %.0f m, yaw %.2f" % [look_d, player.yaw])
	var on_avenue := false
	for s in City.streets:
		if s["cls"] == "avenue" and (s["rect"] as Rect2).has_point(Vector2(City.START_POS.x, City.START_POS.z - 20.0)) and (s["rect"] as Rect2).size.y >= 20.0:
			on_avenue = true
	check("straight ahead of the door is a wide avenue", on_avenue)
	var lo: Dictionary = player.weapons.loadout
	check("the player starts with only a pistol and a knife", lo["pistol"].size() == 1 and lo["melee"].size() == 1 and lo["rifle"].is_empty())
	player.weapons.loadout["rifle"].append(Weapons.new_weapon("rifle"))     # the shooting tests below use the rifle
	check("enemies spread across the city", Game.enemies.size() == main.spawned_total, "%d (expected %d)" % [Game.enemies.size(), main.spawned_total])
	var kinds := {}
	for e in Game.enemies:
		kinds[e.kind] = true
	check("all five enemy kinds present", kinds.size() == 5, str(kinds.keys()))
	var far_ok := true
	for e in Game.enemies:
		if e.global_position.distance_to(player.global_position) < 60.0:
			far_ok = false
			print("   near enemy at ", e.global_position, " player ", player.global_position)
	check("enemies start far away (>60 m)", far_ok)
	var grounded := true
	for e in Game.enemies:
		if not e.is_on_floor():
			grounded = false
	check("enemies stand on the terrain", grounded)
	var wandering := true
	for e in Game.enemies:
		if e.state != Enemy.State.WANDER and e.state != Enemy.State.EXHAUSTED:          # (the two story soldiers sitting against a wall are calm too)
			wandering = false
	check("enemies are wandering, not hunting", wandering)
	lander_spawn_checks()
	await secs(4.0)
	var moved := 0
	for e in Game.enemies:
		if e.global_position.distance_to(e.home) > 0.3:
			moved += 1
	check("some enemies walk around", moved >= 1, "%d moved" % moved)
	await clear_civilians()         # the AI tests below must not have soldiers turning to shoot at passers-by
	# the physics / weapon tests below are not about the AI: park everybody outside the map and move to the central junction
	for en in all:
		place(en, park_pos(en), true)
	player.global_position = Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO
	await secs(0.6)

	check("the player starts with no grenades (story)", Game.grenades == 0)
	print("--- terrain / player physics ---")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(40, 60, 0), Vector3(40, -60, 0), Game.L_WORLD)
	var rh := player.get_world_3d().direct_space_state.intersect_ray(ray)
	check("ground raycast hits terrain", not rh.is_empty() and absf(rh["position"].y - World.height_at(40, 0)) < 1.5, str(rh.get("position")))

	Input.action_press("jump")
	var peak := player.global_position.y
	for i in 70:
		await frames(1)
		peak = maxf(peak, player.global_position.y)
	Input.action_release("jump")
	await secs(1.0)
	var jump_h := peak - World.height_at(player.global_position.x, player.global_position.z)
	check("jump height 1.0-2.2 m", jump_h > 1.0 and jump_h < 2.2, "%.2f m" % jump_h)

	var start_y := player.global_position.y
	player.global_position.y += 1.0
	player.velocity = Vector3.ZERO
	Input.action_press("jump")
	await frames(3)
	Input.action_release("jump")
	var tap_peak := player.global_position.y
	for i in 120:
		await frames(1)
		tap_peak = maxf(tap_peak, player.global_position.y)
	await secs(0.8)
	check("a short tap jumps lower than a held jump", (tap_peak - start_y) < jump_h + 0.9, "tap %.2f vs hold %.2f" % [tap_peak - start_y - 1.0, jump_h])

	player.health = Game.MAX_HEALTH
	player.health = Game.MAX_HEALTH
	player.global_position = Vector3(0, 7.5, 10)
	player.velocity = Vector3.ZERO
	await secs(3.0)
	check("fall damage after a 2-storey drop (it hurts)", player.health < Game.MAX_HEALTH - 10.0 and player.health > 40.0, "health %.0f" % player.health)
	check("player alive after the drop", not Game.dead)
	player.health = Game.MAX_HEALTH
	player.global_position = Vector3(0, 1.0, 10)
	await secs(1.0)
	var h_small := player.health
	player.global_position = Vector3(0, 3.5, 10)
	await secs(1.0)
	check("a small drop (3 m) is harmless", player.health == h_small, "health %.0f" % player.health)

	print("--- walking, step-up ---")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.global_position = Vector3(0, 1.0, 8)
	player.yaw = 0.0
	player.pitch = 0.0
	await secs(0.6)
	var p0 := player.global_position
	Input.action_press("move_forward")
	await secs(1.5)
	Input.action_release("move_forward")
	var walked := p0.distance_to(player.global_position)
	check("walking forward moves ~5 m/s", walked > 5.0 and walked < 9.0, "%.1f m in 1.5 s" % walked)
	check("walking goes toward -z", player.global_position.z < p0.z - 4.0)

	# walk up the real terrain: the feet must follow the ground height
	for dirs in [Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1)]:
		var sx: float = dirs.x * 50.0
		var sz: float = dirs.y * 50.0
		player.global_position = Vector3(sx, World.height_at(sx, sz) + 0.5, sz)
		player.velocity = Vector3.ZERO
		player.yaw = atan2(-dirs.x, -dirs.y)
		await secs(0.6)
		Input.action_press("move_forward")
		var worst := 0.0
		for i in 1200:
			await frames(1)
			var gp := player.global_position
			worst = maxf(worst, absf(gp.y - World.height_at(gp.x, gp.z)))
		Input.action_release("move_forward")
		check("feet follow the terrain walking %s" % str(dirs), worst < 1.5, "max gap %.2f m" % worst)
	player.yaw = 0.0

	await secs(0.8)
	player.global_position = Vector3(0, 1.0, 8)
	player.velocity = Vector3.ZERO
	await secs(0.5)
	var ledge := StaticBody3D.new()
	ledge.collision_layer = Game.L_WORLD
	var lcs := CollisionShape3D.new()
	var lb := BoxShape3D.new()
	lb.size = Vector3(6, 0.4, 3)
	lcs.shape = lb
	ledge.add_child(lcs)
	main.add_child(ledge)
	ledge.global_position = Vector3(0, World.height_at(0, 4) + 0.2, 4.0)
	await frames(3)
	Input.action_press("move_forward")
	await secs(2.0)
	Input.action_release("move_forward")
	check("steps up a 0.4 m ledge", player.global_position.z < 3.0, "z=%.2f" % player.global_position.z)
	ledge.queue_free()
	var wall := StaticBody3D.new()
	wall.collision_layer = Game.L_WORLD
	var wcs := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(6, 2.0, 1)
	wcs.shape = wb
	wall.add_child(wcs)
	main.add_child(wall)
	player.global_position = Vector3(0, 1.0, 8)
	await secs(0.6)
	wall.global_position = Vector3(0, World.height_at(0, 4) + 1.0, 4.0)
	await frames(3)
	Input.action_press("move_forward")
	await secs(2.0)
	Input.action_release("move_forward")
	check("a 2 m wall stops the player", player.global_position.z > 4.4, "z=%.2f" % player.global_position.z)
	wall.queue_free()

	print("--- shooting ---")
	player.global_position = Vector3(0, 1.0, 0)
	player.velocity = Vector3.ZERO
	await secs(0.5)
	var w: Weapons = player.weapons
	var e: Enemy = all[0]
	place(e, Vector3(0, 0, -25), true)
	e.health = 100.0          # the headshot arithmetic below needs a full 100 (soldiers have 90 now)
	await secs(0.6)
	var ebody := e.global_position + Vector3(0, 1.13, 0)
	var ehead := e.global_position + Vector3(0, 1.64, 0)
	w.ads_k = 1.0
	var hp0 := e.health
	var ammo0 := w.ammo()
	aim_at(ebody)
	w.cooldown = 0.0
	w._fire_shot()
	await frames(2)
	check("pistol uses one round per shot", w.ammo() == ammo0 - 1, "%d -> %d" % [ammo0, w.ammo()])
	check("body hit does damage", e.health < hp0, "%.0f -> %.0f" % [hp0, e.health])
	check("pistol body damage is 28 at 25 m", absf((hp0 - e.health) - 28.0) < 0.5, "%.1f" % (hp0 - e.health))
	var hp1 := e.health
	var head_dmg := 0.0
	for attempt in 25:      # spread is random: try again if the shot went into the body
		w.state[w.current]["ammo"] = maxi(2, int(w.state[w.current]["ammo"]))
		hp1 = e.health
		aim_at(ehead)
		w.bloom = 0.0
		w.cooldown = 0.0
		w._fire_shot()
		await frames(2)
		head_dmg = hp1 - e.health
		if head_dmg > 40.0:
			break
	check("headshot does 2.5x damage", absf(head_dmg - 70.0) < 1.0, "%.1f" % head_dmg)
	check("enemy is hunting after being shot", e.state != Enemy.State.WANDER and e.state != Enemy.State.DEAD, str(e.state))
	await secs(0.3)

	place(e, Vector3(9, 0, -25), true)       # out of the line of fire
	# fresh target for falloff and legs
	var e2: Enemy = all[1]
	place(e2, Vector3(0, 0, -80), true)
	await secs(0.6)
	var hpf := e2.health
	aim_at(e2.global_position + Vector3(0, 1.13, 0))
	w.ads_k = 1.0
	w.bloom = 0.0
	w._fire_shot()
	await frames(2)
	var far_dmg := hpf - e2.health
	check("damage falls off with distance (80 m)", far_dmg > 0.0 and far_dmg < 24.0, "%.1f at 80 m" % far_dmg)

	# accuracy: ADS standing vs hip moving
	var e3: Enemy = all[2]
	place(e3, Vector3(0, 0, -30), true)
	e3.health = 1.0e6
	await secs(0.6)
	var hits_ads := 0
	var hits_hip := 0
	for i in 40:
		w.bloom = 0.0
		w.ads_k = 1.0
		aim_at(e3.global_position + Vector3(0, 1.13, 0))
		var h_before := e3.health
		w._fire_shot()
		await frames(1)
		if e3.health < h_before:
			hits_ads += 1
	for i in 40:
		w.bloom = 0.0
		w.ads_k = 0.0
		player.velocity = Vector3(0, 0, -6)
		aim_at(e3.global_position + Vector3(0, 1.13, 0))
		var h_before2 := e3.health
		w._fire_shot()
		await frames(1)
		if e3.health < h_before2:
			hits_hip += 1
	player.velocity = Vector3.ZERO
	check("aimed shots are more accurate than moving hip fire", hits_ads > hits_hip, "ads %d/40, hip-moving %d/40" % [hits_ads, hits_hip])
	check("aimed shots mostly hit at 30 m", hits_ads >= 30, "%d/40" % hits_ads)

	print("--- recoil, reload, rifle ---")
	player.recoil_pitch = 0.0
	w.ads_k = 0.0
	var ammo_b := w.ammo()
	w.cooldown = 0.0
	w._fire_shot()
	check("a shot kicks the view up", player.recoil_pitch > 0.005, "%.3f rad" % player.recoil_pitch)
	await secs(1.5)
	check("recoil settles back", player.recoil_pitch < 0.003, "%.4f" % player.recoil_pitch)
	w.state[w.current]["ammo"] = 9
	var mags_before := w.spare_mags()
	var left := w.ammo()
	w.start_reload()
	check("reload starts", w.reloading)
	await secs(float(w.stats()["reload_time"]) + 0.2)
	check("reload finished", not w.reloading)
	check("reloading with a part-used magazine loses its rounds (a fresh full magazine, nothing chambered)", w.ammo() == int(w.stats()["mag"]) or w.ammo() < left + 100, "ammo %d (was %d)" % [w.ammo(), left])
	check("the part-used magazine is not kept: one spare magazine less", w.spare_mags() == mags_before - 1, "%d mags (was %d)" % [w.spare_mags(), mags_before])

	w.switch_to("rifle")
	await secs(0.6)
	check("switched to the rifle", w.current == "rifle")
	check("rifle magazine is 30", w.ammo() == 30)
	var rifle_dmg_hp := 0.0
	var e4: Enemy = all[3]
	place(e4, Vector3(0, 0, -20), true)
	e4.health = 1.0e6
	await secs(0.6)
	aim_at(e4.global_position + Vector3(0, 1.13, 0))
	w.ads_k = 1.0
	var h4 := e4.health
	w.cooldown = 0.0
	w._fire_shot()
	await frames(2)
	rifle_dmg_hp = h4 - e4.health
	check("rifle body damage is 24", absf(rifle_dmg_hp - 24.0) < 0.5, "%.1f" % rifle_dmg_hp)
	var rp := 0.0
	player.recoil_pitch = 0.0
	for i in 8:
		w.cooldown = 0.0
		w._fire_shot()
		await frames(1)
	rp = player.recoil_pitch
	check("rifle recoil climbs while firing", rp > 0.05, "%.3f rad after 8 shots" % rp)
	w.switch_to("pistol")
	await secs(0.6)

	print("--- enemy AI ---")
	for en in all:
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			place(en, park_pos(en), true)
	var hunter: Enemy = main._spawn_enemy_at(Vector3(0, 0, -30), "blade")
	all.append(hunter)
	player.global_position = Vector3(0, 1.0, 0)
	player.velocity = Vector3.ZERO
	player.health = Game.MAX_HEALTH
	await secs(0.3)
	# 30 m away and facing us: it should notice, alert, then run at us
	hunter.global_position = Vector3(0, World.height_at(0, -30) + 0.1, -30)
	hunter.facing = 0.0 + PI   # facing +z, toward the player
	hunter.rig.rotation.y = hunter.facing
	hunter.stun = 0.0
	hunter.state = Enemy.State.WANDER
	hunter.wait_t = 0.0
	await secs(0.2)
	check("enemy that sees the player becomes alert", hunter.state == Enemy.State.ALERT or hunter.state == Enemy.State.CHASE, str(hunter.state))
	await secs(1.0)
	check("enemy runs at the player", hunter.state == Enemy.State.CHASE or hunter.state == Enemy.State.ATTACK, str(hunter.state))
	var d1 := hunter.global_position.distance_to(player.global_position)
	await secs(0.5)
	var d2 := hunter.global_position.distance_to(player.global_position)
	check("enemy closes distance at running speed", d1 - d2 > 2.0 or d2 < 3.0, "%.1f -> %.1f in 0.5 s" % [d1, d2])
	var waited := 0.0
	while player.health >= Game.MAX_HEALTH and waited < 12.0:
		await frames(6)
		waited += 0.05
	check("enemy reaches the player and attacks", player.health < Game.MAX_HEALTH, "health %.0f" % player.health)
	check("blade melee does 18 per strike", int(Game.MAX_HEALTH - player.health) % 18 == 0 and not Game.dead, "%.0f" % (Game.MAX_HEALTH - player.health))

	# player kills it with real shots from close up
	var kills0 := Game.kills
	player.health = Game.MAX_HEALTH
	w.ads_k = 0.0
	var shots := 0
	while hunter.state != Enemy.State.DEAD and shots < 30:
		aim_at(hunter.global_position + Vector3(0, 1.13, 0))
		w.cooldown = 0.0
		if w.ammo() <= 0:
			w.state[w.current]["ammo"] = 15
		w._fire_shot()
		shots += 1
		await frames(3)
	check("enemy dies from pistol shots", hunter.state == Enemy.State.DEAD, "%d shots" % shots)
	check("kill counted", Game.kills == kills0 + 1)
	await secs(1.2)
	check("corpse lies down", corpse_lying(hunter), "head %.2f m, tilt %.2f rad" % [hunter.model.head_node.global_position.y - hunter.global_position.y, hunter.tilt.rotation.x])
	check("corpse can no longer be hit", hunter.hitboxes.is_empty())

	# gunshot alerts a wanderer within hearing, but not one far away
	for en in all:
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			place(en, park_pos(en), true)
	var near_e: Enemy = main._spawn_enemy_at(Vector3(10, 0, 20))
	var far_e: Enemy = main._spawn_enemy_at(Vector3(100, 0, 9))
	all.append(near_e)
	all.append(far_e)
	place(near_e, Vector3(10, 0, 20), false)
	near_e.wait_t = 99.0
	near_e.facing = 0.0
	place(far_e, Vector3(100, 0, 9), false)
	far_e.wait_t = 99.0
	Game.gunshot.emit(player.global_position, 55.0)
	await frames(2)
	check("a nearby gunshot alerts a wanderer", near_e.state != Enemy.State.WANDER, str(near_e.state))
	check("a far-away enemy stays calm", far_e.state == Enemy.State.WANDER, str(far_e.state))

	# line of sight: a wall between enemy and player blocks sight
	for en in all:
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			place(en, park_pos(en), true)
	var blocker := StaticBody3D.new()
	blocker.collision_layer = Game.L_WORLD
	var bcs := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(20, 10, 1)
	bcs.shape = bbox
	blocker.add_child(bcs)
	main.add_child(blocker)
	blocker.global_position = Vector3(0, 5, -10)
	for old_body in Enemy.bodies.duplicate():      # corpses from earlier tests would make him suspicious
		if is_instance_valid(old_body):
			old_body.queue_free()
	await frames(3)
	var watcher: Enemy = main._spawn_enemy_at(Vector3(0, 0, -20))
	all.append(watcher)
	place(watcher, Vector3(0, 0, -20), false)
	watcher.facing = PI
	watcher.rig.rotation.y = PI
	watcher.wait_t = 99.0
	await secs(0.6)
	check("enemy behind a wall does not see the player", watcher.state == Enemy.State.WANDER, str(watcher.state))
	blocker.queue_free()

	print("--- enemy kinds ---")
	for en in all:
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			place(en, park_pos(en), true)
	player.global_position = Vector3(0, World.height_at(0, 0) + 0.1, 0)
	player.velocity = Vector3.ZERO
	player.health = Game.MAX_HEALTH
	await secs(0.3)

	# rifleman at 25 m: stops running, shoots from a distance, damages the player
	var rifleman: Enemy = main._spawn_enemy_at(Vector3(0, 0, -25), "rifleman")
	all.append(rifleman)
	await frames(2)
	rifleman.state = Enemy.State.CHASE
	var shot_from_afar := false
	for i in 3600:        # his bursts are inaccurate: give him half a minute
		await frames(1)
		if player.health < Game.MAX_HEALTH and rifleman.global_position.distance_to(player.global_position) > 8.0:
			shot_from_afar = true
			break
	check("rifleman hurts the player from a distance", shot_from_afar, "hp %.0f, dist %.1f, state %d" % [player.health, rifleman.global_position.distance_to(player.global_position), rifleman.state])
	check("rifleman is in shoot mode, not melee", rifleman.state == Enemy.State.SHOOT, str(rifleman.state))
	rifleman.stun = 999.0
	rifleman.state = Enemy.State.DEAD   # park it, no more shooting
	rifleman.rig.visible = false
	Game.enemies.erase(rifleman)

	# marksman: charge shows a laser, a standing target is hit for 38, a moving one is missed
	var marksman: Enemy = main._spawn_enemy_at(Vector3(0, 0, -60), "marksman")
	all.append(marksman)
	await frames(2)
	player.health = Game.MAX_HEALTH
	marksman.state = Enemy.State.SHOOT
	marksman.cooldown = 0.0
	await secs(0.8)
	check("marksman charges with a visible laser", marksman.charging and marksman.laser.visible)
	await secs(1.6)
	check("standing still gets you sniped for 30", absf((Game.MAX_HEALTH - player.health) - 30.0) < 0.5, "lost %.0f" % (Game.MAX_HEALTH - player.health))
	player.health = Game.MAX_HEALTH
	marksman.cooldown = 0.0
	await secs(0.3)
	var steps := 0
	while marksman.charging and steps < 200:      # side-step once the laser has locked
		if marksman.aim_locked:
			player.velocity = Vector3(8, 0, 0)
			player.global_position.x += 0.2
		await frames(1)
		steps += 1
	await frames(2)
	check("moving after the laser locks dodges the shot", player.health == Game.MAX_HEALTH, "lost %.0f" % (Game.MAX_HEALTH - player.health))
	marksman.stun = 999.0
	marksman.state = Enemy.State.DEAD
	marksman.rig.visible = false
	Game.enemies.erase(marksman)

	# blade fighter: fast, hits for 22 in melee
	player.global_position = Vector3(0, World.height_at(0, 0) + 0.1, 0)
	player.velocity = Vector3.ZERO
	player.health = Game.MAX_HEALTH
	var blade: Enemy = main._spawn_enemy_at(Vector3(0, 0, -20), "blade")
	all.append(blade)
	await frames(2)
	blade.state = Enemy.State.CHASE
	var t0 := blade.global_position.distance_to(player.global_position)
	await secs(1.0)
	var t1 := blade.global_position.distance_to(player.global_position)
	check("blade fighter closes in fast", t0 - t1 > 4.5, "%.1f -> %.1f in 1 s" % [t0, t1])
	await secs(3.0)
	check("blade strikes do 18", player.health < Game.MAX_HEALTH and int(Game.MAX_HEALTH - player.health) % 18 == 0, "lost %.0f" % (Game.MAX_HEALTH - player.health))
	blade.stun = 999.0
	blade.state = Enemy.State.DEAD
	blade.rig.visible = false
	Game.enemies.erase(blade)

	print("--- loadout, loot, pickups, melee ---")
	var lw: Weapons = player.weapons
	check("start loadout: pistol, rifle, knife", lw.loadout["pistol"].size() == 1 and lw.loadout["rifle"].size() == 1 and lw.loadout["melee"].size() == 1)

	# enemy magazines: ammo goes down while shooting, a dry gun reloads (infinite mags)
	var gunr: Enemy = main._spawn_enemy_at(Vector3(0, 0, -25), "rifleman")
	all.append(gunr)
	await frames(2)
	player.global_position = Vector3(0, World.height_at(0, 0) + 0.1, 0)
	player.health = Game.MAX_HEALTH
	check("rifleman starts with a full pulse carbine magazine", gunr.ammo == 24 and gunr.weapon_id == "carbine", "%d %s" % [gunr.ammo, gunr.weapon_id])
	gunr.state = Enemy.State.CHASE
	await secs(2.5)
	check("rifleman spends rounds while shooting", gunr.ammo < 24 or gunr.reloading, "ammo %d" % gunr.ammo)
	gunr.ammo = 2
	gunr.burst_left = 0
	gunr.cooldown = 0.0
	var saw_reload := false
	for i in 600:
		await frames(1)
		if gunr.reloading:
			saw_reload = true
			break
	check("rifleman reloads once the magazine is empty", saw_reload, "ammo %d" % gunr.ammo)
	await secs(float(WeaponsDB.WEAPONS["carbine"]["reload_time"]) + 0.5)
	check("reload gives a fresh full magazine", gunr.ammo > 2 and not gunr.reloading, "ammo %d" % gunr.ammo)
	gunr.stun = 999.0
	gunr.state = Enemy.State.DEAD
	gunr.rig.visible = false
	Game.enemies.erase(gunr)

	# a killed rifleman drops its carbine with the rounds that were left, plus a couple of loose magazines
	for pk in Game.pickups.duplicate():
		pk.queue_free()
	await frames(2)
	var victim: Enemy = main._spawn_enemy_at(Vector3(40, 0, 0), "rifleman")
	all.append(victim)
	await frames(2)
	victim.stun = 999.0
	victim.ammo = 17
	victim.sidearm_ammo = 9
	victim.take_hit(1000.0, "body", Vector3.ZERO, victim.global_position + Vector3(0, 1.2, 0))
	await frames(3)
	var drop_w: Pickup = null
	var drop_pistol: Pickup = null
	var drop_ammo: Array[Pickup] = []
	for pk in Game.pickups:
		var p := pk as Pickup
		if p.is_ammo:
			drop_ammo.append(p)
		elif p.weapon_id == "carbine":
			drop_w = p
		elif p.weapon_id == "pistol":
			drop_pistol = p
	check("fallen soldier drops his weapon with the rounds left in it", drop_w != null and drop_w.ammo == 17, "%s" % (str(drop_w.ammo) if drop_w else "none"))
	check("fallen soldier leaves a couple of magazines", drop_ammo.size() == 2, str(drop_ammo.size()))
	check("sidearm drops with its own rounds", drop_pistol != null and drop_pistol.ammo == 9)

	# walking over a loose magazine collects it automatically, but only for a weapon the player carries
	var rifle_inst: Dictionary = lw.loadout["rifle"][0]
	(rifle_inst["spare"] as Array).resize(4)     # earlier kills near the player already dropped magazines for him
	var mags_before_pick := (rifle_inst["spare"] as Array).size()
	var m4_ammo := Pickup.spawn_ammo(main, Vector3(0, 0, -6), "rifle", 20)
	var rail_ammo := Pickup.spawn_ammo(main, Vector3(0, 0, -6.5), "railgun", 5)
	player.global_position = Vector3(0, World.height_at(0, -6) + 0.1, -6)
	player.velocity = Vector3.ZERO
	await secs(0.5)
	check("loose magazine is picked up automatically", not is_instance_valid(m4_ammo) or m4_ammo.is_queued_for_deletion())
	check("it was added to the rifle's spare magazines", (rifle_inst["spare"] as Array).size() == mags_before_pick + 1 and (rifle_inst["spare"] as Array).back() == 20, str((rifle_inst["spare"] as Array)))
	check("ammo for a weapon you do not carry stays on the ground", is_instance_valid(rail_ammo) and not rail_ammo.is_queued_for_deletion())
	rail_ammo.queue_free()

	# stand on the carbine and press Q: it joins the rifle slot with 17 rounds and a full set of spare mags
	player.global_position = Vector3(drop_w.global_position.x, World.height_at(drop_w.global_position.x, drop_w.global_position.z) + 0.1, drop_w.global_position.z)
	player.velocity = Vector3.ZERO
	await secs(0.4)
	check("standing over a weapon offers it", lw.hover == drop_w)
	Input.action_press("pickup")
	await frames(3)
	Input.action_release("pickup")
	await secs(0.6)
	check("Q picks it up into the rifle slot", lw.loadout["rifle"].size() == 2 and lw.loadout["rifle"][1]["id"] == "carbine")
	var carb: Dictionary = lw.loadout["rifle"][1]
	check("picked-up weapon keeps the rounds it had", carb["ammo"] == 17, str(carb["ammo"]))
	check("picked-up weapon comes with a full set of finite magazines", (carb["spare"] as Array).size() >= 4 and (carb["spare"] as Array).size() <= Weapons.MAX_SPARE_MAGS and (carb["spare"] as Array).slice(0, 4).all(func(m): return m == 24), str(carb["spare"]))
	check("it is now in hand", lw.current == "carbine")

	# third rifle: only two fit, the one in hand is dropped on the ground
	var ground_before := Game.pickups.size()
	var hmg_pk := Pickup.spawn_weapon(main, player.global_position + Vector3(0.5, 0, 0), "hmg", 41)
	for stray in Game.pickups.duplicate():      # loot dropped by earlier kills (random spots, maybe a sidearm) must not be taken instead
		if is_instance_valid(stray) and stray != hmg_pk and not (stray as Pickup).is_ammo and (stray as Pickup).global_position.distance_to(player.global_position) < 4.0:
			(stray as Pickup).queue_free()
	await frames(3)
	Input.action_press("pickup")
	await frames(3)
	Input.action_release("pickup")
	await secs(0.6)
	check("a slot never holds more than two weapons", lw.loadout["rifle"].size() == 2)
	check("the new weapon replaced the one in hand", lw.current == "hmg" and lw.state["hmg"]["ammo"] == 41, lw.current)
	var dropped_carbine := false
	for pk in Game.pickups:
		if not (pk as Pickup).is_ammo and (pk as Pickup).weapon_id == "carbine" and (pk as Pickup).ammo == 17:
			dropped_carbine = true
	check("the replaced weapon lies on the ground with its rounds", dropped_carbine)

	# slot keys: pressing the same slot flips between its two weapons
	lw._slot_key("rifle")
	await secs(0.5)
	check("pressing the slot again swaps to the other rifle", lw.current == "rifle", lw.current)
	lw._slot_key("rifle")
	await secs(0.5)
	check("and back", lw.current == "hmg", lw.current)

	# melee: knife in hand, swing at a nearby enemy
	var dummy: Enemy = main._spawn_enemy_at(Vector3(0, 0, -30), "soldier")
	all.append(dummy)
	await frames(2)
	dummy.stun = 999.0
	dummy.health = 1.0e6
	player.global_position = Vector3(0, World.height_at(0, 0) + 0.1, 0)
	player.velocity = Vector3.ZERO
	dummy.global_position = Vector3(0, World.height_at(0, -1.6) + 0.1, -1.6)
	await secs(0.4)
	lw.switch_to("knife")
	await secs(0.6)
	check("knife is in hand", lw.current == "knife" and lw.is_melee(), lw.current)
	aim_at(dummy.global_position + Vector3(0, 1.1, 0))
	var kh0 := dummy.health
	lw.cooldown = 0.0
	lw._melee_swing()
	await secs(0.5)
	check("knife slash does 45 damage", absf((kh0 - dummy.health) - 45.0) < 0.5, "%.1f" % (kh0 - dummy.health))
	dummy.stun = 999.0
	dummy.state = Enemy.State.DEAD
	dummy.rig.visible = false
	Game.enemies.erase(dummy)

	print("--- city ---")
	var tallest := 0.0
	var lowest := 1.0e9
	for b in City.buildings:
		tallest = maxf(tallest, float(b["h"]))
		lowest = minf(lowest, float(b["h"]))
	check("city has buildings from one floor to supertall towers", lowest < 7.0 and tallest > 220.0, "lowest %.1f m, tallest %.1f m" % [lowest, tallest])
	var classes := {}
	var width_by_class := {}
	for s in City.streets:
		classes[s["cls"]] = true
		var rr: Rect2 = s["rect"]
		var narrow := minf(rr.size.x, rr.size.y)
		width_by_class[s["cls"]] = minf(float(width_by_class.get(s["cls"], 1.0e9)), narrow)
	check("street classes: avenues, streets, footpaths and alleys", classes.has("avenue") and classes.has("street") and classes.has("walk") and classes.has("alley"), str(classes.keys()))
	check("alleys are very narrow, avenues are wide", float(width_by_class["alley"]) < 4.0 and float(width_by_class["avenue"]) >= 20.0, str(width_by_class))
	var in_building := 0
	for en_b in Game.enemies:
		for b in City.buildings:
			if (b["rect"] as Rect2).has_point(Vector2(en_b.global_position.x, en_b.global_position.z)):
				in_building += 1
	check("nobody stands inside a building", in_building == 0, str(in_building))
	var srng := RandomNumberGenerator.new()
	srng.seed = 9
	var by_class := {"avenue": 0, "plaza": 0, "street": 0, "walk": 0, "alley": 0}
	for i in 3000:
		var sp := City.random_spawn(srng, Vector3.ZERO, 100.0)
		by_class[sp["cls"]] += 1
	check("wide streets get the most soldiers, narrow ones the fewest", by_class["avenue"] > by_class["street"] and by_class["street"] > by_class["walk"] and by_class["walk"] > by_class["alley"] and by_class["avenue"] > by_class["plaza"], str(by_class))
	var route := City.path(Vector3(0, 0, -80), Vector3(112, 0, -105))
	var route_ok := route.size() > 1
	for wp in route:
		if not City.is_free(wp):
			route_ok = false
	check("path finding finds a route between two avenues", route_ok, "%d waypoints" % route.size())

	print("--- soldiers: shooting, hearing, losing track ---")
	for en in all:
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			place(en, park_pos(en), true)
	player.global_position = Vector3(0, World.height_at(0, 0) + 0.1, 0)
	player.velocity = Vector3.ZERO
	player.health = Game.MAX_HEALTH
	await secs(0.3)

	# a soldier now shoots: he hurts the player from a distance
	var shooter: Enemy = main._spawn_enemy_at(Vector3(0, 0, -25), "soldier")
	all.append(shooter)
	await frames(2)
	shooter.state = Enemy.State.CHASE
	var soldier_shot := false
	for i in 900:
		await frames(1)
		if player.health < Game.MAX_HEALTH and shooter.global_position.distance_to(player.global_position) > 8.0:
			soldier_shot = true
			break
	check("a soldier shoots from a distance", soldier_shot, "hp %.0f state %d" % [player.health, shooter.state])
	shooter.stun = 999.0
	shooter.state = Enemy.State.DEAD
	shooter.rig.visible = false
	Game.enemies.erase(shooter)

	# sneaking: crouched behind a soldier = unheard, standing next to him = heard
	player.health = Game.MAX_HEALTH
	player.global_position = Vector3(0, World.height_at(0, -17) + 0.1, -17)
	player.velocity = Vector3.ZERO
	var guard: Enemy = main._spawn_enemy_at(Vector3(0, 0, -20), "soldier")
	all.append(guard)
	await frames(2)
	guard.global_position = Vector3(0, 0.1, -20)
	guard.facing = 0.0                 # facing -z, away from the player who stands 3 m behind him
	guard.rig.rotation.y = 0.0
	guard.wait_t = 99.0
	guard.stun = 999.0                 # frozen until the player has finished crouching
	guard.state = Enemy.State.WANDER
	Input.action_press("crouch")
	await secs(0.8)
	guard.stun = 0.0
	await secs(1.5)
	check("a crouched player behind a soldier is not noticed", guard.state == Enemy.State.WANDER, str(guard.state))
	Input.action_release("crouch")
	await secs(0.8)
	check("the same player standing up is heard", guard.state != Enemy.State.WANDER, str(guard.state))
	guard.stun = 999.0
	guard.state = Enemy.State.DEAD
	guard.rig.visible = false
	Game.enemies.erase(guard)

	# out of sight for a few seconds: the hunt ends and he wanders again
	player.global_position = Vector3(0, World.height_at(0, 0) + 0.1, 0)
	player.velocity = Vector3.ZERO
	var wall2 := StaticBody3D.new()
	wall2.collision_layer = Game.L_WORLD
	var w2cs := CollisionShape3D.new()
	var w2b := BoxShape3D.new()
	w2b.size = Vector3(30, 12, 1)
	w2cs.shape = w2b
	wall2.add_child(w2cs)
	main.add_child(wall2)
	wall2.global_position = Vector3(0, 6, -22)
	var hunter2: Enemy = main._spawn_enemy_at(Vector3(0, 0, -45), "soldier")
	all.append(hunter2)
	await frames(2)
	hunter2.state = Enemy.State.CHASE
	hunter2.last_known = Vector3(0, 0, 0)
	hunter2.unseen_t = 0.0
	await secs(1.0)
	check("a soldier with no line of sight keeps hunting at first", hunter2.state == Enemy.State.CHASE, str(hunter2.state))
	await secs(Enemy.LOSE_TIME + 1.5)
	check("after losing the player for a few seconds he just wanders", hunter2.state == Enemy.State.WANDER, str(hunter2.state))
	hunter2.stun = 999.0
	hunter2.state = Enemy.State.DEAD
	hunter2.rig.visible = false
	Game.enemies.erase(hunter2)
	wall2.queue_free()

	print("--- loot expiry, vehicles, scopes ---")
	for pk in Game.pickups.duplicate():
		pk.queue_free()
	await frames(2)
	var old_w := Pickup.spawn_weapon(main, Vector3(0, 0, -50), "carbine", 10)
	var old_a := Pickup.spawn_ammo(main, Vector3(0, 0, -52), "carbine", 10)
	old_w._t = Pickup.LIFE_WEAPON - 0.1
	old_a._t = Pickup.LIFE_AMMO - 0.1
	await secs(0.4)
	check("an unclaimed weapon disappears after a while", not is_instance_valid(old_w) or old_w.is_queued_for_deletion())
	check("an unclaimed magazine disappears after a while", not is_instance_valid(old_a) or old_a.is_queued_for_deletion())
	var fresh_w := Pickup.spawn_weapon(main, Vector3(0, 0, -50), "carbine", 10)
	await secs(0.4)
	check("a fresh drop stays", is_instance_valid(fresh_w) and not fresh_w.is_queued_for_deletion())
	fresh_w.queue_free()
	var car_types := {}
	var car_lengths := {}
	for c in City.cars:
		car_types[c["type"]] = true
		car_lengths[snappedf((c["size"] as Vector3).z, 0.5)] = true
	check("parked vehicles come in several types and sizes", car_types.size() >= 4 and car_lengths.size() >= 6, "%s, %d lengths" % [str(car_types.keys()), car_lengths.size()])
	var sw: Weapons = player.weapons
	sw.loadout["rifle"][1] = Weapons.new_weapon("railgun")
	sw._equip("rifle", 1)
	sw.ads_k = 1.0
	check("the rail rifle looks through a scope when aimed", sw.is_scoped())
	sw.loadout["rifle"][1] = Weapons.new_weapon("carbine")
	sw._equip("rifle", 1)
	check("the other guns do not", not sw.is_scoped())
	var sights_ok := true
	for wid in ["carbine", "hmg", "railgun"]:
		var wd: Dictionary = WeaponsDB.WEAPONS[wid]
		var ap := sw._ads_pos(wd)
		# sight tips (top_y + SIGHT_H) land on the line of sight; the receiver top is SIGHT_H below it
		if absf(ap.y + float(wd["top_y"]) + Weapons.SIGHT_H) > 0.001:
			sights_ok = false
	check("box-built guns are aimed along their iron sights, not through the receiver", sights_ok)
	sw.ads_k = 0.0

	print("--- battle sites, border, goal ---")
	check("there are battle sites", City.sites.size() == City.SITE_COUNT and main.world.sites.size() == City.SITE_COUNT, str(City.sites.size()))
	for en in all:
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			place(en, park_pos(en), true)
	# big groups with at least one blade fighter and one sniper stand at every site
	var groups_ok: bool = main.site_groups.size() == City.sites.size()
	for gi in main.site_groups.size():
		var n_near: int = (main.site_groups[gi] as Array).size()
		var has_blade := false
		var has_sniper := false
		for member in main.site_groups[gi]:
			has_blade = has_blade or (member as Enemy).kind == "blade"
			has_sniper = has_sniper or (member as Enemy).kind == "marksman"
		if n_near < 3 or not has_blade or not has_sniper:          # sites hold 3-4 (the first 5) since the soldiers were halved
			groups_ok = false
			print("   site ", gi, ": ", n_near, " blade ", has_blade, " sniper ", has_sniper)
	check("every battle site has a big group with a blade fighter and a sniper", groups_ok)
	# detail is streamed by distance: only the site around the player burns
	var near_site: Site = main.world.sites[0]
	var far_site: Site = main.world.sites[0]
	for s2 in main.world.sites:
		var pd := (s2 as Site).position.distance_to(City.START_POS)
		if pd > far_site.position.distance_to(City.START_POS):
			far_site = s2
	player.global_position = Vector3(near_site.position.x + 3.0, 0.1, near_site.position.z + 3.0)
	player.velocity = Vector3.ZERO
	await secs(1.0)
	var near_smoke: CPUParticles3D = near_site._fires[0]["smoke"]
	check("the site around the player is fully lit and smoking", near_site.lod == 3 and near_site._light.visible and near_smoke.emitting, "lod %d" % near_site.lod)
	if far_site != near_site and far_site.position.distance_to(near_site.position) > Site.FAR + 10.0:
		check("a distant site is switched off completely", far_site.lod == 0 and not far_site.visible, "lod %d" % far_site.lod)
	var any_off := false
	for s3 in main.world.sites:
		if (s3 as Site).lod < 2:
			var sm: CPUParticles3D = (s3 as Site)._fires[0]["smoke"]
			any_off = any_off or not sm.emitting
	check("sites away from the player do not run their fire particles", any_off or main.world.sites.size() < 2)
	check("level of detail by distance", Site.lod_for(10.0, 0) == 3 and Site.lod_for(80.0, 0) == 2 and Site.lod_for(160.0, 0) == 1 and Site.lod_for(300.0, 3) == 0)
	# far wanderers still walk, just with a cheaper update
	for old_body in Enemy.bodies.duplicate():      # corpses of earlier tests would make him suspicious
		if is_instance_valid(old_body):
			old_body.queue_free()
	await frames(3)
	var far_walker: Enemy = main._spawn_enemy_at(Vector3(0, 0, 0), "soldier")
	all.append(far_walker)
	await frames(2)
	player.global_position = Vector3(0, 0.1, 200.0)
	player.velocity = Vector3.ZERO
	far_walker.state = Enemy.State.WANDER
	far_walker.stun = 0.0
	far_walker.wait_t = 0.0
	far_walker.home = far_walker.global_position
	far_walker._pick_wander_point()
	var fw0 := far_walker.global_position
	await secs(4.0)
	check("a wanderer far from the player still walks around", far_walker.global_position.distance_to(fw0) > 1.5 and far_walker.state == Enemy.State.WANDER, "%.1f m" % far_walker.global_position.distance_to(fw0))
	far_walker.stun = 999.0
	place(far_walker, park_pos(far_walker), true)
	# the map is closed by buildings: the whole ring around the playable area is covered and rays from the middle all hit something
	var gaps := 0
	for i in 200:
		var t := -1.0 + 2.0 * float(i) / 199.0
		var probes := [Vector2(t * (City.OUT_X - 1.0), City.IN_Z + City.RING * 0.5), Vector2(t * (City.OUT_X - 1.0), -City.IN_Z - City.RING * 0.5),
			Vector2(City.IN_X + City.RING * 0.5, t * (City.OUT_Z - 1.0)), Vector2(-City.IN_X - City.RING * 0.5, t * (City.OUT_Z - 1.0))]
		for probe in probes:
			var covered := false
			for b in City.buildings:
				if (b["rect"] as Rect2).has_point(probe):
					covered = true
			if not covered:
				gaps += 1
	check("buildings close the whole map border, no gaps", gaps == 0, "%d gaps" % gaps)
	var free_rays := 0
	for i in 72:
		var a2 := TAU * float(i) / 72.0
		var origin := Vector3(0, 1.0, 0)
		var q2 := PhysicsRayQueryParameters3D.create(origin, origin + Vector3(cos(a2), 0, sin(a2)) * 420.0, Game.L_WORLD)
		if player.get_world_3d().direct_space_state.intersect_ray(q2).is_empty():
			free_rays += 1
	check("nothing leads out of the map", free_rays == 0, "%d open directions" % free_rays)
	check("the map is a strip, longer than wide", City.OUT_Z > City.OUT_X * 1.8)
	await mission_and_map_tests()

	print("--- group alerts, route, border lanes ---")
	for en in all:
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			place(en, park_pos(en), true)
	player.global_position = Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO
	player.health = Game.MAX_HEALTH
	await secs(0.4)
	# three soldiers of one group see the player: the fourth, who is looking the other way, is told
	var crew: Array[Enemy] = []
	for sp in [Vector3(-3, 0, -30), Vector3(0, 0, -30), Vector3(3, 0, -30), Vector3(9, 0, -16)]:
		var cs: Enemy = main._spawn_enemy_at(sp, "soldier")
		cs.group = 900
		all.append(cs)
		crew.append(cs)
	await frames(3)
	for i in crew.size():
		var cm := crew[i]
		cm.facing = PI if i < 3 else 0.0           # the first three face the player, the fourth faces away
		cm.rig.rotation.y = cm.facing
		cm.wait_t = 99.0
		cm.stun = 0.0
		cm.state = Enemy.State.WANDER
	await secs(1.5)
	check("soldiers who see the player on their own start hunting", crew[0].state != Enemy.State.WANDER and crew[1].state != Enemy.State.WANDER and crew[2].state != Enemy.State.WANDER)
	check("with three of the group aware the fourth is told too", crew[3].state != Enemy.State.WANDER and not crew[3].noticed_self, "state %d" % crew[3].state)
	for cm in crew:
		cm.stun = 999.0
		cm.state = Enemy.State.DEAD
		cm.rig.visible = false
		Game.enemies.erase(cm)
	for old_body2 in Enemy.bodies.duplicate():
		if is_instance_valid(old_body2):
			old_body2.queue_free()
	await frames(3)
	# one soldier (or a lone sniper) notices him: nobody else finds out
	var lone: Array[Enemy] = []
	for sp2 in [Vector3(0, 0, -30), Vector3(9, 0, -30), Vector3(-9, 0, -30)]:
		var ls: Enemy = main._spawn_enemy_at(sp2, "soldier")
		ls.group = 901
		all.append(ls)
		lone.append(ls)
	await frames(3)
	for i in lone.size():
		var lm := lone[i]
		lm.facing = PI if i == 0 else 0.0
		lm.rig.rotation.y = lm.facing
		lm.wait_t = 99.0
		lm.stun = 0.0
		lm.state = Enemy.State.WANDER
	await secs(2.0)
	check("a single soldier that spots the player acts alone", lone[0].state != Enemy.State.WANDER and lone[1].state == Enemy.State.WANDER and lone[2].state == Enemy.State.WANDER, "%d %d %d" % [lone[0].state, lone[1].state, lone[2].state])
	for lm in lone:
		lm.stun = 999.0
		lm.state = Enemy.State.DEAD
		lm.rig.visible = false
		Game.enemies.erase(lm)
	# the way to the goal passes campfires, the map has no walled-in pockets and the lanes along the border are broken up
	var route_sites := 0
	for s in City.sites:
		if absf((s["center"] as Vector3).x) < 15.0:
			route_sites += 1
	check("there is a campfire on the central avenue on the way home", route_sites >= 1, str(route_sites))
	var goal_route := City.path(City.START_POS, City.HOME_POS)
	check("a walkable route leads from the start to the home", goal_route.size() > 1)
	var frac := City.reachable_fraction(City.START_POS)
	check("everything inside the map can be reached on foot (no walled-in pockets)", frac > 0.985, "%.3f" % frac)
	var plugs := 0
	var open_lane_len := 0.0
	for b in City.buildings:
		if b.get("plug", false):
			plugs += 1
	for s in City.streets:
		var rr: Rect2 = s["rect"]
		if s["cls"] == "walk" and is_equal_approx(rr.position.y, -City.IN_Z) and is_equal_approx(rr.size.y, City.LANE):
			open_lane_len += rr.size.x
	check("border lanes are broken up by buildings (no ring road)", plugs >= 8 and open_lane_len > 20.0 and open_lane_len < City.IN_X * 2.0 * 0.85, "%d plugs, north lane open %.0f of %.0f m" % [plugs, open_lane_len, City.IN_X * 2.0])
	var avenue_n := 0
	for s in City.streets:
		if s["cls"] == "avenue":
			avenue_n += 1
	check("only a few wide streets", avenue_n <= 5, str(avenue_n))

	print("--- weapon models ---")
	var models_ok := true
	for wid in WeaponsDB.ORDER:
		for lod in [1, 2]:
			var gm := GunModels.build(wid, lod)
			var gmesh := gm.mesh as ArrayMesh
			if gmesh == null or gmesh.get_surface_count() < 1 or gmesh.get_aabb().size.length() < 0.2:
				models_ok = false
			gm.free()
		if GunModels.profile(wid).size() < 5:
			models_ok = false
	check("every weapon has a procedural model with several parts and a HUD profile", models_ok)
	var detail_1 := (GunModels.build("carbine", 1).mesh as ArrayMesh).get_aabb().size
	var parts_1: int = (GunModels.build("carbine", 1).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	var parts_2: int = (GunModels.build("carbine", 2).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	check("the viewmodel version has more detail than the world version", parts_2 > parts_1, "%d vs %d vertices" % [parts_2, parts_1])
	check("models are shared, not rebuilt per soldier", GunModels.build("carbine", 1).mesh == GunModels.build("carbine", 1).mesh and detail_1.z > 0.5)
	var low_ok := true
	for wid in ["carbine", "hmg"]:
		var top: float = (GunModels.build(wid, 2).mesh as ArrayMesh).get_aabb().end.y
		if top > GunModels.SIGHT_H + 0.002:
			low_ok = false       # nothing may stand higher than the sight tips, or it would block the view when aiming
	check("nothing on the aimed guns rises above their sights", low_ok)
	var held_ok := true
	for held in Game.enemies:
		if (held as Enemy).muzzle == null and (held as Enemy).ranged:
			held_ok = false
	check("every shooting soldier holds a model with a muzzle", held_ok)

	await stealth_tests()
	await grenade_tests()
	await civilian_tests()
	await character_tests()
	await street_tests()
	await building_tests()
	await climb_tests()
	await passage_tests()
	await collider_tests()
	await perf_tool_tests()
	await squad_tests()
	await invasion_tests()
	await lander_tests()
	await checkpoint_and_finish_tests()      # prints the result and quits


# ---------------------------------------------------------------- Chapter One

var snap := {}


func tp(p: Vector3, yaw: float = 0.0) -> void:
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.yaw = yaw
	player.pitch = 0.0
	player.rotation.y = yaw
	player.head.rotation = Vector3.ZERO
	player.recoil_pitch = 0.0
	player.recoil_yaw = 0.0


func plen(from: Vector3, pts: PackedVector3Array) -> float:
	var t := 0.0
	var prev := from
	for p in pts:
		t += Vector2(p.x - prev.x, p.z - prev.z).length()
		prev = p
	return t


## True when no wall is between the consecutive flat waypoints of a path (chest height ray).
func path_clear(from: Vector3, pts: PackedVector3Array) -> bool:
	var space := player.get_world_3d().direct_space_state
	var prev := from
	for p in pts:
		if absf(p.y - prev.y) < 0.2:
			var q := PhysicsRayQueryParameters3D.create(prev + Vector3(0, 1.0, 0), p + Vector3(0, 1.0, 0), Game.L_WORLD)
			if not space.intersect_ray(q).is_empty():
				print("   wall between ", prev, " and ", p)
				return false
		prev = p
	return true


func home_pt(u: float, v: float) -> Vector3:
	return Vector3(City.HOME_ORIGIN.x + u, 0.0, City.HOME_ORIGIN.y + v)


func mission_and_map_tests() -> void:
	print("--- Chapter One: mission, Institute, home, cellar, park ---")
	var ms: Mission = Game.mission
	var texts: Array = []
	for o in ms.objectives:
		texts.append(String(o["text"]))
	check("the story mission starts with the three Chapter One objectives in order, then the roof, the lookout, the marksman, his rifle, the park fight and the lanes (The Lander, part one)", ms.id == "chapter_one" and texts.slice(0, 3) == ["LEAVE THE INSTITUTE", "GET HOME", "GO TO THE CELLAR"] and texts.slice(3, 8) == ["CLIMB TO THE ROOF", "LOOK OUT OVER THE CITY", "TAKE OUT THE MARKSMAN ON THE BALCONY", "TAKE HIS RIFLE", "THIN OUT THE GUARDS AT THE RAMP"], str(texts))
	check("enemies respawn in the sandbox mission only", not ms.respawn_enemies and Mission.sandbox().respawn_enemies)
	check("the first objective is active and the marker hangs over it", ms.index == 0 and main.world._marker.visible and main.world._marker.position.y > 60.0 and absf(main.world._marker.position.x - City.INSTITUTE_EXIT.x) < 1.0 and absf(main.world._marker.position.z - City.INSTITUTE_EXIT.z) < 1.0)
	check("the first objective saved a checkpoint", main.checkpoint != null and main.checkpoint.objective == 0 and Game.has_checkpoint)
	var hud_line: String = ms.hud_text(player)
	check("the HUD line shows the objective and the distance", hud_line.begins_with("LEAVE THE INSTITUTE") and hud_line.ends_with(" m"), hud_line)
	var tall_ok := false
	var pale_ok := false
	for b in City.buildings:
		if b.get("institute", false):
			tall_ok = float(b["h"]) > 175.0 and float(b["h"]) < 200.0
			var c: Color = b["color"]
			pale_ok = c.r > 0.88 and c.g > 0.88 and c.b > 0.8
	check("the Institute is a pale tower about 180 m tall", tall_ok and pale_ok)
	var lob := City.LOBBY
	check("the lobby is 16 x 12 m, 5 m high, with a 3 m doorway in the front wall", is_equal_approx(lob.size.x, 16.0) and is_equal_approx(lob.size.y, 12.0) and is_equal_approx(City.LOBBY_H, 5.0))
	var door_ray_ok := true
	var space := player.get_world_3d().direct_space_state
	for dx in [-1.4, 0.0, 1.4]:
		var qd := PhysicsRayQueryParameters3D.create(Vector3(City.START_POS.x + dx, 1.0, 252.0), Vector3(City.START_POS.x + dx, 1.0, 240.0), Game.L_WORLD)
		if not space.intersect_ray(qd).is_empty():
			door_ray_ok = false
	var qw := PhysicsRayQueryParameters3D.create(Vector3(City.START_POS.x - 3.0, 1.0, 252.0), Vector3(City.START_POS.x - 3.0, 1.0, 240.0), Game.L_WORLD)
	check("the doorway is open 3 m wide and the walls beside it are solid", door_ray_ok and not space.intersect_ray(qw).is_empty())
	# routes
	var direct := City.path(City.INSTITUTE_EXIT, City.HOME_POS)
	var d_len := plen(City.INSTITUTE_EXIT, direct)
	check("the home is 250 - 300 m from the Institute by road", d_len >= 250.0 and d_len <= 300.0, "%.0f m" % d_len)
	var saved: Array = []
	var grid: AStarGrid2D = City._astar
	for gz in range(int(City.OUT_Z - 12.0), int(City.OUT_Z + 226.0)):
		for gx in range(int(City.OUT_X - 12.0), int(City.OUT_X + 12.0)):
			if not grid.is_point_solid(Vector2i(gx, gz)):
				saved.append(Vector2i(gx, gz))
				grid.set_point_solid(Vector2i(gx, gz), true)
	var back := City.path(City.INSTITUTE_EXIT, City.HOME_POS)
	for c in saved:
		grid.set_point_solid(c, false)
	var b_len := plen(City.INSTITUTE_EXIT, back)
	check("with the wide avenue closed a longer back route through streets and alleys still leads home", back.size() > 1 and b_len > d_len * 1.15, "direct %.0f m, back %.0f m" % [d_len, b_len])
	check("alleys and footpaths between the Institute and the home are quieter, the avenue busier", City.spawn_weight("alley", Rect2(0, 0, 3, 100)) < City.spawn_weight("alley", Rect2(100, 0, 3, 100)) and City.spawn_weight("walk", Rect2(0, 0, 8, 100)) < City.spawn_weight("walk", Rect2(100, 0, 8, 100)) and City.spawn_weight("avenue", Rect2(0, 0, 24, 100)) > City.spawn_weight("avenue", Rect2(100, 0, 24, 100)))
	var sites_ok := true
	for s in City.sites:
		var sc: Vector3 = s["center"]
		if sc.distance_to(City.HOME_POS) < 60.0 or sc.distance_to(City.INSTITUTE_POS) < 60.0:
			sites_ok = false
	check("no battle site is within 60 m of the home or the Institute", sites_ok)
	# the apartment
	var home_ok := City.layer_of(City.HOME_POS) >= 0 and City.layer_of(City.CELLAR_POS) >= 0 and City.layer_of(City.CELLAR_POS) != City.layer_of(City.HOME_POS)
	check("the home and the cellar are separate navigation layers", home_ok)
	check("the apartment is 14 x 10 m with 3 m ceilings, the cellar 6 x 5 m and 2.4 m high", is_equal_approx(City.APT_H, 3.0) and is_equal_approx(City.CELLAR_RECT.size.x, 6.0) and is_equal_approx(City.CELLAR_RECT.size.y, 5.0) and is_equal_approx(City.CELLAR_CEIL_Y - City.CELLAR_FLOOR_Y, 2.4))
	var rooms := {"hallway": home_pt(2.0, 5.0), "kitchen": home_pt(2.5, 1.7), "living room": home_pt(10.0, 3.0), "bedroom": home_pt(9.0, 8.5), "bathroom": home_pt(1.5, 8.5), "stairs door": City.CELLAR_DOOR_POS}
	var rooms_ok := true
	for rn in rooms:
		var pr := City.path(Vector3(City.HOME_POS.x - 10.0, 0.0, City.HOME_POS.z), rooms[rn])
		if pr.size() < 2 or Vector2(pr[pr.size() - 1].x - rooms[rn].x, pr[pr.size() - 1].z - rooms[rn].z).length() > 1.0 or not path_clear(Vector3(City.HOME_POS.x - 10.0, 0.0, City.HOME_POS.z), pr):
			rooms_ok = false
			print("   cannot walk to the ", rn)
	check("from the street every room of the apartment can be walked to through its doorways", rooms_ok)
	var cellar_route := City.path(Vector3(City.HOME_POS.x - 10.0, 0.0, City.HOME_POS.z), City.CELLAR_POS)
	var through_door := false
	var down_stairs := false
	for wp in cellar_route:
		if Vector2(wp.x - City.HOME_POS.x, wp.z - City.HOME_POS.z).length() < 1.5:
			through_door = true
		if wp.y < -1.0:
			down_stairs = true
	check("an enemy path leads in through the front door and down the stairs into the cellar", cellar_route.size() > 3 and through_door and down_stairs and cellar_route[cellar_route.size() - 1].y < -2.0, "%d waypoints" % cellar_route.size())
	check("those waypoints do not cut through walls", path_clear(Vector3(City.HOME_POS.x - 10.0, 0.0, City.HOME_POS.z), cellar_route))
	var out_route := City.path(City.CELLAR_POS, Vector3(City.HOME_POS.x - 10.0, 0.0, City.HOME_POS.z))
	check("and a path leads back up and out", out_route.size() > 3)
	var hole_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(20.2, 2.0, -27.0), Vector3(20.2, -5.0, -27.0), Game.L_WORLD))
	check("the ground is open above the stairs and a slope leads down", not hole_hit.is_empty() and (hole_hit["position"] as Vector3).y < -1.0 and (hole_hit["position"] as Vector3).y > -2.7, str(hole_hit.get("position")))
	var ceil_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(20.4, -1.0, -22.5), Vector3(20.4, 3.0, -22.5), Game.L_WORLD))
	var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(20.4, -0.5, -22.5), Vector3(20.4, -5.0, -22.5), Game.L_WORLD))
	check("the cellar has a ceiling at -0.3 m and a floor 2.4 m below it", not ceil_hit.is_empty() and absf((ceil_hit["position"] as Vector3).y - City.CELLAR_CEIL_Y) < 0.05 and not floor_hit.is_empty() and absf((floor_hit["position"] as Vector3).y - City.CELLAR_FLOOR_Y) < 0.05)
	var cover := false
	for pr2 in City.props:
		if String(pr2["nav"]) == "home" and float(pr2["y1"]) >= 0.9 and float(pr2["y1"]) <= 1.2 and (pr2["rect"] as Rect2).get_center().distance_to(Vector2(City.HOME_ORIGIN.x + 2.0, City.HOME_ORIGIN.y + 0.5)) < 3.0:
			cover = true
	check("the kitchen counter is a solid, waist-high object (cover)", cover)
	var shelves := 0
	for pr3 in City.props:
		if String(pr3["nav"]) == "cellar" and float(pr3["y1"]) - float(pr3["y0"]) > 1.5:
			shelves += 1
	check("the cellar has storage shelves along its walls", shelves >= 3, str(shelves))
	# the park
	var park_clear := true
	var lz := City.LANDING
	for t in City.trees:
		if lz.grow(0.5).has_point(t["pos"]):
			park_clear = false
	for pr4 in City.props:
		if lz.intersects(pr4["rect"]):
			park_clear = false
	for b2 in City.buildings:
		if lz.intersects(b2["rect"]):
			park_clear = false
	for gx2 in range(0, 31, 5):
		for gz2 in range(0, 16, 5):
			var gp2 := Vector3(lz.position.x + gx2, 0.0, lz.position.y + gz2)
			if not City.is_free(gp2) and not Rect2(City.LANDER_POS.x - 10.5, City.LANDER_POS.z - 7.7, 21.0, 15.4).has_point(Vector2(gp2.x, gp2.z)):          # (only the landing craft's hull blocks the ground there)
				park_clear = false
	check("the landing area (30 x 15 m) in the middle of the park is clear of trees, props and buildings (the landing craft stands on it, its ramp facing west)", park_clear and is_equal_approx(lz.size.x, 30.0) and is_equal_approx(lz.size.y, 15.0) and City.PARK_RECT.encloses(lz))
	check("the park is within 120 m of the home and 40 x 40 m", City.PARK_POS.distance_to(City.HOME_POS) < 120.0 and is_equal_approx(City.PARK_RECT.size.x, 40.0) and is_equal_approx(City.PARK_RECT.size.y, 40.0))
	var park_trees := 0
	for t2 in City.trees:
		if City.PARK_RECT.has_point(t2["pos"]):
			park_trees += 1
	check("there are about a dozen trees in the park", park_trees >= 10 and park_trees <= 14, str(park_trees))
	var to_park := City.path(City.START_POS, City.PARK_POS)
	check("the park centre can be reached from the start on foot", to_park.size() > 1)
	var to_balcony := City.path(City.START_POS, City.BALCONY_POS)
	check("the balcony can be reached by the outside stair", to_balcony.size() > 3 and absf(to_balcony[to_balcony.size() - 1].y - City.BALCONY_Y) < 0.2)
	check("the balcony ledge overlooks the park, 2nd floor high", City.BALCONY_POS.y > 3.0 and City.BALCONY_POS.z > City.PARK_RECT.end.y - 1.0 and City.layer_of(City.BALCONY_POS) >= 0)
	var street_trees := 0
	for t3 in City.trees:
		if not City.PARK_RECT.has_point(t3["pos"]):
			street_trees += 1
	check("street trees line the wide avenues (each blocks its nav cell)", street_trees >= 60 and not City.is_free(Vector3(City.trees[City.trees.size() - 1]["pos"].x, 0.0, City.trees[City.trees.size() - 1]["pos"].y)), str(street_trees))
	check("the distant skyline is all towers (no scattered trees)", City.far_trees.is_empty() and City.backdrop.size() > 100, str(City.backdrop.size()))
	# an enemy that hunts walks in through the door and down the stairs
	var hunter: Enemy = main._spawn_enemy_at(Vector3(20.2, 0.0, -31.2), "soldier")
	all.append(hunter)
	await frames(3)
	tp(Vector3(80.0, 0.1, -50.0))
	hunter.last_known = City.CELLAR_POS
	hunter.state = Enemy.State.CHASE
	hunter.unseen_t = 0.0
	await secs(3.0)
	check("a hunting soldier walks down the stairs into the cellar", hunter.global_position.y < -2.0 and hunter.global_position.distance_to(Vector3(City.CELLAR_POS.x, hunter.global_position.y, City.CELLAR_POS.z)) < 6.0, str(hunter.global_position))
	hunter.stun = 999.0
	place(hunter, park_pos(hunter), true)
	await secs(0.4)
	# the player walks out of the lobby: first objective done
	var done: Array = []
	Game.objective_completed.connect(func(oid: String, _t: String) -> void: done.append(oid))
	tp(City.START_POS)
	await secs(0.6)
	check("the player stands inside the lobby on the floor", player.is_on_floor() and City.LOBBY.has_point(Vector2(player.global_position.x, player.global_position.z)))
	Input.action_press("move_forward")
	await secs(3.2)
	Input.action_release("move_forward")
	check("the player walks out of the doorway and LEAVE THE INSTITUTE completes", player.global_position.z < 244.0 and done == ["leave_institute"] and ms.index == 1, "z=%.1f %s" % [player.global_position.z, str(done)])
	check("a checkpoint was saved for the new objective", main.checkpoint.objective == 1)
	await secs(1.2)
	check("the marker moved over the home", absf(main.world._marker.position.x - City.HOME_POS.x) < 1.0 and absf(main.world._marker.position.z - City.HOME_POS.z) < 1.0)
	# a few civilians (and two bodies) far away, so the checkpoint taken at the next objective has some to restore
	for i in 5:
		var cc := Civilian.spawn(main, player, Vector3(-3.0 + 1.5 * i, 0.0, -230.0), 500 + i)
		cc.leave_t = 1.0e9
	Civilian.spawn(main, player, Vector3(-3.0, 0.0, -235.0), 520).lie_down()
	Civilian.spawn(main, player, Vector3(0.0, 0.0, -236.0), 521).lie_down()
	await frames(4)
	# walk in through the front door: GET HOME completes at the door, the player ends up inside the hallway
	tp(Vector3(12.6, 0.1, City.HOME_POS.z), -PI * 0.5)
	await secs(0.4)
	Input.action_press("move_forward")
	await secs(2.2)
	Input.action_release("move_forward")
	check("walking through the front door completes GET HOME", done == ["leave_institute", "get_home"] and ms.index == 2, str(done))
	check("the player is inside the apartment, walked through the doorways", player.global_position.x > 17.0 and player.global_position.x < 30.0 and City.layer_of(player.global_position) == City.layer_of(City.HOME_POS) and player.is_on_floor(), str(player.global_position))
	await secs(0.3)
	snap = {"pos": main.checkpoint.pos, "health": player.health, "kills": Game.kills, "fired": Game.shots_fired, "hit": Game.shots_hit,
		"loadout": str(player.weapons.loadout), "enemies": Game.enemies.size(), "uids": [], "cp_enemies": main.checkpoint.enemies.size()}
	for e in Game.enemies:
		(snap["uids"] as Array).append(e.uid)
	player.global_position = Vector3(0, 0.1, 0)
	player.velocity = Vector3.ZERO
	await secs(0.5)


func checkpoint_and_finish_tests() -> void:
	print("--- player death, checkpoint ---")
	var ms: Mission = Game.mission
	var cp: Checkpoint = main.checkpoint
	check("the GET HOME objective's checkpoint is the active one", cp != null and cp.objective == 2)
	check("the checkpoint holds the full loadout, the counters and the enemies", cp.loadout.has("pistol") and cp.enemies.size() == snap["cp_enemies"] and cp.kills == snap["kills"])
	# change everything the checkpoint saves
	var w := player.weapons
	w.loadout["pistol"][0]["ammo"] = 1
	(w.loadout["pistol"][0]["spare"] as Array).clear()
	w.loadout["rifle"][0]["ammo"] = 2
	Game.kills += 7
	Game.shots_fired += 50
	Game.shots_hit += 20
	var killed_uids: Array = []
	for e in Game.enemies.duplicate():
		if killed_uids.size() < 3 and is_instance_valid(e) and e.state != Enemy.State.DEAD:
			e.take_hit(9999.0, "body", Vector3.ZERO, e.global_position)
			killed_uids.append(e.uid)
	var extra: Enemy = main._spawn_enemy_at(Vector3(5, 0, 5), "soldier")
	extra.stun = 999.0
	var died := [false]
	player.died.connect(func() -> void: died[0] = true)
	player.take_damage(500.0)
	await frames(2)
	check("player dies at 0 health", Game.dead and died[0])
	check("the death screen offers R = checkpoint and Shift+R = whole mission", main.hud.death_stats.text.contains("restart from checkpoint") and main.hud.death_stats.text.contains("SHIFT+R") and main.hud.death_stats.text.contains("Civilians lost"))
	await secs(0.5)
	Civilian.clock = 0.0           # (the crowd would have left long ago: keep the restored one around for the count)
	Game.checkpoint_requested.emit()
	await secs(0.8)
	check("R restarts from the checkpoint: alive again, death screen gone", not Game.dead and not main.hud.death_panel.visible and player.health == snap["health"])
	check("the player is back at the checkpoint position", Vector2(player.global_position.x - snap["pos"].x, player.global_position.z - snap["pos"].z).length() < 0.6, str(player.global_position))
	check("the exact loadout is back (rounds loaded and every spare magazine)", str(player.weapons.loadout) == snap["loadout"], str(player.weapons.loadout))
	check("kills and accuracy counters are back", Game.kills == snap["kills"] and Game.shots_fired == snap["fired"] and Game.shots_hit == snap["hit"])
	var uids_now: Array = []
	for e2 in Game.enemies:
		uids_now.append(e2.uid)
	uids_now.sort()
	var uids_then: Array = (snap["uids"] as Array).duplicate()
	uids_then.sort()
	check("the same enemies are alive again, the extra one is gone", uids_now == uids_then and Game.enemies.size() == snap["enemies"], "%d now, %d then" % [Game.enemies.size(), snap["enemies"]])
	var dead_back := true
	for uid in killed_uids:
		if not uids_now.has(uid):
			dead_back = false
	check("enemies killed after the checkpoint are alive again", dead_back)
	check("the mission is on the checkpoint's objective", ms.index == 2 and not Game.won)
	check("civilians are restored from the checkpoint (living ones and the bodies)", Game.civilians.size() >= cp.civilians.size() - 2 and Game.civilians.size() <= cp.civilians.size() and Game.civilians_lost == cp.civilians_lost, "%d vs %d" % [Game.civilians.size(), cp.civilians.size()])
	await secs(0.5)
	check("the player stands on the floor after the teleport", player.is_on_floor(), str(player.global_position))
	# finish: down the stairs into the cellar completes the last objective and wins
	tp(Vector3(City.CELLAR_DOOR_POS.x, 0.1, City.CELLAR_DOOR_POS.z - 2.0), PI)
	await secs(0.4)
	Input.action_press("move_forward")
	await secs(1.0)
	var y_on_stairs := player.global_position.y
	var dbg := "crouch %.2f ads %.2f slide %.2f vel %s floor %s pos %s climbing %s focus %s fwd %s paused %s dead %s" % [player.crouch_k, player.weapons.ads_k, player.sliding, str(player.velocity), str(player.is_on_floor()), str(player.global_position), str(player.climbing), str(Game.has_focus()), str(Input.is_action_pressed("move_forward")), str(get_tree().paused), str(Game.dead)]
	await secs(2.0)
	Input.action_release("move_forward")
	check("the player walks down the stairs (on the slope, not floating)", y_on_stairs < -1.0 and y_on_stairs > -2.7, "y=%.2f " % y_on_stairs + dbg)
	check("reaching the cellar completes GO TO THE CELLAR and starts CLIMB TO THE ROOF (the story goes on: The Lander)", not Game.won and not ms.finished and String(ms.active().get("id", "")) == "climb_roof" and player.global_position.y < -2.0, "y=%.2f won=%s" % [player.global_position.y, Game.won])
	check("the marker hangs over the foot of the lookout stair", main.world._marker.visible and absf(main.world._marker.position.x - CityStory.lookout["foot"].x) < 1.0)
	get_tree().paused = false
	await secs(0.3)

	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- stealth, grenades, squads

func spawn(kind: String, pos: Vector3, freeze: bool = true) -> Enemy:
	var e: Enemy = main._spawn_enemy_at(Vector3(pos.x, 0.0, pos.z), kind)
	all.append(e)
	if freeze:
		e.stun = 999.0          # no AI until the test lets him loose (stun = 0)
	return e


func park_all() -> void:
	for en in Game.enemies.duplicate():
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			en.stun = 999.0
			en.state = Enemy.State.WANDER
			en.global_position = Vector3(200.0 + 3.0 * (Game.enemies.find(en) % 15), 0.1, 3.0 * (Game.enemies.find(en) / 15) - 40.0)
	await frames(3)


func kill(e: Enemy) -> void:
	e.take_hit(99999.0, "body", Vector3.ZERO, e.global_position + Vector3(0, 1.0, 0))


func stealth_tests() -> void:
	print("--- stealth: takedowns, bodies, stamina, breathing, indicator ---")
	await park_all()
	player.health = Game.MAX_HEALTH
	Game.dead = false
	var lw := player.weapons
	lw.loadout["melee"][0]["id"] = "knife"
	lw.switch_to("knife")
	tp(Vector3(0, 0.1, 0), 0.0)
	await secs(0.7)
	var shots := [0]
	Game.gunshot.connect(func(_p: Vector3, _l: float) -> void: shots[0] += 1)
	# --- takedown from behind: kills at once, silently; an enemy 15 m away is not alerted
	var witness := spawn("soldier", Vector3(0, 0, -16.2))
	witness.facing = 0.0
	witness.rig.rotation.y = 0.0
	var victim := spawn("soldier", Vector3(0, 0, -1.2))
	victim.facing = 0.0
	victim.rig.rotation.y = 0.0
	await frames(4)
	witness.stun = 0.0
	witness.wait_t = 99.0
	var kills0 := Game.kills
	check("a knife in hand shows the takedown prompt when an unaware enemy has his back turned", lw.takedown_target == victim, str(lw.takedown_target))
	await frames(3)
	check("the HUD shows E - TAKEDOWN", main.hud.interact_label.text == "E - TAKEDOWN", main.hud.interact_label.text)
	Input.action_press("fire")
	await frames(3)
	var stab_t := lw.takedown_t
	Input.action_release("fire")
	await secs(0.3)
	check("LMB takedown kills at once", victim.state == Enemy.State.DEAD and victim.health <= 0.0 and Game.kills == kills0 + 1 and Game.takedowns == 1, "takedowns %d" % Game.takedowns)
	check("a takedown makes no gunshot noise", shots[0] == 0, str(shots[0]))
	check("the enemy 15 m away is not alerted", witness.state == Enemy.State.WANDER and not witness.noticed_self, str(witness.state))
	await secs(0.8)         # the knife is still recovering from the first stab
	var victim2 := spawn("rifleman", Vector3(0, 0, -1.2))
	victim2.facing = 0.0
	victim2.rig.rotation.y = 0.0
	await frames(4)
	Input.action_press("interact")
	await frames(3)
	Input.action_release("interact")
	await secs(0.3)
	check("E performs the takedown too", victim2.state == Enemy.State.DEAD and Game.takedowns == 2)
	check("a distinct stab animation plays and the stab sound exists", stab_t > 0.0 and Sfx.get_sound("stab").data.size() > 100, "%.2f" % stab_t)
	# front: no takedown, normal damage
	await secs(0.8)
	var front := spawn("soldier", Vector3(0, 0, -1.2))
	front.facing = PI
	front.rig.rotation.y = PI
	front.max_health = 500.0
	front.health = 500.0
	await frames(4)
	check("facing the player: no takedown possible", lw.takedown_target == null)
	var hp_before := front.health
	Input.action_press("fire")
	await frames(3)
	Input.action_release("fire")
	await secs(0.6)
	check("a melee hit on an enemy who faces the player does normal damage", front.state != Enemy.State.DEAD and absf((hp_before - front.health) - float(lw.stats()["damage"])) < 1.0, "%.0f -> %.0f" % [hp_before, front.health])
	# alerted enemy, even from behind
	var alerted := spawn("soldier", Vector3(0, 0, -1.2))
	alerted.facing = 0.0
	alerted.rig.rotation.y = 0.0
	alerted.max_health = 500.0
	alerted.health = 500.0
	alerted.state = Enemy.State.CHASE
	alerted.noticed_self = true
	await frames(4)
	check("an enemy who has noticed the player cannot be taken down", lw.takedown_target == null)
	await secs(0.8)
	hp_before = alerted.health
	Input.action_press("fire")
	await frames(3)
	Input.action_release("fire")
	await secs(0.6)
	check("a melee hit on an alerted enemy keeps doing normal damage", alerted.state != Enemy.State.DEAD and absf((hp_before - alerted.health) - float(lw.stats()["damage"])) < 1.0, "%.0f -> %.0f" % [hp_before, alerted.health])
	await park_all()
	lw.switch_to("pistol")
	await secs(0.6)

	# --- a body makes a passer-by suspicious; he investigates and goes back to wandering
	for old_body in Enemy.bodies.duplicate():       # earlier kills: only the new corpse may make him suspicious
		if is_instance_valid(old_body):
			old_body.queue_free()
	await frames(3)
	tp(Vector3(0, 0.1, 150.0))
	var corpse := spawn("soldier", Vector3(0, 0, -20.0))
	await frames(4)
	kill(corpse)
	await secs(1.0)
	var watcher := spawn("soldier", Vector3(0, 0, -35.0))
	watcher.facing = PI
	watcher.rig.rotation.y = PI
	await frames(3)
	var wfov := watcher.sight_fov
	check("the vision cone of a calm soldier is his normal one", is_equal_approx(watcher.vision_fov(), wfov))
	watcher.stun = 0.0
	watcher.wait_t = 99.0
	await secs(1.0)
	check("a soldier who sees a body becomes SUSPICIOUS", watcher.state == Enemy.State.SUSPICIOUS and watcher.seen_bodies.size() == 1, str(watcher.state))
	check("a suspicious soldier's vision cone is 25% wider", absf(watcher.vision_fov() - wfov * 1.25) < 0.01, "%.0f vs %.0f" % [watcher.vision_fov(), wfov])
	check("suspicion is not an alert: he has not noticed the player", not watcher.noticed_self)
	await secs(7.0)
	check("he walks to the body and looks around", watcher.state == Enemy.State.SUSPICIOUS and watcher.susp_phase >= 1 and watcher.global_position.distance_to(corpse.global_position) < 4.0, "phase %d at %.1f m" % [watcher.susp_phase, watcher.global_position.distance_to(corpse.global_position)])
	await secs(8.5)
	check("after 8 s of looking he searches the area", watcher.state == Enemy.State.SUSPICIOUS and watcher.susp_phase == 2)
	await secs(15.5)
	check("after the search he goes back to wandering without ever noticing the player", watcher.state == Enemy.State.WANDER and not watcher.noticed_self, str(watcher.state))
	await secs(1.5)
	check("the same body does not make him suspicious again", watcher.state == Enemy.State.WANDER)
	check("dead bodies stay in the world", is_instance_valid(corpse) and Enemy.bodies.has(corpse))
	# the three-to-alert rule does not count suspicious soldiers
	await park_all()
	var crew: Array[Enemy] = []
	for i in 4:
		var c := spawn("soldier", Vector3(-6.0 + 4.0 * i, 0, -60.0))
		c.group = 960
		crew.append(c)
	await frames(3)
	for i in 3:
		crew[i]._start_suspicion(Vector3(0, 0, -50))
	crew[0]._alert_group()
	check("three suspicious soldiers do not alert the fourth (suspicion is not noticing)", crew[3].state == Enemy.State.WANDER and not crew[0].noticed_self)
	# seeing the player turns suspicion into an alert
	await park_all()
	tp(Vector3(0, 0.1, -30.0), 0.0)
	var susp := spawn("soldier", Vector3(0, 0, -45.0))
	susp.facing = PI
	susp.rig.rotation.y = PI
	await frames(3)
	susp.stun = 0.0
	susp._start_suspicion(Vector3(0, 0, -40))
	await secs(1.0)
	check("a suspicious soldier who sees the player becomes alerted (and noticed_self)", susp.state != Enemy.State.SUSPICIOUS and susp.state != Enemy.State.WANDER and susp.noticed_self, str(susp.state))
	# the stealth indicator and the arcs
	await park_all()
	tp(Vector3(0, 0.1, -10.0), 0.0)
	var eye_e := spawn("soldier", Vector3(25.0, 0, -10.0))
	await frames(3)
	eye_e.stun = 0.0
	eye_e.facing = -PI * 0.5
	eye_e._start_suspicion(Vector3(25.0, 0, -20.0))
	await frames(8)
	check("the indicator shows the yellow eye for a suspicious soldier", main.hud.stealth.mode == 1 and main.hud.stealth.arcs.size() >= 1, "mode %d" % main.hud.stealth.mode)
	check("the eye fills as he gets closer", main.hud.stealth.fill > 0.0)
	eye_e.state = Enemy.State.CHASE
	eye_e.stun = 999.0
	await frames(8)
	check("the indicator turns into a red eye once he hunts the player", main.hud.stealth.mode == 2)
	eye_e.state = Enemy.State.WANDER
	await frames(8)
	check("nobody suspicious or hunting: nothing is shown", main.hud.stealth.mode == 0 and main.hud.stealth.arcs.is_empty())
	await park_all()

	# --- stamina
	tp(Vector3(0, 0.1, 150.0))
	var runner := spawn("soldier", Vector3(0, 0, -100.0))
	await frames(3)
	runner.stun = 0.0
	runner.state = Enemy.State.CHASE
	var s0 := runner.stamina
	for i in 12:
		runner.unseen_t = 0.0
		runner.last_known = player.global_position
		await secs(0.25)
	check("stamina drains while running in a chase", runner.stamina < s0 - 20.0 and runner.winded_t <= 0.0, "%.0f -> %.0f" % [s0, runner.stamina])
	check("gunner 70 and blade fighter 130 stamina, others 100", Enemy.KINDS["gunner"]["stamina"] == 70.0 and Enemy.KINDS["blade"]["stamina"] == 130.0 and runner.max_stamina == 100.0)
	runner.stamina = 1.0
	for i in 8:
		runner.unseen_t = 0.0
		await secs(0.1)
	check("at 0 stamina he is winded: stopped and bent forward", runner.winded_t > 0.0 and Vector2(runner.velocity.x, runner.velocity.z).length() < 0.8 and runner.tilt.rotation.x < -0.5, "winded %.1f tilt %.2f" % [runner.winded_t, runner.tilt.rotation.x])
	check("winded lasts 3 to 5 s", runner.winded_t <= Enemy.WINDED_MAX and runner.winded_t > 0.0)
	# hearing halves while winded: a walking player is heard at 11 m, at 5.5 m while winded
	tp(runner.global_position + Vector3(0.0, 0.1, 8.0), 0.0)
	await frames(3)
	runner.facing = 0.0
	runner.rig.rotation.y = 0.0
	player.velocity = Vector3(3.0, 0.0, 0.0)
	var heard_winded := runner._notices_player()
	var wt := runner.winded_t
	runner.winded_t = 0.0
	var heard_normal := runner._notices_player()
	runner.winded_t = wt
	check("hearing range halves while winded (heard at 8 m normally, not when winded)", heard_normal and not heard_winded, "%s %s" % [heard_normal, heard_winded])
	tp(Vector3(0, 0.1, 150.0))
	await secs(0.3)
	runner.stun = 999.0
	runner.state = Enemy.State.WANDER
	# recovery: winded ends after 3-5 s, then 60% speed until stamina is back above 40
	var waited := 0.0
	while runner.winded_t > 0.0 and waited < 7.0:
		await secs(0.25)
		waited += 0.25
	check("the winded spell ends and he is slowed down", runner.winded_t <= 0.0 and runner.recovering and runner.stamina < Enemy.RECOVER_UNTIL, "stamina %.0f recovering %s after %.1f s" % [runner.stamina, runner.recovering, waited])
	var s_test := runner._stamina_step(0.01, Vector3(5.2, 0, 0))
	check("while recovering he moves at 60% speed", absf(s_test.length() - 5.2 * Enemy.RECOVER_SPEED) < 0.2, "%.2f" % s_test.length())
	waited = 0.0
	while runner.recovering and waited < 14.0:
		await secs(0.5)
		waited += 0.5
	check("stamina recovers above 40 and normal speed returns", not runner.recovering and runner.stamina > Enemy.RECOVER_UNTIL, "%.0f after %.1f s" % [runner.stamina, waited])
	# a winded rifleman cannot shoot, then shoots again
	await park_all()
	tp(Vector3(0, 0.1, -60.0), 0.0)
	var shooter := spawn("rifleman", Vector3(0, 0, -76.0))
	await frames(3)
	shooter.stun = 0.0
	shooter.facing = 0.0
	shooter.rig.rotation.y = 0.0
	shooter.state = Enemy.State.CHASE
	shooter.last_known = player.global_position
	await secs(0.6)
	shooter.stamina = 0.5
	shooter.winded_t = 4.0
	shooter.burst_left = 0
	shooter.cooldown = 0.0
	var ammo0 := shooter.ammo
	var hp0 := player.health
	for i in 12:
		player.health = Game.MAX_HEALTH
		shooter.unseen_t = 0.0
		await secs(0.25)
	check("a winded soldier cannot shoot", shooter.winded_t > 0.0 and shooter.ammo == ammo0, "ammo %d -> %d winded %.1f" % [ammo0, shooter.ammo, shooter.winded_t])
	var shot_later := false
	for i in 40:
		player.health = Game.MAX_HEALTH
		shooter.unseen_t = 0.0
		await secs(0.25)
		if shooter.ammo < ammo0:
			shot_later = true
			break
	check("once he has his breath back he shoots again", shot_later and shooter.winded_t <= 0.0, "ammo %d" % shooter.ammo)
	player.health = Game.MAX_HEALTH
	await park_all()
	# --- breathing is heard only within 10 m
	tp(Vector3(0, 0.1, 0.0))
	var br := spawn("soldier", Vector3(5.0, 0, 0.0))
	await frames(3)
	br.stun = 999.0
	await frames(6)
	check("breathing plays when the soldier is within 10 m", br.breath_player.playing)
	var pitch_full := br.breath_player.pitch_scale
	var vol_full := br.breath_player.volume_db
	br.stamina = 5.0
	await frames(4)
	check("it gets faster and louder as stamina drops", br.breath_player.pitch_scale > pitch_full + 0.2 and br.breath_player.volume_db > vol_full + 4.0, "%.2f / %.1f dB -> %.2f / %.1f dB" % [pitch_full, vol_full, br.breath_player.pitch_scale, br.breath_player.volume_db])
	br.winded_t = 3.0
	await frames(4)
	var loud_winded := br.breath_player.volume_db
	check("it is loudest when winded", loud_winded > br.breath_player.volume_db - 0.01 and loud_winded > vol_full + 8.0, "%.1f dB" % loud_winded)
	br.winded_t = 0.0
	br.global_position = Vector3(15.0, 0.1, 0.0)
	await frames(6)
	check("it is not played beyond 10 m", not br.breath_player.playing)
	br.stamina = br.max_stamina
	await park_all()
	# --- the bodies cap
	var before_bodies := Enemy.bodies.size()
	var first_body: Enemy = Enemy.bodies[0] if before_bodies > 0 else null
	for i in 66:
		var bb := spawn("soldier", Vector3(-8.0 + 2.0 * (i % 8), 0, -200.0 - 2.0 * (i / 8)))
		await frames(1)
		kill(bb)
	await frames(3)
	check("at most 60 bodies stay, the oldest are removed first", Enemy.bodies.size() == Enemy.BODY_CAP and (first_body == null or not is_instance_valid(first_body) or first_body.is_queued_for_deletion()), str(Enemy.bodies.size()))
	tp(Vector3(0, 0.1, 0))


func grenade_tests() -> void:
	print("--- frag grenades ---")
	await park_all()
	Game.dead = false
	player.health = Game.MAX_HEALTH
	var w := player.weapons
	check("the carrying limit is 4 grenades", Game.MAX_GRENADES == 4)
	Game.grenades = 4
	tp(Vector3(0, 0.1, 40.0), 0.0)
	await secs(0.4)
	aim_at(Vector3(0, 7.0, 10.0))
	var space := player.get_world_3d().direct_space_state
	var pred := Grenade.predict(space, w.throw_start(), w.throw_velocity())
	var g := w.throw_grenade()
	check("throwing uses one grenade", g != null and Game.grenades == 3)
	var gt := 0.0
	while not g.resting and gt < 2.4:
		await frames(1)
		gt += 1.0 / 120.0
	var land_err := (g.first_land as Vector3).distance_to(pred["land"]) if g.first_land != Vector3.INF else 99.0
	var rest_err := (g.rest_pos as Vector3).distance_to(pred["rest"]) if g.rest_pos != Vector3.INF else 99.0
	check("the arc preview lands within 1 m of where the real grenade lands", land_err < 1.0, "%.2f m" % land_err)
	check("and its ring is within 1 m of where it comes to rest", rest_err < 1.0, "%.2f m" % rest_err)
	check("the preview has a dotted trajectory", (pred["points"] as PackedVector3Array).size() > 8)
	# the fuse, the explosion call, loudness
	var heard := [0, 0.0]
	var cb := func(_pos: Vector3, loud: float) -> void:
		heard[0] += 1
		heard[1] = loud
	Game.gunshot.connect(cb)
	await park_all()
	tp(Vector3(0, 0.1, 150.0))
	var exp_at := Vector3(0, 0, 20.0)
	check("the fuse is 2.5 s", is_equal_approx(Grenade.FUSE, 2.5))
	var t_fuse := 0.0
	while is_instance_valid(g) and t_fuse < 3.0:
		await frames(1)
		t_fuse += 1.0 / 120.0
	check("the grenade explodes after its fuse and calls Game.gunshot with a large loudness", not is_instance_valid(g) and heard[0] >= 1 and heard[1] >= 100.0, "%d calls, loudness %.0f, %.2f s" % [heard[0], heard[1], t_fuse])
	Game.gunshot.disconnect(cb)
	# damage falls off with distance and walls protect
	await park_all()
	var base := Vector3(0, 0, -40.0)
	var dist_list := [1.5, 3.0, 5.0, 6.5, 8.0]
	var targets: Array[Enemy] = []
	for i in dist_list.size():
		var tgt := spawn("soldier", base + Vector3(float(dist_list[i]), 0, 0))
		tgt.max_health = 5000.0
		tgt.health = 5000.0
		targets.append(tgt)
	await secs(0.5)         # let them drop to the ground: the chest height decides the distance
	var wall := StaticBody3D.new()
	wall.collision_layer = Game.L_WORLD
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(0.5, 4.0, 8.0)
	ws.shape = wb
	wall.add_child(ws)
	wall.position = base + Vector3(-3.0, 2.0, 0.0)
	main.add_child(wall)
	var shielded := spawn("soldier", base + Vector3(-4.0, 0, 0))
	shielded.max_health = 5000.0
	shielded.health = 5000.0
	var open_twin := spawn("soldier", base + Vector3(0.0, 0, 4.0))
	open_twin.max_health = 5000.0
	open_twin.health = 5000.0
	await secs(0.5)
	Grenade.detonate(main, base)
	await frames(2)
	var dmg: Array = []
	var fall_ok := true
	for i in dist_list.size():
		var d := float(5000.0 - targets[i].health)
		dmg.append(snappedf(d, 1.0))
		var chest_d := Vector3(float(dist_list[i]), 1.0, 0.0).distance_to(Vector3(0, 0.15, 0))
		var expect := Grenade.damage_at(chest_d)
		if absf(d - expect) > 2.0:
			fall_ok = false
	check("damage is 140 at the centre and falls off linearly to 0 at 7 m", fall_ok and Grenade.damage_at(0.0) == 140.0 and Grenade.damage_at(7.0) == 0.0, str(dmg))
	check("nothing is hurt beyond the radius", targets[4].health == 5000.0)
	check("a wall protects: the soldier behind it takes no damage", shielded.health == 5000.0 and open_twin.health < 5000.0, "%.0f / %.0f" % [shielded.health, open_twin.health])
	wall.queue_free()
	await frames(2)
	# the player is hurt by his own grenade
	await park_all()
	tp(Vector3(0, 0.1, 0.0))
	await secs(0.4)
	player.health = Game.MAX_HEALTH
	Grenade.detonate(main, Vector3(3.0, 0.0, 0.0))
	await frames(2)
	check("the player is hurt by his own grenade", player.health < Game.MAX_HEALTH - 40.0 and player.shake > 0.5, "health %.0f shake %.2f" % [player.health, player.shake])
	player.health = Game.MAX_HEALTH
	player.shake = 0.0
	Grenade.detonate(main, Vector3(0.0, 0.0, 40.0))
	check("far explosions shake the camera less (none beyond 30 m)", player.shake == 0.0)
	Grenade.detonate(main, Vector3(0.0, 0.0, 25.0))
	check("shake scales with distance (between 10 and 30 m)", player.shake > 0.0 and player.shake < 1.0, "%.2f" % player.shake)
	player.shake = 0.0
	player.health = Game.MAX_HEALTH
	# blasts alert soldiers within about 60 m
	await park_all()
	var near_e := spawn("soldier", Vector3(0, 0, -50.0))
	var far_e := spawn("soldier", Vector3(0, 0, -150.0))
	tp(Vector3(0, 0.1, 100.0))
	await frames(4)
	near_e.stun = 0.0
	far_e.stun = 0.0
	Grenade.detonate(main, Vector3(0, 0, -20.0))
	await frames(3)
	check("the blast alerts soldiers within about 60 m, not the ones far away", near_e.state != Enemy.State.WANDER and far_e.state == Enemy.State.WANDER, "%d %d" % [near_e.state, far_e.state])
	check("they head for the blast point", near_e.last_known.distance_to(Vector3(0, 0, -20.0)) < 1.0)
	near_e.stun = 999.0
	# pickups
	await park_all()
	tp(Vector3(0, 0.1, 100.0))
	await secs(0.4)
	Game.grenades = 3
	for i in 3:
		Pickup.spawn_grenade(main, Vector3(0.3 * i, 0.0, 100.0))
	await secs(0.6)
	var left := 0
	for pk in Game.pickups:
		if is_instance_valid(pk) and (pk as Pickup).is_grenade and (pk as Pickup).global_position.distance_to(Vector3(0, 0, 100)) < 4.0:
			left += 1
	check("grenade pickups are collected automatically up to the limit of 4", Game.grenades == 4 and left == 2, "%d carried, %d left" % [Game.grenades, left])
	check("the toast says +1 GRENADE", w.notice == "+1 GRENADE")
	for pk in Game.pickups.duplicate():
		if is_instance_valid(pk):
			pk.queue_free()
	await frames(2)
	# loot odds
	var sg := 0
	var gg := 0
	for i in 140:
		var ls := spawn("soldier", Vector3(0.0, 0, 130.0))
		await frames(1)
		kill(ls)
		for pk in Game.pickups:
			if is_instance_valid(pk) and (pk as Pickup).is_grenade:
				sg += 1
		for pk in Game.pickups.duplicate():
			if is_instance_valid(pk):
				pk.queue_free()
		await frames(1)
	for i in 100:
		var lg := spawn("gunner", Vector3(0.0, 0, 130.0))
		await frames(1)
		kill(lg)
		for pk in Game.pickups:
			if is_instance_valid(pk) and (pk as Pickup).is_grenade:
				gg += 1
		for pk in Game.pickups.duplicate():
			if is_instance_valid(pk):
				pk.queue_free()
		await frames(1)
	check("soldiers drop a grenade about 35% of the time", sg >= 30 and sg <= 70, "%d / 140" % sg)
	check("gunners drop a grenade about 60% of the time", gg >= 45 and gg <= 75, "%d / 100" % gg)
	# holding G shows the preview, a tap throws at once
	Game.grenades = 4
	tp(Vector3(0, 0.1, 100.0), 0.0)
	await secs(0.5)
	Input.action_press("grenade")
	await secs(0.5)
	check("holding G shows the arc and the ring", w._arc_dots != null and w._arc_dots.multimesh.visible_instance_count > 5 and w._arc_ring.visible and Game.grenades == 4)
	Input.action_release("grenade")
	await frames(3)
	check("releasing G throws the grenade", Game.grenades == 3 and not w._arc_ring.visible)
	await secs(0.6)
	Input.action_press("grenade")
	await frames(6)
	Input.action_release("grenade")
	await frames(3)
	check("a quick tap throws at once (no preview)", Game.grenades == 2 and (w._arc_dots == null or not w._arc_ring.visible))
	await secs(3.0)
	player.health = Game.MAX_HEALTH
	Game.dead = false
	Game.grenades = 0
	await park_all()


func squad_tests() -> void:
	print("--- squad regrouping ---")
	await park_all()
	Game.dead = false
	player.health = Game.MAX_HEALTH
	var sq: Squads = main.squads
	sq.reset()
	tp(Vector3(0, 0.1, 150.0))
	await secs(0.4)
	var radio := []
	var rcb := func(text: String) -> void: radio.append(text)
	Game.radio_line.connect(rcb)
	var crew: Array[Enemy] = []
	for i in 5:
		var c := spawn("soldier", Vector3(-8.0 + 4.0 * i, 0, -80.0 + (3.0 if i % 2 == 0 else -3.0)))
		c.group = 970
		crew.append(c)
	await frames(4)
	for c in crew:
		c.stun = 0.0
		c.state = Enemy.State.ALERT
		c.alert_t = 9999.0
		c.noticed_self = true
	await secs(0.7)
	check("an alerted group of 5 does not regroup before it has lost people", sq.squads.is_empty())
	kill(crew[0])
	await secs(0.5)
	check("losing 1 of 5 (20%) does not make them regroup", sq.squads.is_empty())
	kill(crew[1])
	await secs(0.8)
	var rally := Vector3.INF
	var in_hold := 0
	for i in range(2, 5):
		if crew[i].state == Enemy.State.HOLD:
			in_hold += 1
	check("a group that lost 40% (2 of 5) with 3 survivors regroups", sq.squads.size() == 1 and in_hold == 3, "%d squads, %d holding" % [sq.squads.size(), in_hold])
	if not sq.squads.is_empty():
		rally = sq.squads[0]["rally"]
	check("the rally point is open ground, 3 m from walls", rally != Vector3.INF and sq._open(rally))
	await secs(4.0)
	var faces: Array = []
	var spots_ok := true
	for i in range(2, 5):
		faces.append(wrapf(crew[i].hold_face, 0.0, TAU))
		if crew[i].hold_phase != 1 or Vector2(crew[i].global_position.x - crew[i].hold_spot.x, crew[i].global_position.z - crew[i].hold_spot.z).length() > 1.0:
			spots_ok = false
	faces.sort()
	var gaps: Array = []
	for i in faces.size():
		gaps.append(absf(wrapf(float(faces[(i + 1) % faces.size()]) - float(faces[i]), 0.0, TAU)))
	var even := true
	for gp in gaps:
		if absf(float(gp) - TAU / 3.0) > 0.2:
			even = false
	check("they stand at the rally point, each facing a different outward direction (360 degrees split between them)", spots_ok and even, str(gaps))
	var radius_ok := true
	for i in range(2, 5):
		var dr := Vector2(crew[i].global_position.x - rally.x, crew[i].global_position.z - rally.z).length()
		if dr < 0.4 or dr > 2.0:
			radius_ok = false
	check("they form a tight circle round the rally point", radius_ok)
	var p0 := crew[2].global_position
	await secs(2.0)
	check("they hold and do not chase", crew[2].state == Enemy.State.HOLD and crew[2].global_position.distance_to(p0) < 1.5)
	# a grenade landing within 8 m breaks the formation
	Game.grenade_landed.emit(rally + Vector3(5.0, 0.0, 0.0))
	await frames(3)
	var scattering := 0
	for i in range(2, 5):
		if crew[i].state == Enemy.State.HOLD and crew[i].hold_phase == 2:
			scattering += 1
	check("a grenade within 8 m of the rally point breaks the formation: they scatter to cover", sq.squads.is_empty() and scattering == 3, "%d scattering" % scattering)
	var hunting := 0
	for step in 24:
		await secs(0.25)
		hunting = 0
		for i in range(2, 5):
			if crew[i].state != Enemy.State.HOLD and crew[i].state != Enemy.State.WANDER and crew[i].state != Enemy.State.DEAD:
				hunting += 1
		if hunting == 3:
			break
	check("after the scatter they resume the normal hunt", hunting == 3, "%d hunting" % hunting)
	# a grenade far away does not
	await park_all()
	sq.reset()
	var crew2: Array[Enemy] = []
	for i in 5:
		var c2 := spawn("soldier", Vector3(-8.0 + 4.0 * i, 0, -120.0))
		c2.group = 971
		crew2.append(c2)
	await frames(4)
	for c2 in crew2:
		c2.stun = 0.0
		c2.state = Enemy.State.ALERT
		c2.alert_t = 9999.0
	await secs(0.6)
	kill(crew2[0])
	kill(crew2[1])
	await secs(1.0)
	check("a second group regroups the same way", sq.squads.size() == 1)
	var rally2: Vector3 = sq.squads[0]["rally"] if not sq.squads.is_empty() else Vector3.INF
	Game.grenade_landed.emit(rally2 + Vector3(12.0, 0.0, 0.0))
	await frames(3)
	check("a grenade farther than 8 m does not break it", sq.squads.size() == 1)
	# a member killed while holding breaks it
	await secs(3.0)
	kill(crew2[2])
	await secs(0.5)
	check("when a member is killed while holding the formation breaks", sq.squads.is_empty() and (crew2[3].hold_phase == 2 or crew2[3].state != Enemy.State.HOLD))
	# the 20 s run out
	await park_all()
	sq.reset()
	var crew3: Array[Enemy] = []
	for i in 5:
		var c3 := spawn("soldier", Vector3(-8.0 + 4.0 * i, 0, -160.0))
		c3.group = 972
		crew3.append(c3)
	await frames(4)
	for c3 in crew3:
		c3.stun = 0.0
		c3.state = Enemy.State.ALERT
		c3.alert_t = 9999.0
	await secs(0.6)
	kill(crew3[0])
	kill(crew3[1])
	await secs(1.0)
	check("a third group forms up", sq.squads.size() == 1)
	if not sq.squads.is_empty():
		check("the formation lasts 20 s", is_equal_approx(Squads.HOLD_TIME, 20.0))
		sq.squads[0]["t"] = 19.7
		await secs(0.6)
		check("after 20 s the formation breaks by itself", sq.squads.is_empty())
	# radio chatter when the player is near
	await park_all()
	sq.reset()
	radio.clear()
	tp(Vector3(0, 0.1, -105.0), 0.0)
	player.health = 9999.0
	var crew4: Array[Enemy] = []
	for i in 5:
		var c4 := spawn("soldier", Vector3(-8.0 + 4.0 * i, 0, -128.0))
		c4.group = 973
		crew4.append(c4)
	await frames(4)
	for c4 in crew4:
		c4.stun = 0.0
		c4.state = Enemy.State.ALERT
		c4.alert_t = 9999.0
	await secs(0.6)
	kill(crew4[0])
	kill(crew4[1])
	await secs(2.0)
	check("holding soldiers talk over the radio when the player is within 25 m (subtitle)", radio.size() >= 1 and main.hud.radio_label.text.begins_with("[RADIO]"), str(radio))
	check("the radio crackle exists", Sfx.get_sound("radio").data.size() > 100)
	Game.radio_line.disconnect(rcb)
	sq.reset()
	await park_all()
	player.health = Game.MAX_HEALTH
	tp(Vector3(0, 0.1, 0))


# ---------------------------------------------------------------- civilians

func clear_civilians() -> void:
	for c in main.get_children():
		if c is Civilian:
			c.queue_free()
	Game.civilians.clear()
	await frames(3)


func on_avenue(p: Vector3) -> bool:
	for st in City.streets:
		if st["cls"] == "avenue" and (st["rect"] as Rect2).has_point(Vector2(p.x, p.z)):
			return true
	return false


## A civilian that never leaves the area (leave_t far in the future), for tests that watch one civilian.
func mk_civ(pos: Vector3, seed_value: int, child: bool = false, adult: Civilian = null) -> Civilian:
	var c := Civilian.spawn(main, player, pos, seed_value, child, adult)
	c.leave_t = 1.0e9
	return c

func civilian_tests() -> void:
	print("--- civilians ---")
	await park_all()
	await clear_civilians()
	Civilian.clock = 0.0
	Game.dead = false
	player.health = Game.MAX_HEALTH
	tp(Vector3(0, 0.1, 150.0))
	await secs(0.4)
	var shots := [0]
	var gcb := func(_p: Vector3, _l: float) -> void: shots[0] += 1
	Game.gunshot.connect(gcb)
	var w := player.weapons
	# --- running: far goals, away from soldiers, along real paths, off the avenues while a soldier is in sight
	var guard := spawn("soldier", Vector3(0, 0, -40.0))
	await frames(3)
	var civ := mk_civ(Vector3(3.0, 0.0, -48.0), 11)
	await frames(3)
	civ.hide_cd = 9999.0
	var far_ok := true
	var path_ok := true
	var avenue_hits := 0
	for i in 15:
		civ.soldier_seen = true
		civ._pick_target()
		if civ.last_pick_soldier_dist < 80.0:
			far_ok = false
		if City.path(civ.global_position, civ.target).size() < 1:
			path_ok = false
		if on_avenue(civ.target):
			avenue_hits += 1
	check("a civilian picks running goals at least 80 m from the nearest soldier", far_ok)
	check("the goals can be reached along real streets (City.path)", path_ok)
	check("with a soldier in sight he does not run for a wide avenue", avenue_hits == 0, "%d of 15" % avenue_hits)
	civ.soldier_seen = false
	civ._pick_target()
	var p0 := civ.global_position
	await secs(4.0)
	check("civilians run at about 5.5 m/s along their path", civ.state == Civilian.State.PANIC and civ.global_position.distance_to(p0) > 12.0, "%.1f m in 4 s" % civ.global_position.distance_to(p0))
	# --- hiding: behind a car or at a wall, 5-15 s, then back to panic
	var car: Dictionary = {}
	for cd in City.cars:
		var cpz: Vector3 = cd["pos"]
		if cpz.length() > 60.0 and cpz.z > 0.0 and cpz.z < 120.0:
			car = cd
			break
	var hide_ok := false
	if not car.is_empty():
		var cp: Vector3 = car["pos"]
		var hider := mk_civ(cp + Vector3(0, 0, 6.0), 21)
		await frames(3)
		var threat := cp + Vector3(0, 0, -10.0)
		var spot := hider.find_hide(threat)
		var blocked := not player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(threat + Vector3(0, 1, 0), spot + Vector3(0, 1, 0), Game.L_WORLD)).is_empty() if spot != Vector3.INF else false
		hide_ok = spot != Vector3.INF and blocked
		hider.hide_cd = 9999.0
		hider.state = Civilian.State.HIDE
		hider.hide_spot = spot
		hider.hide_phase = 0
		hider.hide_t = 0.0
		hider.hide_dur = 2.0
		var crouched_at := false
		for i in 80:                       # (the walk to the hiding place takes as long as the nearest car is far: wait for him, up to 8 s)
			await secs(0.1)
			if hider.hide_phase == 1 and hider.crouching:
				crouched_at = true
				break
		for i in 80:
			await secs(0.1)
			if hider.state == Civilian.State.PANIC:
				break
		check("a civilian hides in a spot the soldier cannot see (behind a car)", hide_ok)
		check("he crouches there for a while, then runs again", crouched_at and hider.state == Civilian.State.PANIC, "phase %d state %d" % [hider.hide_phase, hider.state])
		hider.queue_free()
	else:
		check("a car is available for the hiding test", false)
	check("hiding lasts 5 to 15 s", Civilian.HIDE_MIN == 5.0 and Civilian.HIDE_MAX == 15.0)
	# a gunshot nearby sends some (not all) civilians into hiding
	var crowd: Array[Civilian] = []
	for i in 16:
		var cc := mk_civ(Vector3(-4.0 + 0.5 * i, 0.0, -90.0), 100 + i)
		crowd.append(cc)
	await frames(3)
	for cc in crowd:
		cc.hide_cd = 0.0
		cc.set_physics_process(false)
	Game.gunshot.emit(Vector3(0.0, 0.0, -88.0), 100.0)
	var hiding := 0
	for cc in crowd:
		if cc.state == Civilian.State.HIDE:
			hiding += 1
	check("a gunshot within 20 m makes some civilians hide (not all of them)", hiding >= 1 and hiding <= 15, "%d of 16" % hiding)
	for cc in crowd:
		cc.queue_free()
	await frames(3)
	# --- children stay with their adult
	var adult := mk_civ(Vector3(0.0, 0.0, -120.0), 31)
	await frames(2)
	var kid := mk_civ(Vector3(1.2, 0.0, -120.0), 32, true, adult)
	await frames(2)
	adult.hide_cd = 9999.0
	adult._pick_target()
	await secs(5.0)
	var kd := kid.global_position.distance_to(adult.global_position)
	check("a child stays within about 2 m of his adult while they run", kid.state == Civilian.State.FOLLOW and kd < 3.2 and kid.body_scale < 0.8 and adult.global_position.distance_to(Vector3(0, 0, -120.0)) > 10.0, "%.1f m" % kd)
	adult.take_hit(9999.0, "body", Vector3.ZERO, adult.global_position)
	await secs(0.5)
	check("when the adult dies the child runs on his own", kid.state == Civilian.State.PANIC and kid.leader == null)
	kid.queue_free()
	# --- steps aside for the player
	var stand := mk_civ(Vector3(0.0, 0.0, -150.0), 41)
	await frames(2)
	stand.state = Civilian.State.HIDE
	stand.hide_phase = 1
	stand.hide_dur = 999.0
	stand.hide_spot = stand.global_position
	tp(Vector3(0.0, 0.1, -148.9), PI)
	await secs(1.2)
	var gap := Vector2(stand.global_position.x - player.global_position.x, stand.global_position.z - player.global_position.z).length()
	check("civilians step aside when the player comes close", gap > 1.8, "%.1f m" % gap)
	stand.queue_free()
	# --- soldiers vs civilians: a soldier who knows nothing of the player shoots a civilian in view
	await park_all()
	tp(Vector3(0, 0.1, 150.0))
	shots[0] = 0
	var shooter := spawn("soldier", Vector3(0, 0, -75.0))
	shooter.facing = PI
	shooter.rig.rotation.y = PI
	var target := mk_civ(Vector3(0.0, 0.0, -60.0), 51)
	await frames(4)
	target.set_physics_process(false)
	target.health = 1000.0
	shooter.stun = 0.0
	shooter.wait_t = 99.0
	var ammo0 := shooter.ammo
	var t_shoot := 0.0
	while shooter.ammo >= ammo0 and t_shoot < 6.0:
		await frames(6)
		t_shoot += 0.05
	check("a soldier who knows nothing of the player shoots at a civilian he sees", shooter.state == Enemy.State.WANDER and shooter.ammo < ammo0 and shooter.civ_target == target, "ammo %d -> %d after %.1f s" % [ammo0, shooter.ammo, t_shoot])
	check("shooting at civilians makes no Game.gunshot", shots[0] == 0, str(shots[0]))
	# a civilian beyond 30 m is left alone
	var far_civ := mk_civ(Vector3(0.0, 0.0, -125.0), 52)
	await frames(3)
	far_civ.set_physics_process(false)
	check("civilians farther than 30 m are not targeted", shooter.civ_target != far_civ)
	far_civ.queue_free()
	# the player comes into view: the soldier forgets the civilian
	var chp := target.health
	tp(Vector3(0.0, 0.1, -63.0), PI)
	await secs(2.5)
	var ignored := true
	for i in 12:
		if shooter.civ_target != null:
			ignored = false
		await secs(0.25)
	check("a soldier who has noticed the player stops targeting civilians", shooter.state != Enemy.State.WANDER and ignored, "state %d" % shooter.state)
	check("and does not shoot them while hunting the player", target.health >= chp - 0.01, "%.0f -> %.0f" % [chp, target.health])
	player.health = Game.MAX_HEALTH
	shooter.stun = 999.0
	shooter.state = Enemy.State.WANDER
	# --- deaths: the counter, bodies, no count for scenery
	await park_all()
	tp(Vector3(0, 0.1, 150.0))
	var lost0 := Game.civilians_lost
	var bodies0 := Enemy.bodies.size()
	var victim := mk_civ(Vector3(0.0, 0.0, -100.0), 61)
	await frames(3)
	victim.take_hit(9999.0, "body", Vector3.ZERO, victim.global_position)
	await secs(1.6)             # the death clip takes about a second
	check("a killed civilian falls and stays as a body in the shared body list", victim.state == Civilian.State.DEAD and Enemy.bodies.has(victim) and victim.model.head_node.global_position.y - victim.global_position.y < 0.7, "head %.2f m" % (victim.model.head_node.global_position.y - victim.global_position.y))
	check("Game.civilians_lost counts the death", Game.civilians_lost == lost0 + 1, "%d -> %d" % [lost0, Game.civilians_lost])
	var scenery := mk_civ(Vector3(2.0, 0.0, -100.0), 62)
	scenery.lie_down()
	check("a body that was already lying there is not a loss", Game.civilians_lost == lost0 + 1 and scenery.state == Civilian.State.DEAD)
	check("soldiers do not become suspicious of civilian bodies", not ((victim as Node) is Enemy))
	# --- the player hits one: toast, mission goes on
	await park_all()
	await clear_civilians()
	for ghost in main.get_children():           # soldiers that earlier tests only marked dead keep their hit boxes: take them away
		if ghost is Enemy and (ghost as Enemy).state == Enemy.State.DEAD:
			for gh in (ghost as Enemy).hitboxes:
				gh.queue_free()
			(ghost as Enemy).hitboxes.clear()
	await frames(2)
	tp(Vector3(0, 0.1, 0.0), 0.0)
	var hit_civ := mk_civ(Vector3(0.0, 0.0, -5.0), 71)
	await frames(4)
	hit_civ.set_physics_process(false)
	hit_civ.health = 1000.0
	w.switch_to("pistol")
	await secs(0.7)
	w.notice = ""
	w.state[w.current]["ammo"] = 15
	var toast := false
	var ray_info := ""
	for i in 8:
		aim_at(hit_civ.chest_pos())
		var rq := PhysicsRayQueryParameters3D.create(player.camera.global_position, player.camera.global_position - player.camera.global_transform.basis.z * 30.0, Game.L_WORLD | Game.L_HITBOX)
		rq.collide_with_areas = true
		var rh := player.get_world_3d().direct_space_state.intersect_ray(rq)
		var owner_node: Node = (rh["collider"] as Node).get_parent().get_parent() if rh.has("collider") else null
		ray_info = "%s (%s, state %s, pos %s) at %s, civ at %s" % [owner_node, owner_node.get_class() if owner_node else "", str(owner_node.get("state")) if owner_node else "", str(owner_node.get("global_position")) if owner_node else "", rh.get("position"), hit_civ.global_position]
		w.bloom = 0.0
		w.cooldown = 0.0
		w._fire_shot()
		await frames(2)
		if w.notice == "CIVILIAN HIT":
			toast = true
			break
	check("when the player hits a civilian the toast says CIVILIAN HIT", toast and hit_civ.health < 1000.0, "toast %s hp %.0f weapon %s ammo %d dead %s notice %s ray %s" % [toast, hit_civ.health, w.current, int(w.state[w.current]["ammo"]), Game.dead, w.notice, ray_info])
	check("the mission does not fail for it", not Game.dead and Game.mission != null and not Game.mission.finished)
	hit_civ.queue_free()
	# --- far civilians update slowly, very far ones are hidden
	tp(Vector3(0, 0.1, 0.0))
	var near_c := mk_civ(Vector3(0.0, 0.0, -20.0), 81)
	var far_c := mk_civ(Vector3(0.0, 0.0, -200.0), 82)
	var gone_c := mk_civ(Vector3(0.0, 0.0, -262.0), 83)
	await frames(6)
	var un0 := near_c.updates
	var uf0 := far_c.updates
	await secs(1.0)
	var near_n := near_c.updates - un0
	var far_n := far_c.updates - uf0
	check("civilians beyond 150 m update only every 0.2 s", far_c.lod_slow and not near_c.lod_slow and near_n > 80 and far_n <= 7 and far_n >= 2, "near %d, far %d updates per second" % [near_n, far_n])
	check("beyond 230 m they are not drawn, within it they are", far_c.visible and not gone_c.visible and near_c.visible)
	for c in [near_c, far_c, gone_c]:
		c.queue_free()
	await frames(3)
	# --- the crowd thins out over the first 5 minutes; nobody new appears
	await clear_civilians()
	Civilian.clock = 0.0
	player.yaw = 0.0
	tp(Vector3(0, 0.1, 255.0), PI)         # south end, looking south: the crowd is behind him
	main._populate_civilians()
	await secs(0.5)
	var n0 := Game.civilians.size()
	var dead_bodies := 0
	for b in Enemy.bodies:
		if is_instance_valid(b) and b is Civilian:
			dead_bodies += 1
	check("the story starts with about 50 civilians, 8 bodies near the Institute exit and more of the dead along the way home (rule changed with the invasion dressing: was 40 and 8)", n0 >= 44 and n0 <= 50 and dead_bodies >= 14, "%d living, %d bodies" % [n0, dead_bodies])
	var kids := 0
	for c in Game.civilians:
		if (c as Civilian).is_child:
			kids += 1
			if (c as Civilian).leader == null or not is_instance_valid((c as Civilian).leader):
				kids += 100
	check("some of them are children, each with an adult", kids >= 6 and kids < 100, str(kids))
	await secs(2.5)
	check("in the first moments hardly anybody has left", Game.civilians.size() >= n0 - 3, "%d of %d" % [Game.civilians.size(), n0])
	var max_n := Game.civilians.size()
	Civilian.clock = 301.0                 # five minutes later
	var t_leave := 0.0
	while t_leave < 40.0 and Game.civilians.size() > n0 / 2:
		await secs(1.0)
		t_leave += 1.0
		max_n = maxi(max_n, Game.civilians.size())
	check("after 5 minutes the number of live civilians has dropped (they fled out of the area)", Game.civilians.size() <= n0 / 2 + 4, "%d of %d after %.0f s" % [Game.civilians.size(), n0, t_leave])
	check("nobody new appeared meanwhile", max_n <= n0)
	await clear_civilians()
	Game.civilians_lost = 0
	player.health = Game.MAX_HEALTH
	tp(Vector3(0, 0.1, 0.0))
	Game.gunshot.disconnect(gcb)


# ---------------------------------------------------------------- skinned characters, hedgehogs

## Horizontal distance-along-a-direction of a model's head from his feet (for "he fell away from the shot").
func head_along(model: CharModel, root: Node3D, dir: Vector3) -> float:
	var d := model.head_node.global_position - root.global_position
	d.y = 0.0
	return d.dot(dir.normalized())


func character_tests() -> void:
	print("--- skinned characters, hedgehogs ---")
	await park_all()
	await clear_civilians()
	tp(Vector3(0, 0.1, 150.0))
	var want := {"soldier": "soldier", "rifleman": "agile", "blade": "agile", "marksman": "marksman", "gunner": "marksman"}
	var models_ok := true
	var boxes_ok := true
	var muzzle_ok := true
	var made := {}
	var i := 0
	for k in want:
		var e := spawn(k, Vector3(210.0, 0.0, 6.0 * i))
		made[k] = e
		i += 1
		if e.model.model_id != want[k] or e.model.skeleton.get_bone_count() < 30:
			models_ok = false
		if e.hitboxes.size() != 3:
			boxes_ok = false
		if e.ranged and e.muzzle == null:
			muzzle_ok = false
	check("every kind wears its skinned model (soldier -> M4 soldier, rifleman / blade -> agile, marksman / gunner -> marksman)", models_ok)
	check("each soldier keeps his three hit boxes", boxes_ok)
	check("ranged soldiers hold a gun with a muzzle", muzzle_ok)
	await secs(0.6)
	var hand_ok := true
	for k in made:
		var e: Enemy = made[k]
		var hand := e.model.hand_node.global_position
		var d := hand.distance_to(e.gun.global_position)
		if d > 0.35:
			hand_ok = false
			print("   ", k, " hand is ", snappedf(d, 0.01), " m from his weapon")
	check("the weapon sits in his hand (within 35 cm of the wrist)", hand_ok)
	var soldier: Enemy = made["soldier"]
	soldier.state = Enemy.State.SHOOT
	await secs(0.5)
	var hr := soldier.model.skeleton.global_transform * soldier.model.skeleton.get_bone_global_pose(soldier.model.bone("hand.R")).origin
	var hl := soldier.model.skeleton.global_transform * soldier.model.skeleton.get_bone_global_pose(soldier.model.bone("hand.L")).origin
	check("the M4 soldier aims with both hands on the rifle (grip and foregrip within 25 cm)", hr.distance_to(soldier.gun.global_position) < 0.25 and hl.distance_to(soldier.gun.to_global(Vector3(0, -0.05, -0.3))) < 0.3, "right %.2f left %.2f" % [hr.distance_to(soldier.gun.global_position), hl.distance_to(soldier.gun.to_global(Vector3(0, -0.05, -0.3)))])
	soldier.state = Enemy.State.WANDER
	# deaths: the clip body falls with his head along the shot, the procedural ones tip over
	var rifle: Enemy = made["rifleman"]
	rifle.stun = 999.0
	var shot := Vector3(0, 0, -4.0)
	rifle.take_hit(9999.0, "body", shot, rifle.global_position + Vector3(0, 1.2, 0))
	await secs(1.6)
	check("a rifleman plays his death clip and ends on the ground", corpse_lying(rifle) and rifle.model.current == "death", "head %.2f m" % (rifle.model.head_node.global_position.y - rifle.global_position.y))
	check("he falls with his head along the shot", head_along(rifle.model, rifle, shot) > 0.5, "%.2f m" % head_along(rifle.model, rifle, shot))
	check("his weapon is hidden (it dropped as a pick-up)", not rifle.gun.visible)
	var marks: Enemy = made["marksman"]
	marks.take_hit(9999.0, "body", Vector3(0, 0, 4.0), marks.global_position + Vector3(0, 1.2, 0))
	await secs(1.2)
	check("a marksman (no clip) tips over", corpse_lying(marks))
	# civilians: one outfit each, people animations, death by direction
	tp(Vector3(0, 0.1, 150.0))
	var outfits := {}
	var civ_ok := true
	for sd in [3, 4, 5, 6, 7, 8]:
		var c := mk_civ(Vector3(-4.0 * sd, 0.0, 120.0), sd)
		var meshes := c.model.body.find_children("*", "MeshInstance3D", true, false)
		var prefixes := {}
		for mi in meshes:
			prefixes[String(mi.name).get_slice("_", 0)] = true
		outfits[prefixes.keys()[0] if prefixes.size() > 0 else "?"] = true
		if prefixes.size() != 1 or meshes.size() < 3 or meshes.size() > 5 or c.model.model_id != "people":
			civ_ok = false
			print("   civilian ", sd, " meshes ", meshes.size(), " outfits ", prefixes.keys())
	check("each civilian wears exactly one outfit of the people pack", civ_ok)
	check("the crowd is varied (several outfits among six people)", outfits.size() >= 3, str(outfits.keys()))
	await clear_civilians()
	var v1 := mk_civ(Vector3(-10.0, 0.0, 100.0), 31)
	var v2 := mk_civ(Vector3(10.0, 0.0, 100.0), 32)
	await frames(4)
	v1.take_hit(9999.0, "body", Vector3(3.0, 0.0, 0.0), v1.global_position + Vector3(0, 1.2, 0))
	v2.take_hit(9999.0, "head", Vector3(0.0, 0.0, -3.0), v2.global_position + Vector3(0, 1.7, 0))
	await secs(1.6)
	check("a shot civilian falls on his back with his head along the shot (east)", v1.model.current == "death" and head_along(v1.model, v1, Vector3(1, 0, 0)) > 0.5, "%.2f" % head_along(v1.model, v1, Vector3(1, 0, 0)))
	check("a headshot drops a civilian too (north)", v2.model.current == "death" and head_along(v2.model, v2, Vector3(0, 0, -1)) > 0.5)
	check("dead civilians lie on the ground", v1.model.head_node.global_position.y - v1.global_position.y < 0.7 and v2.model.head_node.global_position.y - v2.global_position.y < 0.7)
	var v3 := mk_civ(Vector3(0.0, 0.0, 90.0), 33)
	await frames(4)
	v3.take_hit(9999.0, "body", Vector3(0.0, 0.0, -14.0), v3.global_position + Vector3(0, 1.0, 0))
	await secs(0.35)
	check("a blast throws a civilian into a tumble first", absf(v3.spin.rotation.x) > 0.5, "%.2f rad" % v3.spin.rotation.x)
	await secs(2.2)
	check("and then he lies there", v3.state == Civilian.State.DEAD and v3.model.head_node.global_position.y - v3.global_position.y < 0.7 and v3.spin.rotation.length() < 0.01)
	# the dead stop animating (a body costs nothing)
	await secs(2.5)
	check("a settled body freezes its animation", v1.model.frozen and not v1.is_physics_processing())
	await clear_civilians()
	# hedgehog barricades around the campfires
	var per_site := City.OBSTACLE_COUNT
	check("every battle site has its hedgehog barricades", City.obstacles.size() == City.sites.size() * per_site, "%d for %d sites" % [City.obstacles.size(), City.sites.size()])
	var solid_ok := true
	var ray_ok := true
	var near_ok := true
	for ob in City.obstacles:
		var p: Vector3 = ob["pos"]
		if City.is_free(p):
			solid_ok = false
		var side := Basis(Vector3.UP, float(ob["yaw"])).z
		var q := PhysicsRayQueryParameters3D.create(p + side * 5.0 + Vector3(0, 0.4, 0), p - side * 5.0 + Vector3(0, 0.4, 0), Game.L_WORLD)
		var h := player.get_world_3d().direct_space_state.intersect_ray(q)
		if h.is_empty() or (h["position"] as Vector3).distance_to(p + Vector3(0, 0.4, 0)) > 2.0:
			ray_ok = false
		var near_site := false
		for s in City.sites:
			if Vector2(p.x - s["center"].x, p.z - s["center"].z).length() < City.SITE_RADIUS:
				near_site = true
		if not near_site:
			near_ok = false
	check("hedgehogs block the navigation grid", solid_ok)
	check("bullets and people stop at a hedgehog (it has a collider)", ray_ok)
	check("hedgehogs stand inside the battle sites", near_ok)
	var frac2 := City.reachable_fraction(City.START_POS)
	check("the barricades do not wall anything in", frac2 > 0.985, "%.3f" % frac2)
	var inside := 0
	for e in Game.enemies:
		for ob in City.obstacles:
			if (ob["rect"] as Rect2).has_point(Vector2(e.global_position.x, e.global_position.z)) and e.global_position.x < 190.0:
				inside += 1
	check("nobody was spawned inside a hedgehog", inside == 0, str(inside))
	await park_all()



# ---------------------------------------------------------------- the war-torn city: streets, trees, cars, obstacles (stage 1)

## Walk `secs_` seconds forward from `from` facing `yaw` and return the highest y reached.
func walk_max_y(from: Vector3, yaw: float, secs_: float) -> float:
	tp(from, yaw)
	await frames(10)
	var top := player.global_position.y
	Input.action_press("move_forward")
	var n := int(secs_ * 120.0)
	for i in n:
		await get_tree().physics_frame
		top = maxf(top, player.global_position.y)
	Input.action_release("move_forward")
	return top


## How many things (other than the battle sites' own barricades) a straight ray between two points hits.
func band_blockers(from: Vector3, to: Vector3) -> int:
	var space := player.get_world_3d().direct_space_state
	var dir := (to - from).normalized()
	var cur := from
	var n := 0
	for i in 40:
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(cur, to, Game.L_WORLD))
		if h.is_empty():
			break
		var hp: Vector3 = h["position"]
		var at_site := false
		for s in City.sites:
			if Vector2(hp.x - s["center"].x, hp.z - s["center"].z).length() < 24.0:
				at_site = true
		if not at_site:
			n += 1
			print("   blocker at ", hp)
		cur = hp + dir * 0.4
	return n


func street_tests() -> void:
	print("--- streets: time of day, kerbs, trees, cars, obstacles ---")
	await park_all()
	await clear_civilians()
	var space := player.get_world_3d().direct_space_state
	var sun_x: float = main.world.sun.rotation_degrees.x
	check("the sun stands 50-55 degrees up (about 11:30 on a March morning)", sun_x <= -50.0 and sun_x >= -56.0, "%.0f" % sun_x)
	# the two central avenues stay open
	var clear_ns := true
	var clear_ew := true
	for y in [0.4, 1.2, 2.2]:
		clear_ns = clear_ns and band_blockers(Vector3(0, y, -275), Vector3(0, y, 275)) == 0
		clear_ew = clear_ew and band_blockers(Vector3(-140, y, 0), Vector3(140, y, 0)) == 0
	check("the avenue x = 0 is free of obstacles from end to end", clear_ns)
	check("the avenue z = 0 is free of obstacles from end to end", clear_ew)
	var band_ok := true
	for ob in CityWar.war_obstacles:
		for kc in CityWar.KEEP_CLEAR:
			if (kc as Rect2).intersects(ob["rect"]):
				band_ok = false
	for c in City.cars:
		for kc in CityWar.KEEP_CLEAR:
			if (kc as Rect2).intersects(c["rect"]):
				band_ok = false
	for t in City.trees:
		for kc in CityWar.KEEP_CLEAR:
			if (kc as Rect2).intersects(t["rect"]):
				band_ok = false
	check("no car, tree or barricade stands in the 7 m band along x = 0 and z = 0", band_ok)
	var frac := City.reachable_fraction(City.START_POS)
	check("with all the new obstacles the walkable ground is still connected", frac > 0.985, "%.4f" % frac)
	var route := City.path(City.START_POS, City.HOME_POS)
	check("the way from the start to the goal is open", route.size() > 1 and plen(City.START_POS, route) < 420.0, "%.0f m" % plen(City.START_POS, route))
	# trees
	var street_trees := 0
	var burning := 0
	var fallen := 0
	var stumps := 0
	for t in City.trees:
		if not t["planter"]:
			continue
		street_trees += 1
		match String(t["state"]):
			"burning":
				burning += 1
			"fallen":
				fallen += 1
			"stump":
				stumps += 1
	var fb := float(burning) / maxf(1.0, float(street_trees))
	var ff := float(fallen) / maxf(1.0, float(street_trees))
	var fs := float(stumps) / maxf(1.0, float(street_trees))
	check("city trees no longer burn", burning == 0, "%d of %d" % [burning, street_trees])
	check("about 10% lie across the road or pavement", ff > 0.05 and ff < 0.15, "%d of %d" % [fallen, street_trees])
	check("about 10% are burnt black stumps", fs > 0.05 and fs < 0.15, "%d of %d" % [stumps, street_trees])
	check("there are no randomly scattered trees any more (the backdrop is all towers)", City.far_trees.is_empty() and street_trees > 150)
	var in_planter := true
	for t in City.trees:
		if t["planter"]:
			var tp2: Vector2 = t["pos"]
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(tp2.x, 2.0, tp2.y - 0.45), Vector3(tp2.x, 0.1, tp2.y - 0.45), Game.L_WORLD)).is_empty():
				in_planter = false
	check("every city tree stands in a planter box with a collider", in_planter)
	var trunk_ok := false
	var crouch_ok := false
	for t in City.trees:
		if String(t["state"]) == "fallen":
			var tr: Array = t["trunk"]
			var mid: Vector3 = ((tr[0] as Vector3) + (tr[1] as Vector3)) * 0.5
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mid + Vector3(0, 3.0, 0), mid - Vector3(0, 1.0, 0), Game.L_WORLD))
			if not hit.is_empty():
				trunk_ok = true
			if bool(t["prop"]):
				var near_stump: Vector3 = (tr[0] as Vector3).lerp(tr[1] as Vector3, 0.12)
				near_stump.y = 0.0
				var under := space.intersect_ray(PhysicsRayQueryParameters3D.create(near_stump + Vector3(0, 0.1, 0), near_stump + Vector3(0, 3.0, 0), Game.L_WORLD))
				if not under.is_empty() and (under["position"] as Vector3).y > Game.CROUCH_HEIGHT + 0.05 and (under["position"] as Vector3).y < Game.STAND_HEIGHT + 0.5:
					crouch_ok = true
	check("a fallen trunk is a collider (the player must jump over it)", trunk_ok)
	check("a propped-up trunk leaves room to crouch under it", crouch_ok)
	var fell_block := true
	for t in City.trees:
		if String(t["state"]) == "fallen":
			var tr2: Array = t["trunk"]
			var mid2: Vector3 = ((tr2[0] as Vector3) + (tr2[1] as Vector3)) * 0.5
			if City.is_free(Vector3(mid2.x, 0.0, mid2.z)):
				fell_block = false
	check("a fallen tree is an obstacle in the navigation grid", fell_block)
	# cars
	var damaged := 0
	var kinds := {}
	for c in City.cars:
		if String(c["dmg"]) != "":
			damaged += 1
			kinds[c["dmg"]] = true
	var fd := float(damaged) / float(City.cars.size())
	check("about 40% of the cars are damaged", fd > 0.3 and fd < 0.55, "%d of %d" % [damaged, City.cars.size()])
	check("the wrecks come in several kinds (burnt, burning, flipped, crushed, doors open)", kinds.has("burnt") and kinds.has("burning") and kinds.has("crushed") and kinds.has("doors") and (kinds.has("side") or kinds.has("roof")), str(kinds.keys()))
	var near_sum := 0.0
	var far_sum := 0.0
	var near_n := 0
	var far_n := 0
	for c in City.cars:
		var cp: Vector3 = c["pos"]
		var near := 1.0e9
		for s in City.sites:
			near = minf(near, Vector2(cp.x - s["center"].x, cp.z - s["center"].z).length())
		if near < 60.0:
			near_n += 1
			near_sum += 1.0 if String(c["dmg"]) != "" else 0.0
		elif near > 140.0:
			far_n += 1
			far_sum += 1.0 if String(c["dmg"]) != "" else 0.0
	check("cars near the battle sites are wrecked more often", near_n < 3 or near_sum / float(near_n) > far_sum / maxf(1.0, float(far_n)), "%d/%d near, %d/%d far" % [int(near_sum), near_n, int(far_sum), far_n])
	var burnt_black := true
	var flipped_seen := false
	for c in City.cars:
		if String(c["dmg"]) == "burning" and (c["color"] as Color).get_luminance() > 0.2:
			burnt_black = false
		if absf(float(c["roll"])) > 1.0:
			flipped_seen = true
	check("burnt cars are charred and the flipped ones lie rolled over", burnt_black and flipped_seen)
	# obstacles
	var kinds_o := {}
	var alley_obs := 0
	var avenue_obs := 0
	for ob in CityWar.war_obstacles:
		kinds_o[ob["kind"]] = true
		var op: Vector3 = ob["pos"]
		for st in City.streets:
			if (st["rect"] as Rect2).has_point(Vector2(op.x, op.z)):
				if st["cls"] == "alley":
					alley_obs += 1
				elif st["cls"] == "avenue":
					avenue_obs += 1
				break
	check("barriers, sandbags, barricades, tank traps, fallen lamps / poles, rubble and containers all exist", kinds_o.size() >= 6, str(kinds_o.keys()))
	check("war obstacles are dense on the avenues and rare in the alleys", avenue_obs > alley_obs * 3 and alley_obs <= 3, "%d avenue, %d alley" % [avenue_obs, alley_obs])
	var obstacle_solid := true
	for ob in CityWar.war_obstacles:
		var orect: Rect2 = ob["rect"]
		var any_solid := false
		for fx in 5:
			for fz in 5:
				if not City.is_free(Vector3(orect.position.x + orect.size.x * (float(fx) + 0.5) / 5.0, 0.0, orect.position.y + orect.size.y * (float(fz) + 0.5) / 5.0)):
					any_solid = true
		if not any_solid:
			obstacle_solid = false
			print("   obstacle with no solid cell: ", ob["kind"], " ", ob["pos"])
	check("every war obstacle blocks the navigation grid", obstacle_solid)
	# kerbs
	var kerb_hit := false
	var kerb_y := 0.0
	for b in City.buildings:
		if b.get("border", false) or b.get("no_slab", false) or b.get("institute", false) or b.get("plug", false):
			continue
		var r: Rect2 = b["rect"]
		if r.size.x < 8.0:
			continue
		var x := r.get_center().x
		var z := r.end.y + 0.5
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 2.0, z), Vector3(x, -1.0, z), Game.L_KERB))
		if not h.is_empty():
			kerb_hit = true
			kerb_y = (h["position"] as Vector3).y
			break
	check("the pavement edge is a 0.15 m kerb (only the player collides with it)", kerb_hit and absf(kerb_y - 0.15) < 0.01 and Game.L_KERB != Game.L_WORLD and (Game.L_ENEMY & Game.L_KERB) == 0, "%.2f" % kerb_y)
	var stepped := false
	for b in City.buildings:
		if b.get("border", false) or b.get("no_slab", false) or b.get("institute", false) or b.get("plug", false) or b.get("home", false):
			continue
		var r2: Rect2 = b["rect"]
		if r2.size.x < 10.0 or r2.end.y > 200.0 or r2.end.y < -200.0:
			continue
		var cx := r2.get_center().x
		var start := Vector3(cx, 0.1, r2.end.y + 2.2)
		var clear := space.intersect_ray(PhysicsRayQueryParameters3D.create(start + Vector3(0, 0.5, 0), Vector3(cx, 0.5, r2.end.y + 0.1), Game.L_WORLD))
		if not clear.is_empty() or not City.is_free(Vector3(cx, 0.0, r2.end.y + 2.2)):
			continue
		var top := await walk_max_y(start, 0.0, 0.8)
		if top > 0.13 and top < 0.2:
			stepped = true
			break
	check("walking onto the pavement steps over the kerb by itself", stepped)
	# fires
	var n_alley := 0
	var n_walk := 0
	var n_wide := 0
	for st in City.streets:
		match String(st["cls"]):
			"alley":
				n_alley += 1
			"walk":
				n_walk += 1
			"street", "avenue":
				n_wide += 1
	check("there are many narrow streets and alleys (3-6 m) between the buildings", n_alley >= 35 and n_alley + n_walk >= 3 * n_wide, "%d alleys, %d walks, %d streets / avenues" % [n_alley, n_walk, n_wide])
	check("burning things exist (cars, buildings, wires)", Scn.fires.size() >= 10, str(Scn.fires.size()))
	var tree_fire := Vector3.INF
	for f in Scn.fires:
		if f["kind"] == "car":
			tree_fire = f["pos"]
			break
	tp(Vector3(tree_fire.x + 4.0, 0.1, tree_fire.z))
	main.world.fires.update(player.global_position)
	var lit := 0
	for k in main.world.fires._lights:
		for l in main.world.fires._lights[k]:
			if (l as OmniLight3D).visible:
				lit += 1
	check("only the nearest few fires get a real light", lit >= 1 and lit <= 11 and main.world.fires.active_count <= Fires.MAX_ACTIVE, "%d lights, %d active" % [lit, main.world.fires.active_count])
	tp(Vector3(0, 0.1, 150.0))
	main.world.fires.update(player.global_position)
	await park_all()




# ---------------------------------------------------------------- building variety and war damage (stage 2)

func building_tests() -> void:
	print("--- buildings: variety, damage, collapsed corners, holes, fires ---")
	await park_all()
	await clear_civilians()
	var space := player.get_world_3d().direct_space_state
	var archs := {}
	var inner := 0
	var inner_heavy := 0
	var inner_light := 0
	var border := 0
	var border_heavy := 0
	var border_dmg := 0
	var corner: Dictionary = {}
	var hole: Dictionary = {}
	var collapse := 0
	var shops := 0
	for b in City.buildings:
		if not b.has("arch") or String(b["arch"]) == "":
			continue
		archs[b["arch"]] = int(archs.get(b["arch"], 0)) + 1
		var d: float = b["damage"]
		if b.get("border", false):
			border += 1
			if d >= 0.66:
				border_heavy += 1
			if d >= 0.2:
				border_dmg += 1
		else:
			inner += 1
			if d >= 0.66:
				inner_heavy += 1
			elif d >= 0.2:
				inner_light += 1
		if b.has("chunk") and corner.is_empty():
			corner = b
		if b.has("hole") and hole.is_empty():
			hole = b
		if String(b.get("arch_damage", "")) == "collapse":
			collapse += 1
		if b.get("ground_box", false):
			shops += 1
	var fh := float(inner_heavy) / maxf(1.0, float(inner))
	var fl := float(inner_light) / maxf(1.0, float(inner))
	check("about 20% of the buildings are heavily damaged", fh > 0.14 and fh < 0.27, "%d of %d" % [inner_heavy, inner])
	check("about 40% are lightly damaged (the rest intact)", fl > 0.32 and fl < 0.48, "%d of %d" % [inner_light, inner])
	check("the border ring is damaged the same way (heavy and light)", border > 0 and float(border_heavy) / float(border) > 0.2 and float(border_dmg) / float(border) > 0.5, "%d heavy, %d damaged of %d" % [border_heavy, border_dmg, border])
	check("there are several building designs (apartments, shops, houses, offices, towers)", archs.size() >= 5, str(archs))
	check("apartment blocks have shop fronts on the ground floor and balconies", shops >= 10 and Scn.parts["glow"].size() > 0)
	var roof_ok := false
	for hb in City.buildings:
		if hb.get("roof_pitched", false):
			var hc: Vector2 = (hb["rect"] as Rect2).get_center()
			var hh := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(hc.x, 40.0, hc.y), Vector3(hc.x, 0.0, hc.y), Game.L_WORLD))
			if not hh.is_empty() and (hh["position"] as Vector3).y > float(hb["boxes"][0]["y1"]) + 0.6:
				roof_ok = true
				break
	check("old houses have pitched roofs with colliders (the ridge is above the eaves)", archs.has("house") and roof_ok)
	check("collapsed tops, missing corners and holes all exist", collapse >= 3 and not corner.is_empty() and not hole.is_empty(), "%d collapsed" % collapse)
	# a missing corner is really missing: from above it you fall past where the floors were
	if not corner.is_empty():
		var ch: Dictionary = corner["chunk"]
		var cr: Rect2 = ch["rect"]
		var c := cr.get_center()
		var top := float(ch["y1"]) + 3.0
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(c.x, top, c.y), Vector3(c.x, -1.0, c.y), Game.L_WORLD))
		var hy := (hit["position"] as Vector3).y if not hit.is_empty() else -1.0
		check("the missing corner is open space above its floor stubs (colliders match the shape)", hy < float(ch["y1"]) - 2.0, "first hit at y=%.1f, chunk %.0f-%.0f" % [hy, float(ch["y0"]), float(ch["y1"])])
	# a hole is a cavity: a ray entering through it travels at least 2.5 m before it hits a wall
	if not hole.is_empty():
		var hd: Dictionary = hole["hole"]
		var hr: Rect2 = hd["rect"]
		var s: int = hd["side"]
		var n: Vector2 = CityBuildings.SIDE_N[s]
		var cc := hr.get_center()
		var y := (float(hd["y0"]) + float(hd["y1"])) * 0.5
		var from := Vector3(cc.x + n.x * 8.0, y, cc.y + n.y * 8.0)
		var to := Vector3(cc.x - n.x * 12.0, y, cc.y - n.y * 12.0)
		var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, Game.L_WORLD))
		var depth := 0.0
		if not h2.is_empty():
			var hp: Vector3 = h2["position"]
			match s:
				0:
					depth = hp.z - hr.position.y
				1:
					depth = hr.end.y - hp.z
				2:
					depth = hp.x - hr.position.x
				_:
					depth = hr.end.x - hp.x
		check("a hole through the facade is a cavity the ray passes into", not h2.is_empty() and depth > 2.5, "%.1f m deep" % depth)
	# burning buildings: glowing windows and smoke; only the 3 nearest get a light
	var burning := 0
	for b in City.buildings:
		if b.get("burning", false):
			burning += 1
	check("some of the heavily damaged buildings burn", burning >= 3, str(burning))
	var fire_pos := Vector3.INF
	for f in Scn.fires:
		if f["kind"] == "build":
			fire_pos = f["pos"]
			break
	check("a burning building has a fire entry (flames and smoke near the player)", fire_pos != Vector3.INF)
	if fire_pos != Vector3.INF:
		tp(Vector3(fire_pos.x, 0.1, fire_pos.z + 20.0))
		main.world.fires.update(player.global_position)
		var lit := 0
		for l in main.world.fires._lights["build"]:
			if (l as OmniLight3D).visible:
				lit += 1
		check("at most 3 burning buildings get a real light", lit >= 1 and lit <= 3, str(lit))
	var tall_ok := true
	for b in City.buildings:
		if b.get("border", false) and float(b["h"]) < 30.0:
			tall_ok = false
	check("the border ring is still a wall of tall buildings after the damage", tall_ok)
	var frac := City.reachable_fraction(City.START_POS)
	check("the rubble does not wall anything in", frac > 0.985, "%.4f" % frac)
	tp(Vector3(0, 0.1, 150.0))
	main.world.fires.update(player.global_position)
	await park_all()




# ---------------------------------------------------------------- moving through the city: ladders, roofs, bridges, crouch passages, tunnels (stage 3)

## Yaw that makes the player look along the horizontal direction (dx, dz).
func yaw_for(d: Vector2) -> float:
	return atan2(-d.x, -d.y)


## Hold forward (and optionally crouch / jump) for `t` seconds and return the player's final position.
func hold_forward(t: float, crouch: bool = false) -> Vector3:
	Input.action_press("move_forward")
	if crouch:
		Input.action_press("crouch")
	await secs(t)
	Input.action_release("move_forward")
	Input.action_release("crouch")
	return player.global_position


func climb_tests() -> void:
	print("--- climbing: ladders, fire escapes, roofs, bridges, falling ---")
	await park_all()
	await clear_civilians()
	Game.dead = false
	player.health = Game.MAX_HEALTH
	var space := player.get_world_3d().direct_space_state
	check("there are ladders, fire escapes and pass-through buildings", City.ladders.size() >= 8 and City.escapes.size() >= 4 and City.tunnels.size() >= 4, "%d ladders, %d escapes, %d tunnels" % [City.ladders.size(), City.escapes.size(), City.tunnels.size()])
	# ---- a wall ladder up to a roof
	var lad: Dictionary = {}
	for l in City.ladders:
		if l["kind"] == "wall" and float(l["top"]) > 3.0:
			lad = l
			break
	var ladder_ok := false
	var top_ok := false
	var speed_ok := false
	var no_fire := true
	var switch_ok := false
	if not lad.is_empty():
		var base: Vector3 = lad["pos"]
		var n: Vector2 = lad["n"]
		var top: float = lad["top"]
		tp(Vector3(base.x + n.x * 0.9, 0.1, base.z + n.y * 0.9), yaw_for(-n))
		await secs(0.3)
		Input.action_press("move_forward")
		await secs(0.6)
		ladder_ok = player.climbing
		var y_a := player.global_position.y
		await secs(1.0)
		var y_b := player.global_position.y
		speed_ok = absf((y_b - y_a) - Game.CLIMB_SPEED) < 0.6 and player.climbing
		# no firing while climbing, but weapons can be switched
		var shots_before := Game.shots_fired
		Input.action_press("fire")
		await secs(0.4)
		Input.action_release("fire")
		no_fire = Game.shots_fired == shots_before
		var before_weapon := player.weapons.current
		Input.action_press("slot_3")
		await frames(2)
		Input.action_release("slot_3")
		await secs(0.6)
		switch_ok = player.weapons.current != before_weapon
		await secs(top / Game.CLIMB_SPEED + 1.0)
		Input.action_release("move_forward")
		await secs(0.4)
		top_ok = not player.climbing and absf(player.global_position.y - top) < 0.4 and player.is_on_floor()
		# the roof edge has only a low parapet, no invisible wall: nothing at head height 1.4 m above the roof next to the wall
		player.weapons.switch_to("pistol")
	check("walking into a ladder and pressing forward attaches the player", ladder_ok)
	check("W climbs at about 2.5 m/s", speed_ok)
	check("the player cannot fire while climbing, but can switch weapons", no_fire and switch_ok)
	check("reaching the top steps the player onto the roof", top_ok, "y=%.2f" % player.global_position.y)
	# ---- Space jumps off backwards
	var jump_ok := false
	if not lad.is_empty():
		var base2: Vector3 = lad["pos"]
		var n2: Vector2 = lad["n"]
		tp(Vector3(base2.x + n2.x * 0.9, 0.1, base2.z + n2.y * 0.9), yaw_for(-n2))
		await secs(0.3)
		Input.action_press("move_forward")
		await secs(1.4)
		Input.action_release("move_forward")
		var on_ladder := player.climbing
		Input.action_press("jump")
		await frames(3)
		Input.action_release("jump")
		await secs(0.5)
		var away := (Vector2(player.global_position.x, player.global_position.z) - Vector2(base2.x, base2.z)).dot(n2)
		jump_ok = on_ladder and not player.climbing and away > 1.0
	check("Space jumps off the ladder backwards", jump_ok)
	player.health = Game.MAX_HEALTH
	await secs(3.0)
	# ---- a shipping container: ladder to its roof
	var cl: Dictionary = {}
	for l2 in City.ladders:
		if l2["kind"] == "container":
			cl = l2
			break
	var cont_ok := false
	if not cl.is_empty():
		var cb: Vector3 = cl["pos"]
		var cn: Vector2 = cl["n"]
		tp(Vector3(cb.x + cn.x * 0.9, 0.1, cb.z + cn.y * 0.9), yaw_for(-cn))
		await secs(0.3)
		await hold_forward(1.35)
		cont_ok = not player.climbing and absf(player.global_position.y - 2.6) < 0.3
	check("a shipping container can be climbed by its ladder", cont_ok, "y=%.2f" % player.global_position.y)
	player.health = Game.MAX_HEALTH
	# ---- a fire escape: walk up its first flight
	var esc_ok := false
	if not City.escapes.is_empty():
		var es: Dictionary = City.escapes[0]
		var st: Vector3 = es["start"]
		var side: int = es["side"]
		var d := Vector2(1, 0) if side < 2 else Vector2(0, 1)
		tp(Vector3(st.x, 0.1, st.z), yaw_for(d))
		# the foot of the stair can lie under a ramp start: nudge back a little
		tp(Vector3(st.x - d.x * 0.3, 0.1, st.z - d.y * 0.3), yaw_for(d))
		await secs(0.3)
		var top_y := 0.0
		Input.action_press("move_forward")
		for i in 360:
			await get_tree().physics_frame
			top_y = maxf(top_y, player.global_position.y)
		Input.action_release("move_forward")
		esc_ok = top_y > 1.8
		check("a fire escape / stair can be walked up (ramp colliders under the steps)", esc_ok, "reached y=%.1f" % top_y)
	# ---- roofs: a parapet, no invisible wall
	var parapet_ok := false
	var open_ok := false
	for b in City.buildings:
		if not b.get("access", false) or b.has("tunnel"):
			continue
		var r: Rect2 = b["rect"]
		var topy := 0.0
		for bx in b["boxes"]:
			if float(bx.get("style", 0.0)) < 0.97:
				topy = maxf(topy, float(bx["y1"]))
		# the far (south) side of the roof: a ray from outside at 0.5 m above the roof hits the parapet, one at 1.5 m does not
		var x := r.get_center().x
		var from_lo := Vector3(x, topy + 0.5, r.end.y + 3.0)
		var from_hi := Vector3(x, topy + 1.6, r.end.y + 3.0)
		var hit_lo := space.intersect_ray(PhysicsRayQueryParameters3D.create(from_lo, Vector3(x, topy + 0.5, r.end.y - 0.1), Game.L_WORLD))
		var hit_hi := space.intersect_ray(PhysicsRayQueryParameters3D.create(from_hi, Vector3(x, topy + 1.6, r.end.y - 0.1), Game.L_WORLD))
		if not hit_lo.is_empty() and hit_hi.is_empty():
			parapet_ok = true
			open_ok = true
			break
	check("reachable roofs have a low parapet and no invisible wall above it", parapet_ok and open_ok)
	# ---- a bridge: walk across it between two roofs
	var bridge: Dictionary = {}
	for br in City.bridges:
		if not br["broken"]:
			bridge = br
			break
	var cross_ok := false
	var open_gap := false
	if not bridge.is_empty():
		var p0: Vector3 = bridge["p0"]
		var p1: Vector3 = bridge["p1"]
		var dir := (p1 - p0)
		dir.y = 0.0
		var dn := dir.normalized()
		tp(Vector3(p0.x - dn.x * 3.0, p0.y + 0.15, p0.z - dn.z * 3.0), yaw_for(Vector2(dn.x, dn.z)))
		await secs(0.4)
		await hold_forward((dir.length() + 6.0) / Game.WALK_SPEED)
		var left := Vector2(player.global_position.x - p1.x, player.global_position.z - p1.z).dot(Vector2(dn.x, dn.z))
		cross_ok = left > 1.0 and absf(player.global_position.y - p1.y) < 0.5
		check("a bridge can be walked across from one roof to the other", cross_ok, "%.1f past the far end, y=%.1f" % [left, player.global_position.y])
	# ---- a broken bridge has a gap you must jump (nothing under the deck for about 2 m)
	for br2 in City.bridges:
		if br2["broken"]:
			var q0: Vector3 = br2["p0"]
			var q1: Vector3 = br2["p1"]
			var gp := q0.lerp(q1, float(br2["gap_t"]))
			var hit_gap := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(gp.x, q0.y + 1.5, gp.z), Vector3(gp.x, q0.y - 4.0, gp.z), Game.L_WORLD))
			var hit_deck := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(q0.x + (q1.x - q0.x) * 0.05, q0.y + 1.5, q0.z + (q1.z - q0.z) * 0.05), Vector3(q0.x + (q1.x - q0.x) * 0.05, q0.y - 4.0, q0.z + (q1.z - q0.z) * 0.05), Game.L_WORLD))
			open_gap = hit_gap.is_empty() or (hit_gap["position"] as Vector3).y < q0.y - 3.0
			open_gap = open_gap and not hit_deck.is_empty()
			break
	check("a damaged bridge has a gap in the middle (jump across it)", open_gap or not _any_broken_bridge())
	check("there are open footbridges and glass walkways", _bridge_kinds() >= 2 or City.bridges.size() < 2, str(City.bridges.size()))
	# ---- falling: 2 storeys hurts, 4 is very dangerous, 6 kills
	var g_eff := Game.GRAVITY * Game.FALL_GRAVITY_MULT
	var d2 := Player.fall_damage(sqrt(2.0 * g_eff * 6.8))
	var d4 := Player.fall_damage(sqrt(2.0 * g_eff * 13.6))
	var d6 := Player.fall_damage(sqrt(2.0 * g_eff * 20.4))
	check("fall damage: 2 storeys hurts, 4 storeys is very dangerous, 6 storeys is deadly", d2 > 15.0 and d2 < 45.0 and d4 > 60.0 and d4 < 100.0 and d6 >= 100.0, "%.0f / %.0f / %.0f" % [d2, d4, d6])
	player.health = Game.MAX_HEALTH
	Game.dead = false
	tp(Vector3(0, 20.5, 6.0))
	await secs(3.0)
	check("a real fall from six storeys kills the player", Game.dead, "health %.0f" % player.health)
	Game.dead = false
	player.health = Game.MAX_HEALTH
	tp(Vector3(0, 13.7, 6.0))
	await secs(3.0)
	check("a real fall from four storeys leaves the player barely alive", not Game.dead and player.health < 45.0, "health %.0f" % player.health)
	player.health = Game.MAX_HEALTH
	Game.dead = false
	tp(Vector3(0, 0.1, 150.0))
	await secs(1.0)


func _any_broken_bridge() -> bool:
	for br in City.bridges:
		if br["broken"]:
			return true
	return false


func _bridge_kinds() -> int:
	var k := {}
	for br in City.bridges:
		k[br["kind"]] = true
	return k.size()


## Colliders follow the shapes: a car's hood is lower than its roof, a truck's cab lower than its cargo, a tram's bogie is solid,
## a jersey barrier is narrower on top than at its foot, and a sandbag stack narrows towards the top.
func collider_tests() -> void:
	print("--- precise colliders ---")
	await park_all()
	await frames(2)
	var space := player.get_world_3d().direct_space_state
	var down := func(x: float, z: float) -> float:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 12.0, z), Vector3(x, -1.0, z), Game.L_WORLD)
		var hit := space.intersect_ray(q)
		return float(hit["position"].y) if not hit.is_empty() else -9.0
	var cars_ok := 0
	var cars_tested := 0
	for c in City.cars:
		if cars_tested >= 6:
			break
		if String(c["type"]) not in ["hatch", "sedan"] or String(c.get("dmg", "")) != "" or absf(float(c.get("roll", 0.0))) > 0.01:
			continue
		var sz: Vector3 = c["size"]
		var b: Basis = c["basis"]
		var o: Vector3 = c["origin"]
		var roof := o + b * Vector3(0, 0, sz.z * 0.04)
		var hood := o + b * Vector3(0, 0, -sz.z * 0.46)
		var rh: float = down.call(roof.x, roof.z)
		var hh: float = down.call(hood.x, hood.z)
		cars_tested += 1
		if rh > hh + 0.25 and hh > 0.3:
			cars_ok += 1
		else:
			print("   car ", c["type"], " at ", o, " roof ", snappedf(rh, 0.01), " hood ", snappedf(hh, 0.01))
	check("a parked car's cabin is higher than its bonnet", cars_tested >= 3 and cars_ok == cars_tested, "%d of %d" % [cars_ok, cars_tested])
	if not CityStory.tram.is_empty():
		var tc: Vector3 = CityStory.tram["pos"]
		var bog := tc + Vector3(-5.2, CityStory.TRAM_H * 0.5, CityStory.TRAM_W * 0.5 + 0.35)
		var q2 := PhysicsRayQueryParameters3D.create(bog + Vector3(0, 0, 3.0), bog + Vector3(0, 0, -0.1), Game.L_WORLD)
		var h2 := space.intersect_ray(q2)
		check("the tram's bogie sticking out sideways is solid, not just the body", not h2.is_empty() and absf(float(h2["position"].z) - (bog.z + 0.3)) < 0.15, str(h2.get("position", "none")))
	var jersey := 0
	var jersey_ok := 0
	for ob in CityWar.war_obstacles:
		if String(ob["kind"]) != "jersey" or jersey >= 4:
			continue
		jersey += 1
		var jp: Vector3 = ob["pos"]
		var jy: float = ob["yaw"]
		var side := Basis(Vector3.UP, jy) * Vector3(0, 0, 1)
		# a horizontal ray at 0.7 m from the side meets the narrow body (0.18 m from the middle), one at 0.15 m the wide foot (0.3 m)
		var hi := space.intersect_ray(PhysicsRayQueryParameters3D.create(jp + Vector3(0, 0.7, 0) + side * 1.0, jp + Vector3(0, 0.7, 0), Game.L_WORLD))
		var lo := space.intersect_ray(PhysicsRayQueryParameters3D.create(jp + Vector3(0, 0.15, 0) + side * 1.0, jp + Vector3(0, 0.15, 0), Game.L_WORLD))
		if not hi.is_empty() and not lo.is_empty() and ((lo["position"] - jp) as Vector3).dot(side) > ((hi["position"] - jp) as Vector3).dot(side) + 0.08:
			jersey_ok += 1
	check("a jersey barrier is narrower on top than at its foot", jersey >= 1 and jersey_ok == jersey, "%d of %d" % [jersey_ok, jersey])
	var sandbags := 0
	var sand_ok := 0
	for ob in CityWar.war_obstacles:
		if String(ob["kind"]) != "sandbags" or sandbags >= 4:
			continue
		sandbags += 1
		var sp: Vector3 = ob["pos"]
		var sy: float = ob["yaw"]
		var along := Basis(Vector3.UP, sy) * Vector3(1, 0, 0)
		var low := space.intersect_ray(PhysicsRayQueryParameters3D.create(sp + Vector3(0, 0.3, 0) + along * 3.0, sp + Vector3(0, 0.3, 0), Game.L_WORLD))
		var top := space.intersect_ray(PhysicsRayQueryParameters3D.create(sp + Vector3(0, 0.73, 0) + along * 3.0, sp + Vector3(0, 0.73, 0), Game.L_WORLD))
		if not low.is_empty() and not top.is_empty() and ((low["position"] - sp) as Vector3).dot(along) > ((top["position"] - sp) as Vector3).dot(along) + 0.25:
			sand_ok += 1
	check("a sandbag stack narrows towards the top", sandbags >= 2 and sand_ok >= sandbags - 1, "%d of %d" % [sand_ok, sandbags])


func passage_tests() -> void:
	print("--- crouch passages and pass-through buildings ---")
	await park_all()
	await clear_civilians()
	Game.dead = false
	player.health = Game.MAX_HEALTH
	var space := player.get_world_3d().direct_space_state
	check("the standing head (1.8 m) does not fit under a blocker but the crouched one (1.1 m) does", CityClimb.BLOCKER_BOTTOM > Game.CROUCH_HEIGHT + 0.1 and CityClimb.BLOCKER_BOTTOM < Game.STAND_HEIGHT - 0.2, "%.2f m" % CityClimb.BLOCKER_BOTTOM)
	check("there are crouch passages in the alleys", City.crouch_passages.size() >= 6, str(City.crouch_passages.size()))
	var tested := 0
	var blocked_ok := 0
	var crouch_ok := 0
	var path_ok := 0
	var solid_nav := 0
	var hint_ok := 0
	var kinds := {}
	for p in City.crouch_passages:
		if tested >= 8:
			break
		var c: Vector3 = p["pos"]
		var along_x: bool = p["along_x"]
		var dir := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		kinds[p["kind"]] = true
		# the nav grid knows the blocker, and a path between the two sides does not run through it
		var a := c - dir * 4.0
		var b := c + dir * 4.0
		if not City.is_free(c):
			solid_nav += 1
		var route := City.path(a, b)
		var inside := false
		var prev := a
		for wp in route:
			for k in 20:
				var q := prev.lerp(wp, float(k) / 19.0)
				if (p["rect"] as Rect2).grow(-0.05).has_point(Vector2(q.x, q.z)):
					inside = true
			prev = wp
		if not inside:
			path_ok += 1
		# standing: walk in, stop at the blocker; crouched: walk through
		var start := c - dir * 2.6
		var yaw := yaw_for(Vector2(dir.x, dir.z))
		tp(Vector3(start.x, 0.1, start.z), yaw)
		await secs(0.3)
		if tested == 0:
			hint_ok += 1 if player.context_hint() == 2 else 0
			await frames(1)
		var stand_end := await hold_forward(3.2)
		var stand_along := (stand_end - c).dot(dir)
		tp(Vector3(start.x, 0.1, start.z), yaw)
		await secs(0.3)
		var crouch_end := await hold_forward(4.4, true)
		var crouch_along := (crouch_end - c).dot(dir)
		if stand_along < 0.6:
			blocked_ok += 1
		else:
			print("   standing got through a ", p["kind"], " passage at ", c, " along_x ", along_x, " width ", p["width"], " reached ", snappedf(stand_along, 0.1), " at ", stand_end)
		if crouch_along > 1.2:
			crouch_ok += 1
		else:
			print("   crouch passage ", p["kind"], " ", c, " stand ", snappedf(stand_along, 0.1), " crouch ", snappedf(crouch_along, 0.1))
		tested += 1
	check("standing, the player cannot pass a crouch passage", tested >= 4 and blocked_ok >= tested - 1, "%d of %d" % [blocked_ok, tested])
	check("crouched, the player can pass it", tested >= 4 and crouch_ok >= tested - 1, "%d of %d" % [crouch_ok, tested])
	check("every crouch passage is blocked in the enemy navigation grid", solid_nav == tested, "%d of %d" % [solid_nav, tested])
	check("enemy paths never run through a crouch passage", path_ok == tested, "%d of %d" % [path_ok, tested])
	check("the HUD shows a crouch hint when the player faces a passage", hint_ok >= 1)
	check("the passages come in several kinds (pipe, fallen ladder, slab, low gap)", kinds.size() >= 3, str(kinds.keys()))
	# ---- pass-through buildings
	check("some buildings can be walked through (entrance on one street, exit on the other)", City.tunnels.size() >= 6, str(City.tunnels.size()))
	var thru_ok := 0
	var short_ok := 0
	var lit := 0
	for t in City.tunnels:
		var ta: Vector3 = t["a"]
		var tb: Vector3 = t["b"]
		var tr: Rect2 = t["rect"]
		var route2 := City.path(ta, tb)
		var through := false
		var prev2 := ta
		for wp2 in route2:
			for k2 in 24:
				var q2 := prev2.lerp(wp2, float(k2) / 23.0)
				if tr.has_point(Vector2(q2.x, q2.z)):
					through = true
			prev2 = wp2
		if through:
			thru_ok += 1
		if route2.size() > 0 and plen(ta, route2) < ta.distance_to(tb) + 6.0:
			short_ok += 1
	check("the navigation grid leads through a pass-through building", thru_ok >= City.tunnels.size() - 1, "%d of %d" % [thru_ok, City.tunnels.size()])
	check("and it is the short way (a direct line through the corridor)", short_ok >= City.tunnels.size() - 1, "%d of %d" % [short_ok, City.tunnels.size()])
	# an enemy hunting across really walks through the corridor
	var tun: Dictionary = City.tunnels[0]
	var hunter: Enemy = spawn("soldier", tun["a"], false)
	hunter.stun = 999.0
	place(hunter, tun["a"], true)
	await frames(3)
	tp(Vector3(0, 0.1, 150.0))
	hunter.stun = 0.0
	hunter.last_known = tun["b"]
	hunter.state = Enemy.State.CHASE
	hunter.unseen_t = 0.0
	var seen_inside := false
	for i in 12 * 30:
		await get_tree().physics_frame
		if (tun["rect"] as Rect2).has_point(Vector2(hunter.global_position.x, hunter.global_position.z)):
			seen_inside = true
		hunter.unseen_t = 0.0
	check("a hunting soldier walks through the corridor", seen_inside and hunter.global_position.distance_to(tun["b"]) < 8.0, str(hunter.global_position))
	hunter.stun = 999.0
	# the corridor: a light and a lit strip, doors and boxes
	tp(Vector3(tun["a"].x, 0.1, tun["a"].z))
	main.world.fires.update(player.global_position)
	for k3 in main.world.fires._lights["tunnel"]:
		if (k3 as OmniLight3D).visible:
			lit += 1
	check("one cheap light per corridor, only near the player (at most 2 at a time)", lit >= 1 and lit <= 2, str(lit))
	var floor_ok := true
	for t in City.tunnels:
		var tr3: Rect2 = t["rect"]
		var cx := tr3.get_center()
		var fl := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(cx.x, 2.0, cx.y), Vector3(cx.x, -0.5, cx.y), Game.L_WORLD))
		if fl.is_empty() or (fl["position"] as Vector3).y > 0.2:
			floor_ok = false
		var roof := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(cx.x, 1.0, cx.y), Vector3(cx.x, 6.0, cx.y), Game.L_WORLD))
		if roof.is_empty() or absf((roof["position"] as Vector3).y - 3.4) > 0.1:
			floor_ok = false
	check("the corridor has a floor at street level and a ceiling at 3.4 m", floor_ok)
	var frac := City.reachable_fraction(City.START_POS)
	check("the walkable ground is still connected (crouch passages and escapes included)", frac > 0.985, "%.4f" % frac)
	tp(Vector3(0, 0.1, 150.0))
	await park_all()


## Diagnostics: adapter info, F3 overlay, hitch detector, GPU warning.
func perf_tool_tests() -> void:
	print("-- perf tools --")
	var g: Dictionary = Game.gpu
	check("the video adapter is recorded (name, vendor, type, driver, method, os, godot)", g.has("name") and g.has("vendor") and g.has("type") and g.has("driver") and g.has("method") and g.has("os") and g.has("godot") and String(g["godot"]) != "", str(g))
	check("the adapter type is one of the known words", String(g["type"]) in Game.ADAPTER_TYPES, String(g["type"]))
	var ov: PerfOverlay = main.hud.debug_overlay
	check("the F3 overlay exists, is hidden and does not process", ov != null and not ov.visible and not ov.is_processing())
	ov.toggle()
	await frames(40)
	check("F3 shows it and it processes", ov.visible and ov.is_processing(), "%s %s" % [ov.visible, ov.is_processing()])
	check("the overlay lists adapter, FPS, draw calls, lights, particles, last hitch", ov.text.contains(String(g["driver"])) and ov.text.contains("FPS") and ov.text.contains("draw calls") and ov.text.contains("lights") and ov.text.contains("particle") and ov.text.contains("last hitch"), ov.text)
	check("the overlay counts at least the sun as a light", ov.lights_total >= 1, str(ov.lights_total))
	ov.toggle()
	check("F3 again hides it and stops its processing", not ov.visible and not ov.is_processing())
	# hitch detector
	var n0: int = Game.hitch_total
	Game.mark("selftest_tag")
	check("a first mark is tagged (first), a second is not", Game._tags.has("selftest_tag(first)"))
	Game._tags.clear()
	Game.mark("selftest_tag")
	check("the second mark of a tag has no (first)", Game._tags.has("selftest_tag") and not Game._tags.has("selftest_tag(first)"))
	Game._tags.clear()
	Game.mark("selftest_tag")
	Game._log_hitch(40.0, Time.get_ticks_usec(), false)
	var h: Dictionary = Game.hitches[Game.hitches.size() - 1]
	check("a hitch record keeps ms, time, position and the frame's tags", Game.hitch_total == n0 + 1 and absf(float(h["ms"]) - 40.0) < 0.01 and h["tags"].has("selftest_tag") and Game.hitch_stats.has("selftest_tag"))
	var real0: int = Game.hitch_total
	await frames(3)
	Game.mark("selftest_real")
	OS.delay_msec(60)
	await frames(3)
	var real_ok := false
	for i in range(maxi(0, Game.hitches.size() - (Game.hitch_total - real0)), Game.hitches.size()):
		if (Game.hitches[i]["tags"] as Array).has("selftest_real(first)"):
			real_ok = float(Game.hitches[i]["ms"]) > 50.0
	check("a real 60 ms stall is detected and carries the tag marked during that frame", real_ok, str(Game.hitches.slice(maxi(0, Game.hitches.size() - 3))))
	var c0: int = Game._tag_count.get("enemy_spawn", 0)
	var sp := spawn("soldier", Vector3(0, 0.3, 150), true)
	check("spawning an enemy through Main marks enemy_spawn", int(Game._tag_count.get("enemy_spawn", 0)) == c0 + 1)
	kill(sp)
	# the pause-menu warning appears once per adapter, only when the NVIDIA card is not in use
	var saved_nv: bool = Game.gpu_is_nvidia
	var saved_warned: String = Settings.gpu_warned
	var saved_name: String = Game.gpu["name"]
	Game.gpu["name"] = "Test GPU"
	Game.gpu_is_nvidia = true
	main.hud._show_gpu_warning()
	check("on the NVIDIA GPU there is no warning", not main.hud.gpu_warning.visible)
	Game.gpu_is_nvidia = false
	Settings.gpu_warned = ""
	main.hud._show_gpu_warning()
	var shown: bool = main.hud.gpu_warning.visible and main.hud.gpu_warning.text.contains("README")
	main.hud._show_gpu_warning()
	check("on another GPU the warning shows once, then not again for the same adapter", shown and not main.hud.gpu_warning.visible)
	Game.gpu_is_nvidia = saved_nv
	Game.gpu["name"] = saved_name
	Settings.gpu_warned = saved_warned
	Settings.save()
	main.hud.gpu_warning.visible = false


# ---------------------------------------------------------------- the invasion morning: sky, invaders, lane, dead, pulse rifle

func sound_peak(id: String) -> float:
	var data: PackedByteArray = Sfx.get_sound(id).data
	var peak := 0.0
	for i in range(0, data.size() - 1, 2):
		peak = maxf(peak, absf(float(data.decode_s16(i))) / 32768.0)
	return peak


func invasion_tests() -> void:
	print("--- the invasion morning: sky, invaders, first lane, lone soldier, dead, pulse rifle ---")
	await park_all()
	await clear_civilians()
	player.health = Game.MAX_HEALTH
	Game.dead = false
	# --- the sky: Veil
	var vl: Veil = main.world.veil
	check("the veil sky is built (shader sky, 8 landers, shimmer columns, smoke pillars)", vl != null and vl.sky_mat != null and vl.hull_mm != null and vl.hull_mm.instance_count == Veil.LANDERS and vl.shimmer_mm.instance_count == Veil.LANDERS and Veil.PILLARS.size() >= 4)
	check("the sky shader does not use TIME or POSITION built-ins (no radiance re-render): time and camera come in as uniforms", not Veil.SKY_SHADER.contains("TIME") and not Veil.SKY_SHADER.contains("POSITION") and vl.sky_mat.shader.code == Veil.SKY_SHADER)
	var t0_low := 0
	for i in Veil.LANDERS:
		if Veil.lander_pos(i, 0.0).y < Veil.DOME_H:
			t0_low += 1
	check("a handful of landers already drift below the veil at the start, the rest follow", t0_low >= 3 and t0_low < Veil.LANDERS, "%d of %d" % [t0_low, Veil.LANDERS])
	var descend_ok := true
	var rest_ok := true
	for i in Veil.LANDERS:
		var p0 := Veil.lander_pos(i, 0.0)
		var p1 := Veil.lander_pos(i, 150.0)
		var p9 := Veil.lander_pos(i, 900.0)
		descend_ok = descend_ok and p1.y <= p0.y + 0.01 and (p1.y < p0.y - 20.0 or i >= 5)
		rest_ok = rest_ok and p9.y >= 150.0 and p9.y <= 330.0
	check("the landers sink over the first minutes and come to rest between 150 and 330 m", descend_ok and rest_ok)
	var cam := player.camera
	vl._update_landers()
	var far_ok := true
	for i in Veil.LANDERS:
		var o := vl.hull_mm.get_instance_transform(i).origin
		far_ok = far_ok and o.distance_to(cam.global_position) <= cam.far * Veil.LANDER_DIST_MAX + 1.0
	check("every lander is kept inside the camera far plane (pulled in along the view line and shrunk)", far_ok, "far %.0f" % cam.far)
	var tt0 := Time.get_ticks_usec()
	for k in 200:
		vl._update_landers()
	var lander_ms := float(Time.get_ticks_usec() - tt0) / 200.0 / 1000.0
	check("updating the landers costs under 0.1 ms (done 4 times a second)", lander_ms < 0.1, "%.3f ms" % lander_ms)
	var c0 := vl.clock
	await secs(0.5)
	check("the veil clock runs (the sky flickers from it)", vl.clock > c0 + 0.3)
	var pillars_out := true
	for p in Veil.PILLARS:
		pillars_out = pillars_out and (absf(float(p[0])) > City.OUT_X + 30.0 or absf(float(p[1])) > City.OUT_Z + 30.0)
	check("the smoke pillars of the power stations stand south and east, outside the ring", pillars_out)

	# --- the invaders: speed, stamina, lean on walls, rust
	var speeds_ok := true
	var slow_ok := true
	for k in Enemy.KINDS:
		var ek: Enemy = spawn(k, Vector3(150.0, 0, 0))
		var base_run: float = Enemy.KINDS[k]["run"]
		var ratio := ek.run_speed / base_run
		speeds_ok = speeds_ok and ratio >= 0.7 and ratio <= 0.8
		slow_ok = slow_ok and ek.run_speed < Game.SPRINT_SPEED * 0.6 and ek.walk_speed <= float(Enemy.KINDS[k]["walk"])
	check("every kind runs at 70-80% of its old speed", speeds_ok)
	check("a sprinting player (8 m/s) outruns every invader (fastest 4.7 m/s) and they walk slower than before", slow_ok)
	var sold: Enemy = spawn("soldier", Vector3(150.0, 0, 5.0))
	await frames(3)
	var drain_t := 0.0
	while sold.winded_t <= 0.0 and drain_t < 12.0:
		sold._stamina_step(0.05, Vector3(0, 0, -sold.run_speed))
		drain_t += 0.05
	check("a soldier running flat out is winded after 4-6.5 s", sold.winded_t > 0.0 and drain_t >= 4.0 and drain_t <= 6.5, "%.1f s" % drain_t)
	var blade_e: Enemy = spawn("blade", Vector3(150.0, 0, 10.0))
	var blade_t := 0.0
	while blade_e.winded_t <= 0.0 and blade_t < 14.0:
		blade_e._stamina_step(0.05, Vector3(0, 0, -blade_e.run_speed))
		blade_t += 0.05
	check("the blade fighter (130 stamina) tires later than the soldier but still within 8 s", blade_t > drain_t and blade_t <= 8.0, "%.1f s" % blade_t)
	var rusty := true
	for k2 in Enemy.KINDS:
		var er: Enemy = spawn(k2, Vector3(150.0, 0, 15.0))
		var sum := Color(0, 0, 0)
		var n := 0
		for mi in er.model.body.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			for si in m.mesh.get_surface_count():
				var mat := m.get_active_material(si) as StandardMaterial3D
				if mat != null:
					sum += mat.albedo_color
					n += 1
		var avg := sum / maxf(float(n), 1.0)
		rusty = rusty and n > 0 and avg.r > avg.b * 1.15
	check("every kind wears dull rust-coloured armour (red above blue in the model's colours)", rusty)
	check("the blade fighter keeps his violet plasma blade", (WeaponsDB.WEAPONS["blade"]["glow"] as Color).b > 0.9 and (WeaponsDB.WEAPONS["blade"]["glow"] as Color).r > 0.6)
	# lean on a wall: a winded soldier in the first lane drags himself to the wall and props himself up
	var lane := CityStory.first_lane()
	check("the first narrow lane beside the walk home exists (an alley or footpath, at most 6 m wide)", not lane.is_empty() and minf((lane["rect"] as Rect2).size.x, (lane["rect"] as Rect2).size.y) <= 6.1)
	var lean_e: Enemy = spawn("soldier", Vector3(150.0, 0, 20.0))
	var lane_pos: Vector3 = lane["pos"]
	var wall_d := 99.0
	var wall_dir := Vector3.ZERO
	for lk in 4:                  # (lots are inset, so the opening can be wider than the lane's rectangle: stand 1 m off the nearest wall)
		var ldir := Vector3(cos(PI * 0.5 * lk), 0, sin(PI * 0.5 * lk))
		var lq := PhysicsRayQueryParameters3D.create(lane_pos + Vector3(0, 1.2, 0), lane_pos + Vector3(0, 1.2, 0) + ldir * 5.0, Game.L_WORLD)
		var lh := player.get_world_3d().direct_space_state.intersect_ray(lq)
		if not lh.is_empty() and (lane_pos + Vector3(0, 1.2, 0)).distance_to(lh["position"]) < wall_d:
			wall_d = (lane_pos + Vector3(0, 1.2, 0)).distance_to(lh["position"])
			wall_dir = ldir
	lean_e.global_position = lane_pos + (wall_dir * (wall_d - 1.0) if wall_d < 99.0 else Vector3.ZERO) + Vector3(0, 0.1, 0)
	lean_e.velocity = Vector3.ZERO
	await frames(10)
	lean_e.stun = 0.0
	lean_e.post = true
	lean_e.stamina = 0.1
	lean_e._stamina_step(0.01, Vector3(0, 0, -4.0))
	check("winded in the lane he finds a wall to lean on", lean_e.winded_t > 0.0 and lean_e.lean_wall != Vector3.ZERO, str(lean_e.lean_wall))
	lean_e.winded_t = 8.0
	await secs(2.5)
	var fwd := Vector3(-sin(lean_e.facing), 0, -cos(lean_e.facing))
	check("he turns to the wall and ends up against it (within 0.7 m)", fwd.dot(lean_e.lean_wall) > 0.8 and lean_e.lean_dist <= Enemy.LEAN_GAP + 0.1, "dot %.2f dist %.2f" % [fwd.dot(lean_e.lean_wall), lean_e.lean_dist])
	var open_e: Enemy = spawn("soldier", Vector3(0, 0, 40.0))
	await frames(5)
	open_e.stamina = 0.1
	open_e._stamina_step(0.01, Vector3(0, 0, -4.0))
	check("winded in the open (no wall within 1.8 m) he just stands bent over", open_e.winded_t > 0.0 and open_e.lean_wall == Vector3.ZERO)
	await park_all()

	# --- the first lane: a blade fighter with no gun who charges
	var blade_role: Enemy = null
	for e in Game.enemies:
		if String(main.story_roles.get((e as Enemy).uid, "")) == "lane_blade":
			blade_role = e
	check("the story spawned the lane blade fighter and the lone soldier through Main (they carry a uid)", blade_role != null and main.story_roles.size() >= 5 and blade_role.uid >= 0 and main.story_roles.values().has("lone_soldier") and main.story_roles.values().has("balcony_marksman") and main.story_roles.values().count("exhausted") == 2)
	var lb: Enemy = main._spawn_enemy_at(lane["pos"], "blade")
	all.append(lb)
	main._assign_role(lb, "lane_blade")
	check("the lane blade fighter has no gun: melee blade only, no muzzle, not a ranged unit", lb.kind == "blade" and not lb.ranged and lb.weapon_id == "blade" and bool(WeaponsDB.WEAPONS[lb.weapon_id].get("melee", false)) and lb.muzzle == null and not lb.cfg.has("engage"))
	var lane_rect: Rect2 = (lane["rect"] as Rect2).grow(1.0)
	check("he stands in the first narrow lane, calm, alone (group -1), at his post", lane_rect.has_point(Vector2(lb.global_position.x, lb.global_position.z)) and lb.state == Enemy.State.WANDER and lb.group == -1 and lb.post)
	var way_len := plen(City.INSTITUTE_EXIT, City.path(City.INSTITUTE_EXIT, lb.global_position))
	check("the lane lies in the first minute of the walk home (path to him under 230 m)", way_len > 20.0 and way_len < 230.0, "%.0f m" % way_len)
	lb.stun = 0.0
	var mouth: Vector3 = lane["near"]
	var look_to := lb.global_position - mouth
	tp(mouth + Vector3(0, 0.1, 0), atan2(-look_to.x, -look_to.z))
	await secs(0.8)
	check("he charges as soon as the player comes in sight within 24 m", lb.state != Enemy.State.WANDER and lb.state != Enemy.State.DEAD, "state %d" % lb.state)
	await secs(3.5)
	var dist_now := Vector2(lb.global_position.x - player.global_position.x, lb.global_position.z - player.global_position.z).length()
	check("and he runs at the player (closes to melee range or is attacking)", dist_now < 4.0 or lb.state == Enemy.State.ATTACK, "%.1f m, state %d" % [dist_now, lb.state])
	var blade_hp := lb.health
	kill(lb)
	check("a pistol is enough: he has 65 HP (3 hits of 28, one headshot) and dies", blade_hp <= 65.0 and ceili(blade_hp / 28.0) <= 3 and lb.state == Enemy.State.DEAD)
	await park_all()

	# --- the lone young soldier near the home
	var lone := CityStory.lone_soldier_spot()
	var lone_way := plen(lone["pos"], City.path(lone["pos"], City.HOME_POS)) if not lone.is_empty() else 0.0
	check("the lone soldier's spot is on the way home, about 46 m before the door", not lone.is_empty() and lone_way > 30.0 and lone_way < 75.0, "%.0f m" % lone_way)
	var ls: Enemy = main._spawn_enemy_at(lone["pos"], "soldier")
	all.append(ls)
	main._assign_role(ls, "lone_soldier")
	ls.stun = 999.0          # frozen like the other takedown tests: no senses while the player steps up behind him
	check("he is young and alone: 60 HP, group -1, idly spinning his rifle, slow to react (lazy alert)", ls.max_health == 60.0 and ls.group == -1 and ls.spin_rifle and ls.lazy_alert >= 0.8 and ls.ranged and ls.weapon_id == "rifle")
	var fw := Vector3(-sin(ls.facing), 0, -cos(ls.facing))
	check("he faces the way the patrol went, so the player comes up behind him", absf(angle_difference(ls.facing, float(lone["face"]))) < 0.2)
	player.weapons.loadout["melee"][0]["id"] = "knife"
	player.weapons.switch_to("knife")
	await secs(0.7)
	tp(ls.global_position - fw * 1.3 + Vector3(0, 0.1, 0), ls.facing)
	await secs(0.3)
	check("the player can take him down silently from behind", player.weapons.find_takedown() == ls)
	var shots_heard := [0]
	var sh_cb := func(_p: Vector3, _l: float) -> void: shots_heard[0] += 1
	Game.gunshot.connect(sh_cb)
	ls.takedown()
	await frames(5)
	Game.gunshot.disconnect(sh_cb)
	check("the takedown is silent (no gunshot event)", shots_heard[0] == 0 and ls.state == Enemy.State.DEAD)
	await secs(0.5)
	var rifles := 0
	for ch in main.get_children():
		if ch is Pickup and (ch as Pickup).weapon_id == "rifle" and (ch as Pickup).global_position.distance_to(ls.global_position) < 3.0:
			rifles += 1
	check("his rifle lies next to him: the player's first pulse rifle", rifles >= 1, "%d" % rifles)
	# a checkpoint restore keeps both scripted soldiers scripted
	var lb2: Enemy = main._spawn_enemy_at(lane["pos"], "blade")
	all.append(lb2)
	main._assign_role(lb2, "lane_blade")
	var info := {"uid": lb2.uid, "kind": "blade", "group": 5, "pos": lb2.global_position, "health": 30.0, "ammo": 0, "sidearm_ammo": -1, "home": lb2.home, "facing": 1.0}
	var re: Enemy = main.spawn_enemy_from(info)
	all.append(re)
	check("a rebuilt story soldier (checkpoint restore) is scripted again: post, group -1, same uid, health kept", re.post and re.group == -1 and re.uid == lb2.uid and re.health == 30.0)
	await park_all()

	# --- the dead, the tram, the stalls, the crowd
	check("the story population is 50 civilians (9 children) and the dead lie along the way home", main.CIVILIAN_COUNT >= 50 and main.CIVILIAN_CHILDREN >= 9)
	var brng := RandomNumberGenerator.new()
	brng.seed = 7117
	var spots: Array = CityStory.body_spots(brng)
	var spots_ok := spots.size() >= 8
	for sp in spots:
		spots_ok = spots_ok and City.is_free(sp) and (sp as Vector3).distance_to(City.INSTITUTE_EXIT) >= 18.0 and (sp as Vector3).distance_to(City.HOME_POS) >= 14.0
	check("at least 8 bodies lie in doorways and gutters on free ground along the way (none at the exit or the home door)", spots_ok, "%d spots" % spots.size())
	check("a tram lies on its side in the Institute avenue", not CityStory.tram.is_empty() and absf((CityStory.tram["pos"] as Vector3).z - 235.0) < 8.0)
	var tram_rect: Rect2 = CityStory.tram["rect"]
	var tram_clear := true
	for b in City.buildings:
		if (b["rect"] as Rect2).intersects(tram_rect):
			tram_clear = false
	check("the tram stands clear of every building and is a long solid box", tram_clear and tram_rect.size.x >= 15.0)
	check("overturned market stalls with spilled goods lie along the avenues (6 or more)", CityStory.stalls.size() >= 6, "%d" % CityStory.stalls.size())
	# ambience: louder near the main avenue
	tp(Vector3(0, 0.1, 100.0), 0.0)
	var near_k: float = main.avenue_closeness()
	tp(Vector3(-90.0, 0.1, -120.0), 0.0)
	var far_k: float = main.avenue_closeness()
	check("the avenue closeness is 1 on the main avenue and 0 deep in the back streets", near_k > 0.95 and far_k < 0.05, "%.2f / %.2f" % [near_k, far_k])
	tp(Vector3(0, 0.1, 100.0), 0.0)
	await clear_civilians()
	for i in 20:
		main._update_crowd(0.5)
	var vol_avenue: float = main._crowd.volume_db
	tp(Vector3(-90.0, 0.1, -120.0), 0.0)
	for i in 20:
		main._update_crowd(0.5)
	var vol_back: float = main._crowd.volume_db
	check("the crowd is heard on the avenue even with nobody close, and fades away in the back streets", vol_avenue > -42.0 and vol_back < -54.0 and vol_avenue > vol_back + 15.0, "%.0f / %.0f dB" % [vol_avenue, vol_back])
	check("distant gunfire and explosions are synthesised (2 s of shots, 3 s of boom)", Sfx.get_sound("far_gun").data.size() >= 2 * Sfx.RATE * 2 and Sfx.get_sound("far_boom").data.size() >= 3 * Sfx.RATE * 2 and sound_peak("far_gun") > 0.1 and sound_peak("far_boom") > 0.1)
	var kids_before: int = main.get_child_count()
	main._ambience_t = 0.0
	main._update_ambience(0.1)
	check("the ambience fires from a random direction and re-arms its timer", main.get_child_count() == kids_before + 1 and main._ambience_t > 1.0, "%.1f s" % main._ambience_t)
	var t_avenue := 0.0
	var t_back := 0.0
	var rr := RandomNumberGenerator.new()
	rr.seed = 5
	for i in 200:
		t_avenue += lerpf(7.0, 2.2, 1.0) * rr.randf_range(0.6, 1.4)
		t_back += lerpf(7.0, 2.2, 0.0) * rr.randf_range(0.6, 1.4)
	check("the distant fighting comes about 3x as often on the avenue as in the back streets", t_back / t_avenue > 2.5, "%.1f x" % (t_back / t_avenue))

	# --- the first rifle: the invaders' pulse rifle
	var pr: Dictionary = WeaponsDB.WEAPONS["rifle"]
	check("the first rifle is the invaders' pulse rifle: new name, white glow, whip sound, no brass, procedural model", String(pr["name"]).contains("PULSE") and (pr["glow"] as Color).r > 0.85 and (pr["glow"] as Color).g > 0.85 and (pr["glow"] as Color).b > 0.85 and String(pr["sound"]) == "whip" and not bool(pr["casing"]) and String(pr["model"]) == "")
	check("its stats are unchanged (24 dmg, 720 rpm, 30 rounds, 4 spare, 2.5 s reload, head x2.2)", pr["damage"] == 24.0 and pr["rpm"] == 720.0 and pr["mag"] == 30 and pr["spare_mags"] == 4 and pr["reload_time"] == 2.5 and pr["head_mult"] == 2.2)
	check("the whip-crack is its own sound: short, sharp, much shorter than the old rifle's report", Sfx.get_sound("whip").data.size() < Sfx.get_sound("rifle").data.size() and sound_peak("whip") > 0.3 and Sfx.get_sound("whip") != Sfx.get_sound("rifle"))
	var hum := Sfx.get_sound("hum")
	check("it hums: a seamless 1 s loop", hum.loop_mode == AudioStreamWAV.LOOP_FORWARD and hum.loop_end == Sfx.RATE and sound_peak("hum") > 0.1 and sound_peak("hum") < 0.8)
	var gm := GunModels.build("rifle", 2)
	check("the model is the sleek procedural one with a glow surface (lit + glowing)", gm.mesh.get_surface_count() == 2 and GunModels.profile("rifle").size() > 10)
	check("soldiers' bolts are white too", (Enemy.KINDS["soldier"]["bolt"] as Color).b > 0.85 and (Enemy.KINDS["soldier"]["bolt"] as Color).r > 0.85)
	var wp := player.weapons
	if wp.loadout["rifle"].is_empty():
		wp.loadout["rifle"].append(Weapons.new_weapon("rifle"))
	wp.switch_to("rifle")
	await secs(1.2)
	check("the pulse rifle's hum plays while it is in hand", wp.hum.playing and wp.current == "rifle")
	wp.switch_to("pistol")
	await secs(1.0)
	check("and stops with another weapon in hand", not wp.hum.playing)
	wp.switch_to("rifle")
	await secs(1.2)
	tp(Vector3(0, 0.1, 0), 0.0)
	wp.state["rifle"]["ammo"] = 30
	wp.cooldown = 0.0
	var before: int = main.get_child_count()
	var brass := wp._casings.size()
	wp._fire_shot()
	var tracer: MeshInstance3D = null
	for i in range(main.get_child_count() - 1, maxi(before - 1, -1), -1):
		var ch2: Node = main.get_child(i)
		if ch2 is MeshInstance3D and (ch2 as MeshInstance3D).mesh is BoxMesh and absf(((ch2 as MeshInstance3D).mesh as BoxMesh).size.x - 0.012) < 0.001:
			tracer = ch2
			break
	var tcol := Color(0, 0, 0)
	if tracer != null:
		tcol = (tracer.material_override as StandardMaterial3D).albedo_color
	check("a shot leaves a bright white tracer (12 mm wide) and no brass", tracer != null and tcol.r > 0.85 and tcol.b > 0.9 and wp._casings.size() == brass, str(tcol))


# ---------------------------------------------------------------- "The Lander", part one

## Right after the spawn (before anything is parked): the story soldiers of the way to the park stand where the story put them.
func lander_spawn_checks() -> void:
	var roles: Dictionary = main.story_roles
	var ex: Array = []
	var mk: Enemy = null
	for e in Game.enemies:
		var r := String(roles.get((e as Enemy).uid, ""))
		if r == "exhausted":
			ex.append(e)
		elif r == "balcony_marksman":
			mk = e
	check("two soldiers sit exhausted against a wall on the way to the park (state EXHAUSTED, helmets off, calm)", ex.size() == 2 and (ex[0] as Enemy).state == Enemy.State.EXHAUSTED and (ex[1] as Enemy).state == Enemy.State.EXHAUSTED and ex[0].group == 202 and ex[0].kind == "soldier", str(ex.size()))
	var helmets_off := true
	for e in ex:
		var hn := ((e as Enemy).model.body.find_child("Object_82", true, false)) as Node3D
		helmets_off = helmets_off and hn != null and not hn.visible
	check("...without helmets", helmets_off)
	var rest := CityStory.rest_spot()
	check("...against the balcony building's west wall, 1.5 m apart, facing the street", not rest.is_empty() and ((rest["a"] as Vector3).distance_to(rest["b"]) - 1.5) < 0.05 and CityStory._near_building((rest["a"] as Vector3) + (rest["wall"] as Vector3) * 1.0, 1.2), str(rest.get("a")))
	check("the marksman stands on the balcony with the LR-9 (kind marksman, group 201, post facing the park)", mk != null and mk.kind == "marksman" and mk.group == 201 and mk.weapon_id == "sniper" and mk.global_position.y > City.BALCONY_Y and City.BALCONY_RECT.has_point(Vector2(mk.global_position.x, mk.global_position.z)) and mk.post and absf(mk.post_facing) < 0.01, str(mk.global_position if mk != null else null))
	check("his field of view is narrow (70 degrees): the stair behind him is out of it", mk != null and mk.sight_fov <= 70.0)
	check("nobody guards the lander yet: the ten guards come when it lands", Game.enemies.filter(func(e): return e.group == ParkFight.GUARD_GROUP).is_empty() and main.world.lander != null and not main.world.lander.visible)


func lander_tests() -> void:
	print("--- The Lander, part one: lookout roof, landing craft, exhausted soldiers, balcony marksman, LR-9, park guards ---")
	await park_all()
	await clear_civilians()
	player.health = Game.MAX_HEALTH
	Game.dead = false
	var w := player.weapons
	var ms: Mission = Game.mission
	var cp_start: Checkpoint = main.checkpoint          # the GO TO THE CELLAR checkpoint: put back at the end, the later sections expect it
	var idx_cellar: int = main._objective_index("go_cellar")
	if ms.index != idx_cellar:           # (run alone through tests/one.gd the mission is still on its first objective)
		ms.index = idx_cellar
		ms.finished = false
		main.checkpoint = Checkpoint.capture(main)
		cp_start = main.checkpoint
	# --- the lookout roof and its way up
	var lk := CityStory.lookout
	check("the old block east of the home has a guaranteed fire escape to a roof 14 m up", not lk.is_empty() and lk["kind"] == "escape" and absf(float(lk["top"]) - 14.0) < 0.01 and (lk["building"] as Dictionary).has("lookout_plot"), str(lk.get("kind")))
	check("the foot of the escape is on the street side of the block, 10 m from the park's street, and walkable from the home door", not lk.is_empty() and City.path(City.HOME_POS, lk["foot"]).size() >= 2 and (lk["foot"] as Vector3).x > 46.0)
	var roof: Vector3 = lk["roof"]
	check("the roof's lookout spot has the whole landing area in sight over the park's trees (a ray from there to the middle of the landing area is clear)", PhysicsRayQueryParameters3D.create(roof + Vector3(0, 1.6, 0), City.LANDER_POS + Vector3(0, 5.5, 0), Game.L_WORLD) != null and player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(roof + Vector3(0, 1.6, 0), City.LANDER_POS + Vector3(0, 5.5, 0), Game.L_WORLD)).is_empty())
	# --- the ship model
	var lander: ShipModels.Lander = main.world.lander
	var m2 := ShipModels.lander_mesh(2)
	var m1 := ShipModels.lander_mesh(1)
	var tris2: int = m2.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3 + (m2.surface_get_arrays(1)[Mesh.ARRAY_INDEX].size() / 3 if m2.get_surface_count() > 1 else 0)
	var tris1: int = m1.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3 + (m1.surface_get_arrays(1)[Mesh.ARRAY_INDEX].size() / 3 if m1.get_surface_count() > 1 else 0)
	check("the lander is ONE cached mesh with two surfaces (lit + glowing) and a cheaper far version", m2 == ShipModels.lander_mesh(2) and m2.get_surface_count() == 2 and tris1 < tris2 and tris2 < 3500, "%d / %d triangles" % [tris2, tris1])
	check("it has a collision box set (hull, doorway alcove, ramp) and the ground patch is one cached mesh", ShipModels.lander_boxes().size() >= 7 and ShipModels.site_mesh() == ShipModels.site_mesh())
	var foot := CityStory.ramp_foot()
	check("it stands on the park's landing area with the ramp facing west, the street side", City.LANDING.has_point(Vector2(City.LANDER_POS.x, City.LANDER_POS.z)) and foot.x < City.LANDER_POS.x - 12.0 and absf(foot.z - City.LANDER_POS.z) < 0.5 and foot.x > City.PARK_RECT.position.x, str(foot))
	var hull_w := lander.hull.global_transform * Vector3(0, 3, 0)
	check("the hull stays inside the landing area (30 x 15 m)", City.LANDING.grow(0.5).has_point(Vector2(hull_w.x - 10.0, hull_w.z)) and City.LANDING.grow(0.5).has_point(Vector2(hull_w.x + 10.0, hull_w.z)))
	check("the doorway is modelled and the interior lies behind a loading threshold area", lander.threshold != null and lander.threshold.collision_mask == Game.L_PLAYER and ShipModels.ramp_top_local().y == ShipModels.SILL_Y)
	check("before the lookout the craft is not in the world: hidden, no collision", not lander.visible and not lander.landed and (lander.body.get_child(0) as CollisionShape3D).disabled)
	check("a few more craft have settled in far plazas (one MultiMesh of the cheap hull, each with its own solid box), hidden until the lookout", CityStory.far_landers.size() >= 1 and main.world.far_landers_node != null and not main.world.far_landers_node.visible and main.world.far_landers_node.multimesh.instance_count == CityStory.far_landers.size() and CityStory.far_landers.all(func(fl): return (fl["pos"] as Vector3).distance_to(City.LANDER_POS) > 90.0), str(CityStory.far_landers.size()))
	# --- the sniper rifle: database, model, loadout
	var sd: Dictionary = WeaponsDB.WEAPONS["sniper"]
	check("the LR-9 is a rifle-slot bolt-action: 5 rounds, 3 spare magazines, high damage, very loud, scoped", sd["slot"] == "rifle" and int(sd["mag"]) == 5 and int(sd["spare_mags"]) == 3 and float(sd["damage"]) >= 100.0 and float(sd["loudness"]) > float(WeaponsDB.WEAPONS["rifle"]["loudness"]) * 1.5 and float(sd["ads_fov"]) < 40.0 and not bool(sd["auto"]) and float(sd["rpm"]) <= 60.0)
	check("it is heavy (the pistol is the safe choice up close), slow shells drop, the breath can be held 3 s", bool(sd["heavy"]) and float(sd["bullet_speed"]) < 400.0 and float(sd["breath_time"]) == 3.0 and float(sd["scope_sway"]) > 0.0)
	var gm := GunModels.build("sniper", 2)
	check("its model is the long procedural one (lit + glow surfaces, longer than the pulse rifle's)", gm.mesh.get_surface_count() == 2 and GunModels.profile("sniper").size() > 20 and gm.mesh.get_aabb().size.z > GunModels.build("rifle", 2).mesh.get_aabb().size.z * 1.2, str(gm.mesh.get_aabb().size.z))
	check("its shot has its own loud sound with a long tail", Sfx.get_sound("longshot").get_length() > 1.4 and sound_peak("longshot") > 0.3)
	# --- ballistics: a shell falls (about 0.2 m at 40 m, 0.8 m at 80 m), traced in pieces
	var wall := StaticBody3D.new()
	wall.collision_layer = Game.L_WORLD
	var wcs := CollisionShape3D.new()
	var wsh := BoxShape3D.new()
	wsh.size = Vector3(60, 60, 1)
	wcs.shape = wsh
	wall.add_child(wcs)
	main.add_child(wall)
	var space := player.get_world_3d().direct_space_state
	var drops: Array = []
	for dist in [40.0, 80.0]:
		wall.global_position = Vector3(0, 700.0, -dist)
		await frames(3)
		var hit := w.shell_trace(space, Vector3(0, 700.0, 0), Vector3(0, 0, -1), float(WeaponsDB.WEAPONS["sniper"]["bullet_speed"]), 200.0)
		drops.append(700.0 - float((hit["position"] as Vector3).y) if not hit.is_empty() else -1.0)
	check("the shell drops: about 0.2 m at 40 m and 0.8 m at 80 m (real ballistics, nothing is scripted to miss)", absf(drops[0] - 0.196) < 0.06 and absf(drops[1] - 0.784) < 0.12 and drops[1] > drops[0] * 3.0, "%.2f / %.2f m" % [drops[0], drops[1]])
	wall.queue_free()
	# --- the lander lands (the lookout objective starts it): collision, spark, guards
	var orig_mk: Enemy = null          # the marksman the game spawned on the balcony (parked far away for now: he is killed when his objective is up)
	for e in Game.enemies.duplicate():
		if String(main.story_roles.get((e as Enemy).uid, "")) == "balcony_marksman":
			orig_mk = e
	for pk in Game.pickups.duplicate():
		pk.queue_free()
	Game.pickups.clear()
	check("the game's own marksman exists (group 201): the objective waits for him", orig_mk != null and orig_mk.group == 201 and main._objective_index("balcony_marksman") >= 0)
	Mission.complete("go_cellar")
	await secs(1.2)
	check("GO TO THE CELLAR hands over to CLIMB TO THE ROOF: marker over the foot of the escape, a checkpoint", String(ms.active()["id"]) == "climb_roof" and main.checkpoint.objective == ms.index and absf(main.world._marker.position.x - (lk["foot"] as Vector3).x) < 1.0)
	tp(Vector3(roof.x, roof.y + 0.1, roof.z), PI * 0.5)
	await secs(1.6)
	check("standing on the roof completes CLIMB TO THE ROOF; LOOK OUT starts the descent and the marker moves to the park", String(ms.active()["id"]) == "lookout" and lander.visible and not lander.landed and absf(main.world._marker.position.x - foot.x) < 1.0, str(ms.active().get("id")))
	check("the craft is high above the park while it comes down", lander.hull.position.y > 20.0 and Game.enemies.filter(func(e): return e.group == ParkFight.GUARD_GROUP).is_empty())
	check("the other craft in the far squares show from the lookout on", main.world.far_landers_node != null and main.world.far_landers_node.visible)
	var objective_before := ms.index
	await secs(5.0)
	check("the lookout does not end before the craft has landed (the player can look around freely)", ms.index == objective_before and not lander.landed)
	await secs(5.0)
	check("the craft touches down after about nine seconds: solid, with the loading threshold active", lander.landed and lander.hull.position.y == 0.0 and not (lander.body.get_child(0) as CollisionShape3D).disabled and lander.threshold.monitoring)
	var guards := park_fight_guards()
	for g in guards:
		if not (g.state == Enemy.State.WANDER and g.post and g.group == ParkFight.GUARD_GROUP and g.global_position.distance_to(foot) < 11.0 and g.is_on_floor()):
			print("   guard ", g.state, " post ", g.post, " group ", g.group, " d ", g.global_position.distance_to(foot), " floor ", g.is_on_floor(), " pos ", g.global_position)
	check("ten guards stand at the foot of the ramp (a new group), calm, at their posts, round the ramp", guards.size() == 10 and guards.all(func(g): return g.state == Enemy.State.WANDER and g.post and g.group == ParkFight.GUARD_GROUP and g.global_position.distance_to(foot) < 11.0 and g.is_on_floor()), str(guards.size()))
	var kinds: Dictionary = {}
	for g in guards:
		kinds[g.kind] = int(kinds.get(g.kind, 0)) + 1
	check("...eight soldiers and two riflemen", kinds.get("soldier", 0) == 8 and kinds.get("rifleman", 0) == 2, str(kinds))
	check("a ray from above the hull hits the craft's collider (bullets can spark)", _hull_hit(lander) != null)
	await secs(3.0)
	check("the lookout ends after the player has watched for a while: KILL THE MARKSMAN is next", String(ms.active()["id"]) == "balcony_marksman" and main.checkpoint.objective == ms.index, str(ms.active().get("id")))
	check("the guards are in that checkpoint", main.checkpoint.enemies.filter(func(d): return int(d["group"]) == ParkFight.GUARD_GROUP).size() == 10)
	# --- the exhausted soldiers: slow to react, knifed even from the front for 2 s
	await park_all()
	var open := Vector3(0.0, 0.0, 30.0)               # an open stretch of the central avenue
	for g in guards:
		g.stun = 999.0
	tp(Vector3(open.x, 0.1, open.z + 4.0), 0.0)
	var ex1: Enemy = spawn("soldier", Vector3(open.x, 0.0, open.z), false)
	main._assign_role(ex1, "exhausted")
	ex1.stun = 0.0
	await secs(0.6)
	check("a sitting soldier is calm, gasping (breath at full stress) and squashed: sitting hit boxes", ex1.state == Enemy.State.EXHAUSTED and ex1.stamina <= Enemy.EXHAUSTED_STAMINA + 0.1 and ex1.hit_root.scale.y < 0.7, "%.2f" % ex1.hit_root.scale.y)
	var react := Enemy.EXHAUSTED_REACT
	tp(Vector3(open.x, 0.1, open.z + 1.6), 0.0)              # in front of him, face to face (he looks north, towards -z... the player is at +z: behind)
	ex1.sit_down(PI)                                          # now he faces the player
	ex1.exh_notice = -1.0
	await frames(2)
	w.switch_to("knife")
	await secs(0.8)
	aim_at(ex1.takedown_point())
	await frames(2)
	check("the knife takedown works from the FRONT on an exhausted soldier", ex1.state == Enemy.State.EXHAUSTED and w.find_takedown() == ex1)
	await secs(react * 0.35)
	check("he has noticed the player but is slow: still sitting after 0.7 s and still knifeable", ex1.exh_notice > 0.5 and ex1.state == Enemy.State.EXHAUSTED and w.find_takedown() == ex1, "%.2f" % ex1.exh_notice)
	var gun_events := [0]
	var on_shot := func(_p: Vector3, _l: float) -> void: gun_events[0] += 1
	Game.gunshot.connect(on_shot)
	var takedowns0 := Game.takedowns
	w.cooldown = 0.0
	w._do_takedown(ex1)
	await frames(3)
	Game.gunshot.disconnect(on_shot)
	check("...the takedown kills him at once and silently (no gunshot, counted)", ex1.state == Enemy.State.DEAD and gun_events[0] == 0 and Game.takedowns == takedowns0 + 1)
	var ex2: Enemy = spawn("soldier", Vector3(open.x + 6.0, 0.0, open.z), false)
	main._assign_role(ex2, "exhausted")
	ex2.sit_down(PI)
	ex2.stun = 0.0
	tp(Vector3(open.x + 6.0, 0.1, open.z + 1.6), 0.0)
	await secs(react + 1.0)
	check("after two seconds he gets up and hunts: no more takedown, still short of breath (cannot run for long)", ex2.state != Enemy.State.EXHAUSTED and ex2.state != Enemy.State.DEAD and not ex2.post and ex2.stamina < 40.0 and not ex2.can_be_taken_down(player.global_position), "state %d stamina %.0f" % [ex2.state, ex2.stamina])
	var ex3: Enemy = spawn("soldier", Vector3(open.x + 12.0, 0.0, open.z), false)
	var ex4: Enemy = spawn("soldier", Vector3(open.x + 17.0, 0.0, open.z), false)
	for ee in [ex3, ex4]:
		main._assign_role(ee, "exhausted")
		ee.sit_down(PI if ee == ex3 else 0.0)          # his friend looks away and sits too far off to notice the player himself
		ee.stun = 0.0
	tp(Vector3(open.x + 12.0, 0.1, open.z + 1.8), 0.0)
	await secs(react + 0.4)
	check("a shout of alarm is passed to his friend: when one gets up, the other follows within a second", ex3.state != Enemy.State.EXHAUSTED and ex4.exh_notice >= 0.9, "ex4 %.2f" % ex4.exh_notice)
	for ee in [ex2, ex3, ex4]:
		if ee.state != Enemy.State.DEAD:
			kill(ee)
	# --- the balcony marksman: silent knife takedown, a close shot, or he snipes
	await park_all()
	var mk: Enemy = main._spawn_enemy_at(CityStory.MARKSMAN_AT, "marksman", "sniper")
	all.append(mk)
	main._assign_role(mk, "balcony_marksman")
	await secs(0.5)
	check("the balcony marksman can stand there (on the ledge, not falling) with the LR-9 in his hands", mk.is_on_floor() and mk.global_position.y > 3.3 and mk.weapon_id == "sniper" and mk.state == Enemy.State.WANDER)
	var path_up := City.path(City.BALCONY_STAIR_FOOT, mk.global_position)
	check("the balcony is reached by the stair from the street (path), the stair's top is at the west end behind his back", path_up.size() > 3 and absf(path_up[path_up.size() - 1].y - City.BALCONY_Y) < 0.7 and City.BALCONY_RECT.position.x < mk.global_position.x - 3.0)
	# up the real stair: walk from its foot
	tp(Vector3(City.BALCONY_STAIR_FOOT.x - 0.5, 0.1, City.BALCONY_STAIR_FOOT.z), -PI * 0.5)
	Input.action_press("crouch")
	await secs(0.5)
	Input.action_press("move_forward")
	var top_y := 0.0
	for i in 900:
		await get_tree().physics_frame
		top_y = maxf(top_y, player.global_position.y)
		if player.global_position.x > 74.0:
			break
	Input.action_release("move_forward")
	check("the player can walk up the outside stair onto the balcony (crouched, quiet)", top_y > 3.0 and player.global_position.x > 72.5, "y=%.2f x=%.1f" % [top_y, player.global_position.x])
	check("a crouched player on the stair is not noticed by the marksman (he looks at the park, the stair is behind him)", mk.state == Enemy.State.WANDER and not mk.noticed_self and not mk.charging, "state %d" % mk.state)
	var gun_events2 := [0]
	var on_shot2 := func(_p: Vector3, _l: float) -> void: gun_events2[0] += 1
	Game.gunshot.connect(on_shot2)
	tp(Vector3(mk.global_position.x - 1.5, City.BALCONY_Y + 0.1, mk.global_position.z + 1.1), -PI * 0.5)
	player.crouch_k = 1.0
	await frames(3)
	aim_at(mk.takedown_point())
	await frames(3)
	check("his back is turned: the takedown is on offer from the side of the stair", mk.can_be_taken_down(player.global_position) and w.find_takedown() == mk)
	w.cooldown = 0.0
	w._do_takedown(mk)
	await secs(0.5)
	Game.gunshot.disconnect(on_shot2)
	Input.action_release("crouch")
	check("the silent knife takedown kills the marksman (no shot heard) and his LR-9 drops with 5 rounds", mk.state == Enemy.State.DEAD and gun_events2[0] == 0 and Game.pickups.any(func(pk): return pk.weapon_id == "sniper" and pk.ammo == 5 and not pk.is_ammo), str(Game.pickups.size()))
	# a close shot works too (55 HP: two pistol hits), and if he spots you he snipes
	var mk2: Enemy = main._spawn_enemy_at(CityStory.MARKSMAN_AT + Vector3(2.0, 0, 0), "marksman", "sniper")
	all.append(mk2)
	main._assign_role(mk2, "balcony_marksman")
	await frames(10)
	check("two pistol hits kill the marksman (55 HP): the close shot works", mk2.max_health <= 56.0 and WeaponsDB.WEAPONS["pistol"]["damage"] * 2.0 >= mk2.max_health)
	tp(Vector3(80.0, City.BALCONY_Y + 0.1, -45.0), PI)           # far side: standing in the park, in front of him
	player.crouch_k = 0.0
	player.global_position = Vector3(80.0, 0.1, -50.0)
	mk2.facing = 0.0
	mk2.rig.rotation.y = 0.0
	mk2.stun = 0.0
	await secs(4.0)
	check("if he spots the player he snipes: hunting, laser charging or a shot fired", mk2.state in [Enemy.State.ALERT, Enemy.State.CHASE, Enemy.State.SHOOT] or mk2.charging or player.health < Game.MAX_HEALTH, "state %d hp %.0f" % [mk2.state, player.health])
	kill(mk2)
	player.health = Game.MAX_HEALTH
	Game.dead = false
	Game.pickups.clear()
	# --- the rifle: picked up from the marksman, in the rifle slot
	await park_all()
	tp(Vector3(77.0, City.BALCONY_Y + 0.1, -30.0), PI)
	var pk_sniper := Pickup.spawn_weapon(main, Vector3(77.0, City.BALCONY_Y + 0.1, -30.0), "sniper", 5)
	await frames(10)
	pk_sniper.global_position = Vector3(77.0, City.BALCONY_Y + 0.1, -30.0)
	check("KILL THE MARKSMAN stays up while one of group 201 lives", String(ms.active()["id"]) == "balcony_marksman", str(ms.active().get("id")))
	kill(orig_mk)
	await secs(0.9)
	check("TAKE HIS RIFLE is active after the marksman is dead", String(ms.active()["id"]) == "take_rifle", str(ms.active().get("id")))
	w.pick_up(pk_sniper)
	await secs(0.5)
	var inst: Dictionary = {}
	for it in w.loadout["rifle"]:
		if it["id"] == "sniper":
			inst = it
	check("the LR-9 goes into the rifle slot as a rifle-class gun: 5 rounds loaded, a full set of spare magazines", not inst.is_empty() and int(inst["ammo"]) == 5 and (inst["spare"] as Array).size() == 3, str(inst))
	check("picking it up starts THIN OUT THE GUARDS: a checkpoint at the start of the balcony fight with the rifle and ten guards", String(ms.active()["id"]) == "park_fight" and main.checkpoint.objective == ms.index and main.checkpoint.enemies.filter(func(d): return int(d["group"]) == ParkFight.GUARD_GROUP).size() == 10 and main.checkpoint.loadout["rifle"].any(func(i): return i["id"] == "sniper"))
	var cp_fight: Checkpoint = main.checkpoint
	# --- steadying the scope: Shift (or Ctrl) holds the breath for 3 s, then the view jumps
	w.switch_to("sniper")
	await secs(1.0)
	tp(Vector3(76.0, City.BALCONY_Y + 0.1, -30.5), 0.0)
	await secs(0.2)
	Input.action_press("aim")
	await secs(1.2)
	check("the scope fills the screen and the breath bar is full", w.current == "sniper" and w.is_scoped() and w.breath > 0.99)
	var free_sway := 0.0
	for i in 240:
		await get_tree().physics_frame
		free_sway = maxf(free_sway, w.sway_view.length())
	Input.action_press("sprint")
	await secs(0.3)
	var steady_sway := 0.0
	for i in 120:
		await get_tree().physics_frame
		steady_sway = maxf(steady_sway, w.sway_view.length())
	check("holding the breath steadies the scope (a tenth of the drift) and uses it up", w.breath_held and free_sway > 0.002 and steady_sway < free_sway * 0.4 and w.breath < 0.85, "free %.4f steady %.4f breath %.2f" % [free_sway, steady_sway, w.breath])
	var saw_gasp := false
	var gasp_sway := 0.0
	var gasp_frames := 0
	for i in 600:
		await get_tree().physics_frame
		if w.gasp_t > 0.0:
			saw_gasp = true
			gasp_sway = maxf(gasp_sway, w.sway_view.length())
			gasp_frames += 1
			if gasp_frames > 70:
				break
	check("after about three seconds the breath is gone and the view swings wide for a moment (gasp)", saw_gasp and gasp_sway > free_sway * 1.3, "free %.4f gasp %.4f" % [free_sway, gasp_sway])
	Input.action_release("sprint")
	Input.action_release("aim")
	await secs(1.0)
	# --- the first shot: any shot heard puts the guards into the confused circle; the shell sparks on the hull
	for g in guards:
		g.stun = 0.0
	tp(Vector3(75.0, City.BALCONY_Y + 0.1, -30.4), 0.0)
	player.crouch_k = 1.0
	await secs(0.5)
	w.switch_to("sniper")
	await secs(0.8)
	w.state["sniper"]["ammo"] = 5
	w.cooldown = 0.0
	var spark_before := lander._spark_t
	aim_at(lander.hull.global_transform * Vector3(0, 3.5, -3.0))
	var pf: ParkFight = main.park_fight
	pf.flash_seen = false
	var chance := ParkFight.FLASH_CHANCE
	w._fire_shot()
	await frames(2)
	check("a shell that hits the hull makes a bright spark (the light flashes)", lander._spark_t > 0.0 and lander._spark_light.visible, "%.2f" % lander._spark_t)
	check("the first shot puts the guards in a circle round the ramp: HOLD, confused, one persistent squad", pf.phase == ParkFight.Phase.SEARCH or pf.phase == ParkFight.Phase.CHARGE, str(pf.phase))
	var holding := park_fight_guards().filter(func(g): return g.state == Enemy.State.HOLD).size()
	check("...with most of them holding, sweeping their sectors and unable to place the shot", holding >= 8 and park_fight_guards().filter(func(g): return g.confused).size() >= 8 or pf.phase == ParkFight.Phase.CHARGE, "%d holding" % holding)
	if pf.phase == ParkFight.Phase.SEARCH:
		var sq_before: Dictionary = pf.squad
		kill(guards[3])
		await secs(0.6)
		check("a guard shot dead does not break the circle (the squad persists with nine)", pf.phase == ParkFight.Phase.SEARCH and sq_before in main.squads.squads and (sq_before["members"] as Array).size() == 9)
		check("the objective counts the dead: one of three so far", pf.killed() == 1 and String(ms.active()["id"]) == "park_fight")
		await secs(3.0)
		check("they hold the circle: nobody charges while the flash has not given the balcony away", pf.phase == ParkFight.Phase.SEARCH and park_fight_guards().filter(func(g): return g.state == Enemy.State.CHASE).is_empty())
		pf.flash_seen = true
		pf._charge_in = 0.05
		await secs(0.4)
		check("when the muzzle flash is seen the circle breaks: they scatter to cover and then charge", pf.phase == ParkFight.Phase.CHARGE and not (sq_before in main.squads.squads))
		var max_hunters := 0
		var trace := ""
		for s in 9:
			await secs(1.0)
			var hist := {}
			var hn := 0
			for g in park_fight_guards():
				hist[g.state] = int(hist.get(g.state, 0)) + 1
				if g.state in [Enemy.State.CHASE, Enemy.State.SHOOT, Enemy.State.ATTACK, Enemy.State.ALERT]:
					hn += 1
			max_hunters = maxi(max_hunters, hn)
			trace += str(hist) + " "
		check("the remaining guards charge the balcony (scatter to cover, then chase to where he is)", max_hunters >= 6, "max %d hunting; %s" % [max_hunters, trace])
	# --- the 20 s timer also breaks it (a second fight from the checkpoint)
	main._restore_checkpoint()
	await secs(1.2)
	check("the checkpoint at the start of the balcony fight brings back the ten guards, the rifle, the landed craft and a calm controller", park_fight_guards().size() == 10 and String(ms.active()["id"]) == "park_fight" and lander.landed and pf.phase == ParkFight.Phase.CALM and w.loadout["rifle"].any(func(i): return i["id"] == "sniper") and park_fight_guards().all(func(g): return g.state == Enemy.State.WANDER and g.post), "%d guards" % park_fight_guards().size())
	for g in park_fight_guards():
		g.stun = 0.0
	tp(Vector3(75.0, City.BALCONY_Y + 0.1, -30.4), 0.0)
	await secs(0.6)
	w.switch_to("sniper")
	await secs(0.8)
	w.state["sniper"]["ammo"] = 5
	w.cooldown = 0.0
	aim_at(lander.hull.global_transform * Vector3(0, 3.5, -3.0))
	pf.flash_seen = false
	w._fire_shot()
	await frames(2)
	if pf.phase == ParkFight.Phase.SEARCH and pf.squad.size() > 0:
		pf.squad["t"] = Squads.HOLD_TIME - 0.5
		pf.flash_seen = false
		await secs(1.6)
		check("after 20 seconds the circle breaks by itself and they charge", pf.phase == ParkFight.Phase.CHARGE and park_fight_guards().filter(func(g): return g.state != Enemy.State.HOLD and g.state != Enemy.State.WANDER).size() >= 5, str(pf.phase))
	# --- abandoning the rifle: heavy, dropped when they are close and the pistol comes out
	var hunter_near: Enemy = null
	for g in park_fight_guards():
		hunter_near = g
	hunter_near.global_position = player.global_position + Vector3(-3.0, 0.2, 0.0)
	hunter_near.state = Enemy.State.CHASE
	hunter_near.stun = 999.0
	w.switch_to("sniper")
	await secs(0.8)
	var rifles_before: int = w.loadout["rifle"].size()
	check("a hunter closer than 16 m: the long rifle is too heavy to swap away quietly", w.hunter_near(Weapons.HEAVY_DROP_RANGE) and w.current == "sniper")
	var pks := Game.pickups.size()
	w.switch_to("pistol")
	await secs(0.8)
	check("switching to the pistol drops the long rifle at the player's feet (a pick-up with its rounds), it leaves the loadout", w.current == "pistol" and w.loadout["rifle"].size() == rifles_before - 1 and Game.pickups.size() == pks + 1 and Game.pickups.any(func(pk): return pk.weapon_id == "sniper"), "%d rifles" % w.loadout["rifle"].size())
	# far from any hunter the same switch keeps the rifle
	hunter_near.global_position = Vector3(200.0, 0.1, 0.0)
	await frames(5)
	var pk2: Pickup = null
	for pk in Game.pickups:
		if pk.weapon_id == "sniper":
			pk2 = pk
	pk2.global_position = player.global_position
	await frames(5)
	w.pick_up(pk2)
	await secs(0.8)
	w.switch_to("sniper")
	await secs(0.8)
	w.switch_to("pistol")
	await secs(0.8)
	check("with nobody hunting him close by the long rifle stays in the loadout", w.loadout["rifle"].any(func(i): return i["id"] == "sniper") and w.current == "pistol")
	# --- the objective chain goes on: three dead guards end THIN OUT, then the lanes
	for g in park_fight_guards().duplicate():
		if park_fight_guards().size() > 6:
			kill(g)
	await secs(0.6)
	check("three dead guards complete THIN OUT THE GUARDS: ESCAPE INTO THE LANES is next with a marker in a lane behind the park", String(ms.active()["id"]) == "escape_lanes" and not CityStory.escape_lane().is_empty() and (CityStory.escape_lane()["pos"] as Vector3).z > -25.0, str(ms.active().get("id")))
	var lane: Dictionary = CityStory.escape_lane()
	var lane_r: Rect2 = lane["rect"]
	check("the lane is a real narrow lane (6.5 m at most), reachable by the pavement from the balcony stair", minf(lane_r.size.x, lane_r.size.y) <= 6.5 and City.path(City.BALCONY_STAIR_FOOT, lane["pos"]).size() >= 2)
	await chase_start_checks()
	await chase_tests()          # the lane mouth, the chase, the courtyard, the wound, the ramp (it also puts the win flags back)
	Game.paused = false
	# put the world back where the next sections expect it (GO TO THE CELLAR with its checkpoint, no craft)
	ms.index = main._objective_index("go_cellar")
	main.checkpoint = cp_start
	main.world.lander.hide_ship()
	main.park_fight.reset()
	main.world.set_marker_target(ms.marker_pos())
	Input.action_release("aim")
	Input.action_release("crouch")
	Input.action_release("sprint")
	player.health = Game.MAX_HEALTH
	Game.dead = false
	for g in park_fight_guards().duplicate():
		Game.enemies.erase(g)
		g.queue_free()
	await frames(3)


func park_fight_guards() -> Array:
	return main.park_fight.guards()


func _hull_hit(lander: ShipModels.Lander) -> Object:
	var from := lander.global_position + Vector3(0, 30.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -40.0, 0), Game.L_WORLD)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return null
	var col: Object = hit["collider"]
	return col if col.has_meta("hull") else null


# ================================================================== "The Lander", part two: the chase, the courtyard, the arm wound

func _freeze_chase(on: bool) -> void:
	for e in main.chase.chasers() + main.chase.court():
		(e as Enemy).stun = 999.0 if on else 0.0


## Right after ESCAPE INTO THE LANES started (the checkpoint of that objective is the one that was just taken).
func chase_start_checks() -> void:
	var ch: ChaseFight = main.chase
	var list := ch.chasers()
	check("ESCAPE INTO THE LANES starts the chase: six soldiers hunt him (four chasers, two stragglers), the ramp's circle is gone", list.size() == 6 and ch.stragglers().size() == 2 and ch.phase == ChaseFight.Phase.CHASE and list.all(func(e): return e.state == Enemy.State.CHASE and e.group == -1) and park_fight_guards().is_empty(), "%d chasers, %d stragglers" % [list.size(), ch.stragglers().size()])
	var tired := ch.stragglers().all(func(e): return e.straggler and e.kind == "soldier" and absf(e.fatigue - ChaseFight.STRAGGLER_FATIGUE) < 0.01 and e.stamina <= e.max_stamina * 0.51 and e.grenade_drop == ChaseFight.STRAGGLER_GRENADES)
	check("the two stragglers are tired soldiers: stamina drains 2.4 times faster, they start half winded, and each is marked to drop 2 grenades", tired)
	var stash := Game.pickups.filter(func(pk): return is_instance_valid(pk) and (pk as Pickup).is_grenade and (pk as Pickup).keep)
	var total_g: int = stash.size() + ch.stragglers().size() * ChaseFight.STRAGGLER_GRENADES
	check("grenades are guaranteed, not random: 2 on the low roof + 2 from each straggler = 6 in the area (at least 4)", stash.size() == 2 and total_g >= 4 and total_g <= 6, "%d in all" % total_g)
	check("the stash lies on the low roof over the courtyard's north wing", stash.all(func(pk): return absf((pk as Pickup).global_position.y - City.COURT_ROOF_Y) < 0.5 and City.COURT_BLOCK.has_point(Vector2((pk as Pickup).global_position.x, (pk as Pickup).global_position.z))))
	check("a checkpoint was taken with the chase (the same six are in it)", main.checkpoint.objective == main._objective_index("escape_lanes") and main.checkpoint.enemies.size() >= 6)


func chase_tests() -> void:
	print("--- The Lander, part two: the chase through the lanes, the courtyard, the arm wound ---")
	var ch: ChaseFight = main.chase
	var w := player.weapons
	var ms: Mission = Game.mission
	var rifles_saved: Array = Checkpoint.copy_loadout(w.loadout)["rifle"]
	_freeze_chase(true)
	# --- the neighbourhood itself
	var pipes := City.ladders.filter(func(l): return l["kind"] == "pipe")
	check("the alleys near the park have climbable drainpipes (ladders of kind pipe) up to low roofs", pipes.size() >= 3 and pipes.all(func(l): return float(l["top"]) >= 4.5 and float(l["top"]) <= 6.0 and (l["pos"] as Vector3).distance_to(City.PARK_POS) < 130.0), "%d pipes" % pipes.size())
	var foot := CityStory.pipe_foot()
	check("the first pipe stands in the west lane beside the north wing; its foot is free ground", City.is_free(foot) and foot.x > 70.0 and foot.x < 73.0 and City.COURT_BLOCK.has_point(Vector2(foot.x, foot.z)), str(foot))
	var gates_ok := true
	for g in CityPlaces.court_gates:
		gates_ok = gates_ok and City.is_free(g) and City.path(City.COURT_POS, g).size() >= 1
	var lane: Dictionary = CityStory.escape_lane()
	var to_court := City.path(lane["pos"], City.COURT_POS)
	check("the courtyard (12 x 12 m) has two 3 m gates and a way in from the lane mouth", gates_ok and to_court.size() >= 2 and plen(lane["pos"], to_court) < 60.0, "%.1f m" % plen(lane["pos"], to_court))
	check("no crouch passage blocks the lanes of the neighbourhood", City.crouch_passages.all(func(c): return not City.COURT_BLOCK.grow(1.0).has_point(Vector2(c["pos"].x, c["pos"].z))))
	check("no battle site within 75 m of the courtyard", City.sites.all(func(s): return (s["center"] as Vector3).distance_to(City.COURT_POS) >= 75.0))
	# --- the run: reaching the lane mouth starts the grenade hunt
	check("before the lane the objective is ESCAPE INTO THE LANES", String(ms.active()["id"]) == "escape_lanes", str(ms.active().get("id")))
	tp(Vector3(lane["pos"].x, 0.1, lane["pos"].z), 0.0)
	await secs(0.6)
	check("reaching the mouth of the west lane completes it: TAKE THE STRAGGLERS' GRENADES is next (a checkpoint)", String(ms.active()["id"]) == "take_grenades" and main.checkpoint.objective == ms.index, str(ms.active().get("id")))
	# --- narrow lanes: shorter sight, slower reaction
	check("a 3 m alley is narrow, the cross avenue and the courtyard are not", ch.is_narrow(Vector3(71.5, 0.0, 30.0)) and ch.is_narrow(Vector3(75.5, 0.0, 36.0)) and not ch.is_narrow(Vector3(60.0, 0.0, 0.0)) and not ch.is_narrow(City.COURT_POS))
	var chasers: Array = ch.members(["chaser"])
	var c0: Enemy = chasers[0]
	for e in chasers:
		place_for_chase(e)
	c0.global_position = Vector3(71.5, 0.2, 42.0)
	c0.velocity = Vector3.ZERO
	c0.state = Enemy.State.CHASE
	c0.seen_now = false
	c0._seen_acc = 0.0
	tp(Vector3(71.5, 0.1, 27.0), PI)
	await secs(0.5)            # (frozen: the controller's tick sets his sight and delay for the alley first)
	c0.stun = 0.0
	c0._seen_acc = 0.0
	var t_seen := -1.0
	var scale_in := 1.0
	for i in 200:
		await frames(1)
		if i == 60:
			scale_in = c0.sight_scale
		if c0.seen_now and t_seen < 0.0:
			t_seen = float(i) / 120.0
			break
	check("in a 3 m alley a chaser sees only 55% as far and needs about 0.7 s to take in what he sees", absf(scale_in - ChaseFight.NARROW_SIGHT) < 0.01 and t_seen >= 0.55 and c0.seen_delay >= ChaseFight.NARROW_DELAY - 0.01, "scale %.2f seen after %.2f s" % [scale_in, t_seen])
	c0.stun = 999.0
	c0.global_position = Vector3(0.0, 0.2, 40.0)
	await frames(60)
	check("in the open street the same soldier reacts quickly again (sight x1, delay 0.15 s)", absf(c0.sight_scale - 1.0) < 0.01 and absf(c0.seen_delay - ChaseFight.OPEN_DELAY) < 0.01, "%.2f / %.2f" % [c0.sight_scale, c0.seen_delay])
	# --- bunching at a corner of the path
	var a: Enemy = chasers[1]
	var b: Enemy = chasers[2]
	a.global_position = Vector3(71.5, 0.2, 30.0)
	b.global_position = Vector3(71.5, 0.2, 48.0)
	a.state = Enemy.State.CHASE
	b.state = Enemy.State.CHASE
	a.seen_now = false
	a.last_known = Vector3(71.5, 0.0, 16.0)
	a.nav_path = PackedVector3Array([Vector3(71.5, 0.0, 28.5), Vector3(76.5, 0.0, 28.5)])
	a.nav_i = 0
	var list := ch.chasers()
	var corner_yes: bool = ch._at_corner(a)
	a.nav_path = PackedVector3Array([Vector3(71.5, 0.0, 28.5), Vector3(71.5, 0.0, 10.0)])
	var corner_no: bool = ch._at_corner(a)
	check("a bend in the path within 3.5 m is a corner, a straight run is not", corner_yes and not corner_no)
	a.nav_path = PackedVector3Array([Vector3(71.5, 0.0, 28.5), Vector3(76.5, 0.0, 28.5)])
	check("a man well behind him (7 m or more, farther from the goal) is what he waits for", ch._man_behind(a, list))
	ch._bunch.erase(a.uid)
	ch._bunch_step(a, true, list, 0.25)
	var waited := a.pace == 0.0
	for k in 7:
		ch._bunch_step(a, true, list, 0.25)
	check("at a corner in an alley a chaser who lost sight of the player waits for the others (pace 0 for 1.4 s), then goes on and does not wait again at once", waited and a.pace == 1.0 and float(ch._bunch[a.uid]["cd"]) > 2.0, "waited %s pace %.1f" % [str(waited), a.pace])
	a.seen_now = true
	ch._bunch_step(a, true, list, 0.25)
	check("a chaser who sees the player never waits", a.pace == 1.0)
	# --- they split up when they lose him
	for e in [a, b, chasers[3]]:
		(e as Enemy).state = Enemy.State.CHASE
		(e as Enemy).unseen_t = 3.0
		(e as Enemy).last_known = Vector3(71.5, 0.0, 16.0)
	ch._split_cd.clear()
	ch._split(ch.chasers())
	var tg: Array = [a.last_known, b.last_known, chasers[3].last_known]
	var spread := minf(minf(tg[0].distance_to(tg[1]), tg[0].distance_to(tg[2])), tg[1].distance_to(tg[2]))
	check("when they lose him the chasers split up: each gets its own search point, at least 5 m from the others, and the hunt clock restarts", spread > 5.0 and a.unseen_t == 0.0 and b.unseen_t == 0.0, "min spacing %.1f m" % spread)
	# --- the stragglers lag: they are winded long before the others
	var st1: Enemy = ch.stragglers()[0]
	st1.winded_t = 0.0
	st1.recovering = false
	a.winded_t = 0.0
	a.stamina = a.max_stamina
	a.recovering = false
	for i in 360:
		st1._stamina_step(1.0 / 120.0, Vector3(0.0, 0.0, -st1.run_speed))
		a._stamina_step(1.0 / 120.0, Vector3(0.0, 0.0, -a.run_speed))
	check("running for 3 seconds winds a straggler (stamina gone) but not a normal chaser", st1.winded_t > 0.0 and a.winded_t <= 0.0 and a.stamina > 30.0, "straggler winded %.1f / chaser stamina %.0f" % [st1.winded_t, a.stamina])
	# --- a gasping straggler can be knifed from behind (the knife works), a normal chaser cannot
	for e in [a, b, chasers[3]]:
		(e as Enemy).winded_t = 0.0
	st1.global_position = Vector3(71.5, 0.2, 34.0)
	st1.facing = PI            # facing south, away from the player at the north
	st1.rig.rotation.y = st1.facing
	st1.winded_t = 6.0
	st1.state = Enemy.State.CHASE
	st1.stun = 999.0
	a.winded_t = 6.0
	a.global_position = Vector3(71.5, 0.2, 50.0)
	tp(Vector3(71.5, 0.1, 32.9), PI)
	w.switch_to("knife")
	await secs(0.8)
	await frames(3)
	var from_behind := st1.can_be_taken_down(player.global_position)
	var from_front := st1.can_be_taken_down(Vector3(71.5, 0.0, 36.0))
	var chaser_behind := a.can_be_taken_down(player.global_position + Vector3(0, 0, 10.0))
	check("a winded straggler is killed silently from behind with the knife (offered), not from the front; a winded ordinary chaser is not offered", from_behind and not from_front and not chaser_behind and w.find_takedown() == st1, "behind %s front %s other %s" % [str(from_behind), str(from_front), str(chaser_behind)])
	var keep_before := Game.pickups.filter(func(pk): return is_instance_valid(pk) and (pk as Pickup).is_grenade and (pk as Pickup).keep).size()
	var carried_before := Game.grenades
	var kills_td := Game.takedowns
	w._do_takedown(st1)
	await frames(10)
	var keep_now := Game.pickups.filter(func(pk): return is_instance_valid(pk) and (pk as Pickup).is_grenade and (pk as Pickup).keep and not (pk as Pickup).is_queued_for_deletion()).size()
	var picked := Game.grenades - carried_before          # (he stands next to the body: some are picked up at once)
	check("the dead straggler drops exactly 2 grenades that stay until taken", st1.state == Enemy.State.DEAD and Game.takedowns == kills_td + 1 and (keep_now - keep_before) + picked == 2, "%d on the ground (+%d taken)" % [keep_now - keep_before, picked])
	var st2: Enemy = ch.stragglers()[0]
	st2.stun = 0.0
	st2.global_position = Vector3(200.0, 0.2, 10.0)
	kill(st2)
	await frames(10)
	var keep_pks := Game.pickups.filter(func(pk): return is_instance_valid(pk) and (pk as Pickup).is_grenade and (pk as Pickup).keep and not (pk as Pickup).is_queued_for_deletion())
	var total_six: int = keep_pks.size() + (Game.grenades - carried_before)
	check("shot instead of stabbed, the second straggler drops his 2 as well: 6 grenades in the area in all (2 on the roof, 4 from them)", total_six == 6 and ch.stragglers().is_empty(), "%d on the ground + %d in the pocket" % [keep_pks.size(), Game.grenades - carried_before])
	for pk in keep_pks:
		pk._t = 500.0
	await frames(10)
	check("the grenade pickups do not fade (story loot)", Game.pickups.filter(func(pk): return is_instance_valid(pk) and (pk as Pickup).keep and not (pk as Pickup).is_queued_for_deletion()).size() == keep_pks.size())
	# --- three grenades in the pocket: the courtyard objective, the four gather
	check("TAKE THE STRAGGLERS' GRENADES waits while there are fewer than 3 grenades", String(ms.active()["id"]) == "take_grenades")
	Game.grenades = ChaseFight.GRENADES_NEEDED
	await secs(0.6)
	check("with 3 grenades the objective moves on: CLEAR THE COURTYARD (a checkpoint)", String(ms.active()["id"]) == "clear_courtyard" and main.checkpoint.objective == ms.index, str(ms.active().get("id")))
	var cp_court: Checkpoint = main.checkpoint
	var court := ch.court()
	check("the four remaining chasers have gone to ground: role courtyard, no chasing, ONE back-to-back squad record", court.size() == ChaseFight.COURT_SOLDIERS and ch.phase == ChaseFight.Phase.COURT and main.squads.back_to_back_of(court[0]).size() > 0 and court.all(func(e): return e.state == Enemy.State.HOLD and e.group == -1), "%d members" % court.size())
	var sq: Dictionary = main.squads.back_to_back_of(court[0])
	check("the squad is the BACK_TO_BACK variant: persistent, no timeout, a circle of 4 spots round the courtyard centre, each facing outwards", sq.get("kind", "") == "b2b" and bool(sq.get("persist", false)) and (sq["members"] as Array).size() == 4 and court.all(func(e): return Vector2(e.hold_spot.x - City.COURT_POS.x, e.hold_spot.z - City.COURT_POS.z).length() < 2.6 and e.hold_walk_max >= 60.0))
	for e in court:
		(e as Enemy).stun = 0.0
		(e as Enemy).global_position = (e as Enemy).hold_spot + Vector3(0, 0.1, 0)
		(e as Enemy).velocity = Vector3.ZERO
	await secs(1.2)
	check("in their places they hold: sweeping a sector, never chasing", court.all(func(e): return e.state == Enemy.State.HOLD and e.hold_phase == 1))
	# --- the 20 s of an ordinary squad do not apply, and a grenade near them does not break it
	sq["t"] = Squads.HOLD_TIME + 30.0
	Game.grenade_landed.emit(City.COURT_POS + Vector3(2.0, 0.0, 0.0))
	await secs(0.7)
	check("this circle does not time out and a grenade landing next to it does not break it", main.squads.back_to_back_of(court[0]).size() > 0 and court.all(func(e): return e.state == Enemy.State.HOLD))
	# --- the drainpipe up to the low roof
	var pipe_l: Dictionary = pipes[0]
	for l in pipes:
		if (l["pos"] as Vector3).distance_to(foot) < 3.0:
			pipe_l = l
	var pbase: Vector3 = pipe_l["pos"]
	var pn: Vector2 = pipe_l["n"]
	player.health = Game.MAX_HEALTH
	tp(Vector3(pbase.x + pn.x * 0.9, 0.1, pbase.z + pn.y * 0.9), yaw_for(-pn))
	await secs(0.4)
	Input.action_press("move_forward")
	await secs(0.7)
	var on_pipe := player.climbing
	await secs(float(pipe_l["top"]) / Game.CLIMB_SPEED + 1.2)
	Input.action_release("move_forward")
	await secs(0.4)
	check("the drainpipe is climbable: forward attaches, a short climb, and the player stands on the low roof (4.6 m)", on_pipe and not player.climbing and absf(player.global_position.y - City.COURT_ROOF_Y) < 0.4 and player.is_on_floor(), "y %.2f" % player.global_position.y)
	# --- soldiers shoot at a head over the roof edge, but see nothing of a player back from the edge
	var shots := [0]
	var counter := func(_e) -> void: shots[0] += 1
	Game.enemy_fired.connect(counter)
	player.health = Game.MAX_HEALTH
	tp(Vector3(84.0, City.COURT_ROOF_Y + 0.1, 25.0), 0.0)
	await secs(3.5)
	var quiet: int = shots[0]
	check("back from the roof edge (5 m) the player is not seen: they do not fire", quiet == 0 and player.health >= Game.MAX_HEALTH - 0.1, "%d shots" % quiet)
	tp(Vector3(84.0, City.COURT_ROOF_Y + 0.1, 29.2), 0.0)
	await secs(2.0)
	check("a player at the roof edge is shot at (they fire when anyone shows on a roof edge) and the circle holds: nobody leaves it", shots[0] > quiet and court.all(func(e): return not is_instance_valid(e) or e.state == Enemy.State.DEAD or (e.state == Enemy.State.HOLD and Vector2(e.global_position.x - City.COURT_POS.x, e.global_position.z - City.COURT_POS.z).length() < 4.0)), "%d shots" % (shots[0] - quiet))
	Game.enemy_fired.disconnect(counter)
	Game.dead = false                       # (twenty bolts at a man standing in the open can kill him: this section goes on)
	player.health = Game.MAX_HEALTH
	tp(Vector3(84.0, City.COURT_ROOF_Y + 0.1, 26.5), 0.0)
	await secs(0.5)
	# --- the grenades: a throw from behind the edge hurts the circle (scenario A: the wound arrives with two left)
	var hp_circle := 0.0
	for e in ch.court():
		hp_circle += (e as Enemy).health
	Game.grenades = 2
	var err := _throw_into_court()
	await secs(3.3)
	var left := ch.court()
	var hp_after := 0.0
	for e in left:
		hp_after += (e as Enemy).health
	check("a grenade thrown into the courtyard from the roof (the arc preview finds the throw) lands inside it and hurts the circle", err < 4.0 and hp_after < hp_circle - 60.0, "lands %.1f m from the middle, circle health %.0f -> %.0f, %d left" % [err, hp_circle, hp_after, left.size()])
	Game.grenades = 1
	var _e := _throw_into_court()
	await secs(3.3)
	left = ch.court()
	var keep_two := 0
	for e in left:
		keep_two += 1
		if keep_two > 2:
			kill(e)
	await secs(0.6)
	left = ch.court()
	check("with two or fewer left they are wounded (28 HP at most) and the next shot at the player will hit his arm", left.size() <= 2 and ch.wound_ready and left.all(func(e): return e.health <= ChaseFight.WOUNDED_HEALTH + 0.1) and not Game.arm_injured, "%d left, ready %s" % [left.size(), str(ch.wound_ready)])
	Game.dead = false
	player.health = Game.MAX_HEALTH
	var hp_before := player.health
	tp(Vector3(84.0, City.COURT_ROOF_Y + 0.1, 29.2), 0.0)
	for i in 80:
		await secs(0.1)
		if Game.arm_injured:
			break
	check("when one of them shoots from the courtyard the right arm is hit: the wound happens", Game.arm_injured)
	await secs(0.5)
	check("the wound: FINISH THEM is the next objective, the player lives, the rifle is on the ground, the pistol is in hand", String(ms.active()["id"]) == "finish_them" and player.health > 0.0 and player.health < hp_before and w.loadout["rifle"].is_empty() and w.current == "pistol" and Game.pickups.any(func(pk): return is_instance_valid(pk) and not (pk as Pickup).is_grenade and (pk as Pickup).weapon_id == "sniper"), str(ms.active().get("id")))
	check("a checkpoint was taken with the wound (arm_injured is in the snapshot)", main.checkpoint.arm_injured and main.checkpoint.objective == ms.index and main.checkpoint.loadout["rifle"].is_empty())
	var cp_wound: Checkpoint = main.checkpoint
	# --- what the wound changes
	w._slot_key("rifle")
	check("the rifle slot is locked: \"CAN'T HOLD A RIFLE\"", w.current == "pistol" and w.notice == "CAN'T HOLD A RIFLE" and w.slot_locked("rifle"))
	w._slot_key("melee")
	check("the knife is locked too (no switching, no takedown)", w.current == "pistol" and w.notice == "CAN'T USE THE KNIFE" and w.find_takedown() == null)
	var rifle_pk: Pickup = null
	for pk in Game.pickups:
		if is_instance_valid(pk) and not (pk as Pickup).is_grenade and (pk as Pickup).weapon_id == "sniper":
			rifle_pk = pk
	if rifle_pk != null:
		rifle_pk.global_position = player.global_position
		await frames(3)
		w.pick_up(rifle_pk)
	check("the dropped rifle cannot be picked up again", w.loadout["rifle"].is_empty() and w.notice == "CAN'T HOLD A RIFLE")
	w.bloom = 0.0
	var spread_inj := w.current_spread()
	Game.arm_injured = false
	var spread_ok := w.current_spread()
	var reload_ok := w.reload_total()
	Game.arm_injured = true
	check("the left hand shoots wide: more spread and bloom, and the reload takes 1.7 times as long", spread_inj > spread_ok * 1.9 and absf(w.reload_total() - reload_ok * Weapons.WOUND_RELOAD_MULT) < 0.01 and Weapons.WOUND_BLOOM_MULT > 1.5, "%.2f vs %.2f" % [spread_inj, spread_ok])
	await secs(0.6)
	check("the pistol viewmodel is mirrored to the left side of the view, the limp arm hangs at the right, the HUD shows the arm icon", w.holder.position.x < -0.05 and w.wound_arm_node.visible and main.hud.arm_icon.visible, "x %.2f" % w.holder.position.x)
	check("the player moves a little slower (7% less)", absf(Weapons.WOUND_MOVE - 0.93) < 0.001)
	for i in 20:
		player.place_drip(player.global_position + Vector3(float(i) * 0.3, 0.0, 0.0))
	check("the arm drips: a ring of at most 12 blood spots on the floor, reused oldest first", player.drips.size() == Player.DRIP_MAX and player.drips.all(func(d): return d.visible))
	# --- the last grenade
	check("FINISH THEM guarantees a grenade (the player has at least one)", Game.grenades >= 1, "%d" % Game.grenades)
	Game.grenades = maxi(Game.grenades, 1)
	var _e2 := _throw_into_court()
	await frames(4)
	check("the grenade is thrown with the left hand (the throwing arm is on the left)", w.throw_arm.position.x < 0.0)
	await secs(3.4)
	check("whatever is left of the squad dies to it", ch.court().is_empty() and String(ms.active()["id"]) == "ramp", "%d left, objective %s" % [ch.court().size(), str(ms.active().get("id"))])
	var ramp_top := City.LANDER_POS + Basis(Vector3.UP, City.LANDER_YAW) * ShipModels.ramp_top_local()
	check("the last objective is the lander's open ramp: nobody guards it any more", Game.enemies.filter(func(e): return e.state != Enemy.State.DEAD and e.global_position.distance_to(ramp_top) < 25.0).is_empty() and absf((ms.marker_pos() as Vector3).x - ramp_top.x) < 1.0)
	tp(Vector3(ramp_top.x, ramp_top.y + 0.1, ramp_top.z), PI * 0.5)
	await secs(0.8)
	check("reaching the ramp ends the chapter's slice", Game.won and ms.finished)
	Game.won = false
	ms.finished = false
	get_tree().paused = false
	main.hud.win_panel.visible = false
	Game.paused = false
	# --- restart at any point restores the right arm
	main.checkpoint = cp_court
	main._restore_checkpoint()
	await secs(1.2)
	check("restarting from the courtyard checkpoint (before the wound) heals the arm: rifle back, squad re-formed", not Game.arm_injured and w.loadout["rifle"].any(func(i): return i["id"] == "sniper") and Game.grenades >= ChaseFight.GRENADES_NEEDED and String(ms.active()["id"]) == "clear_courtyard" and ch.court().size() == ChaseFight.COURT_SOLDIERS and main.squads.back_to_back_of(ch.court()[0]).size() > 0 and ch.phase == ChaseFight.Phase.COURT, "%d in the circle" % ch.court().size())
	await secs(0.6)
	check("...and the viewmodel is back on the right, no limp arm, no arm icon, no blood", w.holder.position.x > 0.05 and not w.wound_arm_node.visible and not main.hud.arm_icon.visible and player.drips.all(func(d): return not d.visible), "x %.2f" % w.holder.position.x)
	# scenario B: the last man falls before he shoots: his burst catches the arm anyway
	Game.grenades = 2
	for e in ch.court().duplicate():
		kill(e)
	await secs(1.0)
	check("if the whole circle dies before anybody shot, the dying burst still wounds the arm and FINISH THEM is done at once (the ramp is next)", Game.arm_injured and ch.court().is_empty() and String(ms.active()["id"]) == "ramp", str(ms.active().get("id")))
	# restoring the wound checkpoint keeps the arm hurt
	main.checkpoint = cp_wound
	main._restore_checkpoint()
	await secs(1.2)
	check("restarting from the FINISH THEM checkpoint keeps the arm wounded: no rifle, pistol in the left hand, the wounded squad back in the courtyard", Game.arm_injured and w.loadout["rifle"].is_empty() and w.current == "pistol" and String(ms.active()["id"]) == "finish_them" and ch.phase == ChaseFight.Phase.FINISH and ch.court().size() >= 1, "%d in the circle" % ch.court().size())
	await secs(0.6)
	check("...and the viewmodel is on the left again", w.holder.position.x < -0.05)
	# --- tidy up for the next sections
	Game.arm_injured = false
	player.clear_drips()
	for e in Game.enemies.duplicate():
		if String(main.story_roles.get((e as Enemy).uid, "")) in ["chaser", "straggler", "courtyard"]:
			Game.enemies.erase(e)
			e.queue_free()
	for pk in Game.pickups.duplicate():
		if is_instance_valid(pk):
			pk.queue_free()
	Game.pickups.clear()
	main.squads.reset()
	ch.phase = ChaseFight.Phase.IDLE
	w.loadout["rifle"] = rifles_saved
	w._equip("pistol", 0)
	w._show_only(w.current)
	Game.grenades = 0
	w.holder.position = Weapons.HIP_POS
	await frames(3)


func place_for_chase(e: Enemy) -> void:
	e.global_position = Vector3(200.0 + 2.0 * (all.size() % 10), 0.2, 20.0)
	e.velocity = Vector3.ZERO
	e.stun = 999.0
	all.append(e)


## Throw one grenade from where the player stands into the middle of the courtyard (the pitch is searched with the arc preview, as a player does).
func _throw_into_court() -> float:
	var w := player.weapons
	var space := player.get_world_3d().direct_space_state
	var to := City.COURT_POS - player.global_position
	player.yaw = atan2(-to.x, -to.z)
	player.rotation.y = player.yaw
	var best_deg := 0
	var best_err := 1.0e9
	for deg in range(-40, 41, 1):
		player.pitch = deg_to_rad(float(deg))
		player.head.rotation = Vector3(player.pitch, 0.0, 0.0)
		player.camera.force_update_transform()
		var r := Grenade.predict(space, w.throw_start(), w.throw_velocity())
		var rest: Vector3 = r["rest"]
		var err := Vector2(rest.x - City.COURT_POS.x, rest.z - City.COURT_POS.z).length()
		if err < best_err:
			best_err = err
			best_deg = deg
	player.pitch = deg_to_rad(float(best_deg))
	player.head.rotation = Vector3(player.pitch, 0.0, 0.0)
	player.camera.force_update_transform()
	w.throw_t = 0.0
	w.throw_grenade()
	return best_err
