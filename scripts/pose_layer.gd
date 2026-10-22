class_name PoseLayer
extends SkeletonModifier3D
## Procedural layer on top of the clips of a CharModel (runs after the AnimationPlayer has posed the skeleton): the hit
## reaction (flinch), the shot's recoil and the victim's side of a silent takedown. Everything is rotated about axes of the
## SKELETON space (up = +y, the model faces +z), so the same numbers work on every rig. The enemy sets the values, the
## layer eases them in and out. `roles` maps a role ("Hips", "Spine", "Neck", "LeftArm", ...) to a bone index.

const ATTACK := 40.0          # how fast a new flinch / recoil snaps in (per second)
const FLINCH_DECAY := 4.5     # a flinch is gone after about 0.3 s
const RECOIL_DECAY := 14.0
const TD_RELEASE := 8.0       # the takedown pose lets go this fast when the death clip takes over

var roles := {}
var _flinch := 0.0            # target 0..1
var _flinch_shown := 0.0
var _flinch_part := "body"
var _flinch_dir := Vector3.BACK       # skeleton space, flat: where the blow pushes him
var _recoil := 0.0
var _recoil_shown := 0.0
var _td := 0.0                # takedown struggle 0..1 (target)
var _td_shown := 0.0
var _td_sign := 1.0           # +1 pulled back from behind, -1 doubled over a blade from the front


## A hit from skeleton-space direction `dir` (the way the bullet flies). `part` is the hit box part, `power` 0..1.
func flinch(part: String, dir: Vector3, power: float = 1.0) -> void:
	var d := Vector3(dir.x, 0.0, dir.z)
	_flinch_dir = d.normalized() if d.length() > 0.01 else Vector3.BACK
	_flinch_part = part
	_flinch = clampf(power, 0.0, 1.0)
	if _flinch_shown < 0.15:
		_flinch_shown = _flinch * 0.25      # starts to move at once instead of waiting for the ease-in


func kick(power: float = 1.0) -> void:
	_recoil = clampf(power, 0.0, 1.0)


func takedown(k: float, sign_: float = 1.0) -> void:
	_td = clampf(k, 0.0, 1.0)
	_td_sign = sign_


func is_idle() -> bool:
	return _flinch < 0.002 and _flinch_shown < 0.002 and _recoil < 0.002 and _recoil_shown < 0.002 and _td < 0.002 and _td_shown < 0.002


func flinch_amount() -> float:
	return _flinch_shown


## Called by the enemy once per physics tick.
func step(delta: float) -> void:
	_flinch = move_toward(_flinch, 0.0, FLINCH_DECAY * delta)
	_recoil = move_toward(_recoil, 0.0, RECOIL_DECAY * delta)
	_flinch_shown = lerpf(_flinch_shown, _flinch, 1.0 - exp(-ATTACK * delta))
	_recoil_shown = lerpf(_recoil_shown, _recoil, 1.0 - exp(-ATTACK * delta))
	_td_shown = lerpf(_td_shown, _td, 1.0 - exp(-(10.0 if _td > _td_shown else TD_RELEASE) * delta))
	if _flinch < 0.002 and _flinch_shown < 0.002:
		_flinch_shown = 0.0
	if _recoil < 0.002 and _recoil_shown < 0.002:
		_recoil_shown = 0.0
	if _td < 0.002 and _td_shown < 0.002:
		_td_shown = 0.0


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or (_flinch_shown <= 0.0 and _recoil_shown <= 0.0 and _td_shown <= 0.0):
		return
	if _td_shown > 0.0:
		_apply_takedown(sk, _td_shown)
	if _flinch_shown > 0.0:
		_apply_flinch(sk, _flinch_shown)
	if _recoil_shown > 0.0:
		# the weapon kicks the shoulders back and the head up
		var back := Vector3.UP.cross(Vector3.FORWARD)          # tips the top toward -z, away from the way he faces
		_turn(sk, "Spine1", back, 0.05 * _recoil_shown)
		_turn(sk, "Spine2", back, 0.05 * _recoil_shown)
		_turn(sk, "Head", back, -0.03 * _recoil_shown)         # the head stays on the target


