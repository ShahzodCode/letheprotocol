extends Node
## Visual check under a virtual display:  xvfb-run godot --path . --rendering-driver opengl3 -- --shots <outdir>
var main
var outdir := "/tmp/shots"

func shot(name: String) -> void:
	if main != null and main.player != null:
		main.player.health = 100.0          # the soldiers must not kill the camera man
		Game.dead = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [outdir, name])
	print("saved ", name, " ", img.get_size())

func aim_at(player: Player, target: Vector3) -> void:
	var d := target - player.camera.global_position
	player.yaw = atan2(-d.x, -d.z)
	player.pitch = asin(d.y / d.length())

## Teleport the camera man, look at a point, let the world settle, take a picture.
func place_shot(pl: Player, from: Vector3, look: Vector3, name: String) -> void:
	pl.global_position = from
	pl.velocity = Vector3.ZERO
	aim_at(pl, look)
	for k in 25:
		await get_tree().physics_frame
	aim_at(pl, look)
	await get_tree().physics_frame
	await shot(name)

func run(m) -> void:
	main = m
	Game.force_input = true
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		outdir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(outdir)
	var pl: Player = m.player
	for k in 40:
		await get_tree().physics_frame
	await shot("01_start")
	# battle site, goal house and the marker seen from far away
	var site0: Site = m.world.sites[0]
	pl.global_position = Vector3(site0.position.x + 9.0, 0.1, site0.position.z + 12.0)
	pl.velocity = Vector3.ZERO
	aim_at(pl, site0.position + Vector3(0, 1.0, 0))
	for k in 80:
		await get_tree().physics_frame
	await shot("01b_site")
	# Chapter One places: lobby, apartment, cellar, park, skyline
	await place_shot(pl, Vector3(-30.0, 0.1, 255.0), Vector3(-30.0, 1.5, 258.0), "20_lobby_lift")
	await place_shot(pl, Vector3(-36.0, 0.1, 256.0), Vector3(-30.0, 1.2, 246.0), "20b_lobby_door")
	await place_shot(pl, Vector3(-30.0, 0.1, 232.0), Vector3(-30.0, 120.0, 257.0), "24_institute_tower")
	await place_shot(pl, Vector3(-3.0, 0.1, 150.0), Vector3(0.0, 40.0, -40.0), "24b_skyline_north")
	await place_shot(pl, Vector3(-3.0, 0.1, 100.0), Vector3(-30.0, 60.0, 400.0), "24c_skyline_south")
	await place_shot(pl, Vector3(0.0, 0.1, -20.0), Vector3(16.0, 2.0, -30.6), "21_home_front")
	await place_shot(pl, Vector3(17.2, 0.1, -30.6), Vector3(27.0, 1.2, -30.6), "21b_apartment_hall")
	await place_shot(pl, Vector3(18.0, 0.1, -34.4), Vector3(18.0, 1.0, -36.0), "21c_apartment_kitchen")
	await place_shot(pl, Vector3(23.0, 0.1, -33.0), Vector3(29.0, 1.0, -26.0), "21d_apartment_living")
	await place_shot(pl, Vector3(20.2, 0.1, -31.0), Vector3(20.2, -1.0, -27.0), "22_stairs_down")
	await place_shot(pl, Vector3(20.4, -2.6, -25.0), Vector3(20.4, -1.2, -21.0), "22b_cellar")
	await place_shot(pl, Vector3(22.0, -2.6, -24.0), Vector3(17.5, -1.4, -23.0), "22c_cellar_shelves")
	await place_shot(pl, Vector3(81.5, 0.1, -36.0), Vector3(81.5, 1.5, -60.0), "23_park")
	await place_shot(pl, Vector3(80.5, 0.1, -46.0), Vector3(82.0, 4.0, -31.0), "23b_balcony")
	await place_shot(pl, Vector3(72.6, 3.5, -30.3), Vector3(81.5, 1.5, -55.0), "23c_balcony_view")
	# stealth: a winded soldier, the stealth indicator (suspicious, alerted), the grenade arc and an explosion
	for en0 in Game.enemies.duplicate():
		en0.stun = 999.0
		en0.global_position = Vector3(260.0, 0.1, 0.0)
	pl.global_position = Vector3(0.0, 0.1, 150.0)
	for k in 10:
		await get_tree().physics_frame
	var winded: Enemy = m._spawn_enemy_at(Vector3(0.0, 0.0, 124.0), "soldier")
	winded.stun = 999.0
	winded.winded_t = 99.0
	winded.stamina = 0.0
	winded.facing = -PI * 0.5
	winded.rig.rotation.y = winded.facing
	pl.global_position = Vector3(0.0, 0.1, 127.5)
	for k in 30:
		await get_tree().physics_frame
	aim_at(pl, Vector3(0.0, 1.0, 124.0))
	for k in 5:
		await get_tree().physics_frame
	await shot("30_winded_soldier")
	winded.winded_t = 0.0
	winded.global_position = Vector3(260.0, 0.1, 10.0)
	var watcher: Enemy = m._spawn_enemy_at(Vector3(6.0, 0.0, 105.0), "soldier")
	watcher.stun = 999.0
	watcher.facing = PI * 0.5
	watcher.rig.rotation.y = watcher.facing
	watcher._start_suspicion(Vector3(10.0, 0.0, 100.0))
	pl.global_position = Vector3(0.0, 0.1, 124.0)
	pl.yaw = 0.0
	pl.pitch = 0.0
	for k in 25:
		await get_tree().physics_frame
	pl.yaw = 0.0
	await shot("31_stealth_suspicious")
	watcher.state = Enemy.State.SHOOT
	for k in 12:
		await get_tree().physics_frame
	await shot("31b_stealth_alerted")
	watcher.global_position = Vector3(260.0, 0.1, 20.0)
	watcher.state = Enemy.State.WANDER
	Game.grenades = 3
	pl.global_position = Vector3(0.0, 0.1, 124.0)
	pl.pitch = deg_to_rad(18)
	for k in 20:
		await get_tree().physics_frame
	Input.action_press("grenade")
	for k in 60:
		await get_tree().physics_frame
	await shot("32_grenade_arc")
	Input.action_release("grenade")
	for k in 4:
		await get_tree().physics_frame
	Game.grenades = 3
	pl.pitch = 0.0
	var blast_pt := Vector3(0.0, 0.0, 112.0)
	var target_e: Enemy = m._spawn_enemy_at(Vector3(3.0, 0.0, 110.0), "soldier")
	target_e.stun = 999.0
	for k in 30:
		await get_tree().physics_frame
	pl.yaw = 0.0
	Grenade.detonate(m, blast_pt)
	for k in 14:
		await get_tree().physics_frame
	await shot("33_explosion")
	for k in 60:
		await get_tree().physics_frame
	await shot("33b_explosion_smoke_scorch")
	for en1 in Game.enemies.duplicate():
		en1.stun = 999.0
		en1.global_position = Vector3(260.0, 0.1, 30.0)
	Game.dead = false
	pl.health = 100.0
	# civilians fleeing along an avenue (some children), a few lying dead
	for old_c in Game.civilians.duplicate():
		old_c.queue_free()
	for k in 3:
		await get_tree().physics_frame
	pl.global_position = Vector3(0.0, 0.1, 172.0)
	pl.velocity = Vector3.ZERO
	pl.yaw = 0.0
	pl.pitch = 0.0
	var fl: Array = []
	for ci in 12:
		var cvx := Civilian.spawn(m, pl, Vector3(-7.0 + float(ci % 4) * 4.5, 0.0, 150.0 - float(ci / 4) * 9.0), 300 + ci * 13, ci % 5 == 4)
		fl.append(cvx)
	for cd in 3:
		Civilian.spawn(m, pl, Vector3(-6.0 + 5.0 * cd, 0.0, 128.0 + 3.0 * cd), 900 + cd).lie_down()
	for k in 20:
		await get_tree().physics_frame
	for cvx2 in fl:
		(cvx2 as Civilian).hide_cd = 9999.0
		(cvx2 as Civilian).target = Vector3(0.0, 0.0, -250.0)
		(cvx2 as Civilian).nav_goal = Vector3.INF
	for k in 50:
		await get_tree().physics_frame
	await shot("34_civilians_fleeing")
	for k in 40:
		await get_tree().physics_frame
	await shot("34b_civilians_fleeing_later")
	for old_c2 in Game.civilians.duplicate():
		old_c2.queue_free()
	pl.global_position = Vector3(0, 0.1, 0)
	pl.velocity = Vector3.ZERO
	pl.yaw = 0.0
	pl.pitch = 0.0
	for k in 30:
		await get_tree().physics_frame
