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
		"hips": "mixamorig_Hips_34", "hide": ["Object_33"], "gun_mesh": "Object_33",
		"anims": {"idle": "Rifle_stand", "walk": "Walk", "run": "Rifle_run", "aim": "Rifle_crouch", "crouch": "Crouch", "idle_plain": "Idle", "run_plain": "Run"},
		"loop": ["idle", "walk", "run", "aim", "crouch", "idle_plain", "run_plain"],
	},
	"agile": {
		"path": "res://models/chars/agile.glb", "height": 0.0935, "foot": -0.003, "hand": "Bind_RightHand_037_038", "head": "Bind_Head_014_015",
		"hips": "Bind_Hips_03_00", "hide": ["Object_10"], "gun_mesh": "Object_10",
		"anims": {
			"idle": "idleWgun", "walk": "walk", "run": "run", "aim": "shooting", "shoot": "rapidShooting", "run_shoot": "runAndShooting",
			"strafe_l": "strafeLeft", "strafe_r": "strafeRight", "back": "backpaddle", "crouch": "crouch", "crouch_walk": "crouchWalk",
			"reload": "reload", "melee": "melee", "death": "death", "look": "walkAndLook", "idle_plain": "idleWithoutGun",
		},
		"loop": ["idle", "walk", "run", "aim", "shoot", "run_shoot", "strafe_l", "strafe_r", "back", "crouch", "crouch_walk", "look", "idle_plain"],
	},
	"soldier": {
		"path": "res://models/chars/soldier.glb", "height": 3118.0, "foot": -9.5, "hand": "hand.R_027", "head": "head_09",
		"hips": "hips_01", "hide": ["Object_78", "Object_80"], "rebind": true, "anims": {}, "loop": [],
	},
}

static var _bad_names := ["Backpack", "Sword", "Pistol", "Horse_Head"]

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
var pose_t := 0.0            # soldier: procedural phase
var pose_state := {}


## outfit: people only ("Adventurer", "Farmer", ...). height: metres.
static func make(id: String, height: float = 1.75, outfit: String = "") -> CharModel:
	var c := CharModel.new()
	c.build(id, height, outfit)
	return c


func build(id: String, height: float = 1.75, outfit: String = "") -> void:
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
		_map_clips()
	hand_node = BoneAttachment3D.new()
	hand_node.bone_name = String(def["hand"])
	skeleton.add_child(hand_node)
	head_node = BoneAttachment3D.new()
	head_node.bone_name = String(def["head"])
	skeleton.add_child(head_node)


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


func has_anim(logical: String) -> bool:
	return clip_of.has(logical)


func clip_length(logical: String) -> float:
	return player.get_animation(clip_of[logical]).length if has_anim(logical) else 0.0


## Plays a logical clip (no-op when already playing it). `speed` scales the playback.
func play(logical: String, speed: float = 1.0, blend: float = 0.2) -> void:
	if player == null or not has_anim(logical):
		return
	if current != logical:
		current = logical
		player.play(clip_of[logical], blend)
	player.speed_scale = speed
	anim_speed = speed


func play_once(logical: String, speed: float = 1.0, blend: float = 0.05) -> void:
	if player == null or not has_anim(logical):
		return
	current = logical
	player.play(clip_of[logical], blend)
	player.speed_scale = speed


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
	n.transform = hand_fit()
	hand_node.add_child(n)
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
