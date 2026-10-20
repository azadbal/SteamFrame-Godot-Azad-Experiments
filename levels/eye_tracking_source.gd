extends RefCounted
# Reads the XR_EXT_eye_gaze_interaction pose straight from the Godot tracker, so it does not
# depend on which pose name Godot gives the "eye_pose" action. Poll update() once per frame.
# raw_dir is the runtime's gaze; gaze_dir has the calibration offset (head-local yaw/pitch) removed.

const GazeMath = preload("res://levels/eye_tracking_math.gd")
const TRACKER_NAME := &"/user/eyes_ext"
const POSE_CANDIDATES: Array[StringName] = [&"eye_pose", &"eye", &"default"]

var origin_node: XROrigin3D
var head: Node3D
var offset := Vector2.ZERO
var valid := false
var gaze_origin := Vector3.ZERO
var raw_dir := Vector3.FORWARD
var gaze_dir := Vector3.FORWARD

func _init(origin: XROrigin3D, head_node: Node3D) -> void:
	origin_node = origin
	head = head_node

func update() -> void:
	valid = false
	var tracker := XRServer.get_tracker(TRACKER_NAME) as XRPositionalTracker
	if tracker == null:
		return
	for candidate in POSE_CANDIDATES:
		var pose := tracker.get_pose(candidate)
		if pose != null and pose.has_tracking_data:
			var global_pose := origin_node.global_transform * pose.get_adjusted_transform()
			gaze_origin = global_pose.origin
			raw_dir = -global_pose.basis.z
			var head_basis := head.global_transform.basis.orthonormalized()
			gaze_dir = head_basis * GazeMath.apply_offset(head_basis.inverse() * raw_dir, offset)
			valid = true
			return
