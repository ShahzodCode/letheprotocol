class_name Checkpoint
extends RefCounted
## A snapshot taken when an objective starts: the player (place, view, health, the full loadout with every instance's loaded
## rounds and each spare magazine's rounds), the kill / accuracy counters, who is alive (where, with how much health) and who
## is dead, and the loot lying around. Restoring it puts all of that back; enemies are rebuilt from the data (corpses and
## everything spawned later disappear).

var objective := 0
var pos := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var health := 100.0
var loadout := {}
var active_slot := "pistol"
var active_idx := 0
var last_idx := {}
var kills := 0
var takedowns := 0
var grenades := 0
var arm_injured := false        # "The Lander" part two: the wound (no rifle / knife, left-handed pistol) is part of the snapshot
var shots_fired := 0
var shots_hit := 0
var enemies: Array = []         # living: {uid, kind, group, pos, home, health, ammo, sidearm_ammo, facing}
var dead_uids: Array = []
var civilians: Array = []       # living: {pos, seed, child, leader (index in this list or -1)}
var civ_bodies: Array = []      # dead civilians lying around: {pos, seed, child}
var civilians_lost := 0
var pickups: Array = []         # {is_ammo, weapon_id, ammo, spare, pos, t}


static func copy_loadout(src: Dictionary) -> Dictionary:
	var out := {}
	for slot in src:
		var arr: Array = []
		for inst in src[slot]:
			arr.append({"id": inst["id"], "ammo": int(inst["ammo"]), "spare": (inst["spare"] as Array).duplicate()})
		out[slot] = arr
	return out


static func capture(main) -> Checkpoint:
	Game.mark("checkpoint_capture")
	var cp := Checkpoint.new()
	var pl: Player = main.player
	var w: Weapons = pl.weapons
	cp.objective = Game.mission.index if Game.mission != null else 0
	cp.pos = pl.global_position
	cp.yaw = pl.yaw
	cp.pitch = pl.pitch
	cp.health = pl.health
	cp.loadout = copy_loadout(w.loadout)
	cp.active_slot = w.active_slot
	cp.active_idx = w.active_idx
	cp.last_idx = w.last_idx.duplicate()
	cp.kills = Game.kills
	cp.takedowns = Game.takedowns
	cp.grenades = Game.grenades
	cp.arm_injured = Game.arm_injured
	cp.shots_fired = Game.shots_fired
	cp.shots_hit = Game.shots_hit
	var alive := {}
	for e in Game.enemies:
		if not is_instance_valid(e) or e.state == Enemy.State.DEAD:
			continue
		alive[e.uid] = true
		cp.enemies.append({"uid": e.uid, "kind": e.kind, "group": e.group, "pos": e.global_position, "home": e.home,
			"health": e.health, "ammo": e.ammo, "sidearm_ammo": e.sidearm_ammo, "facing": e.facing})
	for uid in main.enemy_info:
		if not alive.has(uid):
			cp.dead_uids.append(uid)
	var idx := {}
	var living: Array = []
	for cv in Game.civilians:
		if is_instance_valid(cv) and (cv as Civilian).state != Civilian.State.DEAD:
			idx[cv] = living.size()
			living.append(cv)
	for cv2 in living:
		var civ := cv2 as Civilian
		cp.civilians.append({"pos": civ.global_position, "seed": civ.look_seed, "child": civ.is_child, "leader": int(idx.get(civ.leader, -1))})
	for b in Enemy.bodies:
		if is_instance_valid(b) and b is Civilian:
			cp.civ_bodies.append({"pos": (b as Civilian).global_position, "seed": (b as Civilian).look_seed, "child": (b as Civilian).is_child})
	cp.civilians_lost = Game.civilians_lost
	for pk in Game.pickups:
		if is_instance_valid(pk):
			cp.pickups.append({"is_medkit": pk.is_medkit, "is_grenade": pk.is_grenade, "is_ammo": pk.is_ammo, "weapon_id": pk.weapon_id, "ammo": pk.ammo,
				"spare": (pk.spare as Array).duplicate() if pk.spare != null else null, "pos": pk.global_position, "t": pk._t, "keep": pk.keep})
	return cp


