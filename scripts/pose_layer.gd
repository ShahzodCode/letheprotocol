class_name PoseLayer
extends SkeletonModifier3D
## Procedural layer on top of the clips of a CharModel (runs after the AnimationPlayer has posed the skeleton): the hit
## reaction (flinch), the shot's recoil and the victim's side of a silent takedown. Everything is rotated about axes of the
## SKELETON space (up = +y, the model faces +z), so the same numbers work on every rig. The enemy sets the values, the
## layer eases them in and out. `roles` maps a role ("Hips", "Spine", "Neck", "LeftArm", ...) to a bone index.
##
## Holding the weapon (last, on top of everything else): the gun hangs in the right hand (CharModel.hold); `grip` turns the
## shoulder and wrist so the barrel points at the aim point (at most AIM_MAX: the clip does the rest) and pulls the left hand
## onto the gun's support point with a two-bone solve (the elbow keeps the clip's bend). A gun longer than the arm can reach
## gets the hand as far as it goes along the line, so long rifles look a little stretched but the hand never floats elsewhere.

const ATTACK := 40.0          # how fast a new flinch / recoil snaps in (per second)
const FLINCH_DECAY := 4.5     # a flinch is gone after about 0.3 s
const RECOIL_DECAY := 14.0
const TD_RELEASE := 8.0       # the takedown pose lets go this fast when the death clip takes over
const SWING_SNAP := 45.0      # how fast the blade fighter's cut comes in
const GRIP_EASE := 6.0        # how fast the left hand goes onto / comes off the gun (weight per second)
const AIM_EASE := 5.0         # how fast the barrel correction comes in / goes
const AIM_MAX := 0.35         # the barrel is turned at most this far (radians) toward the aim point
const AIM_ARM := 0.65         # ...this share of it by the shoulder, the rest by the wrist

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
var _coil := 0.0              # blade swing: wound up (torso turned away, leaning back, sword arm raised) 0..1
var _coil_shown := 0.0
var _cut := 0.0               # blade swing: driven through (torso turned into the blow, leaning in, arm forward) 0..1
var _cut_shown := 0.0
var _swing_side := 1.0        # which way the torso turns through the cut (alternates)
# wounds (Enemy: leg / arm hits), kept for the rest of his life
var _limp_side := 0.0         # +1 left leg hurt, -1 right, 0 none
var _limp := 0.0              # 0..1 how bad
var _stride := 0.0            # 0..1 through the current gait clip (set by the enemy every tick)
var _stride_move := 0.0       # 0..1 how much he is moving (no hitch standing still)
var _arm_side := 0.0          # +1 left arm hurt, -1 right, 0 none
var _arm := 0.0
# the weapon in his hands (see hold_gun / grip)
var _gun_fit := Transform3D.IDENTITY     # the gun node's transform in the right-hand bone's space (as CharModel.hold sets it)
var _support := Vector3.INF   # where the left wrist goes, in the gun node's space (INF: one-handed)
var _grip := 0.0              # target 0..1
var _grip_shown := 0.0
var _aim := 0.0               # target 0..1
var _aim_shown := 0.0
var _aim_at := Vector3.INF    # world point the barrel turns toward


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


## A blade swing on top of the melee clip: `coil` 0..1 winds him up, `cut` 0..1 drives him through; `side` +1 / -1.
func swing(coil: float, cut: float, side: float) -> void:
	_coil = clampf(coil, 0.0, 1.0)
	_cut = clampf(cut, 0.0, 1.0)
	_swing_side = side


## The gun is held: `fit` is its transform under the right-hand bone (CharModel.hold), `support` the left wrist's place in the gun
## node's own space (Vector3.INF: a one-handed weapon).
func hold_gun(fit: Transform3D, support: Vector3) -> void:
	_gun_fit = fit
	_support = support


## Each tick: how much the left hand holds the gun (0..1) and how much the barrel is turned toward `aim_at` (world, 0..1).
func grip(hold: float, aim: float = 0.0, aim_at: Vector3 = Vector3.INF) -> void:
	_grip = clampf(hold, 0.0, 1.0)
	_aim = clampf(aim, 0.0, 1.0) if aim_at != Vector3.INF else 0.0
	if aim_at != Vector3.INF:
		_aim_at = aim_at


