class_name CharModel
extends Node3D
## A skinned character from models/chars/*: people pack (civilians, one outfit each), the two Mixamo-style futuristic
## soldiers (marksman / agile) and the M4 soldier (no usable animation: its pose is driven from code, see `pose_soldier`).
## All imported models face +z; `pivot` turns them to face -z like everything else in the game (Godot forward).
## Logical animation names (idle, walk, run, aim, shoot, crouch, crouch_walk, reload, melee, death, hit, strafe_l, strafe_r)
## map to each model's own clips; `has_anim()` tells whether a model has a clip for a name.

const DEFS := {
	"people": {
		"path": "res://models/chars/people.fbx", "height": 1.86, "foot": 0.0, "hand": "Wrist.R", "head": "Head", "hips": "Hips",
		"anims": {
			"idle": "Idle_Neutral", "walk": "Walk", "run": "Run", "hit": "HitRecieve", "hit2": "HitRecieve_2", "death": "Death",
			"wave": "Wave", "roll": "Roll", "interact": "Interact",
		},
		"loop": ["idle", "walk", "run", "wave"],
	},
	"marksman": {
		"path": "res://models/chars/marksman.glb", "height": 3.058, "foot": 0.0, "hand": "mixamorig_RightHand_15", "head": "mixamorig_Head_1",
		"hips": "mixamorig_Hips_34", "hide": ["Object_33"], "gun_mesh": "Object_33", "new_clips": true,
		"anims": {"idle": "Rifle_stand", "walk": "Walk", "run": "Rifle_run", "aim": "Rifle_crouch", "crouch": "Crouch", "idle_plain": "Idle", "run_plain": "Run"},
		"loop": ["idle", "walk", "run", "aim", "crouch", "idle_plain", "run_plain"],
	},
	"agile": {
		"path": "res://models/chars/agile.glb", "height": 0.0935, "foot": -0.003, "hand": "Bind_RightHand_037_038", "head": "Bind_Head_014_015",
		"hips": "Bind_Hips_03_00", "hide": ["Object_10"], "gun_mesh": "Object_10", "new_clips": true,
		"anims": {
			"idle": "idleWgun", "walk": "walk", "run": "run", "aim": "shooting", "shoot": "rapidShooting", "run_shoot": "runAndShooting",
			"strafe_l": "strafeLeft", "strafe_r": "strafeRight", "back": "backpaddle", "crouch": "crouch", "crouch_walk": "crouchWalk",
			"reload": "reload", "melee": "melee", "death": "death", "look": "walkAndLook", "idle_plain": "idleWithoutGun",
		},
		"loop": ["idle", "walk", "run", "aim", "shoot", "run_shoot", "strafe_l", "strafe_r", "back", "crouch", "crouch_walk", "look", "idle_plain"],
	},
	"soldier": {
		"path": "res://models/chars/soldier.glb", "height": 3118.0, "foot": -9.5, "hand": "hand.R_027", "head": "head_09",
		"hips": "hips_01", "hide": ["Object_78", "Object_80"], "rebind": true, "anims": {}, "loop": [], "new_clips": true,
	},
}

static var _bad_names := ["Backpack", "Sword", "Pistol", "Horse_Head"]

## Bone roles of the two Mixamo-style rigs (the name's second "_" word: "Bind_Hips_03_00", "mixamorig_Hips_34").
const ROLES := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "HeadTop", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm",
	"RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]

