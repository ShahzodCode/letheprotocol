extends Node3D
## Builds the field, the player, the HUD and the enemies. `-- --selftest` runs the scripted checks in tests/selftest.gd.

const ENEMY_COUNT := 4
const RESPAWN_DELAY := 25.0

var world: World
var player: Player
var hud: HUD
var _respawns: Array[float] = []


func _ready() -> void:
	Game.reset_stats()
	world = World.new()
	add_child(world)
	world.build()

	player = Player.new()
	player.position = Vector3(0, World.height_at(0, 0) + 0.1, 0)
	add_child(player)

	hud = HUD.new()
	add_child(hud)
	hud.setup(player)

	for i in ENEMY_COUNT:
		_spawn_enemy(i)
	Game.enemy_killed.connect(_on_enemy_killed)

	var args := OS.get_cmdline_user_args()
	if "--selftest" in args or "--shots" in args:
		var t = load("res://tests/selftest.gd" if "--selftest" in args else "res://tests/screenshots.gd").new()
		add_child(t)
		t.run(self)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Enemies start far away, each in a different direction, and wander around their spot.
func _spawn_enemy(index: int) -> Enemy:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var base := TAU * float(index) / float(ENEMY_COUNT) + rng.randf_range(-0.4, 0.4)
	var r := rng.randf_range(75.0, 115.0)
	return _spawn_enemy_at(Vector3(cos(base) * r, 0, sin(base) * r))


func _spawn_enemy_at(p: Vector3) -> Enemy:
	var lim := World.HALF - 14.0
	p.x = clampf(p.x, -lim, lim)
	p.z = clampf(p.z, -lim, lim)
	p.y = World.height_at(p.x, p.z) + 0.3
	var e := Enemy.new()
	e.setup(player, p)
	add_child(e)
	return e


func _on_enemy_killed(_e) -> void:
	_respawns.append(RESPAWN_DELAY)


func _process(delta: float) -> void:
	if Game.dead:
		return
	for i in range(_respawns.size() - 1, -1, -1):
		_respawns[i] -= delta
		if _respawns[i] <= 0.0:
			_respawns.remove_at(i)
			# come back from the far edge, away from where the player is standing
			var a := randf() * TAU
			for tries in 6:
				var cand := Vector3(cos(a) * 110.0, 0, sin(a) * 110.0)
				if cand.distance_to(player.global_position) > 70.0:
					break
				a += 1.0
			_spawn_enemy_at(Vector3(cos(a) * 110.0, 0, sin(a) * 110.0))