# lineup of every enemy kind, facing the player, frozen (rifleman / marksman in their firing pose)
	var kinds := ["soldier", "blade", "rifleman", "gunner", "marksman"]
	var line: Array[Enemy] = []
	for n in kinds.size():
		var x := (n - 2) * 2.4
		var en: Enemy = m._spawn_enemy_at(Vector3(x, 0, -10), kinds[n])
		line.append(en)
	for k in 10:
		await get_tree().physics_frame
	for en in line:
		en.stun = 999
		en.facing = PI
		en.rig.rotation.y = PI
		if en.ranged:
			en.state = Enemy.State.SHOOT
	line[4].charging = true
	line[4].aim_point = pl.global_position + Vector3(0, 1.2, 0)
	line[4].aim_locked = true
	line[4]._update_laser()
	pl.yaw = 0.0
	pl.pitch = 0.0
	for k in 10:
		await get_tree().physics_frame
	await shot("00_lineup")
	# the same line seen from the side, so the weapons in their hands show
	for en in line:
		en.facing = -PI * 0.5
		en.rig.rotation.y = en.facing
	for k in 5:
		await get_tree().physics_frame
	await shot("00c_lineup_side")
	for en in line:
		Game.enemies.erase(en)
		en.queue_free()
	# pick-up box: standing over a rail rifle, with a second carbine already in the rifle slot
	pl.weapons.loadout["rifle"].append(Weapons.new_weapon("carbine", 11))
	Pickup.spawn_weapon(m, pl.global_position + Vector3(0.6, 0, -0.3), "railgun", 4)
	Pickup.spawn_ammo(m, pl.global_position + Vector3(3, 0, -4), "rifle", 20)
	pl.weapons.cooldown = 0.0
	for k in 20:
		await get_tree().physics_frame
	await shot("00b_pickup_box")
	await get_tree().physics_frame
	# an enemy in the distance and one close by
	var e1: Enemy = Game.enemies[0]
	var e2: Enemy = Game.enemies[1]
	e1.position = Vector3(18, World.height_at(18, -45) + 0.1, -45)
	e2.position = Vector3(-4, World.height_at(-4, -9) + 0.1, -9)
	e1.stun = 999
	e2.stun = 999
	e2.rig.rotation.y = PI
	pl.yaw = 0.0
	pl.pitch = 0.0
	for k in 30:
		await get_tree().physics_frame
	aim_at(pl, e2.global_position + Vector3(0, 1.3, 0))
	for k in 5:
		await get_tree().physics_frame
	await shot("02_enemy_close")
	pl.yaw = deg_to_rad(8)
	pl.pitch = deg_to_rad(5)
	for k in 5:
		await get_tree().physics_frame
	await shot("03_pistol_hip")
	pl.weapons.loadout["rifle"].append(Weapons.new_weapon("rifle"))
	pl.weapons.switch_to("rifle")
	for k in 90:
		await get_tree().physics_frame
	await shot("04_rifle_hip")
	Input.action_press("aim")
	for k in 90:
		await get_tree().physics_frame
	await shot("05_rifle_ads")
	Input.action_release("aim")
	# muzzle flash + tracer
	pl.weapons.cooldown = 0.0
	pl.weapons._fire_shot()
	await shot("06_rifle_fire")
	# pistol aimed + flash held for the camera
	pl.weapons.switch_to("pistol")
	for k in 60:
		await get_tree().physics_frame
	Input.action_press("aim")
	for k in 90:
		await get_tree().physics_frame
	await shot("06b_pistol_ads")
	Input.action_release("aim")
	pl.weapons.ads_k = 0.0
	pl.weapons.cooldown = 0.0
	pl.weapons._fire_shot()
	pl.weapons.flash_t = 9.0
	await get_tree().process_frame
	await shot("06c_pistol_flash")
	pl.weapons.flash_t = 0.01
	# dead enemy
	e2.take_hit(500.0, "body", Vector3(0, 0, -6), e2.global_position + Vector3(0, 1.2, 0))
	for k in 140:
		await get_tree().physics_frame
	pl.weapons.ads_k = 0.0
	aim_at(pl, e2.global_position + Vector3(0, 0.6, 0))
	for k in 30:
		await get_tree().physics_frame
	await shot("07_dead_enemy")
	# box-built weapons aimed down their sights: the view must stay clear
	var w2: Weapons = pl.weapons
	w2.loadout["rifle"].append(Weapons.new_weapon("carbine"))
	w2.loadout["rifle"][1] = Weapons.new_weapon("carbine")
	for wid in ["carbine", "hmg", "railgun"]:
		w2.loadout["rifle"][1] = Weapons.new_weapon(wid)
		w2.switch_to("rifle")
		w2._equip("rifle", 1)
		w2._show_only(wid)
		w2.switching = 0.0
		pl.global_position = Vector3(0, 0.1, 0)
		pl.yaw = 0.0
		pl.pitch = 0.0
		for k in 40:
			await get_tree().physics_frame
		await shot("12_hip_" + wid)
		Input.action_press("aim")
		for k in 60:
			await get_tree().physics_frame
		await shot("10_ads_" + wid)
		Input.action_release("aim")
	for wid2 in ["knife", "blade"]:
		w2.loadout["melee"].append(Weapons.new_weapon(wid2))
		var mi2: int = (w2.loadout["melee"] as Array).size() - 1
		w2._equip("melee", mi2)
		w2._show_only(wid2)
		w2.switching = 0.0
		for k in 40:
			await get_tree().physics_frame
		await shot("12_hip_" + wid2)
	w2._equip("pistol", 0)
	w2._show_only("pistol")
	# parked vehicles
	var seen_types := {}
	var cn := 0
	for car in City.cars:
		if seen_types.has(car["type"]) or cn >= 3:
			continue
		seen_types[car["type"]] = true
		var cp: Vector3 = car["pos"]
		var look := cp + Vector3(0, 1.0, 0)
		if bool(car["along_z"]):
			var best := 0.0
			for ax in City.AVENUE_X:
				if absf(ax - cp.x) < absf(best - cp.x) or best == 0.0:
					best = ax
			pl.global_position = Vector3(best, 0.1, cp.z + 9.0)
		else:
			var best2 := 0.0
			for az in City.AVENUE_Z:
				if absf(az - cp.z) < absf(best2 - cp.z) or best2 == 0.0:
					best2 = az
			pl.global_position = Vector3(cp.x + 9.0, 0.1, best2)
		pl.velocity = Vector3.ZERO
		aim_at(pl, look)
		for k in 20:
			await get_tree().physics_frame
		await shot("11_car_" + str(car["type"]))
		cn += 1
	await war_shots(pl)
	await stage3_shots(pl)
	# overview from above
	pl.global_position = Vector3(0, 480, 120)
	pl.velocity = Vector3.ZERO
	pl.pitch = deg_to_rad(-80)
	pl.yaw = 0.0
	pl.set_physics_process(false)
	pl.head.rotation = Vector3(pl.pitch, 0, 0)
	await get_tree().process_frame
	await shot("08_overview")
	# walking up a real hill: the camera must rise with the ground
	pl.set_physics_process(true)
	pl.weapons.ads_k = 0.0
	pl.global_position = Vector3(0, World.height_at(0, -50) + 0.5, -50)
	pl.velocity = Vector3.ZERO
	pl.yaw = 0.0
	pl.pitch = 0.0
	Input.action_press("move_forward")
	for n in 4:
		for k in 240:
			await get_tree().physics_frame
		print("cam y=", pl.camera.global_position.y, " pitch=", pl.camera.global_rotation_degrees)
		print("walk ", n, " player y=", pl.global_position.y, " ground=", World.height_at(pl.global_position.x, pl.global_position.z), " z=", pl.global_position.z)
		await shot("09_hill_%d" % n)
	Input.action_release("move_forward")
	get_tree().quit()




