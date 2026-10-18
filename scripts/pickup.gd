class_name Pickup
extends Node3D
## Loot lying on the ground: a dropped weapon (picked up with Q, keeps its remaining rounds) or a loose
## magazine (picked up automatically by walking over it). Plain boxes plus a thin glowing beacon.

const MAX_ALIVE := 60
const LIFE_WEAPON := 90.0     # seconds on the ground before a weapon fades away
const LIFE_AMMO := 60.0       # loose magazines go sooner
const WARN_TIME := 8.0        # blinks this long before it disappears

var is_ammo := false
var is_grenade := false     # a frag grenade (weapon_id stays empty)
var weapon_id := ""
var ammo := 0               # weapon: rounds in the gun; magazine: rounds in it
var spare = null            # weapon: Array[int] of spare magazines, or null = a full set
var keep := false           # story loot (the stragglers' grenades): never fades away
var _t := 0.0
var _vis: Node3D


## Lying weapon. `spare` null means a full set of magazines (what enemies carry).
static func spawn_weapon(parent: Node, pos: Vector3, id: String, rounds: int, spare_mags = null) -> Pickup:
	Game.mark("pickup_spawn")
	var p := Pickup.new()
	p.weapon_id = id
	p.ammo = rounds
	p.spare = spare_mags
	return _place(parent, p, pos)


static func spawn_ammo(parent: Node, pos: Vector3, id: String, rounds: int) -> Pickup:
	var p := Pickup.new()
	p.is_ammo = true
	p.weapon_id = id
	p.ammo = rounds
	return _place(parent, p, pos)


## A lying frag grenade; collected automatically like a loose magazine.
static func spawn_grenade(parent: Node, pos: Vector3) -> Pickup:
	var p := Pickup.new()
	p.is_grenade = true
	return _place(parent, p, pos)


static func _place(parent: Node, p: Pickup, pos: Vector3) -> Pickup:
	# loot dropped underground (the cellar) keeps its own height
	p.position = Vector3(pos.x, (pos.y if pos.y < -0.5 else World.height_at(pos.x, pos.z)) + 0.05, pos.z)
	parent.add_child(p)
	return p


func display_name() -> String:
	if is_grenade:
		return "FRAG GRENADE"
	var w: Dictionary = WeaponsDB.WEAPONS[weapon_id]
	return String(w["name"])


## The weapon as the player's loadout stores it.
func make_instance() -> Dictionary:
	return Weapons.new_weapon(weapon_id, ammo, spare)


func _ready() -> void:
	if is_grenade:
		_vis = Node3D.new()
		add_child(_vis)
		var gm := Grenade.build_model()
		gm.scale = Vector3.ONE * 2.2
		_vis.add_child(gm)
		_vis.position.y = 0.3
		_beacon(Color(0.4, 0.9, 0.3), 0.7)
		Game.pickups.append(self)
		while Game.pickups.size() > MAX_ALIVE:
			var oldg = Game.pickups.pop_front()
			if is_instance_valid(oldg):
				oldg.queue_free()
		return
	var w: Dictionary = WeaponsDB.WEAPONS[weapon_id]
	var col: Color = w["color"]
	var glow: Color = w.get("glow", Color(0.85, 0.85, 0.9))
	_vis = Node3D.new()
	add_child(_vis)
	if is_ammo:
		# a magazine: dark body, steel lip, three brass rounds on top, a stripe in the weapon's colour
		_box(_vis, Vector3(0.06, 0.18, 0.1), Vector3(0, 0.0, 0), Color(0.14, 0.14, 0.16), false)
		_box(_vis, Vector3(0.066, 0.02, 0.106), Vector3(0, 0.1, 0), Color(0.55, 0.57, 0.6), false)
		for rx in [-0.018, 0.0, 0.018]:
			_box(_vis, Vector3(0.013, 0.035, 0.013), Vector3(rx, 0.13, 0), Color(0.85, 0.65, 0.2), false)
		_box(_vis, Vector3(0.064, 0.03, 0.104), Vector3(0, -0.04, 0), w.get("glow", Color(0.95, 0.8, 0.35)), true)
		_vis.position.y = 0.25
		_vis.scale = Vector3.ONE * 1.4
		_beacon(Color(0.95, 0.8, 0.35), 0.7)
	else:
		# the real model of the weapon, floating and slowly turning
		var gm := GunModels.build(weapon_id, 1)
		gm.position = Vector3(0, 0.05, 0)
		_vis.add_child(gm)
		_vis.scale = Vector3.ONE * 1.15
		_vis.position.y = 0.3
		_beacon(glow, 1.4)
	Game.pickups.append(self)
	# keep the field from filling up: the oldest loot disappears
	while Game.pickups.size() > MAX_ALIVE:
		var old = Game.pickups.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _exit_tree() -> void:
	Game.pickups.erase(self)


func _process(delta: float) -> void:
	_t += delta
	var life := LIFE_AMMO if (is_ammo or is_grenade) else LIFE_WEAPON
	if keep:
		_t = 0.0
	elif _t >= life:
		queue_free()
		return
	visible = life - _t > WARN_TIME or int(_t * 6.0) % 2 == 0
	_vis.position.y = (0.25 if is_ammo else 0.3) + sin(_t * 2.2) * 0.04
	_vis.rotation.y += delta * 0.9


func take() -> void:
	queue_free()


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## A thin translucent light column so loot can be spotted across the field.
func _beacon(color: Color, height: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.035, height, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.45)
	bm.material = m
	mi.mesh = bm
	mi.position = Vector3(0, height * 0.5, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
