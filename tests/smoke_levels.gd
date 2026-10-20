extends SceneTree
# Headless smoke test for the hub and experiment levels (no XR runtime needed):
#   Godot --headless --xr-mode off --path . --script res://tests/smoke_levels.gd
# Checks gaze math, then loads each level scene and runs it for a few frames.
# Any engine or script error printed during the run means a level is broken.

const GazeMath = preload("res://levels/eye_tracking_math.gd")
const XRSupport = preload("res://levels/xr_support.gd")
const SCENES := [
	"res://levels/hub.tscn",
	"res://levels/eye_tracking_cubes.tscn",
]
const FRAMES_PER_SCENE := 8

var failures: Array[String] = []
var index := -1
var frames := 0
var current: Node

func _initialize() -> void:
	_test_math()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _test_math() -> void:
	_check(is_equal_approx(GazeMath.angle_deg(Vector3.FORWARD, Vector3.RIGHT), 90.0), "angle between orthogonal vectors")
	_check(GazeMath.angle_deg(Vector3.ZERO, Vector3.RIGHT) == 0.0, "zero vector yields zero angle")
	var yaw_pitch := GazeMath.yaw_pitch_deg(Vector3(1, 0, -1))
	_check(is_equal_approx(yaw_pitch.x, 45.0) and is_equal_approx(yaw_pitch.y, 0.0), "yaw is positive to the right")
	yaw_pitch = GazeMath.yaw_pitch_deg(Vector3(0, 1, -1))
	_check(is_equal_approx(yaw_pitch.y, 45.0), "pitch is positive upward")
	var steady: Array[Vector3] = [Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD]
	_check(GazeMath.dispersion_deg(steady) < 0.001, "identical samples have no dispersion")
	var spread: Array[Vector3] = [Vector3(0.1, 0, -1), Vector3(-0.1, 0, -1)]
	_check(absf(GazeMath.dispersion_deg(spread) - rad_to_deg(atan(0.1))) < 0.01, "symmetric spread dispersion")
	var summary := GazeMath.summarize([1.0, 3.0])
	_check(is_equal_approx(summary["mean"], 2.0) and is_equal_approx(summary["max"], 3.0) and is_equal_approx(summary["rms"], sqrt(5.0)), "error summary")
	_check(GazeMath.summarize([])["count"] == 0, "empty summary")
	var round_trip := GazeMath.yaw_pitch_deg(GazeMath.from_yaw_pitch_deg(Vector2(-20.0, 12.0)))
	_check(round_trip.is_equal_approx(Vector2(-20.0, 12.0)), "yaw/pitch round trip")
	var biased := GazeMath.from_yaw_pitch_deg(Vector2(3.0, -2.0))
	_check(GazeMath.angle_deg(GazeMath.apply_offset(biased, Vector2(3.0, -2.0)), Vector3.FORWARD) < 0.001, "offset removal recovers the target")

# A controller collider must register on its hand's layer
# only. Physics needs a frame to register the area, so the check runs on the next physics step.
var _collider_hand: XRController3D
var _collider_frames := 0
var _collider_checked := false

func _start_collider_test() -> void:
	_collider_hand = XRController3D.new()
	root.add_child(_collider_hand)
	_collider_hand.position = Vector3(5, 5, 5)
	XRSupport.attach_controller_collider(_collider_hand, 1)

func _physics_process(_delta: float) -> bool:
	if _collider_hand != null:
		_collider_frames += 1
	if _collider_hand != null and _collider_frames >= 3:
		# The sphere sits at the controller's tip, 7 cm along -Z.
		var at := Transform3D(Basis.IDENTITY, Vector3(5.06, 5, 4.93))
		var near := XRSupport.hand_touches_box(_collider_hand, 1, at, Vector3(0.03, 0.03, 0.03))
		var other_hand := XRSupport.hand_touches_box(_collider_hand, 0, at, Vector3(0.03, 0.03, 0.03))
		var far := XRSupport.hand_touches_box(_collider_hand, 1, Transform3D(Basis.IDENTITY, Vector3(5.2, 5, 5)), Vector3(0.03, 0.03, 0.03))
		_check(near and not other_hand and not far, "controller collider touches only nearby boxes on its own hand's layer")
		_collider_hand.queue_free()
		_collider_hand = null
		_collider_checked = true
	return false

