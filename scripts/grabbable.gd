extends RigidBody3D

var floating := false
var held_by := -1
var home := Transform3D.IDENTITY
var hand_offset := Transform3D.IDENTITY
var samples: Array[Dictionary] = []
var previous_pose := Transform3D.IDENTITY

func begin_grab(hand: int, hand_pose: Transform3D) -> bool:
	if held_by != -1:
		return false
	held_by = hand
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	hand_offset = hand_pose.affine_inverse() * global_transform
	previous_pose = global_transform
	samples.clear()
	return true

func move_held(hand_pose: Transform3D, delta: float) -> void:
	if held_by == -1 or delta <= 0.0:
		return
	global_transform = hand_pose * hand_offset
	var rotation_delta := (global_basis.get_rotation_quaternion() * previous_pose.basis.get_rotation_quaternion().inverse()).normalized()
	if rotation_delta.w < 0.0:
		rotation_delta = -rotation_delta
	var angular := Vector3.ZERO
	if rotation_delta.get_angle() > 0.0001:
		angular = rotation_delta.get_axis() * rotation_delta.get_angle() / delta
	samples.append({"linear": (global_position - previous_pose.origin) / delta, "angular": angular, "dt": delta})
	var duration := 0.0
	for sample in samples:
		duration += float(sample.dt)
	while samples.size() > 1 and duration - float(samples[0].dt) >= 0.09:
		duration -= float(samples.pop_front().dt)
	previous_pose = global_transform

func release(safe := false) -> void:
	if held_by == -1:
		return
	held_by = -1
	var linear := Vector3.ZERO
	var angular := Vector3.ZERO
	var duration := 0.0
	if not safe and not floating:
		for sample in samples:
			linear += Vector3(sample.linear) * float(sample.dt)
			angular += Vector3(sample.angular) * float(sample.dt)
			duration += float(sample.dt)
		if duration > 0.0:
			linear /= duration
			angular /= duration
	freeze = floating
	sleeping = false
	linear_velocity = linear.limit_length(8.0)
	angular_velocity = angular.limit_length(20.0)
	samples.clear()

func reset_if_outside() -> bool:
	if held_by != -1 or (global_position.y >= -0.5 and global_position.distance_to(home.origin) < 3.0):
		return false
	global_transform = home
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	return true