## Flinch: the torso is shoved along the blow and snaps back; a head shot whips the head, a leg shot buckles the knees,
## an arm shot twists the shoulders.
func _apply_flinch(sk: Skeleton3D, k: float) -> void:
	var ax := Vector3.UP.cross(_flinch_dir)
	var side := signf(_flinch_dir.x) if absf(_flinch_dir.x) > 0.05 else 1.0
	match _flinch_part:
		"head":
			_turn(sk, "Spine2", ax, 0.14 * k)
			_turn(sk, "Neck", ax, 0.4 * k)
			_turn(sk, "Head", ax, 0.5 * k)
		"legs":
			_turn(sk, "Hips", Vector3.UP.cross(Vector3.BACK), 0.12 * k)
			_turn(sk, "Spine", Vector3.UP.cross(Vector3.BACK), 0.14 * k)
			_turn(sk, "LeftUpLeg", Vector3.LEFT, 0.22 * k)         # thighs forward, shins back: the knees give
			_turn(sk, "RightUpLeg", Vector3.LEFT, 0.22 * k)
			_turn(sk, "LeftLeg", Vector3.LEFT, -0.3 * k)
			_turn(sk, "RightLeg", Vector3.LEFT, -0.3 * k)
		"arms":
			_turn(sk, "Spine", Vector3.UP, 0.12 * k * side)
			_turn(sk, "Spine1", Vector3.UP, 0.12 * k * side)
			_turn(sk, "Spine2", ax, 0.08 * k)
			_turn(sk, "Head", ax, 0.12 * k)
		_:
			_turn(sk, "Spine", ax, 0.15 * k)
			_turn(sk, "Spine1", ax, 0.2 * k)
			_turn(sk, "Spine2", ax, 0.2 * k)
			_turn(sk, "Neck", ax, 0.09 * k)
			_turn(sk, "Head", ax, -0.15 * k)           # the head lags behind the torso


## The victim of a takedown: from behind the head is yanked back, the back arches, the arms fly up and the knees give;
## from the front he doubles over the blade.
func _apply_takedown(sk: Skeleton3D, k: float) -> void:
	var lean := Vector3.UP.cross(Vector3.FORWARD) if _td_sign > 0.0 else Vector3.UP.cross(Vector3.BACK)    # tips the top toward -z (behind him) or +z
	_turn(sk, "Hips", lean, -0.06 * k)
	_turn(sk, "Spine", lean, 0.16 * k)
	_turn(sk, "Spine1", lean, 0.18 * k)
	_turn(sk, "Spine2", lean, 0.18 * k)
	_turn(sk, "Neck", lean, 0.20 * k if _td_sign > 0.0 else 0.35 * k)
	_turn(sk, "Head", lean, 0.38 * k if _td_sign > 0.0 else 0.45 * k)
	_turn(sk, "LeftArm", Vector3.BACK, 0.9 * k)
	_turn(sk, "RightArm", Vector3.BACK, -0.9 * k)
	_turn(sk, "LeftForeArm", Vector3.LEFT, 0.9 * k)
	_turn(sk, "RightForeArm", Vector3.LEFT, 0.9 * k)
	_turn(sk, "LeftUpLeg", Vector3.LEFT, 0.35 * k)
	_turn(sk, "RightUpLeg", Vector3.LEFT, 0.35 * k)
	_turn(sk, "LeftLeg", Vector3.LEFT, -0.5 * k)
	_turn(sk, "RightLeg", Vector3.LEFT, -0.5 * k)


## Rotate the bone of `role` by `angle` about `axis` (skeleton space), on top of its current pose.
func _turn(sk: Skeleton3D, role: String, axis: Vector3, angle: float) -> void:
	if not roles.has(role) or absf(angle) < 0.0005:
		return
	var bone: int = roles[role]
	var g := sk.get_bone_global_pose(bone)
	var p := sk.get_bone_parent(bone)
	var pb := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	var nb := Basis(axis.normalized(), angle) * g.basis.orthonormalized()
	sk.set_bone_pose_rotation(bone, (pb.inverse() * nb).get_rotation_quaternion())