## The hit boxes that follow the skeleton (clip models). Each runs from the bone `from` to the bone `to` (the `to` bone of the
## head is the top of the skull; the agile rig has none, so the head box sits a head's height above the bone), stretched by
## `ext_a` / `ext_b` metres at the ends. Widths and depths are metres for a 1.75 m body (multiplied by the enemy's scale).
## `part` is what the weapons see (damage: head x head_mult, legs x0.75, body and arms x1).
const HIT_PARTS := [
	# id, part, shape, from, to, ext_a, ext_b, width, depth
	["head", "head", "sphere", "Head", "HeadTop", 0.0, 0.0, 0.17, 0.17],
	["chest", "body", "box", "Spine", "Neck", 0.0, 0.06, 0.40, 0.26],
	["pelvis", "body", "box", "Hips", "Spine", 0.14, 0.0, 0.34, 0.24],
	["arm_l", "arms", "capsule", "LeftArm", "LeftForeArm", 0.05, 0.03, 0.12, 0.0],
	["arm_r", "arms", "capsule", "RightArm", "RightForeArm", 0.05, 0.03, 0.12, 0.0],
	["fore_l", "arms", "capsule", "LeftForeArm", "LeftHand", 0.02, 0.10, 0.10, 0.0],
	["fore_r", "arms", "capsule", "RightForeArm", "RightHand", 0.02, 0.10, 0.10, 0.0],
	["thigh_l", "legs", "capsule", "LeftUpLeg", "LeftLeg", 0.0, 0.0, 0.17, 0.0],
	["thigh_r", "legs", "capsule", "RightUpLeg", "RightLeg", 0.0, 0.0, 0.17, 0.0],
	["shin_l", "legs", "capsule", "LeftLeg", "LeftFoot", 0.0, 0.10, 0.14, 0.0],
	["shin_r", "legs", "capsule", "RightLeg", "RightFoot", 0.0, 0.10, 0.14, 0.0],
]

## Clips that cycle with a stride: switching between them keeps the phase (no foot slide, no restart pop).
const GAITS := ["walk", "run", "crouch_walk", "run_shoot", "strafe_l", "strafe_r", "back", "back_aim", "look"]
## Clips that must start at once and are never held back by the anti-flicker hold.
const URGENT := ["death", "melee", "reload", "hit", "hit2"]
const HOLD_TICKS := 24            # a clip stays at least this many physics ticks (0.2 s at 120) before a non-urgent change

var model_id := ""
var def: Dictionary
var body: Node3D
var pivot: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var hand_node: BoneAttachment3D
var head_node: BoneAttachment3D
var current := ""
var anim_speed := 1.0
var clip_of := {}            # logical name -> full clip name in the player
var frozen := false
var _lod_manual := false     # the player is stepped by hand (see lod_tick)
var _lod_acc := 0.0
var pose_t := 0.0            # soldier: procedural phase
var pose_state := {}
var layer: PoseLayer         # agile / marksman: flinch, recoil and takedown pose on top of the clips
var roles := {}              # role -> bone index (see ROLES)
var _started_tick := 0       # physics tick the current clip was started


## outfit: people only ("Adventurer", "Farmer", ...). height: metres.
static func make(id: String, height: float = 1.75, outfit: String = "", legacy: bool = false) -> CharModel:
	var c := CharModel.new()
	c.build(id, height, outfit, legacy)
	return c


## The clips of models/anims, copied onto the rig by AnimRetarget the first time a model of the rig is built (they are kept in the rig's animation
## library). Logical name -> [file, flatten]: they replace the rig's own idle / run and add the aim, run-up and death clips. `flatten`: no travel
## along the ground (the run-up speed and the fall's slide are done by the physics, see Enemy). `legacy` builds keep the rig's own clips only.
const NEW_CLIPS := {
	"idle": ["Rifle Idle", false], "run": ["Rifle Run", false], "aim_hold": ["Rifle Aiming Idle", false],
	"aim_up": ["Rifle Down To Aim", false], "aim_down": ["Rifle Aim To Down", false], "start_run": ["Idle To Running", true],
	"death": ["Walking To Dying", true], "die_run": ["Rifle Run To Dying", true],
	"back": ["Backwards Rifle Walk", false], "back_aim": ["Crouch Walk Backward Aiming", false],
}
const NEW_LOOP := ["idle", "run", "aim_hold", "back", "back_aim"]
var new_clips := false           # this model plays the clips above (its "death" falls forward, the way he faces)