## Lets go of the gun at once (death: the weapon is gone).
func release() -> void:
	_grip = 0.0
	_grip_shown = 0.0
	_aim = 0.0
	_aim_shown = 0.0


func is_idle() -> bool:
	return _grip_shown <= 0.0 and _aim_shown <= 0.0 and _flinch < 0.002 and _flinch_shown < 0.002 and _recoil < 0.002 and _recoil_shown < 0.002 and _td < 0.002 and _td_shown < 0.002 \
		and _coil < 0.002 and _coil_shown < 0.002 and _cut < 0.002 and _cut_shown < 0.002 and _limp <= 0.0 and _arm <= 0.0


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
	# the wind-up eases in, the cut snaps in (it is the fast part)
	_coil_shown = lerpf(_coil_shown, _coil, 1.0 - exp(-(14.0 if _coil > _coil_shown else 30.0) * delta))
	_cut_shown = lerpf(_cut_shown, _cut, 1.0 - exp(-(SWING_SNAP if _cut > _cut_shown else 9.0) * delta))
	if _coil < 0.002 and _coil_shown < 0.002:
		_coil_shown = 0.0
	if _cut < 0.002 and _cut_shown < 0.002:
		_cut_shown = 0.0
	_grip_shown = move_toward(_grip_shown, _grip, GRIP_EASE * delta)
	_aim_shown = move_toward(_aim_shown, _aim, AIM_EASE * delta)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or (_flinch_shown <= 0.0 and _recoil_shown <= 0.0 and _td_shown <= 0.0 and _coil_shown <= 0.0 and _cut_shown <= 0.0 \
			and _limp <= 0.0 and _arm <= 0.0 and _grip_shown <= 0.0 and _aim_shown <= 0.0):
		return
	if _limp > 0.0 and _td_shown <= 0.0:
		_apply_limp(sk)
	if _arm > 0.0 and _td_shown <= 0.0:
		_apply_arm(sk)
	if _td_shown > 0.0:
		_apply_takedown(sk, _td_shown)
	if _coil_shown > 0.0 or _cut_shown > 0.0:
		_apply_swing(sk, _coil_shown, _cut_shown)
	if _flinch_shown > 0.0:
		_apply_flinch(sk, _flinch_shown)
	if _recoil_shown > 0.0:
		# the weapon kicks the shoulders back and the head up
		var back := Vector3.UP.cross(Vector3.FORWARD)          # tips the top toward -z, away from the way he faces
		_turn(sk, "Spine1", back, 0.05 * _recoil_shown)
		_turn(sk, "Spine2", back, 0.05 * _recoil_shown)
		_turn(sk, "Head", back, -0.03 * _recoil_shown)         # the head stays on the target
	if _td_shown <= 0.0:
		if _aim_shown > 0.0 and _aim_at != Vector3.INF:
			_apply_aim(sk, _aim_shown)
		if _grip_shown > 0.0 and _support != Vector3.INF and not (_arm > 0.0 and _arm_side > 0.0):
			_apply_support(sk, _grip_shown)      # (a hurt left arm is held to the body instead)


# ---------------------------------------------------------------- holding the weapon

## The gun node's transform in skeleton space now (it hangs under the right-hand bone).
func _gun_xf(sk: Skeleton3D) -> Transform3D:
	return sk.get_bone_global_pose(roles["RightHand"]) * _gun_fit


## Turns the barrel toward the aim point: AIM_ARM of the turn at the shoulder (the whole arm and the gun swing together), the rest
## at the wrist; never more than AIM_MAX in all.
func _apply_aim(sk: Skeleton3D, k: float) -> void:
	if not roles.has("RightHand") or not roles.has("RightArm"):
		return
	var target: Vector3 = sk.global_transform.affine_inverse() * _aim_at
	var g := _gun_xf(sk)
	var fwd := (g.basis * Vector3.FORWARD).normalized()
	var want := target - g.origin
	if want.length() < 0.001:
		return
	want = want.normalized()
	var ax := fwd.cross(want)
	if ax.length() < 0.0001:
		return
	var ang := minf(fwd.angle_to(want), AIM_MAX) * k
	_turn(sk, "RightArm", ax, ang * AIM_ARM)
	_turn(sk, "RightHand", ax, ang * (1.0 - AIM_ARM))


