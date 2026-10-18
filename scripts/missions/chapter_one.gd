class_name ChapterOne
## Chapter One: Noah gets out of the Institute and goes home through the invaded capital. Every kill matters, so enemies
## do not respawn. Later features hang on the objectives' on_start / on_complete hooks. The story is told by short subtitle
## lines (Game.radio_line), never by a cutscene.
##
## After the cellar come the objectives of "IX. The Lander", part one (the home defence, B2, goes between GO TO THE CELLAR and
## CLIMB TO THE ROOF): climb the fire escape of the old block to its roof and look out over the city (the landing craft settles in the
## park), take the marksman on the balcony (his LR-9 long rifle), and thin out the ten guards at the foot of the ramp from the balcony;
## then (part two) run into the lanes of Noah's neighbourhood with six soldiers behind him, take the stragglers' grenades, clear the courtyard from the low roof,
## take the wound in the right arm and finish what is left with the last grenade; the objective ends at the open ramp of the lander.


static func _say(text: String) -> Callable:
	return func(_m: Mission) -> void: Game.radio_line.emit(text)


static func _main() -> Node:
	return Game.player.get_tree().current_scene


static func build() -> Mission:
	var m := Mission.new()
	m.id = "chapter_one"
	m.win_title = "TO BE CONTINUED"
	m.respawn_enemies = false
	m.objectives = [
		Mission.obj("leave_institute", "LEAVE THE INSTITUTE", {"pos": City.INSTITUTE_EXIT, "radius": 4.0,
			"on_start": _say("CITY GUARD: THE VEIL HAS FAILED. ALL CITIZENS, GO HOME AND STAY INDOORS.")}),
		Mission.obj("get_home", "GET HOME", {"pos": City.HOME_POS, "radius": 3.0,
			"on_start": _say("KEEP MOVING. KEEP QUIET. DO NOT LET THEM SEE YOU.")}),
		Mission.obj("go_cellar", "GO TO THE CELLAR", {"pos": City.CELLAR_POS, "marker_pos": City.HOME_POS, "radius": 2.5, "vertical": 2.0}),
	]
	var lk := CityStory.lookout
	if lk.is_empty():
		return m          # no lookout roof (LETHE_PLAIN=1): the slice ends at the cellar
	var roof: Vector3 = lk["roof"]
	var foot := CityStory.ramp_foot()
	m.objectives.append_array([
		Mission.obj("climb_roof", "CLIMB TO THE ROOF", {"pos": roof, "marker_pos": lk["foot"], "radius": 3.5, "vertical": 2.5,
			"on_start": _say("TOO MANY SOLDIERS IN THE STREETS. FIND A HIGH PLACE. LOOK.")}),
		Mission.obj("lookout", "LOOK OUT OVER THE CITY", {"type": "script", "pos": foot, "marker_pos": foot,
			"on_start": func(mm: Mission) -> void:
				_main().begin_lookout()
				Game.radio_line.emit("THE SHIPS ARE SETTLING IN THE SQUARES. THE NEAREST ONE IS IN THE PARK.")}),
		Mission.obj("balcony_marksman", "TAKE OUT THE MARKSMAN ON THE BALCONY", {"type": "kill_group", "group": 201, "pos": CityStory.MARKSMAN_AT,
			"on_start": _say("A MARKSMAN ON THE BALCONY OVER THE PARK. GO UP THE STAIR BEHIND HIM.")}),
		Mission.obj("take_rifle", "TAKE HIS RIFLE", {"type": "script", "pos": CityStory.MARKSMAN_AT}),
		Mission.obj("park_fight", "THIN OUT THE GUARDS AT THE RAMP", {"type": "script", "pos": foot, "marker_pos": foot,
			"on_start": _say("LIE DOWN. LOOK THROUGH THE SCOPE. TEN GUARDS AT THE FOOT OF THE RAMP.")}),
	])
	var lane := CityStory.escape_lane()
	if lane.is_empty():
		return m
	# "The Lander", part two: the run through Noah's neighbourhood, the courtyard, the wound (see ChaseFight)
	var pipe := CityStory.pipe_foot()
	var ramp_top := City.LANDER_POS + Basis(Vector3.UP, City.LANDER_YAW) * ShipModels.ramp_top_local()
	m.objectives.append_array([
		Mission.obj("escape_lanes", "ESCAPE INTO THE LANES", {"pos": lane["pos"], "radius": 4.0,
			"on_start": func(_mm: Mission) -> void:
				_main().chase.begin()
				Game.radio_line.emit("THEY ARE COMING. RUN FOR THE LANES - YOU KNOW THESE STREETS.")}),
		Mission.obj("take_grenades", "TAKE THE STRAGGLERS' GRENADES", {"type": "script", "marker_pos": pipe,
			"on_start": _say("TWO OF THEM ARE FALLING BEHIND. TAKE WHAT THEY CARRY.")}),
		Mission.obj("clear_courtyard", "CLEAR THE COURTYARD", {"type": "script", "marker_pos": pipe,
			"on_start": func(_mm: Mission) -> void:
				_main().chase.gather()
				Game.radio_line.emit("THEY HAVE GONE TO GROUND IN THE COURTYARD. THE DRAINPIPE. THE LOW ROOF.")}),
		Mission.obj("finish_them", "FINISH THEM", {"type": "script", "marker_pos": CityStory.court_pos(),
			"on_start": func(_mm: Mission) -> void:
				_main().chase.on_finish_start()
				Game.radio_line.emit("ONE GRENADE FOR WHAT IS LEFT. THROW IT WITH THE LEFT HAND.")}),
		Mission.obj("ramp", "REACH THE OPEN RAMP", {"pos": ramp_top, "radius": 3.5, "vertical": 2.2,
			"on_start": _say("THE RAMP IS OPEN. NOBODY IS LEFT TO GUARD IT.")}),
	])
	return m