func build(id: String, height: float = 1.75, outfit: String = "", legacy: bool = false) -> void:
	model_id = id
	def = DEFS[id]
	pivot = Node3D.new()
	pivot.rotation.y = PI
	add_child(pivot)
	var scene := load(String(def["path"])) as PackedScene
	body = scene.instantiate() as Node3D
	pivot.add_child(body)
	var s := height / float(def["height"])
	body.scale = Vector3.ONE * s
	body.position.y = -float(def["foot"]) * s
	skeleton = body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	if id == "people":
		_pick_outfit(outfit)
	for nm in def.get("hide", []):
		var n := body.find_child(String(nm), true, false)
		if n != null:
			(n as Node3D).visible = false
	if bool(def.get("rebind", false)):
		_rebind_skins()
	var pl := body.find_children("*", "AnimationPlayer", true, false)
	if not pl.is_empty():
		player = pl[0] as AnimationPlayer
	elif bool(def.get("new_clips", false)) and not legacy:
		player = AnimationPlayer.new()          # the M4 soldier has none of its own: it plays the clips of models/anims (and some borrowed)
		body.add_child(player)
	if player != null:
		_map_clips()
		if bool(def.get("new_clips", false)) and not legacy:
			_add_new_clips()
	hand_node = BoneAttachment3D.new()
	hand_node.bone_name = String(def["hand"])
	skeleton.add_child(hand_node)
	head_node = BoneAttachment3D.new()
	head_node.bone_name = String(def["head"])
	skeleton.add_child(head_node)
	if player != null and (id == "agile" or id == "marksman" or (id == "soldier" and new_clips)):
		_find_roles()
		layer = PoseLayer.new()
		layer.roles = roles
		skeleton.add_child(layer)


func _find_roles() -> void:
	for i in skeleton.get_bone_count():
		var nm := skeleton.get_bone_name(i)
		var role := AnimRetarget.role_of(nm, true) if model_id == "soldier" else (nm.split("_")[1] if nm.split("_").size() > 1 else "")
		if ROLES.has(role) and not roles.has(role):
			roles[role] = i


func _pick_outfit(outfit: String) -> void:
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		var keep := nm.begins_with(outfit + "_") and not _bad_names.has(nm)
		if not keep:
			mi.get_parent().remove_child(mi)
			mi.queue_free()


## The M4 soldier is exported with its skeleton in the "Standing" pose and its skin scaled 19.5x: take the true T-pose bind
## transforms from the skin (inverse of each bind pose with the scale removed), make that the skeleton's rest pose and
## bind every mesh to it. The soldier is then posed from code relative to a clean T-pose (see Enemy._animate_soldier).
func _rebind_skins() -> void:
	var first: Skin = null
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin != null:
			first = (mi as MeshInstance3D).skin
			break
	if first == null:
		return
	var bind_global := {}
	for j in first.get_bind_count():
		var bi := skeleton.find_bone(first.get_bind_name(j)) if first.get_bind_name(j) != "" else first.get_bind_bone(j)
		var p := first.get_bind_pose(j)
		bind_global[bi] = Transform3D(p.basis.orthonormalized(), p.origin).affine_inverse()
	for i in skeleton.get_bone_count():
		if not bind_global.has(i):
			continue
		var parent := skeleton.get_bone_parent(i)
		var pg: Transform3D = skeleton.get_bone_global_rest(parent) if parent >= 0 else Transform3D.IDENTITY
		skeleton.set_bone_rest(i, pg.affine_inverse() * (bind_global[i] as Transform3D))
	skeleton.reset_bone_poses()
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.skin == null:
			continue
		var old := m.skin
		var sk := Skin.new()
		sk.set_bind_count(old.get_bind_count())
		for j in old.get_bind_count():
			var bi := skeleton.find_bone(old.get_bind_name(j)) if old.get_bind_name(j) != "" else old.get_bind_bone(j)
			sk.set_bind_bone(j, bi)
			sk.set_bind_pose(j, skeleton.get_bone_global_rest(bi).affine_inverse())
		m.skin = sk

