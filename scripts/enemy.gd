class_name Enemy
extends CharacterBody3D
## Enemy: low-poly model from boxes, wanders until the player gets close or shoots, then hunts him.
## One class, several kinds (see KINDS): melee soldier, energy-blade fighter, and ranged units
## (rifleman, heavy gunner, laser marksman). Same kind of physics as the player (gravity, slopes, knockback, stun).

enum State { WANDER, ALERT, CHASE, ATTACK, DEAD, SHOOT, SUSPICIOUS, HOLD, EXHAUSTED }

# ---------- per-kind tuning ----------
# melee kinds: "melee" = [range, damage, windup, cooldown]
# ranged kinds: "engage" max range to start shooting, "prefer" distance they like to hold, "burst" shots per burst,
# "interval" s between shots, "pause" s between bursts, "dmg" per hit, "spread" deg (grows with player speed),
# "strafe" side speed, "charge" > 0 = laser telegraph time before one precise shot, "range" bolt length
const KINDS := {
	"soldier": {
		# conventional rifle with real bullets; clubs you with it when you get too close
		"health": 90.0, "walk": 1.3, "run": 5.2, "sight": 42.0, "fov": 130.0, "give_up": 75.0,
		"melee": [1.9, 13.0, 0.55, 1.0], "scale": 1.0, "weapon": "rifle", "sidearm": true, "grenade": 0.35,
		"engage": 36.0, "prefer": 18.0, "burst": 4, "interval": 0.1, "pause": 1.8, "dmg": 5.0,
		"spread": 2.9, "strafe": 2.4, "charge": 0.0, "range": 80.0, "bolt": Color(0.92, 0.96, 1.0),
	},
	"blade": {   # fast, fragile, plasma-edged blade, no gun
		"health": 65.0, "walk": 1.5, "run": 6.2, "sight": 40.0, "fov": 140.0, "give_up": 80.0,
		"melee": [2.4, 18.0, 0.38, 0.85], "scale": 1.0, "weapon": "blade", "stamina": 130.0,
		"suit": Color(0.07, 0.07, 0.09), "vest": Color(0.12, 0.11, 0.16), "helmet": Color(0.09, 0.08, 0.12),
		"glow": Color(0.78, 0.35, 1.0),
	},
	"rifleman": {   # keeps its distance, strafes, three-round bursts
		"health": 70.0, "walk": 1.3, "run": 5.0, "sight": 50.0, "fov": 130.0, "give_up": 90.0,
		"engage": 40.0, "prefer": 22.0, "burst": 3, "interval": 0.11, "pause": 1.9, "dmg": 5.5,
		"spread": 2.5, "strafe": 3.0, "charge": 0.0, "range": 80.0, "scale": 1.0, "weapon": "carbine", "sidearm": true, "grenade": 0.35,
		"suit": Color(0.16, 0.18, 0.22), "vest": Color(0.1, 0.11, 0.14), "helmet": Color(0.12, 0.13, 0.16),
		"glow": Color(0.25, 0.9, 1.0),
	},
	"gunner": {   # slow armoured heavy with a long suppressing burst
		"health": 190.0, "walk": 1.0, "run": 3.2, "sight": 45.0, "fov": 120.0, "give_up": 90.0,
		"engage": 32.0, "prefer": 16.0, "burst": 8, "interval": 0.09, "pause": 2.1, "dmg": 4.0,
		"spread": 3.8, "strafe": 0.0, "charge": 0.0, "range": 70.0, "scale": 1.18, "weapon": "hmg", "stamina": 70.0, "grenade": 0.6,
		"suit": Color(0.2, 0.2, 0.21), "vest": Color(0.32, 0.26, 0.16), "helmet": Color(0.14, 0.14, 0.15),
		"glow": Color(1.0, 0.55, 0.12),
	},
	"marksman": {   # far sight, red laser telegraph, locks aim before firing: move and it misses
		"health": 55.0, "walk": 1.1, "run": 4.7, "sight": 85.0, "fov": 110.0, "give_up": 140.0,
		"engage": 90.0, "prefer": 60.0, "burst": 1, "interval": 0.0, "pause": 3.2, "dmg": 30.0,
		"spread": 0.0, "strafe": 0.0, "charge": 1.8, "range": 200.0, "scale": 1.0, "weapon": "railgun",
		"suit": Color(0.62, 0.64, 0.68), "vest": Color(0.3, 0.31, 0.34), "helmet": Color(0.8, 0.82, 0.85),
		"glow": Color(1.0, 0.15, 0.12),
	},
}
const RANGED_ARM := -1.45    # arm pitch while aiming (arm horizontal, gun along it)

# ---------- shared tuning ----------
const HEAR_WALK := 11.0           # a walking player is heard this close from any direction (half that through walls)
const HEAR_SPRINT := 20.0
const HEAR_STILL := 6.0           # standing still but not crouched: breathing, shuffling
const HEAR_CROUCH := 0.0          # a crouched player makes no noise: only eyes (front cone) can find him
const TOUCH_RANGE := 1.0          # ...unless he bumps into the soldier
const LOSE_TIME := 4.0            # unseen for this long and the hunt is off: back to wandering
const SEEN_MULT := 1.6            # once alerted, a soldier keeps seeing you (any direction) up to sight_range * this
const REPATH_TIME := 0.7
const ROOF_REACH := 6.0           # the player this far above a hunter and off every nav layer is on a roof nobody follows him to (see _approach_goal)
const LOD_DIST := 150.0           # wanderers farther than this from the player update only every LOD_STEP seconds
const LOD_STEP := 0.2
const ANIM_NEAR := 12.0          # animation update-rate LOD (see _anim_interval): full rate inside this distance...
const ANIM_STEP2 := 35.0         # ...30 Hz from here (and 8 Hz for one the player is not looking at, from ANIM_NEAR)...
const ANIM_MID := 70.0           # ...15 Hz...
const ANIM_FAR := 120.0          # ...8 Hz
static var NO_ARMOUR := OS.get_environment("LETHE_NOARMOUR") != ""           # A/B switch: the invader armour kit (InvaderArmour) off
static var ANIM_LOD_OFF := OS.get_environment("LETHE_NOANIMLOD") != ""      # A/B switch for the perf tools
const ALERT_TIME := 0.6
const GROUP_ALERT_COUNT := 3      # soldiers of one group that must notice the player on their own before the others are told
const KNOCK_DECAY := 6.0
const ROAM_RADIUS := 22.0
## City pass, phase 4: hunters in the back streets give up faster, lone back-street soldiers only shout to their neighbours.
const NARROW_STREET := 6.5        # a street this wide or less counts as narrow (alleys 3 m, side streets 6 m)
const NARROW_SIGHT_SCALE := 0.55  # the chase's alley numbers (ChaseFight): a hunter in a narrow street sees less far...
const NARROW_SEEN_DELAY := 0.7    # ...takes 0.7 s to take in what he sees...
const LOSE_TIME_NARROW := 2.5     # ...and gives up after this long out of sight (LOSE_TIME elsewhere)
const SHOUT_RADIUS := 25.0        # a lone soldier's shout reaches only soldiers this close, with a line to them or a short way round
const SHOUT_PATH_MAX := 35.0
# ---------- stealth: bodies, suspicion, stamina, breathing ----------
const INVADER_RUN := 0.75           # the invaders are heavy under Earth's gravity: every kind runs at 75% of the speed in KINDS...
const INVADER_WALK := 0.9           # ...and walks at 90% (the player sprints at 8 m/s: he can outrun any of them)
const RUN_ANIM_SPEED := 2.2         # above this speed the run clip (played slower: a stomp) and the forward hunch are used
const LEAN_RANGE := 1.8             # a winded soldier shuffles to a wall this close and leans on it
const LEAN_GAP := 0.65              # he stops this far from the wall (body centre)
const BODY_CAP := 60                # dead bodies stay in the world; the oldest go first
const EXHAUSTED_REACT := 2.0        # a gasping soldier sitting against a wall needs this long to react once he notices the player (he can be knifed meanwhile, even from the front)
const EXHAUSTED_STAMINA := 6.0      # his stamina while he sits: he pants loudly, and when he gets up he cannot run for long
const SIT_HIT_SCALE := 0.62         # hit boxes squashed while he sits (static boxes only: clip models' boxes follow the bones)
const TAKEDOWN_STRUGGLE := 0.55     # seconds the victim of a takedown thrashes before the death clip takes him down
const SUSPECT_LOOK_TIME := 8.0      # at the body: looks around this long...
const SUSPECT_SEARCH_TIME := 15.0   # ...then searches nearby points this long, then goes back to wandering
const SUSPECT_FOV_MULT := 1.25      # a suspicious soldier's vision cone is 25% wider
const SUSPECT_SEARCH_RADIUS := 8.0
const DEFAULT_STAMINA := 100.0      # per kind in KINDS ("stamina")
const STAMINA_DRAIN_RUN := 18.0     # per second of running flat out (Earth gravity tires the invaders: about 5.5 s with 100)
const STAMINA_REGAIN_WALK := 8.0
const STAMINA_REGAIN_STAND := 20.0
const STAMINA_REGAIN_JOG := 4.0     # slow jog while recovering
const STAMINA_REGAIN_WINDED := 6.0  # panting
const WINDED_MIN := 3.0
const WINDED_MAX := 5.0
const RECOVER_SPEED := 0.6          # speed multiplier after being winded, until stamina is back above RECOVER_UNTIL
const RECOVER_UNTIL := 40.0
const BREATH_RANGE := 14.0          # his breathing is heard (positional) only this close (the invaders pant even when they only walk)
const IDLE_POSE_STEP := 0.25        # a calm soldier standing still is re-posed only this often (seconds) instead of every physics tick
const IDLE_POSE_STEP_SITTING := 0.1  # ...a sitting one (he heaves) a little more often
const SENSE_STEP := 0.05             # a calm soldier looks and listens 20 times a second (not every physics tick: a ray each adds up)
static var bodies: Array = []       # every dead Enemy / Civilian node still lying around, oldest first (one shared cap)
const CIVILIAN_RANGE := 30.0        # a calm soldier shoots at a civilian he sees this close
const CIVILIAN_SPREAD := 7.0        # degrees: soldiers are bad at hitting running civilians


## Register a dead body (enemy or civilian) and drop the oldest ones above the cap.
static func add_body(n: Node) -> void:
	bodies.append(n)
	while bodies.size() > BODY_CAP:
		var oldest = bodies.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

