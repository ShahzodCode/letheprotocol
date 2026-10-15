extends Node
## Headless checks. Run:  godot --headless --path . -- --selftest
## Prints PASS / FAIL per check and exits non-zero if anything failed.

var main
var player: Player
var fails := 0
var passes := 0
var all: Array = []


func check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", name, "  ", detail)
	else:
		fails += 1
		print("FAIL  ", name, "  ", detail)


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
	check("4 enemies spawned", Game.enemies.size() == 4, str(Game.enemies.size()))
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
		if e.state != Enemy.State.WANDER:
			wandering = false
	check("enemies are wandering, not hunting", wandering)
	await secs(4.0)
	var moved := 0
	for e in Game.enemies:
		if e.global_position.distance_to(e.home) > 0.3:
			moved += 1
	check("some enemies walk around", moved >= 1, "%d moved" % moved)

	print("--- terrain / player physics ---")
	var ray := PhysicsRayQueryParameters3D.create(Vector3(40, 60, 40), Vector3(40, -60, 40), Game.L_WORLD)
	var rh := player.get_world_3d().direct_space_state.intersect_ray(ray)
	check("ground raycast hits terrain", not rh.is_empty() and absf(rh["position"].y - World.height_at(40, 40)) < 1.5, str(rh.get("position")))

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
	player.global_position = Vector3(0, 30, 10)
	player.velocity = Vector3.ZERO
	await secs(3.0)
	check("fall damage after a 30 m drop", player.health < Game.MAX_HEALTH, "health %.0f" % player.health)
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
	aim_at(ehead)
	w.bloom = 0.0
	w._fire_shot()
	await frames(2)
	var head_dmg := hp1 - e.health
	check("headshot does 2.5x damage", absf(head_dmg - 70.0) < 1.0, "%.1f" % head_dmg)
	check("enemy is hunting after being shot", e.state != Enemy.State.WANDER and e.state != Enemy.State.DEAD, str(e.state))
	await secs(0.3)

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
	check("tactical reload keeps a chambered round", w.ammo() == 16, "ammo %d (was %d)" % [w.ammo(), left])
	check("partly used magazine returns to the pouch", w.spare_mags() == mags_before, "%d mags" % w.spare_mags())

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
			place(en, Vector3(100, 0, 100), true)
	var hunter: Enemy = main._spawn_enemy_at(Vector3(0, 0, -30))
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
	await secs(6.0)
	check("enemy reaches the player and attacks", player.health < Game.MAX_HEALTH, "health %.0f" % player.health)
	check("melee does 16 per strike", int(Game.MAX_HEALTH - player.health) % 16 == 0, "%.0f" % (Game.MAX_HEALTH - player.health))

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
	check("corpse lies down", absf(hunter.tilt.rotation.x) > 1.2, "%.2f rad" % hunter.tilt.rotation.x)
	check("corpse can no longer be hit", hunter.hitboxes.is_empty())

	# gunshot alerts a wanderer within hearing, but not one far away
	for en in all:
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			place(en, Vector3(100, 0, 100), true)
	var near_e: Enemy = main._spawn_enemy_at(Vector3(10, 0, 20))
	var far_e: Enemy = main._spawn_enemy_at(Vector3(100, 0, 100))
	all.append(near_e)
	all.append(far_e)
	place(near_e, Vector3(10, 0, 20), false)
	near_e.wait_t = 99.0
	near_e.facing = 0.0
	place(far_e, Vector3(100, 0, 100), false)
	far_e.wait_t = 99.0
	Game.gunshot.emit(player.global_position, 55.0)
	await frames(2)
	check("a nearby gunshot alerts a wanderer", near_e.state != Enemy.State.WANDER, str(near_e.state))
	check("a far-away enemy stays calm", far_e.state == Enemy.State.WANDER, str(far_e.state))

	# line of sight: a wall between enemy and player blocks sight
	for en in all:
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			place(en, Vector3(100, 0, 100), true)
	var blocker := StaticBody3D.new()
	blocker.collision_layer = Game.L_WORLD
	var bcs := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(20, 10, 1)
	bcs.shape = bbox
	blocker.add_child(bcs)
	main.add_child(blocker)
	blocker.global_position = Vector3(0, 5, -10)
	var watcher: Enemy = main._spawn_enemy_at(Vector3(0, 0, -20))
	all.append(watcher)
	place(watcher, Vector3(0, 0, -20), false)
	watcher.facing = PI
	watcher.rig.rotation.y = PI
	watcher.wait_t = 99.0
	await secs(0.6)
	check("enemy behind a wall does not see the player", watcher.state == Enemy.State.WANDER, str(watcher.state))
	blocker.queue_free()

	print("--- player death ---")
	var died := [false]
	player.died.connect(func() -> void: died[0] = true)
	player.take_damage(500.0)
	await frames(2)
	check("player dies at 0 health", Game.dead and died[0])
	await secs(0.5)

	print("")
	print("RESULT: %d passed, %d failed" % [passes, fails])
	get_tree().quit(1 if fails > 0 else 0)
