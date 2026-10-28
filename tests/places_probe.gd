extends Node
## Starts one chapter-select place the way the menu does (fast-forward + standard kit), prints where the story and the player are, then
## round-trips the checkpoint through the save format and restores it (CONTINUE).   -- --script res://tests/places_probe.gd place=<id>
func run(m) -> void:
	var id := "raid"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("place="):
			id = a.substr(6)
	Game.force_input = true
	await get_tree().physics_frame
	await m._start_from({"mode": "place", "place": id})
	await get_tree().create_timer(1.0).timeout
	_report(m, "kit start")
	var e := {"cp": m.checkpoint.to_dict(), "roles": m.story_roles.duplicate(), "info": m.enemy_info.duplicate(true), "next_uid": m._next_uid}
	var back: Dictionary = str_to_var(var_to_str(e))
	m.checkpoint = Checkpoint.from_dict(back["cp"])
	await m._restore_checkpoint()
	await get_tree().create_timer(1.0).timeout
	_report(m, "after save round trip")
	print("PROBE DONE")
	get_tree().quit()


func _report(m, what: String) -> void:
	var near := 0
	var alive := 0
	for en in Game.enemies:
		if is_instance_valid(en) and en.state != Enemy.State.DEAD:
			alive += 1
			if en.global_position.distance_to(m.player.global_position) < 40.0:
				near += 1
	var ids: Array = []
	for slot in m.player.weapons.loadout:
		for inst in m.player.weapons.loadout[slot]:
			ids.append(inst["id"])
	print("PROBE %s: objective %s (%d)  player %s  health %d  dead %s  enemies %d (%d within 40 m)  kit %s  grenades %d  arm %s  ship %s  landed %s" % [
		what, m.mission.active().get("id", "?"), m.mission.index, str(m.player.global_position.snapped(Vector3(0.1, 0.1, 0.1))), int(m.player.health),
		str(Game.dead), alive, near, str(ids), Game.grenades, str(Game.arm_injured), str(m.ship.inside), str(m.world.lander.landed)])