## The left hand onto the gun: a two-bone solve from the shoulder to the support point (blended with where the clip put the hand by
## `k`). The elbow bends the way the clip bends it, pulled down and out a little so a straight arm still folds the right way.
func _apply_support(sk: Skeleton3D, k: float) -> void:
	if not roles.has("RightHand") or not roles.has("LeftArm") or not roles.has("LeftForeArm") or not roles.has("LeftHand"):
		return
	var a: int = roles["LeftArm"]
	var f: int = roles["LeftForeArm"]
	var h: int = roles["LeftHand"]
	var sp := sk.get_bone_global_pose(a).origin
	var ep := sk.get_bone_global_pose(f).origin
	var hp := sk.get_bone_global_pose(h).origin
	var l1 := sp.distance_to(ep)
	var l2 := ep.distance_to(hp)
	if l1 < 0.000001 or l2 < 0.000001:
		return
	var goal := hp.lerp(_gun_xf(sk) * _support, k)
	var to := goal - sp
	if to.length() < 0.000001:
		return
	var dir := to.normalized()
	var d := clampf(to.length(), absf(l1 - l2) + (l1 + l2) * 0.01, (l1 + l2) * 0.995)    # out of reach: the hand stops short on the line
	var cosa := (l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d)
	var ang := acos(clampf(cosa, -1.0, 1.0))
	var bend := (ep - sp) - dir * (ep - sp).dot(dir)
	var pole := (bend.normalized() if bend.length() > l1 * 0.05 else Vector3.ZERO) + Vector3(0.45, -0.9, -0.2)     # his left is +x, down is -y
	pole -= dir * pole.dot(dir)
	if pole.length() < 0.0001:
		return
	pole = pole.normalized()
	var elbow := sp + (dir * cos(ang) + pole * sin(ang)) * l1
	_point(sk, a, ep, elbow)
	_point(sk, f, sk.get_bone_global_pose(h).origin, sp + dir * d)


## Turns `bone` (by the shortest arc, keeping its twist) so the child joint now at `child_now` ends up at `child_want` (skeleton space).
func _point(sk: Skeleton3D, bone: int, child_now: Vector3, child_want: Vector3) -> void:
	var g := sk.get_bone_global_pose(bone)
	var cur := child_now - g.origin
	var want := child_want - g.origin
	if cur.length() < 0.000001 or want.length() < 0.000001:
		return
	var q := Quaternion(cur.normalized(), want.normalized())
	var p := sk.get_bone_parent(bone)
	var pb := sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	var nb := Basis(q) * g.basis.orthonormalized()
	sk.set_bone_pose_rotation(bone, (pb.inverse() * nb).get_rotation_quaternion())


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


## The blade fighter's swing: wound up he turns his torso away from the cut, leans back and lifts the sword arm (the
## anticipation you can read from a distance); through the cut the torso whips round the other way, he leans into it and
## the arm drives forward and across. The hips turn less than the shoulders, the head stays on the target.
func _apply_swing(sk: Skeleton3D, coil: float, cut: float) -> void:
	var s := _swing_side
	var twist := (0.32 * coil - 0.42 * cut) * s
	var back := Vector3.UP.cross(Vector3.FORWARD)          # tips the top toward -z, away from the way he faces
	var lean := 0.1 * coil - 0.16 * cut                     # back while winding up, forward into the cut
	_turn(sk, "Hips", Vector3.UP, twist * 0.3)
	_turn(sk, "Spine", Vector3.UP, twist * 0.3)
	_turn(sk, "Spine1", Vector3.UP, twist * 0.35)
	_turn(sk, "Spine2", Vector3.UP, twist * 0.35)
	_turn(sk, "Spine1", back, lean)
	_turn(sk, "Spine2", back, lean)
	_turn(sk, "Head", Vector3.UP, -twist * 0.6)             # eyes stay on him
	_turn(sk, "RightArm", Vector3.BACK, -0.55 * coil + 0.2 * cut)
	_turn(sk, "RightArm", Vector3.LEFT, -0.25 * coil + 0.5 * cut)
	_turn(sk, "RightForeArm", Vector3.LEFT, 0.35 * coil - 0.2 * cut)
	_turn(sk, "LeftArm", Vector3.BACK, 0.25 * cut)          # the free arm swings out for balance
	_turn(sk, "LeftUpLeg", Vector3.LEFT, 0.18 * cut)         # a step into the blow: front knee bends
	_turn(sk, "LeftLeg", Vector3.LEFT, -0.22 * cut)


