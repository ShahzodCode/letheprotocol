extends Node
## Prints the facts of Noah's neighbourhood (the courtyard block): lane mouth, paths, drainpipes, buildings, objective list.
## -- --script res://tests/chase_probe.gd

func run(m) -> void:
	await get_tree().physics_frame
	print("court block ", City.COURT_BLOCK, " courtyard ", City.COURT_RECT, " pos ", City.COURT_POS)
	var lane := CityStory.escape_lane()
	print("escape lane ", lane)
	var foot: Vector3 = City.BALCONY_STAIR_FOOT
	var p1 := City.path(foot, lane["pos"]) if not lane.is_empty() else PackedVector3Array()
	print("path stair foot -> lane mouth: ", p1.size(), " points, length ", _len(p1))
	var inside := City.path(lane["pos"], City.COURT_POS) if not lane.is_empty() else PackedVector3Array()
	print("path lane mouth -> courtyard: ", inside.size(), " points, length ", _len(inside), " free(centre) ", City.is_free(City.COURT_POS))
	print("pipes ", CityPlaces.pipes.size(), " ladders of kind pipe ", City.ladders.filter(func(l): return l["kind"] == "pipe").size())
	for g in CityPlaces.court_gates:
		print("gate ", g, " free ", City.is_free(g))
	print("pipe foot ", CityStory.pipe_foot(), " free ", City.is_free(CityStory.pipe_foot()))
	print("crouch passages in the lanes: ", City.crouch_passages.filter(func(c): return City.COURT_BLOCK.grow(1.0).has_point(Vector2(c["pos"].x, c["pos"].z))).size())
	print("sites: ", City.sites.map(func(s): return s["center"]))
	print("plazas: ", City.streets.filter(func(s): return s["cls"] == "plaza").size(), " far landers ", CityStory.far_landers.size())
	var ms: Mission = Game.mission
	for i in ms.objectives.size():
		print("  obj ", i, " ", ms.objectives[i]["id"])
	get_tree().quit(0)


func _len(p: PackedVector3Array) -> float:
	var t := 0.0
	for i in p.size() - 1:
		t += p[i].distance_to(p[i + 1])
	return snappedf(t, 0.1)