var kind := "soldier"
var cfg: Dictionary = KINDS["soldier"]
var state := State.WANDER
var health := 100.0
var max_health := 100.0
var walk_speed := 1.5
var run_speed := 6.4
var sight_range := 34.0
var sight_fov := 130.0
var give_up_dist := 75.0
var melee_range := 1.9
var melee_damage := 16.0
var melee_windup := 0.5
var melee_cooldown := 0.9
var ranged := false
var body_scale := 1.0
var player: Player
var home := Vector3.ZERO
var wander_target := Vector3.ZERO
var wait_t := 0.0
var alert_t := 0.0
var attack_t := 0.0
var cooldown := 0.0
var lost_t := 0.0
var stun := 0.0
var knock := Vector3.ZERO
var facing := 0.0                 # yaw
var phase := 0.0
var flinch := 0.0
var stuck_t := 0.0
var side_t := 0.0
var side_dir := 1.0
var step_dist := 0.0
var strike_done := false
var dead_t := 0.0
# hunting memory and navigation
var last_known := Vector3.ZERO    # where he last saw / heard the player
var unseen_t := 0.0               # seconds without seeing the player while hunting
var seen_now := false
var nav_path := PackedVector3Array()
var nav_i := 0
var nav_goal := Vector3.INF
var repath_t := 0.0
var _nav_prog := 0.0          # seconds without getting closer to the current waypoint
var _nav_last_d := 0.0
var _nav_skips := 0
var melee_cd := 0.0               # rifle-butt cooldown for shooters
var lod_acc := 0.0
var group := -1                   # campfire / roaming group id; -1 = alone (nobody shares anything with him)
var uid := -1                     # unique id given by Main (checkpoints refer to enemies by it)
var noticed_self := false         # noticed the player with his own senses (not told by the group)
# ranged state
var burst_left := 0
var shot_t := 0.0
var strafe_t := 0.0
var no_los_t := 0.0
var charging := false
var charge_t := 0.0
var aim_locked := false
var aim_point := Vector3.ZERO
# weapon: infinite magazines, but each magazine runs dry and has to be swapped (what is left when he dies drops with him)
var weapon_id := ""
var mag_size := 0
var ammo := 0
var reloading := false
var reload_left := 0.0
var sidearm_ammo := -1            # >= 0: carries an M9 that drops too
# stealth state
var stamina := DEFAULT_STAMINA
var max_stamina := DEFAULT_STAMINA
var winded_t := 0.0               # > 0: winded (stopped, bent over, cannot shoot, hearing halved)
var lean_wall := Vector3.ZERO     # winded next to a wall: unit direction to it (he leans on it), else ZERO
var lean_dist := INF
var post := false                 # story soldier who stands at his post while calm (no wandering), facing `post_facing`
var post_facing := 0.0
var lazy_alert := 0.0             # extra seconds before he reacts once he notices the player (the grinning lone soldier)
var exh_notice := -1.0            # EXHAUSTED: seconds since he noticed the player (-1 = has not); at EXHAUSTED_REACT he gets up and hunts
var _idle_pose_t := 0.0
var _sense_t := 0.0
var confused := false             # HOLD: a shot came from nowhere he can place: he sweeps his sector and sees the player only close up (12 m) until told where he is
var spin_rifle := false           # idles by spinning his rifle (tests the M4 soldier's pose code)
var recovering := false           # after being winded: 60% speed until stamina is back above RECOVER_UNTIL
var seen_bodies := {}             # instance ids of the bodies that already made him suspicious
var susp_pos := Vector3.ZERO      # the body he investigates
var susp_phase := 0               # 0 walking to the body, 1 looking around, 2 searching nearby
var susp_t := 0.0
var search_target := Vector3.INF
var body_check_t := 0.0
var breath_player: AudioStreamPlayer3D
# squad formation (see Squads): back to back around a rally point
var hold_spot := Vector3.ZERO     # his place in the circle (phase 0/1) or the cover point he runs to (phase 2)
var hold_face := 0.0              # outward facing (yaw)
var hold_sector := TAU            # the arc he watches
var hold_phase := 0               # 0 moving to the spot, 1 holding, 2 scattering to cover
var hold_t := 0.0
var sight_scale := 1.0            # "The Lander" chase: multiplies his sight (shorter in a 3 m alley, see ChaseFight)
var seen_delay := 0.0             # seconds the player must stay in view before a hunting soldier counts him as seen
var _seen_acc := 0.0
var narrow_tuning := false        # city soldiers (not the story roles): the narrow-street hunter numbers above apply to him
var in_narrow := false            # he stands in a narrow street (refreshed 4 times a second while he hunts)
var _narrow_t := 0.0
var _shouted := false
var lone_shout := false           # a lone back-street soldier: when he notices the player he shouts to soldiers within SHOUT_RADIUS (no group alarm)
var patrol: Array = []            # Vector3 waypoints of a loop he walks while calm (empty = wanders round `home`)
var patrol_i := 0
var knows_player := false         # story: he knows exactly where the player is (the balcony marksman once the lookout is over), line of sight or not
var _roof_goal := Vector3.INF     # a hunter's own spot on a ring round a player standing out of reach on a roof (see _approach_goal)
var _roof_t := 0.0
var pace := 1.0                  # multiplies the chase speed (bunching at corners)
var fatigue := 1.0                # multiplies the stamina drain of running (the two stragglers of the chase)
var damage_scale := 1.0           # multiplies the damage he takes
var grenade_drop := -1            # >= 0: he drops exactly this many grenades (the stragglers); -1 = the random drop of his kind
var straggler := false            # a winded straggler can be knifed from behind even though he hunts
var hold_walk_max := 8.0          # HOLD phase 0: seconds he may take to reach his place before he holds where he stands
var civ_target: Civilian = null   # the civilian a calm soldier is shooting at
var civ_scan_t := 0.0

var rig: Node3D
var tilt: Node3D
var head_node: Node3D
var model: CharModel                  # the skinned soldier (see CharModel)
var gun: Node3D                      # the weapon in his hands (grip at its origin)
var hit_root: Node3D                 # hit boxes live here (squashed while the marksman crouches)
var _melee_played := false
var _aim_pose := 0.0
var muzzle: Node3D
var laser: MeshInstance3D
var hitboxes: Array[Area3D] = []
var _anim_iv := 0.0                  # seconds between animation / hit box updates (animation LOD), 0 = every tick
var _sync_acc := 0.0
var _bone_boxes: Array = []       # clip models: {area, bone, local} for every hit box that rides on a bone
var _td_t := 0.0                    # > 0: the victim of a takedown is still struggling; the death clip starts when it runs out
var _td_sign := 1.0                 # +1 pulled back from behind, -1 doubled over a blade from the front
var _rng := RandomNumberGenerator.new()


## Call BEFORE add_child: the physics body must enter the world already at its spawn point
## (changing global_position after add_child reaches the physics server one frame late).
func setup(p: Player, home_pos: Vector3, kind_id: String = "soldier") -> void:
	player = p
	home = home_pos
	position = home_pos
	kind = kind_id if KINDS.has(kind_id) else "soldier"
	cfg = KINDS[kind]
	max_health = cfg["health"]
	health = max_health
	walk_speed = float(cfg["walk"]) * INVADER_WALK
	run_speed = float(cfg["run"]) * INVADER_RUN
	sight_range = cfg["sight"]
	sight_fov = cfg["fov"]
	give_up_dist = cfg["give_up"]
	body_scale = cfg["scale"]
	ranged = cfg.has("engage")
	weapon_id = cfg.get("weapon", "")
	max_stamina = float(cfg.get("stamina", DEFAULT_STAMINA))
	stamina = max_stamina
	mag_size =int(WeaponsDB.WEAPONS[weapon_id]["mag"]) if weapon_id != "" else 0
	ammo = mag_size
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if bool(cfg.get("sidearm", false)) and rng.randf() < 0.5:
		var pm := int(WeaponsDB.WEAPONS["pistol"]["mag"])
		sidearm_ammo = int(round(pm * rng.randf_range(0.4, 1.0)))
	if cfg.has("melee"):
		var m: Array = cfg["melee"]
		melee_range = m[0]
		melee_damage = m[1]
		melee_windup = m[2]
		melee_cooldown = m[3]


func _ready() -> void:
	_rng.randomize()
	collision_layer = Game.L_ENEMY
	collision_mask = Game.L_WORLD | Game.L_ENEMY | Game.L_PLAYER
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.45
	floor_stop_on_slope = true
	max_slides = 5
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75 * body_scale
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	add_child(cs)
	_build_model()
	breath_player = AudioStreamPlayer3D.new()
	breath_player.stream = Sfx.get_sound("breath")
	breath_player.max_distance = BREATH_RANGE + 2.0
	breath_player.unit_size = 3.0
	breath_player.position = Vector3(0, 1.6 * body_scale, 0)
	add_child(breath_player)
	Game.enemies.append(self)
	facing = _rng.randf() * TAU
	_pick_wander_point()
	wait_t = _rng.randf_range(0.5, 3.0)
	Game.gunshot.connect(_on_gunshot)


# ---------------------------------------------------------------- model

func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.95
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(color, glow)
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi


func _limb(parent: Node3D, pivot: Vector3, size: Vector3, color: Color, end_color: Color) -> Node3D:
	var p := Node3D.new()
	p.position = pivot
	parent.add_child(p)
	_box(p, size, Vector3(0, -size.y * 0.5, 0), color)
	_box(p, Vector3(size.x * 1.05, size.y * 0.22, size.z * 1.05), Vector3(0, -size.y * 0.89, 0), end_color)
	return p


func _sphere(parent: Node3D, radius: float, squash: float, pos: Vector3, color: Color, segs: int = 8, rings: int = 5) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0 * squash
	sm.radial_segments = segs
	sm.rings = rings
	sm.material = _mat(color)
	mi.mesh = sm
	mi.position = pos
	parent.add_child(mi)
	return mi


const MODEL_OF := {"soldier": "soldier", "rifleman": "agile", "blade": "agile", "marksman": "marksman", "gunner": "marksman"}
## Dull rust-coloured armour on every kind (the multiplier of the model's own colours); the blade fighter keeps his violet plasma blade (the weapon glow).
const RUST := Color(0.86, 0.46, 0.27)
const TINT := {"soldier": RUST, "rifleman": Color(1.5, 0.88, 0.52), "blade": Color(1.4, 0.8, 0.48), "marksman": Color(1.55, 0.98, 0.62), "gunner": Color(1.25, 0.72, 0.42)}


