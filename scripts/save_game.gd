class_name SaveGame
## The save file, user://save.dat (var_to_str text, so Vector3s survive): the last checkpoint of the story (CONTINUE) and, for every
## chapter-select place the player has reached, the checkpoint taken when it began (CHAPTER SELECT starts there with the kit he had).
## An entry is {cp: Checkpoint.to_dict(), roles: Main.story_roles, info: Main.enemy_info, next_uid, objective_id, index}.
## Written by Main on every checkpoint of the story mission (never the sandbox, never a test run). The city has a fixed seed, so the
## places in an entry still fit the world; `ids` (the objective list it was saved with) tells whether the objective list changed since.

const PATH := "user://save.dat"
const VERSION := 1

static var _data := {}
static var _loaded := false
static var enabled := true              # Main turns it off for test runs and the sandbox


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = {}
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var v: Variant = str_to_var(f.get_as_text())
			if v is Dictionary and int((v as Dictionary).get("version", 0)) == VERSION:
				_data = v
	return _data


static func _write() -> void:
	var d := data()
	d["version"] = VERSION
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(var_to_str(d))


static func has_continue() -> bool:
	return data().has("last")


## "GET HOME  -  saved 24 Oct 14:02" for the CONTINUE button.
static func continue_text() -> String:
	var d := data()
	if not d.has("last"):
		return "NO SAVED GAME"
	var e: Dictionary = d["last"]
	var t := Time.get_datetime_dict_from_unix_time(int(d.get("saved_at", 0)) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
	return "%s  -  saved %d %s %02d:%02d" % [String(e.get("text", "")), int(t["day"]), months[clampi(int(t["month"]) - 1, 0, 11)], int(t["hour"]), int(t["minute"])]


static func place_entry(id: String) -> Dictionary:
	return (data().get("places", {}) as Dictionary).get(id, {})


static func place_open(id: String) -> bool:
	return bool(data().get("all_open", false)) or not place_entry(id).is_empty() or id == String(StoryPlaces.PLACES[0]["id"])


static func unlock_all() -> void:
	data()["all_open"] = true
	_write()


## Main took a checkpoint: it becomes the CONTINUE entry, and the entry of its place when the objective starts one.
static func record(main) -> void:
	if not enabled or main.checkpoint == null or main.mission == null or main.mission.finished:
		return
	var ms: Mission = main.mission
	var o := ms.active()
	var e := {
		"cp": main.checkpoint.to_dict(),
		"roles": (main.story_roles as Dictionary).duplicate(),
		"info": (main.enemy_info as Dictionary).duplicate(true),
		"next_uid": int(main._next_uid),
		"objective_id": String(o["id"]),
		"text": String(o["text"]),
		"index": ms.index,
	}
	var d := data()
	d["last"] = e
	d["saved_at"] = int(Time.get_unix_time_from_system())
	d["ids"] = ms.objectives.map(func(x): return String(x["id"]))
	if not StoryPlaces.get_place(String(o["id"])).is_empty():
		var places: Dictionary = d.get("places", {})
		places[String(o["id"])] = e
		d["places"] = places
	_write()