# ---------------------------------------------------------------- the war-torn city (stages 1-3)

## A spot on the ground `dist` m from `target` with a clear line of sight to it (16 directions per distance), or Vector3.INF.
func clear_cam(target: Vector3, dists: Array, face_dir: Vector3 = Vector3.ZERO) -> Vector3:
	var space: PhysicsDirectSpaceState3D = main.player.get_world_3d().direct_space_state
	for d in dists:
		for k in 16:
			var a := TAU * float(k) / 16.0
			var p := Vector3(target.x + cos(a) * float(d), 0.1, target.z + sin(a) * float(d))
			if absf(p.x) > City.IN_X - 4.0 or absf(p.z) > City.IN_Z - 4.0 or not City.is_free(p):
				continue
			if face_dir != Vector3.ZERO and Vector3(cos(a), 0, sin(a)).dot(face_dir) < 0.3:
				continue
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.7, 0), target, Game.L_WORLD)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or (hit["position"] as Vector3).distance_to(target) < 2.0:
				return p
	return Vector3.INF


func look_shot(pl: Player, target: Vector3, dists: Array, name: String, face_dir: Vector3 = Vector3.ZERO) -> void:
	var p := clear_cam(target, dists, face_dir)
	if p == Vector3.INF:
		print("no clear view for ", name)
		return
	await place_shot(pl, p, target, name)