func _build_model() -> void:
	rig = Node3D.new()
	rig.scale = Vector3.ONE * body_scale
	add_child(rig)
	tilt = Node3D.new()
	rig.add_child(tilt)
	hit_root = Node3D.new()
	rig.add_child(hit_root)
	head_node = Node3D.new()
	head_node.position = Vector3(0, 1.63, 0)
	tilt.add_child(head_node)
	model = CharModel.make(MODEL_OF[kind], 1.75)
	tilt.add_child(model)
	if TINT.has(kind):
		_tint(model.body, TINT[kind])
	if not NO_ARMOUR:
		model.armour = InvaderArmour.build(model, kind)
	# the weapon: our own model (the very mesh that lies on the ground when he dies), grip at the holder's origin
	gun = Node3D.new()
	var gm := GunModels.build(weapon_id, 1)
	gm.position = -GunModels.grip(weapon_id)
	gun.add_child(gm)
	if kind != "blade":
		muzzle = Node3D.new()
		muzzle.position = GunModels.muzzle(weapon_id)
		gm.add_child(muzzle)
	if model.model_id == "soldier":
		tilt.add_child(gun)          # no usable animation: arms and legs are posed from code (_animate_soldier)
		gun.position = Vector3(0.1, 1.15, -0.3)
	else:
		model.hold(gun)
	if kind == "marksman":
		laser = MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.012, 0.012, 1.0)
		lm.material = _mat(cfg.get("glow", Color.WHITE), true)
		laser.mesh = lm
		laser.top_level = true
		laser.visible = false
		laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(laser)
	if model.layer != null:
		# clip models: the hit boxes ride on the bones (head, chest, pelvis, arms, legs), so a shot lands where the body is
		# in the middle of a run, a crouch or a death fall (`_sync_hitboxes` moves them with the animation)
		for spec in model.hit_specs(body_scale):
			_bone_hitbox(spec)
		_sync_hitboxes()
	else:
		# the M4 soldier has no clips: static boxes (squashed by `hit_root` while he sits)
		_hitbox("legs", BoxShape3D.new(), Vector3(0.42, 0.8, 0.32), Vector3(0, 0.4, 0))
		_hitbox("body", BoxShape3D.new(), Vector3(0.7, 0.66, 0.4), Vector3(0, 1.13, 0))
		var sph := SphereShape3D.new()
		sph.radius = 0.17
		_hitbox("head", sph, Vector3.ZERO, Vector3(0, 1.64, 0))


## Multiply every surface colour of a model (blade fighters and gunners reuse the other soldiers' models).
func _tint(root: Node, col: Color) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s) as StandardMaterial3D
			if src == null:
				continue
			var mat := src.duplicate() as StandardMaterial3D
			mat.albedo_color = mat.albedo_color * col
			m.set_surface_override_material(s, mat)

func _hitbox(part: String, shape: Shape3D, size: Vector3, pos: Vector3) -> void:
	var a := Area3D.new()
	a.collision_layer = Game.L_HITBOX
	a.collision_mask = 0
	a.monitoring = false
	a.set_meta("part", part)
	a.set_meta("enemy", self)
	if shape is BoxShape3D and size != Vector3.ZERO:
		(shape as BoxShape3D).size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	a.position = pos
	hit_root.add_child(a)
	hitboxes.append(a)


## A hit box that follows a bone: `spec` comes from `CharModel.hit_specs`. It is top level (world metres, no scale from the rig).
func _bone_hitbox(spec: Dictionary) -> void:
	_hitbox(String(spec["part"]), spec["shape"], Vector3.ZERO, Vector3.ZERO)
	var a: Area3D = hitboxes[hitboxes.size() - 1]
	a.top_level = true
	_bone_boxes.append({"area": a, "bone": int(spec["bone"]), "local": spec["local"]})


## Put every bone-bound hit box where its bone is now. Called after each animation step. A distant soldier (animation LOD) moves
## his boxes at the same slower rate as his bones (11 physics-server moves per soldier per tick are the dearest part of him): the
## error is at most one step of his walk, 0.13 m at 70 m and 0.25 m at 120 m, well inside the aim spread at that range.
func _sync_hitboxes(force := false) -> void:
	if _anim_iv > 0.0 and not force:
		_sync_acc += get_physics_process_delta_time()
		if _sync_acc < _anim_iv:
			return
		_sync_acc = 0.0
	for bb in _bone_boxes:
		(bb["area"] as Area3D).global_transform = model.bone_world(bb["bone"], bb["local"])


# ---------------------------------------------------------------- damage

func take_hit(damage: float, part: String, impulse: Vector3, point: Vector3) -> bool:
	if state == State.DEAD:
		return false
	health -= damage * damage_scale
	_blood(point, impulse)
	knock += Vector3(impulse.x, 0.0, impulse.z) + Vector3(0, minf(impulse.length() * 0.25, 1.5), 0)
	stun = maxf(stun, 0.1 + minf(damage / 250.0, 0.25))
	flinch = 1.0
	if model.layer != null and health > 0.0:       # hit reaction: the bones answer the blow (torso shoved, head whipped, knees give)
		model.layer.flinch(part, model.skeleton.global_transform.basis.inverse() * impulse, 1.0 if part == "head" else clampf(damage / 40.0, 0.45, 1.0))
	if charging:     # a hit throws off the marksman's aim
		_cancel_charge()
		cooldown = maxf(cooldown, 1.2)
	if health <= 0.0:
		_die(impulse)
		return true
	_aggravate(true)
	_alert_group()
	return false


func _aggravate(own: bool = true) -> void:
	if state == State.EXHAUSTED:
		_get_up()
	if state == State.WANDER or state == State.SUSPICIOUS:
		Game.mark("enemy_wake")    # a group waking up is a burst: hurt sound, path requests, shooting all start together
		civ_target = null          # the player comes first: he forgets about civilians
		burst_left = 0
		state = State.ALERT
		alert_t = ALERT_TIME * _rng.randf_range(0.6, 1.2) + lazy_alert
		noticed_self = own
		if player != null:
			last_known = player.global_position
		unseen_t = 0.0
		nav_goal = Vector3.INF
		Sfx.play_at(get_tree().current_scene, global_position + Vector3(0, 1.6, 0), "hurt", -2.0, _rng.randf_range(0.6, 0.8), 70.0)


func _on_gunshot(pos: Vector3, loudness: float) -> void:
	if state == State.EXHAUSTED:
		if exh_notice < 0.0 and global_position.distance_to(pos) < loudness * 0.45:
			exh_notice = 0.5        # he takes it in slowly
		return
	if state != State.WANDER and state != State.SUSPICIOUS:
		return
	if global_position.distance_to(pos) < loudness * 0.45:
		_aggravate(true)
		if loudness >= 100.0:
			last_known = pos          # a blast: he goes to where it went off
		_alert_group()


func _blood(point: Vector3, dir: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 12
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = dir.normalized() if dir.length() > 0.01 else Vector3.UP
	p.spread = 45.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -10, 0)
	var m := BoxMesh.new()
	m.size = Vector3(0.04, 0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.05, 0.05)
	m.material = mat
	p.mesh = m
	p.finished.connect(p.queue_free)
	get_tree().current_scene.add_child(p)
	p.global_position = point


## Fallen soldiers leave their weapon (with the rounds still in it), a couple of loose magazines and sometimes a sidearm.
func _drop_loot() -> void:
	if weapon_id == "":
		return
	var scene := get_tree().current_scene
	var spots: Array[Vector3] = []
	for i in 5:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(0.5, 1.3)
		spots.append(global_position + Vector3(cos(a) * r, 0, sin(a) * r))
	Pickup.spawn_weapon(scene, spots[0], weapon_id, ammo)
	if mag_size > 0:
		for i in 2:
			Pickup.spawn_ammo(scene, spots[1 + i], weapon_id, int(round(mag_size * _rng.randf_range(0.5, 1.0))))
	if sidearm_ammo >= 0:
		Pickup.spawn_weapon(scene, spots[3], "pistol", sidearm_ammo)
	if grenade_drop >= 0:
		for gi in grenade_drop:                    # the stragglers of the chase: guaranteed, and they stay until taken
			var gp := Pickup.spawn_grenade(scene, global_position + Vector3(cos(float(gi) * 2.4), 0, sin(float(gi) * 2.4)) * 0.9)
			gp.keep = true
	elif _rng.randf() < float(cfg.get("grenade", 0.0)):
		Pickup.spawn_grenade(scene, spots[4])      # soldiers and riflemen 35%, gunners 60%


