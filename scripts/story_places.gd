class_name StoryPlaces
## The places CHAPTER SELECT offers (each is an objective of ChapterOne where a part of the book begins), with the short recap the loading
## screen, chapter select and the objective log show, and the standard kit used when a place is opened by the "unlock all" cheat
## (a place reached by playing starts from the checkpoint taken when it began, so with the kit the player really had).
##
## `spot`: where the player stands for a standard-kit start (null = where the story's own hooks put him); `kit`: weapon ids per slot,
## grenades, the arm wound.

const CHAPTER := "CHAPTER ONE"
const CHAPTER_TITLE := "THE MORNING THE VEIL BROKE"

const PLACES := [
	{"id": "leave_institute", "section": "IV. THE STREETS", "name": "THE INSTITUTE",
		"recap": "The Veil has broken over Verdance. Noah is in the lobby of the Institute with his father's bag: a pistol and a knife. Get out, and get home.",
		"kit": {"pistol": ["pistol"], "rifle": [], "melee": ["knife"]}},
	{"id": "get_home", "section": "V. THE ROAD HOME", "name": "THE ROAD HOME",
		"recap": "Invaders are firing into the crowds in the streets. Home is almost three hundred metres north, past the soldiers. Keep low, keep moving.",
		"kit": {"pistol": ["pistol"], "rifle": [], "melee": ["knife"]}},
	{"id": "search_home", "section": "VI. THE BASEMENT", "name": "HOME",
		"recap": "Noah made it across the city to the family flat. The door is open and the rooms are empty. Mum and Mira have to be somewhere.",
		"kit": {"pistol": ["pistol"], "rifle": ["rifle"], "melee": ["knife"]}},
	{"id": "raid", "section": "VI. THE BASEMENT", "name": "THE RAID",
		"recap": "Mum and Mira were hiding in the cellar. Then boots on the floor above: soldiers searching every house, every room. Four of them are upstairs.",
		"kit": {"pistol": ["pistol"], "rifle": ["rifle"], "melee": ["knife"]}},
	{"id": "climb_roof", "section": "IX. THE LANDER", "name": "THE LOOKOUT",
		"recap": "Mum is dead. Mira is locked in the cellar, and only Noah or Dad may open the door. Too many soldiers in the streets: Noah needs a high place to see the city.",
		"kit": {"pistol": ["pistol"], "rifle": ["rifle"], "melee": ["knife"]}},
	{"id": "park_fight", "section": "IX. THE LANDER", "name": "THE GUARDS AT THE RAMP",
		"recap": "A landing craft came down in the park. The marksman on the balcony is dead and his LR-9 is Noah's. Ten guards stand at the foot of the ramp.",
		"kit": {"pistol": ["pistol"], "rifle": ["rifle", "sniper"], "melee": ["knife"]}},
	{"id": "escape_lanes", "section": "IX. THE LANDER", "name": "THE LANES",
		"recap": "The guards know where the shots came from. Six of them are coming for Noah, and he knows these alleys better than they do.",
		"kit": {"pistol": ["pistol"], "rifle": ["rifle", "sniper"], "melee": ["knife"]}},
	{"id": "clear_courtyard", "section": "IX. THE LANDER", "name": "THE COURTYARD",
		"recap": "Noah took the stragglers' grenades. The other hunters fell back into a courtyard and stand back to back. A drainpipe climbs to the low roof above them.",
		"kit": {"pistol": ["pistol"], "rifle": ["rifle", "sniper"], "melee": ["knife"], "grenades": 2}},
	{"id": "ship_sneak", "section": "X. THE COMMANDER", "name": "THE COMMANDER",
		"recap": "The ramp stood open and Noah walked in, his right arm torn by a bolt. Somewhere in this ship is the one who gave the order: every house, every room.",
		"kit": {"pistol": ["pistol"], "rifle": [], "melee": ["knife"], "arm": true}},
]


static func get_place(id: String) -> Dictionary:
	for p in PLACES:
		if String(p["id"]) == id:
			return p
	return {}


## Where a standard-kit start puts the player (null: the hooks did, e.g. inside the lander).
static func spot(id: String) -> Variant:
	match id:
		"leave_institute":
			return City.START_POS
		"get_home":
			return City.INSTITUTE_EXIT
		"search_home":
			return City.HOME_POS
		"raid":
			return City.CELLAR_POS
		"climb_roof":
			return CityStory.lookout.get("foot", City.HOME_POS)
		"park_fight", "escape_lanes":
			return City.BALCONY_POS
		"clear_courtyard":
			return CityStory.pipe_foot()
	return null


## The place the running mission's current objective belongs to: the last place at or before it ("" without a mission).
static func current_place() -> String:
	return place_at(Game.mission.index if Game.mission != null else 0)


static func place_at(index: int) -> String:
	var best := String(PLACES[0]["id"])
	var main := Game.player.get_tree().current_scene if Game.player != null and is_instance_valid(Game.player) else null
	for p in PLACES:
		var i: int = main._objective_index(String(p["id"])) if main != null else -1
		if i >= 0 and i <= index:
			best = String(p["id"])
	return best


## The recap of the part of the story the player is in (the objective log's STORY SO FAR).
static func recap_at(index: int) -> Dictionary:
	return get_place(place_at(index))