func war_shots(pl: Player) -> void:
	for en in Game.enemies.duplicate():
		en.stun = 999.0
		en.global_position = Vector3(260.0, 0.1, 0.0)
	# an avenue with wrecked cars and a fallen tree: the fallen tree with the most damaged cars near it
	var best_tree: Dictionary = {}
	var best_score := -1
	for t in City.trees:
		if String(t["state"]) != "fallen":
			continue
		var tp2: Vector2 = t["pos"]
		var score := 0
		for c in City.cars:
			if String(c["dmg"]) != "" and (c["pos"] as Vector3).distance_to(Vector3(tp2.x, 0.0, tp2.y)) < 26.0:
				score += 1
		if score > best_score:
			best_score = score
			best_tree = t
	if not best_tree.is_empty():
		var tr: Array = best_tree["trunk"]
		var mid: Vector3 = ((tr[0] as Vector3) + (tr[1] as Vector3)) * 0.5
		await look_shot(pl, Vector3(mid.x, 0.8, mid.z), [16.0, 22.0, 12.0], "40_avenue_wrecks_fallen_tree")
	# a burning car close up
	for c in City.cars:
		if String(c["dmg"]) == "burning":
			var cp: Vector3 = c["pos"]
			await look_shot(pl, Vector3(cp.x, 1.0, cp.z), [9.0, 12.0], "40b_burning_car")
			break
	for t in City.trees:
		if String(t["state"]) == "burning" and (t["pos"] as Vector2).length() > 40.0:
			var bp: Vector2 = t["pos"]
			await look_shot(pl, Vector3(bp.x, 5.0, bp.y), [10.0, 14.0], "40c_burning_tree")
			break
	# obstacles: sandbags / barricade / tank trap
	for want in ["sandbags", "barricade", "tank_trap", "pole_down"]:
		for ob in CityWar.war_obstacles:
			if ob["kind"] == want:
				var op: Vector3 = ob["pos"]
				await look_shot(pl, Vector3(op.x, 0.8, op.z), [7.0, 10.0, 14.0], "40d_obstacle_" + want)
				break
	# a heavily damaged, burning building; a missing corner; a hole through the facade; collapsed top floors
	var done := {}
	for f in Scn.fires:
		if f["kind"] == "build" and not done.has("burn"):
			done["burn"] = true
			await look_shot(pl, f["pos"], [26.0, 34.0, 44.0], "41_burning_building")
	for b in City.buildings:
		if b.get("border", false):
			continue
		if b.has("chunk") and not done.has("corner") and float(b["h"]) < 120.0:
			done["corner"] = true
			var ch: Dictionary = b["chunk"]
			var cc := (ch["rect"] as Rect2).get_center()
			await look_shot(pl, Vector3(cc.x, float(ch["y0"]) + 4.0, cc.y), [32.0, 42.0, 54.0], "42_missing_corner")
		elif b.has("hole") and not done.has("hole"):
			done["hole"] = true
			var hd: Dictionary = b["hole"]
			var hc := (hd["rect"] as Rect2).get_center()
			var n: Vector2 = CityBuildings.SIDE_N[hd["side"]]
			await look_shot(pl, Vector3(hc.x, (float(hd["y0"]) + float(hd["y1"])) * 0.5, hc.y), [14.0, 22.0, 30.0], "43_hole_in_facade", Vector3(n.x, 0, n.y))
		elif String(b.get("arch_damage", "")) == "collapse" and not done.has("collapse") and float(b["h"]) < 60.0:
			done["collapse"] = true
			var rc: Rect2 = b["rect"]
			await look_shot(pl, Vector3(rc.get_center().x, float(b["h"]) - 1.0, rc.get_center().y), [30.0, 40.0, 50.0], "44_collapsed_top")
	# the border ring: the end of an avenue and the east edge
	await place_shot(pl, Vector3(0.0, 0.1, -240.0), Vector3(0.0, 70.0, -312.0), "45_border_ring_north")
	await place_shot(pl, Vector3(140.0, 0.1, 20.0), Vector3(172.0, 60.0, 20.0), "45b_border_ring_east")