func _die(impulse: Vector3, silent: bool = false) -> void:
	Game.mark("enemy_death")
	state = State.DEAD
	_anim_iv = 0.0
	if model != null:
		model.lod_tick(0.0, 0.0)           # the death clip runs on its own again
	reloading = false
	winded_t = 0.0
	_cancel_charge()
	if breath_player != null:
		breath_player.stop()
	_drop_loot()
	Game.kills += 1
	Game.enemy_killed.emit(self)
	Game.enemies.erase(self)
	civ_target = null
	add_body(self)                      # the body stays (cap BODY_CAP, oldest first) so others can find it
	for h in hitboxes:
		h.queue_free()
	hitboxes.clear()
	_bone_boxes.clear()
	collision_layer = 0
	collision_mask = Game.L_WORLD
	if not silent:
		Sfx.play_at(get_tree().current_scene, global_position + Vector3(0, 1.2, 0), "death", 0.0, _rng.randf_range(0.8, 1.0), 60.0)
	# fall backwards if shot from the front, forwards if shot from behind
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	var flat := Vector3(impulse.x, 0, impulse.z)
	var back := flat.dot(fwd) < 0.0
	gun.visible = false                  # the weapon drops as a pick-up
	if model.has_anim("death"):
		# the clip falls backwards: turn him so his head ends up along the shot
		model.rotation.y = (atan2(flat.x, flat.z) - rig.rotation.y) if flat.length() > 0.1 else 0.0
		if model.player != null:
			model.player.active = true       # a calm far soldier had his animation paused: the death must play
		if _td_t > 0.0:
			model.layer.takedown(1.0, _td_sign)      # a takedown: he struggles first, `_dead_step` starts the fall
		else:
			model.play_once("death", 1.0, 0.12)
	else:
		if model.model_id == "soldier":
			_pose_limp()
		var tw := create_tween().set_parallel(true)
		tw.tween_property(tilt, "rotation:x", (PI * 0.5) if back else (-PI * 0.5), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(tilt, "position:y", 0.12, 0.55)
	knock += Vector3(impulse.x, 0, impulse.z) * 1.5
	dead_t = 0.0


# ---------------------------------------------------------------- AI

## A random walkable spot near home (never inside a building).
func _pick_wander_point() -> void:
	if not patrol.is_empty():
		patrol_i = (patrol_i + 1) % patrol.size()
		wander_target = patrol[patrol_i]
		nav_goal = Vector3.INF
		return
	var p := City.random_point_near(_rng, home, 6.0, ROAM_RADIUS)
	wander_target = p if p != Vector3.INF else home
	nav_goal = Vector3.INF


## Direction (flat, unit) to walk towards `target`: straight when `direct`, else along an A* path around the buildings.
func _nav_dir(target: Vector3, delta: float, direct: bool) -> Vector3:
	var to := target - global_position
	to.y = 0.0
	if direct:
		return to.normalized()
	repath_t -= delta
	if repath_t <= 0.0 or nav_goal == Vector3.INF or nav_goal.distance_to(target) > 5.0:
		repath_t = REPATH_TIME * _rng.randf_range(0.8, 1.3)
		nav_path = City.path(global_position, target)
		nav_i = 0
		nav_goal = target
	while nav_i < nav_path.size():
		var wpv := nav_path[nav_i]
		var wp := wpv - global_position
		wp.y = 0.0
		# doors and stairs need exact waypoints (a rounded corner catches the frame); open ground may cut them
		var reach := 0.4 if (City.near_link(wpv) or City.near_link(global_position)) else 0.9
		if wp.length() < reach:
			nav_i += 1
			_nav_prog = 0.0
		else:
			# no progress towards this waypoint for a second: a door frame or a stair edge has caught him; path again, and skip it the second time
			var d := wp.length()
			if d < _nav_last_d - 0.15 * delta:
				_nav_prog = 0.0
			else:
				_nav_prog += delta
			_nav_last_d = d
			if _nav_prog > 1.0:
				_nav_prog = 0.0
				_nav_skips += 1
				repath_t = 0.0
				if _nav_skips % 2 == 0:
					nav_i += 1
				if is_on_floor():
					velocity.y = 0.0
			return wp.normalized()
	return to.normalized() if to.length() > 0.6 else Vector3.ZERO


## Where a hunter runs. Normally to where the player was last seen. When that spot is up on a roof nobody can climb to (its nav cell is
## the building's footprint, so every hunter used to run to the same corner at the foot of the wall), each hunter takes his own spot on
## a ring 9 - 16 m round the player, one with a clear line up to him, and picks another every few seconds: they spread out and shoot up.
func _approach_goal(delta: float) -> Vector3:
	if last_known.y - global_position.y < ROOF_REACH or City.layer_of(last_known) >= 0:
		_roof_goal = Vector3.INF
		return last_known
	_roof_t -= delta
	if _roof_goal != Vector3.INF and _roof_t > 0.0 and Vector2(_roof_goal.x - last_known.x, _roof_goal.z - last_known.z).length() < 20.0:
		return _roof_goal
	_roof_t = _rng.randf_range(4.0, 8.0)
	var target := last_known + Vector3(0.0, 1.0, 0.0)
	var space := get_world_3d().direct_space_state
	var base := _rng.randf() * TAU
	var best := Vector3.INF
	for i in 10:
		var a := base + float(i) * 0.63
		var p := Vector3(last_known.x + cos(a) * _rng.randf_range(9.0, 16.0), global_position.y, last_known.z + sin(a) * _rng.randf_range(9.0, 16.0))
		if not City.is_free(p):
			continue
		if best == Vector3.INF:
			best = p                      # fallback: a free spot even without a view
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0.0, 1.65, 0.0), target, Game.L_WORLD)).is_empty():
			best = p
			break
	_roof_goal = best if best != Vector3.INF else last_known
	return _roof_goal


func _eye_pos() -> Vector3:
	return global_position + Vector3(0, 1.65 * body_scale, 0)


func _chest() -> Vector3:
	return player.global_position + Vector3(0, 1.2 if player.crouch_k < 0.5 else 0.8, 0)