func _map_clips() -> void:
	var loops: Array = def.get("loop", [])
	var lib: Dictionary = {}
	for full in player.get_animation_list():
		var short := String(full).get_slice("|", String(full).get_slice_count("|") - 1)
		lib[short] = full
	var anims: Dictionary = def["anims"]
	for logical in anims:
		var short := String(anims[logical])
		if lib.has(short):
			clip_of[logical] = lib[short]
			var a := player.get_animation(lib[short])
			a.loop_mode = Animation.LOOP_LINEAR if loops.has(logical) else Animation.LOOP_NONE


## Clips the M4 soldier borrows from the other rigs (it has none of its own and models/anims has no walk, reload, melee, shots or strafes):
## logical name -> [rig, clip]. Retargeted like the others.
const BORROWED := {"walk": ["agile", "walk"], "reload": ["agile", "reload"], "melee": ["agile", "melee"], "shoot": ["agile", "rapidShooting"],
	"strafe_l": ["agile", "strafeLeft"], "strafe_r": ["agile", "strafeRight"]}
const BORROWED_LOOP := ["walk", "shoot", "strafe_l", "strafe_r"]


func _add_borrowed(lib: AnimationLibrary, prefix: String) -> void:
	var rigs := {}                  # rig -> its model instance (made once, freed at the end)
	for logical in BORROWED:
		var key := "lp_" + String(logical)
		if not lib.has_animation(key):
			var info: Array = BORROWED[logical]
			if not rigs.has(info[0]):
				rigs[info[0]] = (load(String(DEFS[info[0]]["path"])) as PackedScene).instantiate() as Node3D
			var src_root: Node3D = rigs[info[0]]
			var sks := src_root.find_children("*", "Skeleton3D", true, false)
			var aps := src_root.find_children("*", "AnimationPlayer", true, false)
			if not sks.is_empty() and not aps.is_empty():
				var ap := aps[0] as AnimationPlayer
				for full in ap.get_animation_list():
					if String(full).get_slice("|", String(full).get_slice_count("|") - 1) == String(info[1]):
						lib.add_animation(key, AnimRetarget.retarget(ap.get_animation(full), sks[0] as Skeleton3D, src_root, skeleton, body, prefix, true, false, false))
						break
		if lib.has_animation(key):
			lib.get_animation(key).loop_mode = Animation.LOOP_LINEAR if BORROWED_LOOP.has(logical) else Animation.LOOP_NONE
			clip_of[logical] = key
	for r in rigs.values():
		(r as Node).free()


func _add_new_clips() -> void:
	if not player.has_animation_library(&""):
		player.add_animation_library(&"", AnimationLibrary.new())
	var lib := player.get_animation_library(&"")
	var prefix := String(player.get_node(player.root_node).get_path_to(skeleton))
	for logical in NEW_CLIPS:
		var key := "lp_" + String(logical)
		if not lib.has_animation(key):
			var info: Array = NEW_CLIPS[logical]
			var ps := load("res://models/anims/%s.fbx" % info[0]) as PackedScene
			if ps == null:
				continue
			var src_root := ps.instantiate() as Node3D
			var sks := src_root.find_children("*", "Skeleton3D", true, false)
			var aps := src_root.find_children("*", "AnimationPlayer", true, false)
			if not sks.is_empty() and not aps.is_empty():
				var ap := aps[0] as AnimationPlayer
				var names := ap.get_animation_list()
				if not names.is_empty():
					lib.add_animation(key, AnimRetarget.retarget(ap.get_animation(names[0]), sks[0] as Skeleton3D, src_root, skeleton, body, prefix,
							model_id == "soldier", false, bool(info[1])))
			src_root.free()
		if lib.has_animation(key):
			lib.get_animation(key).loop_mode = Animation.LOOP_LINEAR if NEW_LOOP.has(logical) else Animation.LOOP_NONE
			clip_of[logical] = key
			new_clips = true
	if model_id == "soldier":
		_add_borrowed(lib, prefix)