## Stage 3: a fire escape, a ladder, a rooftop with a bridge (open and glass, one broken), a crouch passage, a pass-through corridor.
func stage3_shots(pl: Player) -> void:
	if not City.escapes.is_empty():
		var es: Dictionary = City.escapes[City.escapes.size() / 2]
		var st: Vector3 = es["start"]
		await look_shot(pl, Vector3(st.x, minf(float(es["top"]) * 0.45, 12.0), st.z), [14.0, 20.0, 28.0], "50_fire_escape")
	for l in City.ladders:
		if l["kind"] == "wall":
			var lb: Vector3 = l["pos"]
			var n: Vector2 = l["n"]
			await look_shot(pl, Vector3(lb.x, minf(float(l["top"]) * 0.5, 8.0), lb.z), [8.0, 12.0, 16.0], "50b_ladder", Vector3(n.x, 0, n.y))
			break
	var shown := {}
	for br in City.bridges:
		var key := String(br["kind"]) + str(br["broken"])
		if shown.has(key):
			continue
		shown[key] = true
		var p0: Vector3 = br["p0"]
		var p1: Vector3 = br["p1"]
		var dn := (p1 - p0)
		dn.y = 0.0
		dn = dn.normalized()
		var start := Vector3(p0.x - dn.x * 4.0, p0.y + 0.15, p0.z - dn.z * 4.0)
		await place_shot(pl, start, Vector3(p1.x + dn.x * 4.0, p1.y + 1.2, p1.z + dn.z * 4.0), "51_roof_bridge_%s_%s" % [br["kind"], "broken" if br["broken"] else "whole"])
		# and the bridge seen from the street
		var mid := p0.lerp(p1, 0.5)
		await look_shot(pl, Vector3(mid.x, p0.y, mid.z), [18.0, 26.0, 36.0], "51b_bridge_from_street_%s_%s" % [br["kind"], "broken" if br["broken"] else "whole"])
	# a crouch passage, seen from two metres away (the HUD shows the crouch hint)
	var pi := 0
	for p in City.crouch_passages:
		var c: Vector3 = p["pos"]
		var dir := Vector3(1, 0, 0) if p["along_x"] else Vector3(0, 0, 1)
		await place_shot(pl, c - dir * 2.8, c + Vector3(0, 1.4, 0), "52_crouch_passage_%d_%s" % [pi, p["kind"]])
		pi += 1
		if pi >= 3:
			break
	# a pass-through corridor: from the entrance looking in, and from inside looking out
	if not City.tunnels.is_empty():
		var t: Dictionary = City.tunnels[0]
		var ta: Vector3 = t["a"]
		var tb: Vector3 = t["b"]
		await place_shot(pl, ta, tb + Vector3(0, 1.6, 0), "53_corridor_entrance")
		await place_shot(pl, ta.lerp(tb, 0.5), tb + Vector3(0, 1.6, 0), "53b_corridor_inside")