func _los_to_player() -> bool:
	var q := PhysicsRayQueryParameters3D.create(_eye_pos(), _chest(), Game.L_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _notices_player() -> bool:
	if player == null or Game.dead:
		return false
	var chest := _chest()
	var to := chest - _eye_pos()
	var d := to.length()
	# ears: any direction, but a crouched player is silent and walls halve the range
	var crouched := player.crouch_k > 0.5
	var hear := HEAR_WALK
	var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
	if crouched:
		hear = HEAR_CROUCH
	elif player.is_sprinting():
		hear = HEAR_SPRINT
	elif hspeed < 0.5:
		hear = HEAR_STILL
	hear = maxf(hear, TOUCH_RANGE)
	if winded_t > 0.0 or state == State.EXHAUSTED:
		hear *= 0.5            # panting drowns out the world
	# eyes: only what is in front of him (crouching shortens the distance); a suspicious soldier looks wider
	var sight := sight_range * sight_scale * (0.6 if crouched else 1.0)
	var flat := Vector3(to.x, 0, to.z).normalized()
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	var in_cone := fwd.dot(flat) > cos(deg_to_rad(vision_fov() * 0.5))
	if not ((d < sight and in_cone) or d < hear):
		return false
	var q := PhysicsRayQueryParameters3D.create(_eye_pos(), chest, Game.L_WORLD)
	var clear := get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	if clear:
		return true
	return d < hear * 0.5 and not crouched      # heard through a wall, only when close and not crouched


## While hunting: does he have the player in view right now (clear line, any direction, within range)?
func _sees_player() -> bool:
	if Game.dead:
		return false
	var d := (player.global_position - global_position).length()
	if d > sight_range * sight_scale * SEEN_MULT:
		return false
	return _los_to_player()


## Seconds between animation updates for a soldier `d2` (squared metres) from the player: every frame up close, then 30 / 15 / 8
## Hz with distance; one that is behind the player (out of the view cone) is stepped at 8 Hz from 12 m on.
func _anim_interval(d2: float, in_view: bool) -> float:
	if ANIM_LOD_OFF or d2 < ANIM_NEAR * ANIM_NEAR:
		return 0.0
	if d2 > ANIM_FAR * ANIM_FAR:
		return 0.125
	if d2 > ANIM_MID * ANIM_MID:
		return 0.066
	if d2 > ANIM_STEP2 * ANIM_STEP2:
		return 0.033
	if d2 > 144.0 and not in_view:
		return 0.125
	return 0.0


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_dead_step(delta)
		return
	if player == null:
		return
	_update_breath()
	if model != null and model.player != null and state != State.DEAD:
		# far calm soldiers do not need their skeleton animated
		var d2a := global_position.distance_squared_to(player.global_position)
		var in_view := d2a < 2500.0 and player.camera.is_position_in_frustum(global_position + Vector3(0, 1.0, 0))
		model.player.active = (state != State.WANDER and d2a < 10000.0) or in_view
		_anim_iv = _anim_interval(d2a, in_view)
		model.lod_tick(delta, _anim_iv)
		if not model.armour.is_empty():
			model.show_armour(d2a < InvaderArmour.SHOW_DIST * InvaderArmour.SHOW_DIST * (1.2 if model._armour_shown else 1.0))
	# Far-away wanderers are not worth a full update: about 5 a second, the step scaled up to match (see move_and_slide below)
	var lod_scale := 1.0
	if state == State.WANDER and global_position.distance_squared_to(player.global_position) > LOD_DIST * LOD_DIST:
		lod_acc += delta
		if lod_acc < LOD_STEP:
			return
		delta = lod_acc
		lod_acc = 0.0
		lod_scale = delta * float(Engine.physics_ticks_per_second)
	cooldown = maxf(0.0, cooldown - delta)
	_tick_reload(delta)
	flinch = move_toward(flinch, 0.0, delta * 5.0)
	if model.layer != null:
		model.layer.step(delta)
	knock = knock.move_toward(Vector3.ZERO, KNOCK_DECAY * delta * maxf(1.0, knock.length() * 0.6))

	var want := Vector3.ZERO     # desired horizontal velocity
	var anim_speed := 0.0
	var turn_rate := 7.0
	var to_player := player.global_position - global_position
	var dist := Vector2(to_player.x, to_player.z).length()

	if stun > 0.0:
		stun -= delta
	else:
		match state:
			State.WANDER:
				if _sense_due(delta) and _notices_player():
					_aggravate(true)
					_alert_group()
				elif _check_bodies(delta):
					pass
				elif _civilian_fire(delta):
					pass
				elif post:
					if winded_t <= 0.0:         # (winded he turns to his wall instead, see _stamina_step)
						_face(Vector3(-sin(post_facing), 0, -cos(post_facing)), delta, 2.0)
				elif wait_t > 0.0:
					wait_t -= delta
				else:
					var to_t := wander_target - global_position
					to_t.y = 0
					if to_t.length() < 1.5:
						wait_t = _rng.randf_range(1.5, 5.0)
						_pick_wander_point()
					else:
						var wdir := _nav_dir(wander_target, delta, false)
						if wdir == Vector3.ZERO:      # no way there: pick another spot
							_pick_wander_point()
							wait_t = 0.5
						else:
							want = wdir * walk_speed
							_face(wdir, delta, 3.0)
							anim_speed = walk_speed
							turn_rate = 3.0
			State.ALERT:
				_face(to_player, delta, 10.0)
				alert_t -= delta
				if alert_t <= 0.0:
					state = State.CHASE
					lost_t = 0.0
			State.CHASE:
				# Hunting: run at where he last saw the player (the player himself while in view). Out of sight for
				# LOSE_TIME and the hunt is off: he goes back to wandering where he stands.
				if narrow_tuning:
					_narrow_t -= delta
					if _narrow_t <= 0.0:
						_narrow_t = 0.25
						in_narrow = City.street_width_at(global_position) <= NARROW_STREET
						sight_scale = NARROW_SIGHT_SCALE if in_narrow else 1.0
						seen_delay = NARROW_SEEN_DELAY if in_narrow else 0.0
				seen_now = _sees_player()
				if seen_delay > 0.0:           # slow to take in what he sees (the alleys of the chase: ChaseFight sets this)
					_seen_acc = _seen_acc + delta if seen_now else 0.0
					seen_now = seen_now and _seen_acc >= seen_delay
				if knows_player and not Game.dead:
					seen_now = true
				if seen_now:
					last_known = player.global_position
					unseen_t = 0.0
				else:
					unseen_t += delta
				var goal := _approach_goal(delta)
				var to_goal := goal - global_position
				to_goal.y = 0.0
				var goal_d := to_goal.length()
				var dirv := Vector3.ZERO
				var spd := run_speed * pace
				if not seen_now and goal_d < 2.5:
					# reached the last known spot and nobody is here: look around
					facing += delta * 1.6
					rig.rotation.y = facing
					spd = 0.0
				else:
					dirv = _nav_dir(goal, delta, seen_now and dist < 14.0 and goal == last_known)
					dirv += _separation() * 0.8
					# stuck on something? sidestep around it for a moment
					if side_t > 0.0:
						side_t -= delta
						dirv = dirv.rotated(Vector3.UP, side_dir * 1.2)
					dirv = dirv.normalized()
					if is_on_floor():
						var n := get_floor_normal()
						var nh := Vector3(n.x, 0, n.z)
						if nh.length() > 0.001:
							spd *= clampf(1.0 + dirv.dot(nh.normalized()) * nh.length() * 0.9, 0.6, 1.2)
					_face(to_player if (seen_now and ranged and dist < float(cfg["engage"])) else dirv, delta, 9.0)
				want = dirv * spd
				anim_speed = spd
				if spd > 0.0 and Vector2(velocity.x, velocity.z).length() < run_speed * 0.3 and is_on_floor():
					stuck_t += delta
					if stuck_t > 0.5:
						stuck_t = 0.0
						side_t = 0.7
						side_dir = 1.0 if _rng.randf() < 0.5 else -1.0
				else:
					stuck_t = 0.0
				if seen_now:
					if ranged:
						if dist < float(cfg["engage"]):
							_enter_shoot()
					elif dist < melee_range and absf(to_player.y) < 2.0:
						state = State.ATTACK
						attack_t = 0.0
						strike_done = false
				if unseen_t > (LOSE_TIME_NARROW if in_narrow else LOSE_TIME):
					_give_up_hunt()
			State.ATTACK:
				_face(to_player, delta, 12.0)
				if cooldown <= 0.0:
					attack_t += delta
					if attack_t >= melee_windup and not strike_done:
						strike_done = true
						_strike(dist)
				if strike_done and cooldown <= 0.0:
					cooldown = melee_cooldown
					attack_t = 0.0
					strike_done = false
					if dist > melee_range + 0.8:
						state = State.CHASE
			State.SHOOT:
				var res := _shoot_step(delta, to_player, dist)
				want = res[0]
				anim_speed = res[1]
			State.SUSPICIOUS:
				var sres := _suspicious_step(delta)
				want = sres[0]
				anim_speed = sres[1]
				turn_rate = 4.0
			State.HOLD:
				var hres := _hold_step(delta, to_player, dist)
				want = hres[0]
				anim_speed = hres[1]
			State.EXHAUSTED:
				# sits against a wall, gasping: slow to notice anyone, and once he has, EXHAUSTED_REACT seconds to get up
				if exh_notice < 0.0:
					if _sense_due(delta) and _notices_player():
						exh_notice = 0.0
				else:
					exh_notice += delta
					if exh_notice >= EXHAUSTED_REACT:
						_get_up()
						_aggravate(true)
						_alert_group()
	want = _stamina_step(delta, want)
	if winded_t > 0.0:
		anim_speed = 0.0

	# ---- physics ----
	# A calm soldier standing still on the ground (a guard at his post, a sitter) needs no physics step: move_and_slide is the dearest thing a
	# standing soldier does (two calls per tick against the colliders of the whole city). Whatever moves, falls or is pushed takes the full path.
	var idle_body := want == Vector3.ZERO and stun <= 0.0 and (state == State.WANDER or state == State.EXHAUSTED) and lod_scale <= 1.0 and is_on_floor() \
			and knock.length_squared() < 0.0001 and Vector2(velocity.x, velocity.z).length_squared() < 0.0004
	if idle_body:
		velocity = Vector3.ZERO
	if not idle_body:
		var accel := 16.0 if is_on_floor() else 2.5
		var k := 1.0 - exp(-accel * delta)
		velocity.x = lerpf(velocity.x, want.x + knock.x, k if stun <= 0.0 else 1.0 - exp(-3.0 * delta))
		velocity.z = lerpf(velocity.z, want.z + knock.z, k if stun <= 0.0 else 1.0 - exp(-3.0 * delta))
		if not is_on_floor():
			velocity.y -= Game.GRAVITY * delta
		elif knock.y > 0.0:
			velocity.y = knock.y
			knock.y = 0.0
		else:
			velocity.y = maxf(velocity.y, -1.0)
		if lod_scale > 1.0:
			# the step is longer than one physics tick: scale the horizontal speed so the walk covers the same ground
			var vx := velocity.x
			var vz := velocity.z
			var vy := velocity.y
			velocity.y = maxf(velocity.y * lod_scale, -1.5 * lod_scale)      # falls at most 1.5 m per step: always lands on the ground
			velocity.x *= lod_scale
			velocity.z *= lod_scale
			move_and_slide()
			velocity.x = vx
			velocity.z = vz
			velocity.y = -1.0 if is_on_floor() else vy
			_sync_hitboxes(true)
			return
		move_and_slide()
		move_and_slide()

	# ---- animation / footsteps ----
	if _pose_is_idle(anim_speed):       # a calm soldier standing still cannot change his pose: skeleton posing (IK arms and legs) is the dearest part of him
		_idle_pose_t -= delta
		if _idle_pose_t <= 0.0:
			_idle_pose_t = IDLE_POSE_STEP_SITTING if state == State.EXHAUSTED else IDLE_POSE_STEP
			_animate(_idle_pose_t, anim_speed)
	else:
		_idle_pose_t = 0.0
		_animate(delta, anim_speed)
	if is_on_floor() and anim_speed > 0.5:
		step_dist += Vector2(velocity.x, velocity.z).length() * delta
		if step_dist > (2.6 if state == State.CHASE else 1.2):
			step_dist = 0.0
			if global_position.distance_to(player.global_position) < 45.0:
				Sfx.play_at(get_tree().current_scene, global_position, "step", -8.0, _rng.randf_range(0.8, 1.1), 40.0)


func _face(dir: Vector3, delta: float, rate: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	var target := atan2(-dir.x, -dir.z)
	if absf(angle_difference(facing, target)) < 0.002:
		return          # already looking there: do not touch the rig's transform (that notifies the whole skinned model every tick)
	facing = lerp_angle(facing, target, 1.0 - exp(-rate * delta))
	rig.rotation.y = facing


func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in Game.enemies:
		var o := e as Enemy
		if o == self or o.state == State.DEAD:
			continue
		var d := global_position - o.global_position
		d.y = 0
		var l := d.length()
		if l < 1.6 and l > 0.01:
			push += d / l * (1.6 - l)
	return push


## Soldiers do not share what they know. Only when THREE or more soldiers of the same group (the same campfire, or the same
## roaming group) have noticed the player with their own eyes or ears is the rest of that group told where he is.
## A lone sniper that spots you from far away just starts shooting by itself.
func _alert_group() -> void:
	if group < 0:
		if lone_shout:
			_shout()
		return
	var aware := 0
	for e in Game.enemies:
		var o := e as Enemy
		if o.group == group and o.state != State.WANDER and o.state != State.SUSPICIOUS and o.state != State.DEAD and o.noticed_self:
			aware += 1
	if aware < GROUP_ALERT_COUNT:
		return
	for e in Game.enemies:
		var o2 := e as Enemy
		if o2.group == group and (o2.state == State.WANDER or o2.state == State.SUSPICIOUS):
			o2._aggravate(false)



# ---------------------------------------------------------------- stealth

## Heavy breathing, positional, only while the player is within BREATH_RANGE: faster and louder as stamina drops, loudest winded.
func _update_breath() -> void:
	if breath_player == null:
		return
	var near := state != State.DEAD and global_position.distance_to(player.global_position) < BREATH_RANGE
	if not near:
		if breath_player.playing:
			breath_player.stop()
		return
	var low := 1.0 - clampf(stamina / max_stamina, 0.0, 1.0)
	var winded := winded_t > 0.0
	breath_player.pitch_scale = lerpf(0.85, 1.5, low) + (0.2 if winded else 0.0)
	breath_player.volume_db = lerpf(-15.0, -5.0, low) + (6.0 if winded else 0.0)
	if not breath_player.playing:
		breath_player.play()


## Calm soldiers look and listen SENSE_STEP seconds apart (20 a second instead of 120); each starts at his own offset so they do not all cast on the same tick.
func _sense_due(delta: float) -> bool:
	_sense_t -= delta
	if _sense_t > 0.0:
		return false
	_sense_t = SENSE_STEP + float(absi(uid) % 7) * 0.002
	return true


## His vision cone in degrees: 25% wider while he is suspicious.
func vision_fov() -> float:
	return minf(sight_fov * (SUSPECT_FOV_MULT if state == State.SUSPICIOUS else 1.0), 360.0)


## Stamina bookkeeping. Running flat out drains it, walking and standing refill it; at 0 he is winded for 3-5 s (he stops, bends
## forward, cannot shoot, hears half as far) and afterwards moves at 60% speed until stamina is back above RECOVER_UNTIL.
## Takes the desired velocity, returns the one to use.
func _stamina_step(delta: float, want: Vector3) -> Vector3:
	if state == State.EXHAUSTED:
		stamina = minf(stamina, EXHAUSTED_STAMINA)         # he sits and heaves: no rest gets him back on his feet
		return Vector3.ZERO
	if winded_t > 0.0:
		winded_t -= delta
		stamina = minf(max_stamina, stamina + STAMINA_REGAIN_WINDED * delta)
		if winded_t <= 0.0:
			winded_t = 0.0
			recovering = true
			lean_wall = Vector3.ZERO
		elif lean_wall != Vector3.ZERO:           # he drags himself to the wall, turns to it and props himself against it
			_face(lean_wall, delta, 3.0)
			if lean_dist > LEAN_GAP:
				lean_dist -= 0.7 * delta
				return lean_wall * 0.7
		return Vector3.ZERO
	var spd := Vector2(want.x, want.z).length()
	var cur_max := run_speed * (RECOVER_SPEED if recovering else 1.0)
	if spd > walk_speed * 2.0 and spd > cur_max * 0.75:
		stamina += (STAMINA_REGAIN_JOG if recovering else -STAMINA_DRAIN_RUN * fatigue) * delta
	elif spd > 0.3:
		stamina += STAMINA_REGAIN_WALK * delta
	else:
		stamina += STAMINA_REGAIN_STAND * delta
	stamina = clampf(stamina, 0.0, max_stamina)
	if stamina <= 0.0:
		winded_t = _rng.randf_range(WINDED_MIN, WINDED_MAX)
		burst_left = 0
		_cancel_charge()
		_find_lean_wall()
		return Vector3.ZERO
	if recovering and stamina > RECOVER_UNTIL:
		recovering = false
	return want * RECOVER_SPEED if recovering else want


## The nearest wall within LEAN_RANGE (4 horizontal rays at chest height, once when he becomes winded): `lean_wall` is the unit
## direction to it, `lean_dist` how far away it is. ZERO when he stands in the open.
func _find_lean_wall() -> void:
	lean_wall = Vector3.ZERO
	lean_dist = INF
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.2, 0)
	for k in 4:
		var dir := Vector3(cos(PI * 0.5 * k), 0, sin(PI * 0.5 * k))
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * LEAN_RANGE, Game.L_WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var d := from.distance_to(hit["position"] as Vector3)
			if d < lean_dist:
				lean_dist = d
				lean_wall = dir


## A body he has not seen before, in his cone (wider when suspicious), inside sight range with a clear line: go and look.
## Returns true when suspicion started.
func _check_bodies(delta: float) -> bool:
	body_check_t -= delta
	if body_check_t > 0.0:
		return false
	body_check_t = 0.3
	var fov := vision_fov()
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	var eye := _eye_pos()
	var space := get_world_3d().direct_space_state
	for b in bodies:
		if not is_instance_valid(b) or b == self or not (b is Enemy) or seen_bodies.has(b.get_instance_id()):
			continue
		var target: Vector3 = b.global_position + Vector3(0, 0.3, 0)
		var to := target - eye
		var d := to.length()
		if d > sight_range:
			continue
		var flat := Vector3(to.x, 0, to.z).normalized()
		if fwd.dot(flat) < cos(deg_to_rad(fov * 0.5)):
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, target, Game.L_WORLD)).is_empty():
			continue
		seen_bodies[b.get_instance_id()] = true
		_start_suspicion(b.global_position)
		return true
	return false