func has_anim(logical: String) -> bool:
	return clip_of.has(logical)


func clip_length(logical: String) -> float:
	return player.get_animation(clip_of[logical]).length if has_anim(logical) else 0.0


## How long the cross-fade from clip `from` into clip `to` lasts: fast into a shot or a blow, slower between gaits and
## into / out of standing still.
func blend_time(from: String, to: String) -> float:
	if to == "melee" or to == "death":
		return 0.06
	if to == "shoot" or from == "shoot":
		return 0.1
	if GAITS.has(from) and GAITS.has(to):
		return 0.28
	if to == "aim" or from == "aim":
		return 0.16
	if to == "reload" or from == "reload":
		return 0.18
	return 0.3


## Plays a logical clip (no-op when already playing it). `speed` scales the playback. `blend` < 0: `blend_time`.
## A change is held back until the current clip has played HOLD_TICKS (so aim / shoot / run do not flicker when the state
## wobbles); a stride clip handed over to another stride clip carries its phase along.
func play(logical: String, speed: float = 1.0, blend: float = -1.0) -> void:
	if player == null or not has_anim(logical):
		return
	if current != logical:
		var tick := Engine.get_physics_frames()
		if current != "" and not URGENT.has(logical) and not URGENT.has(current) and tick - _started_tick < HOLD_TICKS:
			return
		var phase := -1.0
		if GAITS.has(current) and GAITS.has(logical) and player.current_animation != "":
			var old_len := player.current_animation_length
			if old_len > 0.0:
				phase = fmod(player.current_animation_position / old_len, 1.0)
		var b := blend_time(current, logical) if blend < 0.0 else blend
		current = logical
		_started_tick = tick
		player.play(clip_of[logical], b)
		if phase >= 0.0:
			player.seek(phase * clip_length(logical), false)
	player.speed_scale = speed
	anim_speed = speed


func play_once(logical: String, speed: float = 1.0, blend: float = 0.05) -> void:
	if player == null or not has_anim(logical):
		return
	current = logical
	_started_tick = Engine.get_physics_frames()
	player.play(clip_of[logical], blend)
	player.speed_scale = speed


## Animation update-rate LOD. `interval` <= 0: the AnimationPlayer runs on its own every frame. Above 0 it is stepped by hand
## once per `interval` seconds, handed all the time that went by in one advance (a distant soldier's blend tree + skeleton pose
## then costs a fraction; the clips cross-fade and loop as before, they just move in bigger steps).
func lod_tick(delta: float, interval: float) -> void:
	if player == null:
		return
	if interval <= 0.0:
		if _lod_manual:
			_lod_manual = false
			_lod_acc = 0.0
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		return
	if not _lod_manual:
		_lod_manual = true
		_lod_acc = interval
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_lod_acc += delta
	if _lod_acc >= interval:
		var dt := _lod_acc
		_lod_acc = 0.0
		if player.active:
			player.advance(dt)


func seek_end(logical: String) -> void:
	if player == null or not has_anim(logical):
		return
	current = logical
	player.play(clip_of[logical], 0.0)
	player.seek(clip_length(logical), true)
	player.pause()


func stop() -> void:
	if player != null:
		player.pause()
	frozen = true


# ---------------------------------------------------------------- landmarks for add-on parts (InvaderArmour)

const ANCHOR_ROLES := {"hips": "Hips", "chest": "Spine2", "neck": "Neck", "head": "Head", "headtop": "HeadTop", "arm_l": "LeftArm", "arm_r": "RightArm", "fore_l": "LeftForeArm",
	"fore_r": "RightForeArm", "hand_l": "LeftHand", "hand_r": "RightHand"}
