class_name ChapterOne
## Chapter One: Noah gets out of the Institute and goes home through the invaded capital. Every kill matters, so enemies
## do not respawn. Later features hang on the objectives' on_start / on_complete hooks. The story is told by short subtitle
## lines (Game.radio_line), never by a cutscene.
##
## After the cellar come the objectives of "IX. The Lander", part one (the home defence, B2, goes between GO TO THE CELLAR and
## CLIMB TO THE ROOF): climb the fire escape of the old block to its roof and look out over the city (the landing craft settles in the
## park), take the marksman on the balcony (his LR-9 long rifle), and thin out the ten guards at the foot of the ramp from the balcony;
## then (part two) run into the lanes of Noah's neighbourhood with six soldiers behind him, take the stragglers' grenades, clear the courtyard from the low roof,
## take the wound in the right arm and finish what is left with the last grenade; the next objective ends at the open ramp of the lander,
## and "X. The Commander" goes inside it (LanderInterior): sneak, the alarm, the run to the command deck, the Commander, the capture.


static func _say(text: String) -> Callable:
	return func(_m: Mission) -> void: Game.radio_line.emit(text)


static func _main() -> Node:
	return Game.player.get_tree().current_scene


## The marksman is dead: his LR-9 goes straight into the player's rifle slot (nobody has to walk down to the guards and up the balcony stair
## for it), and the one he dropped is removed.
static func _grant_rifle(_m: Mission) -> void:
	var w: Weapons = Game.player.weapons
	for inst in w.loadout["rifle"]:
		if String(inst["id"]) == "sniper":
			return
	for pk in Game.pickups.duplicate():
		if is_instance_valid(pk) and pk.weapon_id == "sniper" and not pk.is_ammo:
			pk.take()
	w.switching = 0.0
	w.pick_up(Pickup.spawn_weapon(_main(), Game.player.global_position, "sniper", 5))


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
	# "VI. The Basement" to "VIII. The Locked Door" (HomeScene): the empty flat, the cellar, the raid, the mother, five more, the cabinet
	m.objectives.insert(2, Mission.obj("search_home", "FIND MUM AND MIRA", {"type": "script", "marker_pos": HomeScene.KITCHEN_POS,
		"on_start": func(_mm: Mission) -> void: _main().home.begin_search()}))
	var cellar: Dictionary = m.objectives[3]
	cellar["text"] = "GO DOWN TO THE CELLAR"
	cellar["marker_pos"] = City.CELLAR_DOOR_POS
	m.objectives.append_array([
		Mission.obj("reunion", "MUM AND MIRA", {"type": "script", "marker_pos": HomeScene.MOTHER_AT,
			"on_start": func(_mm: Mission) -> void: _main().home.begin_reunion()}),
		Mission.obj("raid", "STOP THEM - FOUR SOLDIERS UPSTAIRS", {"type": "script", "marker_pos": City.CELLAR_DOOR_POS,
			"on_start": func(_mm: Mission) -> void: _main().home.begin_raid()}),
		Mission.obj("cellar_door", "THE CELLAR - GET DOWN THERE", {"type": "script", "marker_pos": City.CELLAR_POS,
			"on_start": func(_mm: Mission) -> void: _main().home.begin_cellar_door()}),
		Mission.obj("mother", "MUM", {"type": "script", "marker_pos": HomeScene.MOTHER_AT,
			"on_start": func(_mm: Mission) -> void: _main().home.begin_mother()}),
		Mission.obj("five_more", "FIVE MORE - KEEP THEM AWAY FROM MIRA", {"type": "script",
			"on_start": func(_mm: Mission) -> void: _main().home.begin_five()}),
		Mission.obj("back_to_mira", "GO BACK TO MIRA", {"pos": City.CELLAR_POS, "radius": 2.5, "vertical": 2.0,
			"on_start": func(_mm: Mission) -> void: _main().home.begin_back()}),
		Mission.obj("locked_door", "THE LOCKED DOOR", {"type": "script",
			"on_start": func(_mm: Mission) -> void: _main().home.begin_locked()}),
	])
	m.objectives.append_array([
		Mission.obj("climb_roof", "CLIMB TO THE ROOF", {"pos": roof, "marker_pos": lk["foot"], "radius": 3.5, "vertical": 2.5,
			"on_start": _say("TOO MANY SOLDIERS IN THE STREETS. FIND A HIGH PLACE. LOOK.")}),
		Mission.obj("lookout", "LOOK OUT OVER THE CITY", {"type": "script", "pos": foot, "marker_pos": foot,
			"on_start": func(mm: Mission) -> void:
				_main().begin_lookout()
				Game.radio_line.emit("THE SHIPS ARE SETTLING IN THE SQUARES. THE NEAREST ONE IS IN THE PARK.")}),
		Mission.obj("balcony_marksman", "KILL THE MARKSMAN - HE HAS SEEN YOU", {"type": "kill_group", "group": 201, "pos": CityStory.MARKSMAN_AT,
			"on_start": func(_mm: Mission) -> void:
				_main().alert_marksman()
				Game.radio_line.emit("A MARKSMAN ON THE BALCONY. HE KNOWS WHERE YOU ARE. TAKE HIM OUT, NOW."),
			"on_complete": _grant_rifle}),
		Mission.obj("park_fight", "THIN OUT THE GUARDS AT THE RAMP", {"type": "script", "pos": foot, "marker_pos": foot,
			"on_start": _say("HIS LR-9 IS YOURS. LIE DOWN. LOOK THROUGH THE SCOPE. TEN GUARDS AT THE FOOT OF THE RAMP.")}),
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
			"on_start": _say("THE RAMP IS OPEN. NOBODY IS LEFT TO GUARD IT."),
			"on_complete": func(_mm: Mission) -> void: _main().ship.enter()}),
	])
	# "X. The Commander" (LanderInterior): inside the lander, sneak north past the patrols, the alarm, the run to the command deck, the Commander
	m.objectives.append_array([
		Mission.obj("ship_sneak", "FIND THE COMMANDER - STAY LOW, STAY QUIET", {"pos": LanderInterior.alarm_point(), "radius": 3.5, "vertical": 2.5,
			"on_start": _say("THE SHIP IS FULL OF SOLDIERS. EVERY HOUSE, EVERY ROOM. SOMEONE GAVE THAT ORDER.")}),
		Mission.obj("ship_run", "THE ALARM - RUN FOR THE COMMAND DECK", {"pos": LanderInterior.deck_door(), "radius": 2.5, "vertical": 2.5,
			"on_start": func(_mm: Mission) -> void:
				_main().ship.begin_alarm()
				Game.radio_line.emit("INTRUDER ON BOARD. ALL DECKS. SEAL THE SHIP.")}),
		Mission.obj("commander", "KILL THE COMMANDER", {"type": "script",
			"on_start": func(_mm: Mission) -> void: _main().ship.begin_confrontation()}),
	])
	return m