func _start_suspicion(at: Vector3) -> void:
	state = State.SUSPICIOUS
	susp_pos = at
	susp_phase = 0
	susp_t = 0.0
	search_target = Vector3.INF
	nav_goal = Vector3.INF
	wait_t = 0.0


## One step of the SUSPICIOUS state: walk to the body, look around for 8 s, search nearby points for 15 s, then wander again.
## Returns [desired velocity, animation speed].
func _suspicious_step(delta: float) -> Array:
	if _notices_player():
		_aggravate(true)
		_alert_group()
		return [Vector3.ZERO, 0.0]
	_check_bodies(delta)          # another new body restarts the investigation (_start_suspicion)
	var flat := susp_pos - global_position
	flat.y = 0.0
	match susp_phase:
		0:
			if flat.length() < 2.2:
				susp_phase = 1
				susp_t = 0.0
				return [Vector3.ZERO, 0.0]
			var dir := _nav_dir(susp_pos, delta, false)
			if dir == Vector3.ZERO:
				susp_phase = 1
				susp_t = 0.0
				return [Vector3.ZERO, 0.0]
			_face(dir, delta, 5.0)
			return [dir * walk_speed * 2.0, walk_speed * 2.0]
		1:
			susp_t += delta
			# sweep his gaze back and forth over the body and the area around it
			facing += cos(susp_t * 1.1) * 1.3 * delta
			rig.rotation.y = facing
			if susp_t >= SUSPECT_LOOK_TIME:
				susp_phase = 2
				susp_t = 0.0
				search_target = Vector3.INF
				wait_t = 0.0
			return [Vector3.ZERO, 0.0]
		_:
			susp_t += delta
			if susp_t >= SUSPECT_SEARCH_TIME:
				_finish_suspicion()
				return [Vector3.ZERO, 0.0]
			if wait_t > 0.0:
				wait_t -= delta
				facing += 0.9 * delta
				rig.rotation.y = facing
				return [Vector3.ZERO, 0.0]
			if search_target == Vector3.INF:
				search_target = City.random_point_near(_rng, susp_pos, 2.0, SUSPECT_SEARCH_RADIUS)
				if search_target == Vector3.INF:
					wait_t = 1.0
					return [Vector3.ZERO, 0.0]
			var to_t := search_target - global_position
			to_t.y = 0.0
			if to_t.length() < 1.3:
				search_target = Vector3.INF
				wait_t = _rng.randf_range(1.0, 2.2)
				return [Vector3.ZERO, 0.0]
			var sdir := _nav_dir(search_target, delta, false)
			if sdir == Vector3.ZERO:
				search_target = Vector3.INF
				return [Vector3.ZERO, 0.0]
			_face(sdir, delta, 4.0)
			return [sdir * walk_speed, walk_speed]


func _finish_suspicion() -> void:
	state = State.WANDER
	home = global_position
	nav_goal = Vector3.INF
	noticed_self = false
	_shouted = false
	_pick_wander_point()
	wait_t = _rng.randf_range(0.5, 2.0)


## How close a SUSPICIOUS soldier is to noticing the player (0 .. 1): nearer and in the open means closer. Used by the HUD eye.
func notice_progress() -> float:
	if state != State.SUSPICIOUS or player == null:
		return 0.0
	var reach := sight_range * SUSPECT_FOV_MULT
	var p := clampf(1.0 - global_position.distance_to(player.global_position) / reach, 0.0, 1.0)
	return p if _los_to_player() else p * 0.5


## A calm (wandering) soldier who sees a civilian within 30 m with a clear line shoots at him: normal bursts, wide spread, no
## Game.gunshot. Never while he knows about the player (the WANDER branch only gets here when `_notices_player` said no).
## Returns true while he is busy with a civilian.
func _civilian_fire(delta: float) -> bool:
	if not ranged or float(cfg["charge"]) > 0.0:
		return false
	civ_scan_t -= delta
	if civ_target != null:
		if not is_instance_valid(civ_target) or civ_target.state == Civilian.State.DEAD or global_position.distance_to(civ_target.global_position) > CIVILIAN_RANGE * 1.3:
			civ_target = null
			burst_left = 0
	if civ_target == null:
		if civ_scan_t > 0.0:
			return false
		civ_scan_t = 0.35
		var best := CIVILIAN_RANGE
		var eye := _eye_pos()
		var space := get_world_3d().direct_space_state
		for c in Game.civilians:
			var cv := c as Civilian
			if not is_instance_valid(cv) or cv.state == Civilian.State.DEAD:
				continue
			var d := global_position.distance_to(cv.global_position)
			if d >= best:
				continue
			if space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, cv.chest_pos(), Game.L_WORLD)).is_empty():
				best = d
				civ_target = cv
		if civ_target == null:
			return false
	var to := civ_target.chest_pos() - _eye_pos()
	_face(to, delta, 8.0)
	var los := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(_eye_pos(), civ_target.chest_pos(), Game.L_WORLD)).is_empty()
	if not los:
		burst_left = 0
		return true
	_shoot_logic(delta, los)
	return true


## Squad order: go to `spot` (his place in the back-to-back circle), face `face` (outward) and watch an arc of `sector`.
func hold_order(spot: Vector3, face: float, sector: float) -> void:
	state = State.HOLD
	hold_spot = spot
	hold_face = face
	hold_sector = sector
	hold_phase = 0
	hold_t = 0.0
	burst_left = 0
	_cancel_charge()
	nav_goal = Vector3.INF
	noticed_self = true


## The formation broke: run to `cover`, then carry on with the normal hunt.
func hold_scatter(cover: Vector3) -> void:
	hold_spot = cover
	hold_phase = 2
	hold_t = 0.0
	nav_goal = Vector3.INF
	burst_left = 0


func _end_hold() -> void:
	state = State.CHASE
	lost_t = 0.0
	unseen_t = 0.0
	last_known = player.global_position
	nav_goal = Vector3.INF


## One step of HOLD. Returns [desired velocity, animation speed].
func _hold_step(delta: float, to_player: Vector3, dist: float) -> Array:
	hold_t += delta
	var flat := hold_spot - global_position
	flat.y = 0.0
	match hold_phase:
		0, 2:
			var limit := 0.5 if hold_phase == 0 else 1.2
			if flat.length() < limit or (hold_phase == 2 and hold_t > 4.0) or (hold_phase == 0 and hold_t > hold_walk_max):
				if hold_phase == 2:
					_end_hold()
				else:
					hold_phase = 1
				return [Vector3.ZERO, 0.0]
			var dir := _nav_dir(hold_spot, delta, false)
			if dir == Vector3.ZERO:
				dir = flat.normalized()
			_face(dir, delta, 8.0)
			return [dir * run_speed, run_speed]
		_:
			# holding: turn slowly inside the sector; shoot (or strike) at anyone in view, never chase
			var los := _los_to_player()
			var seen := los and (dist < 12.0 or (not confused and dist < sight_range * sight_scale * SEEN_MULT))
			melee_cd = maxf(0.0, melee_cd - delta)
			if seen:
				last_known = player.global_position
				_face(to_player, delta, 8.0)
				if ranged:
					if dist < float(cfg["engage"]) * 1.2:
						_shoot_logic(delta, los)
				elif dist < melee_range + 0.3 and melee_cd <= 0.0:
					melee_cd = melee_cooldown
					_strike(dist)
			else:
				var target := hold_face + sin(hold_t * 0.55) * hold_sector * 0.45
				facing = lerp_angle(facing, target, 1.0 - exp(-2.5 * delta))
				rig.rotation.y = facing
			return [Vector3.ZERO, 0.0]


## A silent takedown works on someone who has not noticed the player, from behind (more than 120 degrees off his facing).
func can_be_taken_down(from: Vector3) -> bool:
	if state == State.EXHAUSTED:
		return true             # from any side, even face to face: he gasps and reacts slowly (when he gets up the state changes)
	if straggler and winded_t > 0.0 and state != State.DEAD:
		var tw := from - global_position          # a straggler bent over gasping: the knife from behind works though he hunts
		tw.y = 0.0
		return tw.length() > 0.01 and Vector3(-sin(facing), 0, -cos(facing)).dot(tw.normalized()) < cos(deg_to_rad(100.0))
	if state != State.WANDER and state != State.SUSPICIOUS:
		return false
	if noticed_self:
		return false
	var to := from - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return false
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	return fwd.dot(to.normalized()) < cos(deg_to_rad(120.0))


## Story: a soldier carrying another gun (the balcony marksman's LR-9: it is what he drops). Call BEFORE add_child (the model is built in _ready).
func set_weapon(id: String) -> void:
	weapon_id = id
	mag_size = int(WeaponsDB.WEAPONS[id]["mag"])
	ammo = mag_size


## Nothing about him moves: calm (waiting at a post or sitting), no steps, no flinch, nobody to shoot at, rifle not spinning.
func _pose_is_idle(speed: float) -> bool:
	return (state == State.WANDER or state == State.EXHAUSTED) and speed < 0.2 and not spin_rifle and flinch < 0.01 and winded_t <= 0.0 \
		and civ_target == null and attack_t <= 0.0 and not reloading and stun <= 0.0


## The point the knife aims at (the chest: lower while he sits).
func takedown_point() -> Vector3:
	return global_position + Vector3(0, (0.68 if state == State.EXHAUSTED else 1.1) * body_scale, 0)


## Story soldier: sits on the ground against a wall facing `face` (a yaw), gasping, helmet off (see `remove_helmet`). Call after add_child.
func sit_down(face: float) -> void:
	state = State.EXHAUSTED
	post = true
	post_facing = face
	facing = face
	rig.rotation.y = face
	stamina = EXHAUSTED_STAMINA
	exh_notice = -1.0
	hit_root.scale.y = SIT_HIT_SCALE
	nav_goal = Vector3.INF