const ANCHOR_SOLDIER := {"hips": "hips", "chest": "chest", "neck": "neck", "head": "head", "arm_l": "arm.L", "arm_r": "arm.R", "fore_l": "forearm.L",
	"fore_r": "forearm.R", "hand_l": "hand.L", "hand_r": "hand.R"}
var armour: Array = []      # MeshInstance3Ds of the invader armour kit (InvaderArmour), shown / hidden by distance
var _armour_shown := true


## Bone of a landmark ("chest", "head", "arm_l", "fore_r", ...) on any of the rigs; -1 when it has none.
func anchor_bone(a: String) -> int:
	if not (ANCHOR_ROLES.has(a) and (model_id != "soldier" or ANCHOR_SOLDIER.has(a))):
		return -1
	if model_id == "soldier":
		return bone(ANCHOR_SOLDIER[a])
	return roles.get(ANCHOR_ROLES[a], -1)


## Metres per skeleton unit at the fitted size (the model at scale 1: independent of the enemy's body scale).
func rest_k() -> float:
	return (global_transform.affine_inverse() * skeleton.global_transform).basis.get_scale().x


## Where a landmark sits in the rest pose, in metres in the model's frame (+x left, +y up, +z forward).
func anchor_pos(a: String) -> Vector3:
	return skeleton.get_bone_global_rest(anchor_bone(a)).origin * rest_k()


func show_armour(v: bool) -> void:
	if v == _armour_shown:
		return
	_armour_shown = v
	for ba in armour:
		(ba as Node3D).visible = v


# ---------------------------------------------------------------- hit boxes on the bones

## One entry per HIT_PARTS row whose bones exist: {id, part, shape, bone, local}. `bs` is the body scale of the enemy;
## shapes are in world metres. Needs the model inside the scene tree (the fitted scale is read from the skeleton).
## `local` is the box's transform in the `bone`'s rest frame: `bone_world()` carries it along with the animation.
func hit_specs(bs: float) -> Array:
	var out := []
	var k := skeleton.global_transform.basis.get_scale().x       # metres per skeleton unit
	var u := 1.0 / k
	for sp in HIT_PARTS:
		var ai: int = roles.get(sp[3], -1)
		if ai < 0:
			continue
		var ga := skeleton.get_bone_global_rest(ai)
		var a := ga.origin
		var bi: int = roles.get(sp[4], -1)
		var b := skeleton.get_bone_global_rest(bi).origin if bi >= 0 else a + Vector3.UP * 0.26 * bs * u
		var dir := (b - a).normalized()
		var a2 := a - dir * float(sp[5]) * bs * u
		var b2 := b + dir * float(sp[6]) * bs * u
		var len_m := a2.distance_to(b2) * k
		var zr := Vector3.BACK - dir * Vector3.BACK.dot(dir)
		zr = zr.normalized() if zr.length() > 0.2 else Vector3.RIGHT
		var xa := dir.cross(zr).normalized()
		var rest := Transform3D(Basis(xa, dir, xa.cross(dir)), (a2 + b2) * 0.5)
		var w := float(sp[7]) * bs
		var shape: Shape3D
		match String(sp[2]):
			"sphere":
				var s := SphereShape3D.new()
				s.radius = w
				shape = s
			"box":
				var bx := BoxShape3D.new()
				bx.size = Vector3(w, len_m, float(sp[8]) * bs)
				shape = bx
			_:
				var cp := CapsuleShape3D.new()
				cp.radius = w * 0.5
				cp.height = maxf(len_m, cp.radius * 2.0 + 0.02)
				shape = cp
		out.append({"id": sp[0], "part": sp[1], "shape": shape, "bone": ai, "local": ga.affine_inverse() * rest})
	return out