## Put everything back. A coroutine: the player is teleported, then we wait two physics frames (a position written to a
## physics body reaches the physics server a frame late) before the game goes on.
func restore(main) -> void:
	Game.mark("checkpoint_restore")
	var pl: Player = main.player
	var w: Weapons = pl.weapons
	# enemies and loot: out with all of them (corpses too), in with the ones that were alive
	for c in main.get_children():
		if c is Enemy:
			c.queue_free()
	Game.enemies.clear()
	Enemy.bodies.clear()
	for civ_old in main.get_children():
		if civ_old is Civilian:
			civ_old.queue_free()
	Game.civilians.clear()
	for pk in Game.pickups.duplicate():
		if is_instance_valid(pk):
			pk.queue_free()
	Game.pickups.clear()
	main.reset_respawns()
	main.squads.reset()
	for g in main.get_children():
		if g is Grenade:
			g.queue_free()
	for info in enemies:
		main.spawn_enemy_from(info)
	main.rebuild_site_groups()
	var made: Array = []
	for d in civilians:
		if not bool(d["child"]):
			made.append(Civilian.spawn(main, pl, d["pos"], int(d["seed"]), false))
		else:
			made.append(null)
	for i in civilians.size():
		var cd: Dictionary = civilians[i]
		if bool(cd["child"]):
			var lead: Civilian = made[int(cd["leader"])] if int(cd["leader"]) >= 0 else null
			made[i] = Civilian.spawn(main, pl, cd["pos"], int(cd["seed"]), true, lead)
	for bd in civ_bodies:
		Civilian.spawn(main, pl, bd["pos"], int(bd["seed"]), bool(bd["child"])).lie_down()
	for d in pickups:
		var pk: Pickup
		if bool(d.get("is_medkit", false)):
			pk = Pickup.spawn_medkit(main, d["pos"])
		elif bool(d["is_grenade"]):
			pk = Pickup.spawn_grenade(main, d["pos"])
		elif bool(d["is_ammo"]):
			pk = Pickup.spawn_ammo(main, d["pos"], d["weapon_id"], int(d["ammo"]))
		else:
			pk = Pickup.spawn_weapon(main, d["pos"], d["weapon_id"], int(d["ammo"]), d["spare"])
		pk.global_position = d["pos"]
		pk._t = float(d["t"])
		pk.keep = bool(d.get("keep", false))
	# the player: view, health, loadout, counters
	pl.health = health
	pl.heal_t = 0.0
	pl.yaw = yaw
	pl.pitch = pitch
	pl.rotation.y = yaw
	pl.head.rotation = Vector3(pitch, 0.0, 0.0)
	pl.recoil_pitch = 0.0
	pl.recoil_yaw = 0.0
	pl.crouch_k = 0.0
	pl.sliding = 0.0
	pl.hurt_k = 0.0
	pl.fall_speed = 0.0
	pl.velocity = Vector3.ZERO
	pl.global_position = pos
	w.loadout = copy_loadout(loadout)
	w.last_idx = last_idx.duplicate()
	w._equip(active_slot, active_idx)
	w._show_only(w.current)
	w.reloading = false
	w.reload_t = 0.0
	w.switching = 0.0
	w.pending_slot = ""
	w.ads_k = 0.0
	w.cooldown = 0.0
	w.bloom = 0.0
	w.melee_t = 0.0
	w.hover = null
	Game.kills = kills
	Game.civilians_lost = civilians_lost
	Game.takedowns = takedowns
	Game.grenades = grenades
	Game.arm_injured = arm_injured
	pl.clear_drips()
	Game.shots_fired = shots_fired
	Game.shots_hit = shots_hit
	# the mission goes back to the objective this checkpoint belongs to (no hooks run again, no new checkpoint)
	if Game.mission != null:
		Game.mission.index = objective
		Game.mission.finished = false
		Game.mission.age = 0.0
	main.world.set_marker_target(Game.mission.marker_pos() if Game.mission != null else null)
	await main.get_tree().physics_frame
	pl.global_position = pos
	pl.velocity = Vector3.ZERO
	await main.get_tree().physics_frame
	pl.global_position = pos
	pl.velocity = Vector3.ZERO
	Game.dead = false
	Game.won = false