## He stands up: back to a normal (slow, short-winded) soldier. His friend, if he is sitting too, notices a second later.
func _get_up() -> void:
	state = State.WANDER
	post = false
	recovering = true
	exh_notice = -1.0
	for e in Game.enemies:
		var o := e as Enemy
		if o != self and o.state == State.EXHAUSTED and o.group == group and o.exh_notice < 0.0 and global_position.distance_to(o.global_position) < 10.0:
			o.exh_notice = EXHAUSTED_REACT - 1.0


## The M4 soldier's helmet is the biggest part of the tan mesh "Object_82": hide it (bare head, goggles stay).
func remove_helmet() -> void:
	var n := model.body.find_child("Object_82", true, false)
	if n != null:
		(n as Node3D).visible = false
	var skin := model.body.find_child("Object_86", true, false) as MeshInstance3D       # the head and hands: not rust-coloured, just tired skin
	if skin != null and skin.mesh != null:
		for s in skin.mesh.get_surface_count():
			var mat := skin.get_surface_override_material(s) as StandardMaterial3D
			if mat != null:
				mat.albedo_color = Color(0.86, 0.66, 0.54)


## Instant, silent kill (no death cry, nobody is alerted). `from` is where the attacker stands: a clip model first
## struggles for TAKEDOWN_STRUGGLE (head yanked back, back arched, arms up, knees giving - or doubled over when the
## attacker is in front of him), then falls with the death clip, toward the attacker.
func takedown(from: Vector3 = Vector3.INF) -> void:
	health = 0.0
	if model.layer != null and model.has_anim("death"):
		_td_t = TAKEDOWN_STRUGGLE
		_td_sign = 1.0
		if from != Vector3.INF:
			var to_att := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
			if Vector3(-sin(facing), 0.0, -cos(facing)).dot(to_att) > 0.0:
				_td_sign = -1.0
	_die(Vector3.ZERO, true)


func _strike(dist: float) -> void:
	Sfx.play_at(get_tree().current_scene, global_position + Vector3(0, 1.3, 0), "swing", -4.0, 1.0 if kind == "soldier" else 1.5, 30.0)
	var to := player.global_position - global_position
	var fwd := Vector3(-sin(facing), 0, -cos(facing))
	var flat := Vector3(to.x, 0, to.z).normalized()
	if dist < melee_range + 0.5 and fwd.dot(flat) > 0.35 and absf(to.y) < 2.2:
		player.take_damage(melee_damage, global_position)
		player.velocity += flat * 3.0


# ---------------------------------------------------------------- ranged attacks

## Hunt called off: wander from where he stands.
func _give_up_hunt() -> void:
	if narrow_tuning:
		in_narrow = false
		sight_scale = 1.0
		seen_delay = 0.0
	if not patrol.is_empty():                     # a patrol picks its loop up again from the nearest corner
		var best := 0
		var best_d := INF
		for pi in patrol.size():
			var dd := global_position.distance_to(patrol[pi])
			if dd < best_d:
				best_d = dd
				best = pi
		patrol_i = best - 1
	state = State.WANDER
	home = global_position
	unseen_t = 0.0
	noticed_self = false
	_shouted = false
	burst_left = 0
	_cancel_charge()
	nav_goal = Vector3.INF
	_pick_wander_point()
	wait_t = _rng.randf_range(0.5, 2.0)


func _enter_shoot() -> void:
	state = State.SHOOT
	burst_left = 0
	shot_t = 0.0
	no_los_t = 0.0
	strafe_t = _rng.randf_range(0.5, 1.5)
	cooldown = maxf(cooldown, _rng.randf_range(0.2, 0.5))      # a moment to raise the weapon
	_cancel_charge()


## One physics step of the SHOOT state. Returns [desired velocity, animation speed].
func _shoot_step(delta: float, to_player: Vector3, dist: float) -> Array:
	var los := _los_to_player()
	_face(to_player, delta, 10.0 if not charging else 14.0)
	seen_now = los
	if los or knows_player:
		last_known = player.global_position
		unseen_t = 0.0
	else:
		unseen_t += delta
	var engage: float = cfg["engage"]
	if dist > engage * 1.2 or unseen_t > 1.0:
		_cancel_charge()
		state = State.CHASE       # CHASE runs to where he was last seen and gives up after LOSE_TIME
		return [Vector3.ZERO, 0.0]
	# shooters with a melee weapon (soldiers) club anyone who gets in their face
	melee_cd = maxf(0.0, melee_cd - delta)
	if cfg.has("melee") and dist < melee_range + 0.3 and melee_cd <= 0.0 and absf(to_player.y) < 2.0 and not charging:
		melee_cd = 1.3
		_strike(dist)

	# movement: hold the preferred distance, strafe if the unit does that
	var dirv := Vector3(to_player.x, 0, to_player.z).normalized()
	var mv := Vector3.ZERO
	var prefer: float = cfg["prefer"]
	if not charging:
		strafe_t -= delta
		if strafe_t <= 0.0:
			strafe_t = _rng.randf_range(1.0, 2.4)
			side_dir = -side_dir if _rng.randf() < 0.7 else side_dir
		if float(cfg["strafe"]) > 0.0:
			mv += dirv.rotated(Vector3.UP, PI * 0.5) * side_dir * float(cfg["strafe"])
		if dist > prefer + 6.0:
			mv += dirv * walk_speed * 2.0
		elif dist < prefer * (0.55 if kind != "marksman" else 0.4):
			mv -= dirv * walk_speed * 2.5
	mv += _separation() * 1.5
	mv.y = 0.0

	_shoot_logic(delta, los)
	return [mv, mv.length()]


func _shoot_logic(delta: float, los: bool) -> void:
	if winded_t > 0.0:
		return          # gasping for air: no shooting
	if float(cfg["charge"]) > 0.0:
		# marksman: laser follows the player, then locks, then fires at where he WAS
		if reloading:
			return
		if not charging:
			if ammo <= 0:
				_start_reload()
			elif cooldown <= 0.0 and los:
				charging = true
				charge_t = 0.0
				aim_locked = false
				aim_point = _chest()
				Sfx.play_at(get_tree().current_scene, muzzle.global_position, "click", 2.0, 0.5, 120.0)
			return
		charge_t += delta
		if charge_t < float(cfg["charge"]) * 0.65:
			aim_point = _chest()
		else:
			aim_locked = true
		_update_laser()
		if charge_t >= float(cfg["charge"]):
			_fire_bolt()
			_cancel_charge()
			cooldown = float(cfg["pause"]) * _rng.randf_range(0.9, 1.3)
		return
	if reloading:
		return
	if burst_left <= 0:
		if ammo <= 0:
			_start_reload()
		elif cooldown <= 0.0 and los:
			burst_left = mini(int(cfg["burst"]), ammo)
			shot_t = 0.25
		return
	shot_t -= delta
	if shot_t <= 0.0:
		_fire_bolt()
		burst_left -= 1
		shot_t = float(cfg["interval"])
		if burst_left <= 0 or ammo <= 0:
			burst_left = 0
			cooldown = float(cfg["pause"]) * _rng.randf_range(0.8, 1.3)
			if ammo <= 0:
				_start_reload()


func _start_reload() -> void:
	if reloading or weapon_id == "" or ammo >= mag_size:
		return
	reloading = true
	reload_left = float(WeaponsDB.WEAPONS[weapon_id]["reload_time"])
	burst_left = 0
	Sfx.play_at(get_tree().current_scene, global_position + Vector3(0, 1.0, 0), "mag_out", -2.0, 0.9, 50.0)


func _tick_reload(delta: float) -> void:
	if not reloading:
		return
	reload_left -= delta
	if reload_left <= 0.0:
		reloading = false
		ammo = mag_size            # infinite magazines: always a fresh full one
		Sfx.play_at(get_tree().current_scene, global_position + Vector3(0, 1.0, 0), "mag_in", -2.0, 0.9, 50.0)


func _cancel_charge() -> void:
	charging = false
	aim_locked = false
	if laser != null and is_instance_valid(laser):
		laser.visible = false