## A hit box's place in the world now (unscaled, so it can be given to a node of scale 1).
func bone_world(bone: int, local: Transform3D) -> Transform3D:
	var t := skeleton.global_transform * skeleton.get_bone_global_pose(bone) * local
	t.basis = t.basis.orthonormalized()
	return t


## Attach a node (a gun) to the right hand; returns the attachment holder.
func add_to_hand(n: Node3D) -> void:
	hand_node.add_child(n)


# ---------------------------------------------------------------- holding a weapon

static var _fit := {}        # model id -> Transform3D (hand-bone space) where the held weapon's grip sits

## Where a weapon's GRIP sits in the right hand (hand-bone space, basis scaled from metres to skeleton units), worked out
## from the gun that is built into the model (it is hidden; our own weapon model takes its place, so what a soldier holds is
## the same mesh that lies on the ground and sits in the HUD). Needs the model inside the scene tree.
func hand_fit() -> Transform3D:
	if _fit.has(model_id):
		return _fit[model_id]
	var mi := body.find_child(String(def["gun_mesh"]), true, false) as MeshInstance3D
	var te := skeleton.global_transform.affine_inverse() * mi.global_transform
	var bb := mi.get_aabb()
	var ax := 0
	for k in 3:
		if bb.size[k] > bb.size[ax]:
			ax = k
	var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var f: Vector3 = (te.basis * axes[ax]).normalized()
	if f.z < 0.0:
		f = -f                                  # barrel toward the model's front (+z in skeleton space)
	var right: Vector3 = f.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(f).normalized()
	var upm := global_transform.basis.get_scale().x / hand_node.global_transform.basis.get_scale().x   # skeleton units per metre
	var centre := te * bb.get_center()
	var grip_at := centre - f * 0.17 * upm + up * 0.01 * upm
	var hand := skeleton.get_bone_global_rest(skeleton.find_bone(String(def["hand"])))
	var rel := hand.affine_inverse() * Transform3D(Basis(right, up, -f), grip_at)
	rel.basis = rel.basis.scaled_local(Vector3.ONE * upm)
	_fit[model_id] = rel
	return rel


## Put a weapon node (grip at its origin) into the right hand.
func hold(n: Node3D) -> void:
	n.transform = hand_fit_m4() if model_id == "soldier" else hand_fit()
	hand_node.add_child(n)


## Where the rifle's grip sits in the M4 soldier's hand. The M4 has no gun of its own that fits (its rest is a T-pose), so the grip of the marksman
## rig (printed by tests/hand_fit_probe.gd: rotation and origin in metres, in the hand bone's frame) is carried over: the two hands' frames differ
## by the turns `AnimRetarget.frame_turn` gives against the Mixamo clips' hand, so the grip is turned by those. Needs the model inside the tree.
const MARKSMAN_GRIP_Q := Quaternion(0.45634, 0.48265, -0.52510, 0.53205)
const MARKSMAN_GRIP_O := Vector3(0.05671, 0.15245, 0.04326)
static var _fit_m4 := Transform3D.IDENTITY
static var _fit_m4_ready := false


func hand_fit_m4() -> Transform3D:
	if _fit_m4_ready:
		return _fit_m4
	var mk := (load(String(DEFS["marksman"]["path"])) as PackedScene).instantiate() as Node3D
	var mx := (load("res://models/anims/Rifle Idle.fbx") as PackedScene).instantiate() as Node3D
	var mk_sk := mk.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var mx_sk := mx.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var c_mk := AnimRetarget.frame_turn(mx_sk, mx, mk_sk, mk, "RightHand", false)
	var c_m4 := AnimRetarget.frame_turn(mx_sk, mx, skeleton, body, "RightHand", true)
	mk.free()
	mx.free()
	var rot := c_m4.inverse() * c_mk * MARKSMAN_GRIP_Q
	var org := c_m4.inverse() * (c_mk * MARKSMAN_GRIP_O)
	var upm := global_transform.basis.get_scale().x / hand_node.global_transform.basis.get_scale().x
	_fit_m4 = Transform3D(Basis(rot).scaled_local(Vector3.ONE * upm), org * upm)
	_fit_m4_ready = true
	return _fit_m4