# ---------------------------------------------------------------- wounds

## A leg hit: `side` +1 left / -1 right, `amount` 0..1. He limps from now on.
func wound_limp(side: float, amount: float) -> void:
	_limp_side = side
	_limp = clampf(amount, 0.0, 1.0)


## An arm hit: `side` +1 left / -1 right, `amount` 0..1. He holds that arm from now on.
func wound_arm(side: float, amount: float) -> void:
	_arm_side = side
	_arm = clampf(amount, 0.0, 1.0)


## Where he is in his gait clip (0..1) and how much he moves (0..1): the limp hitches once per cycle.
func set_stride(t: float, move: float) -> void:
	_stride = t
	_stride_move = clampf(move, 0.0, 1.0)


## The limp: once a stride, as the weight comes onto the hurt leg, the torso lurches over it and the head dips; that knee stays
## stiff and he leans toward it a little all the time. (Skeleton space: the model faces +z, his left is +x.)
func _apply_limp(sk: Skeleton3D) -> void:
	var s := _limp_side
	var hitch := pow(maxf(0.0, sin(_stride * TAU)), 2.0) * _stride_move
	var k := _limp
	var fwd := Vector3.UP.cross(Vector3.BACK)               # tips the top toward +z, the way he faces
	_turn(sk, "Hips", Vector3.BACK, -0.05 * s * k * hitch)
	_turn(sk, "Spine", Vector3.BACK, -(0.04 + 0.14 * hitch) * s * k)
	_turn(sk, "Spine1", Vector3.BACK, -0.08 * s * k * hitch)
	_turn(sk, "Spine1", fwd, 0.1 * k * hitch)               # bobs forward over the bad step
	_turn(sk, "Head", Vector3.BACK, 0.1 * s * k * hitch)     # the head stays level-ish
	var leg := "LeftLeg" if s > 0.0 else "RightLeg"
	var up := "LeftUpLeg" if s > 0.0 else "RightUpLeg"
	_turn(sk, leg, Vector3.LEFT, 0.25 * k * _stride_move)   # the hurt knee does not bend much
	_turn(sk, up, Vector3.LEFT, -0.12 * k * _stride_move)


## The held arm: the hurt shoulder sags and the elbow is tucked in, the shoulders turn toward the wound and the arm wavers (the
## gun with it).
func _apply_arm(sk: Skeleton3D) -> void:
	var s := _arm_side
	var k := _arm
	var t := Time.get_ticks_msec() * 0.001
	var arm := "LeftArm" if s > 0.0 else "RightArm"
	var fore := "LeftForeArm" if s > 0.0 else "RightForeArm"
	_turn(sk, arm, Vector3.BACK, -0.22 * s * k)              # the shoulder drops
	_turn(sk, arm, Vector3.LEFT, (sin(t * 3.1) * 0.05 + sin(t * 7.3) * 0.025) * k)
	_turn(sk, arm, Vector3.UP, sin(t * 4.3) * 0.04 * k)
	_turn(sk, fore, Vector3.LEFT, 0.25 * k)
	_turn(sk, "Spine2", Vector3.UP, 0.1 * s * k)
	_turn(sk, "Spine2", Vector3.BACK, -0.05 * s * k)         # hunched over it


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