func _update_laser() -> void:
	var from := muzzle.global_position
	var dir := (aim_point - from).normalized()
	var end := from + dir * float(cfg["range"])
	var q := PhysicsRayQueryParameters3D.create(from, end, Game.L_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		end = hit["position"]
	var len := from.distance_to(end)
	if len < 0.5:
		laser.visible = false
		return
	laser.visible = true
	(laser.mesh as BoxMesh).size = Vector3(0.012 if not aim_locked else 0.03, 0.012 if not aim_locked else 0.03, len)
	laser.global_position = from + dir * len * 0.5
	laser.look_at(end, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)


func _fire_bolt() -> void:
	ammo = maxi(0, ammo - 1)
	var from := muzzle.global_position
	var target := _chest()
	var spread := 0.0
	var at_civilian := civ_target != null and is_instance_valid(civ_target) and state == State.WANDER
	if at_civilian:
		target = civ_target.chest_pos()
		spread = deg_to_rad(CIVILIAN_SPREAD)
	elif float(cfg["charge"]) > 0.0:
		target = aim_point
	else:
		var hspeed := Vector2(player.velocity.x, player.velocity.z).length()
		spread = deg_to_rad(float(cfg["spread"])) * (1.0 + hspeed * 0.12)
	var dir := (target - from).normalized()
	if spread > 0.0:
		var ax := dir.cross(Vector3.UP)
		ax = ax.normalized() if ax.length() > 0.01 else Vector3.RIGHT
		var ay := ax.cross(dir)
		var rot := _rng.randf() * TAU
		var ang := spread * sqrt(_rng.randf())
		dir = (dir + (ax * cos(rot) + ay * sin(rot)) * tan(ang)).normalized()
	var end := from + dir * float(cfg["range"])
	var q := PhysicsRayQueryParameters3D.create(from, end, Game.L_WORLD | Game.L_PLAYER | (Game.L_HITBOX if at_civilian else 0))
	q.collide_with_areas = at_civilian
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		end = hit["position"]
		var col: Object = hit["collider"]
		if col == player:
			player.take_damage(float(cfg["dmg"]), global_position)
		elif col is Area3D and (col as Area3D).has_meta("civilian"):
			var victim: Civilian = (col as Area3D).get_meta("owner_civ")
			if is_instance_valid(victim):
				victim.take_hit(float(cfg["dmg"]) * 2.0, String((col as Area3D).get_meta("part")), (end - from).normalized() * 3.0, end)
	_bolt(from, end)
	if model.layer != null:
		model.layer.kick(1.0)
	if not at_civilian:
		Game.enemy_fired.emit(self)
	var wd: Dictionary = WeaponsDB.WEAPONS[weapon_id]
	Sfx.play_at(get_tree().current_scene, from, String(wd.get("sound", weapon_id)), 0.0, float(wd.get("sound_pitch", 1.0)) * _rng.randf_range(0.95, 1.05), 140.0)


## Visible energy bolt: a short glowing streak that flies from the muzzle to the impact point.
func _bolt(from: Vector3, to: Vector3) -> void:
	var len := from.distance_to(to)
	if len < 0.5:
		return
	var glow: Color = cfg.get("glow", cfg.get("bolt", Color(1.0, 0.85, 0.45)))
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var seg := minf(len, 4.0)
	bm.size = Vector3(0.05, 0.05, seg)
	bm.material = _mat(glow, true)
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	var dir := (to - from).normalized()
	mi.global_position = from + dir * seg * 0.5
	mi.look_at(to, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	var travel := maxf(0.0, len - seg)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", from + dir * (travel + seg * 0.5), clampf(len / 160.0, 0.05, 0.5))
	tw.tween_callback(mi.queue_free)


# ---------------------------------------------------------------- animation

func _animate(delta: float, speed: float) -> void:
	var aiming := state == State.SHOOT or (state == State.HOLD and hold_phase == 1 and ranged) or (state == State.WANDER and civ_target != null and ranged)
	if model.model_id == "soldier":
		_animate_soldier(delta, speed, aiming)
	else:
		_animate_clips(delta, speed, aiming)
	var cross := model.model_id != "soldier"
	# clip models answer a hit through the bones (PoseLayer); the soldier without clips tips his whole body
	tilt.rotation.x = (0.16 if speed > RUN_ANIM_SPEED and cross else (0.24 if speed > RUN_ANIM_SPEED else 0.0)) - (flinch * 0.25 if model.layer == null else 0.0)
	hit_root.scale.y = lerpf(hit_root.scale.y, SIT_HIT_SCALE if state == State.EXHAUSTED else (0.74 if (kind == "marksman" and _aim_pose > 0.5) else 1.0), 1.0 - exp(-10.0 * delta))
	if state == State.EXHAUSTED:
		tilt.rotation.x = 0.1 + sin(Time.get_ticks_msec() * 0.011) * 0.035      # heaving, shoulders against the wall
	if winded_t > 0.0:
		# bent double, heaving (bend about the hips: the torso tips forward, the legs are turned back so they stay upright)
		var a := (-1.0 if lean_wall != Vector3.ZERO and lean_dist <= LEAN_GAP + 0.05 else -0.85) + sin(Time.get_ticks_msec() * 0.012) * 0.05
		tilt.rotation.x = a
		tilt.position = Vector3(0.0, 0.86 * (1.0 - cos(a)), -0.86 * sin(a))
	else:
		tilt.position.z = 0.0
	_sync_hitboxes()


## Clip-driven soldiers (agile futuristic model, marksman model): pick the clip that fits what he is doing.
func _animate_clips(delta: float, speed: float, aiming: bool) -> void:
	var moving := speed > 0.2
	var local := Basis(Vector3.UP, facing).inverse() * velocity       # forward is -z, right is +x
	_aim_pose = 0.0
	if state != State.ATTACK:
		_melee_played = false
	if winded_t > 0.0:
		model.play("idle_plain" if model.has_anim("idle_plain") else "idle", 0.4)
	elif reloading and model.has_anim("reload"):
		model.play("reload", model.clip_length("reload") / maxf(reload_left + 0.4, 0.5))
	elif state == State.ATTACK and model.has_anim("melee"):
		if not _melee_played:
			_melee_played = true
			model.play_once("melee", model.clip_length("melee") / maxf(melee_windup + 0.15, 0.3))
	elif state == State.ATTACK:
		model.play("idle")
	elif charging or (kind == "marksman" and state == State.SHOOT):
		_aim_pose = 1.0
		model.play("aim" if model.has_anim("aim") else "idle", 1.0)
	elif aiming and moving and model.has_anim("strafe_r") and absf(local.x) > absf(local.z) * 0.8:
		model.play("strafe_r" if local.x > 0.0 else "strafe_l", clampf(speed / 3.0, 0.7, 1.4))
	elif aiming and moving and local.z > 0.5 and model.has_anim("back"):
		model.play("back", clampf(speed / 3.0, 0.7, 1.4))
	elif aiming and moving and model.has_anim("run_shoot"):
		model.play("run_shoot", clampf(speed / 5.0, 0.7, 1.3))
	elif aiming and burst_left > 0 and model.has_anim("shoot"):
		model.play("shoot", 1.0)
	elif speed > RUN_ANIM_SPEED:
		model.play("run", clampf(speed / 4.8, 0.7, 1.4))
	elif moving:
		model.play("walk", clampf(speed / 1.3, 0.7, 1.8))
	else:
		model.play("idle", 1.0)


## The M4 soldier has one frozen pose and no animations: legs swing from the phase, the hands follow the rifle (two-bone IK).
func _animate_soldier(delta: float, speed: float, aiming: bool) -> void:
	var m := model
	var u := m.unit()
	var run := speed > RUN_ANIM_SPEED
	phase += delta * speed * (1.5 if run else 2.6)
	var amp := 0.9 if run else 0.5
	if speed < 0.2:
		amp = 0.0
		phase = lerpf(phase, 0.0, 0.1)
	m.reset_pose()
	var s := sin(phase)
	m.leg_pose("L", s * amp * 0.9, maxf(0.0, cos(phase)) * amp * 1.1)
	m.leg_pose("R", -s * amp * 0.9, maxf(0.0, -cos(phase)) * amp * 1.1)
	var hips := m.bone("hips")
	var hrest := m.skeleton.get_bone_rest(hips)
	m.skeleton.set_bone_pose_position(hips, hrest.origin + Vector3(0.0, absf(s) * 0.03 * u * amp * 2.0, 0.0))
	if state == State.EXHAUSTED:          # sits on the ground: legs stretched out in front, hips on the floor
		m.leg_pose("L", 1.46, 0.12)
		m.leg_pose("R", 1.36, 0.2)
		m.skeleton.set_bone_pose_position(hips, hrest.origin + Vector3(0.0, -0.72 * u, 0.0))
	# where the rifle is held: across the chest / at the shoulder / low while reloading / swung as a club
	var gp := Vector3(0.12, 1.12, -0.28)
	var gr := Vector3(-0.45, 0.0, 0.0)
	if spin_rifle and state == State.WANDER:          # idly tosses the rifle and spins it (every 1.7 s, 0.7 s of it in the air)
		var cyc := fmod(Time.get_ticks_msec() * 0.001 + float(uid) * 0.37, 1.7)
		if cyc > 1.0:
			var k2 := (cyc - 1.0) / 0.7
			gp.y += sin(k2 * PI) * 0.18
			gr.x = -0.45 + k2 * TAU
	if state == State.ALERT:
		gp = Vector3(0.1, 1.5, -0.3)
		gr = Vector3(-1.3, 0.0, 0.0)
	if aiming:
		gp = Vector3(0.09, 1.43, -0.3)
		gr = Vector3(0.0, 0.0, 0.0)
	if reloading:
		gp = Vector3(0.1, 1.0, -0.3)
		gr = Vector3(-1.0, 0.0, sin(Time.get_ticks_msec() * 0.012) * 0.1)
	if state == State.ATTACK:
		var k := clampf(attack_t / melee_windup, 0.0, 1.0)
		if strike_done:
			gp = Vector3(0.0, 1.1, -0.65)
			gr = Vector3(0.3, 0.4, 0.0)
		else:
			gp = Vector3(0.25, lerpf(1.2, 1.7, k), lerpf(-0.3, 0.1, k))
			gr = Vector3(lerpf(0.0, 1.8, k), 0.0, 0.0)
	if winded_t > 0.0:
		gp = Vector3(0.12, 0.7, -0.15)
		gr = Vector3(-1.2, 0.0, 0.0)
	if state == State.EXHAUSTED:          # the rifle across his knees
		gp = Vector3(0.1, 0.38, -0.3)
		gr = Vector3(-1.0, 0.0, 0.0)
	var kk := 1.0 - exp(-14.0 * delta)
	gun.position = gun.position.lerp(gp, kk)
	gun.rotation = gun.rotation.lerp(gr, kk)
	_aim_pose = 1.0 if aiming else 0.0
	var hand_r := m.skeleton.to_local(gun.global_position)
	var hand_l := m.skeleton.to_local(gun.to_global(Vector3(0.0, -0.05, -0.3)))
	m.ik_arm("R", hand_r, Vector3(-0.6, -1.0, -0.4))
	m.ik_arm("L", hand_l, Vector3(0.6, -1.0, -0.4))


## A dead soldier's arms hang down at his sides.
func _pose_limp() -> void:
	var m := model
	m.ik_arm("R", m.skeleton.to_local(tilt.to_global(Vector3(0.28, 0.75, 0.0))), Vector3(-0.3, -1.0, 0.5))
	m.ik_arm("L", m.skeleton.to_local(tilt.to_global(Vector3(-0.28, 0.75, 0.0))), Vector3(0.3, -1.0, 0.5))

func _dead_step(delta: float) -> void:
	if model.layer != null:
		model.layer.step(delta)
		if _td_t > 0.0:
			_td_t -= delta
			if _td_t <= 0.0:
				model.layer.takedown(0.0)
				model.play_once("death", 1.0, 0.18)
	knock = knock.move_toward(Vector3.ZERO, 5.0 * delta)
	velocity.x = knock.x
	velocity.z = knock.z
	if not is_on_floor():
		velocity.y -= Game.GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	dead_t += delta
	if dead_t > 3.0 and knock.length() < 0.05 and is_on_floor():
		model.stop()
		set_physics_process(false)         # settled: a body costs nothing from now on


func _exit_tree() -> void:
	bodies.erase(self)


## A lone back-street soldier who noticed the player calls out: only soldiers within SHOUT_RADIUS hear it, and only with a clear line to him
## or a short way round (SHOUT_PATH_MAX). No group alarm: that still needs three aware soldiers of one group.
func _shout() -> void:
	if _shouted:
		return
	_shouted = true
	var space := get_world_3d().direct_space_state
	for e in Game.enemies:
		var o := e as Enemy
		if o == self or not is_instance_valid(o) or (o.state != State.WANDER and o.state != State.SUSPICIOUS):
			continue
		if global_position.distance_to(o.global_position) > SHOUT_RADIUS:
			continue
		var heard := false
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.6, 0), o.global_position + Vector3(0, 1.6, 0), Game.L_WORLD)
		if space.intersect_ray(q).is_empty():
			heard = true
		elif AiBudget.path():
			var pts := City.path(global_position, o.global_position)
			var len := 0.0
			var prev := global_position
			for pt in pts:
				len += prev.distance_to(pt)
				prev = pt
			heard = not pts.is_empty() and len <= SHOUT_PATH_MAX
		if heard:
			o._aggravate(false)