# ---------------------------------------------------------------- procedural pose (M4 soldier)

var _bones := {}

## Bone index for the soldier rig (names carry numeric suffixes: "arm.R" finds "arm.R_025", "leg.R" not "upleg.R_038").
func bone(prefix: String) -> int:
	if _bones.has(prefix):
		return _bones[prefix]
	var found := -1
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i)
		if n == prefix or n.begins_with(prefix + "_"):
			found = i
			break
	_bones[prefix] = found
	return found


## Skeleton units per metre of the fitted model (the soldier's skeleton is thousands of units tall).
func unit() -> float:
	return float(def["height"]) / 1.75


## Set a bone's rotation as an offset from its rest, in the bone's parent space, from euler angles.
func rot(prefix: String, e: Vector3) -> void:
	var i := bone(prefix)
	if i < 0:
		return
	var rest := skeleton.get_bone_rest(i)
	skeleton.set_bone_pose_rotation(i, rest.basis.get_rotation_quaternion() * Quaternion.from_euler(e))


## Turn bone `b` so the line from its joint to child `c` points along `dir` (skeleton space). Parents must be posed first.
func point_bone(b: int, c: int, dir: Vector3) -> void:
	if b < 0 or c < 0 or dir.length() < 0.0001:
		return
	var rb := skeleton.get_bone_global_rest(b)
	var rc := skeleton.get_bone_global_rest(c)
	var rest_dir := (rc.origin - rb.origin).normalized()
	var g := Basis(Quaternion(rest_dir, dir.normalized())) * rb.basis.orthonormalized()
	var parent := skeleton.get_bone_parent(b)
	var pb := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(b, (pb.inverse() * g).get_rotation_quaternion())


## Two-bone arm solve (soldier rig): the hand reaches `target` (skeleton space), the elbow bends toward `pole`.
func ik_arm(side: String, target: Vector3, pole: Vector3) -> void:
	var a := bone("arm." + side)
	var f := bone("forearm." + side)
	var h := bone("hand." + side)
	if a < 0 or f < 0 or h < 0:
		return
	var l1 := (skeleton.get_bone_global_rest(f).origin - skeleton.get_bone_global_rest(a).origin).length()
	var l2 := (skeleton.get_bone_global_rest(h).origin - skeleton.get_bone_global_rest(f).origin).length()
	var s_pos := skeleton.get_bone_global_pose(a).origin
	var to := target - s_pos
	var d := clampf(to.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := to.normalized()
	var cosa := (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)
	var ang := acos(clampf(cosa, -1.0, 1.0))
	var side_v := pole - dir * pole.dot(dir)
	side_v = side_v.normalized() if side_v.length() > 0.001 else Vector3.DOWN
	var elbow := s_pos + (dir * cos(ang) + side_v * sin(ang)) * l1
	point_bone(a, f, elbow - s_pos)
	point_bone(f, h, s_pos + dir * d - elbow)


## One leg of a walk / run cycle (soldier rig): thigh swings by `swing` radians, the knee bends by `knee`.
func leg_pose(side: String, swing: float, knee: float) -> void:
	var u := bone("upleg." + side)
	var l := bone("leg." + side)
	var f := bone("foot." + side)
	var t := bone("toe." + side)
	point_bone(u, l, Vector3(0.0, -cos(swing), sin(swing)))
	var shin := swing - knee
	point_bone(l, f, Vector3(0.0, -cos(shin), sin(shin)))
	point_bone(f, t, Vector3(0.0, -0.3, 1.0))


## Back to the rest pose of every bone.
func reset_pose() -> void:
	skeleton.reset_bone_poses()