# Saving the panel's position and placing a fresh panel must restore the same pose.
func _test_panel_save() -> void:
	var ToolPanel = load("res://levels/tool_panel.gd")
	var debug_was = ProjectSettings.get_setting(ToolPanel.DEBUG_SAVE_SETTING, false)
	ProjectSettings.set_setting(ToolPanel.DEBUG_SAVE_SETTING, true)
	var level := Node3D.new()
	level.scene_file_path = "res://levels/smoke_test_level.tscn"
	root.add_child(level)
	var head := Node3D.new()
	level.add_child(head)
	head.position = Vector3(0.2, 1.6, 0.1)
	XRSupport.capture_home(head)
	var first = ToolPanel.new()
	first.setup([] as Array[XRController3D], head)
	level.add_child(first)
	first.global_transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.5, 1.3, -0.4))
	first._save_position()
	var second = ToolPanel.new()
	second.setup([] as Array[XRController3D], head)
	level.add_child(second)
	second.place_default()
	_check(second.global_transform.is_equal_approx(first.global_transform), "saved panel pose restores")
	ProjectSettings.set_setting(ToolPanel.DEBUG_SAVE_SETTING, debug_was)
	# Without the debug setting, a level with a baked pose uses it (eye tracking shares the hub's).
	level.scene_file_path = "res://levels/eye_tracking_cubes.tscn"
	second.place_default()
	var hub: Array = ToolPanel.HUB_POSE
	var expected: Transform3D = XRSupport.home_frame(head) * Transform3D(Vector3(hub[0], hub[1], hub[2]), Vector3(hub[3], hub[4], hub[5]), Vector3(hub[6], hub[7], hub[8]), Vector3(hub[9], hub[10], hub[11]))
	_check(second.global_transform.is_equal_approx(expected), "eye tracking level uses the hub's baked panel pose")
	var positions: Dictionary = first._load_positions()
	positions.erase("smoke_test_level")
	var file := FileAccess.open(first.POSITIONS_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(positions, "\t"))
	file.close()
	level.free()
	Engine.remove_meta(XRSupport.HOME_KEY)

func _process(_delta: float) -> bool:
	if index == -1 and current == null:
		_test_panel_save()
		_start_collider_test()
	if current == null or frames >= FRAMES_PER_SCENE:
		if current != null:
			current.queue_free()
			current = null
		index += 1
		if index >= SCENES.size():
			return _finish()
		var packed := load(SCENES[index]) as PackedScene
		if packed == null:
			failures.append("cannot load " + SCENES[index])
			frames = FRAMES_PER_SCENE
			return false
		current = packed.instantiate()
		root.add_child(current)
		frames = 0
		return false
	frames += 1
	if frames == 3 and SCENES[index].ends_with("eye_tracking_cubes.tscn"):
		_test_clear_calibration()
	return false

# Clear calibration must delete the saved files and drop the offset.
func _test_clear_calibration() -> void:
	var file := FileAccess.open(current.CALIBRATION_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify({"offset_yaw": 2.0, "offset_pitch": -1.0}))
	file.close()
	current._load_calibration()
	current._update_buttons()
	_check(current.gaze.offset == Vector2(2.0, -1.0), "saved calibration loads")
	current.on_button(&"clear_calibration")
	_check(not FileAccess.file_exists(current.CALIBRATION_PATH) and current.calibration.is_empty() and current.gaze.offset == Vector2.ZERO, "clear calibration deletes the file and the offset")

func _finish() -> bool:
	if not _collider_checked:
		# Keep running until the physics-frame collider check has happened.
		index = SCENES.size() - 1
		frames = 0
		return false
	if failures.is_empty():
		print("[smoke] PASS: gaze math and %d level scenes ran %d frames each" % [SCENES.size(), FRAMES_PER_SCENE])
	else:
		for failure in failures:
			printerr("[smoke] FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
	return true
