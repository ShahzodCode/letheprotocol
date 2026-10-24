extends Node
## Walks one soldier of every kind through the clip states (calm, alert, hunt, lose him, run and die, stand and die; the M4 soldier also sits and
## gets up) and prints the clip each stage plays: `-- --script res://tests/enemy_clip_probe.gd` (PROBE_OUT = file to write). Script errors show in the
## engine's error output.


func run(m) -> void:
	var out := PackedStringArray()
	Game.force_input = true
	for i in 60:
		await get_tree().physics_frame
	var base: Vector3 = m.player.global_position + Vector3(0.0, 0.0, 14.0)
	var kinds := ["soldier", "rifleman", "marksman", "gunner", "blade"]
	for ki in kinds.size():
		var kind: String = kinds[ki]
		var e: Enemy = m._spawn_enemy_at(base + Vector3(float(ki) * 3.0, 0.0, 0.0), kind)
		await _frames(30)
		out.append("%s: model %s, new_clips %s, clip %s" % [kind, e.model.model_id, str(e.model.new_clips), e.model.current])
		e._aggravate(true)
		for s in 6:
			await _frames(20)
			out.append("  alert+%d: state %d clip %s speed %.2f ramp %.2f up %s" % [s, e.state, e.model.current, Vector2(e.velocity.x, e.velocity.z).length(), e._ramp_t, str(e._rifle_up)])
		e._give_up_hunt()
		for s in 3:
			await _frames(40)
			out.append("  lost+%d: state %d clip %s hold %.2f up %s" % [s, e.state, e.model.current, e._pose_hold, str(e._rifle_up)])
		e._aggravate(true)
		await _frames(150)
		out.append("  hunting again: state %d clip %s speed %.2f" % [e.state, e.model.current, Vector2(e.velocity.x, e.velocity.z).length()])
		e.take_hit(99999.0, "body", Vector3(2.0, 0.0, 0.0), e.global_position + Vector3(0.0, 1.2, 0.0))
		await _frames(20)
		out.append("  killed (running or not): clip %s" % e.model.current)
		await _frames(240)
	# a calm one shot while standing
	var st: Enemy = m._spawn_enemy_at(base + Vector3(-6.0, 0.0, 0.0), "soldier")
	await _frames(40)
	st.take_hit(99999.0, "head", Vector3(0.0, 0.0, 2.0), st.global_position + Vector3(0.0, 1.6, 0.0))
	await _frames(20)
	out.append("soldier shot standing: clip %s" % st.model.current)
	await _frames(200)
	# the sitting soldier
	var sit: Enemy = m._spawn_enemy_at(base + Vector3(-9.0, 0.0, 0.0), "soldier")
	await _frames(20)
	sit.sit_down(0.0)
	await _frames(60)
	out.append("sitting: _sitting %s, gun parent %s, clip %s" % [str(sit._sitting), sit.gun.get_parent().name, sit.model.current])
	sit._get_up()
	await _frames(60)
	out.append("up again: _sitting %s, gun parent %s, state %d, clip %s" % [str(sit._sitting), sit.gun.get_parent().name, sit.state, sit.model.current])
	var target := OS.get_environment("PROBE_OUT")
	var fa := FileAccess.open(target if target != "" else ProjectSettings.globalize_path("res://.shots/enemy_clip_probe.txt"), FileAccess.WRITE)
	fa.store_string("\n".join(out))
	fa.close()
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
