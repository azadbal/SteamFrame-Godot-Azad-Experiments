extends "res://levels/base.gd"
# Eye tracking cubes: look at a cube and it turns orange; keep looking and it turns green.
# Options: Calibrate, eye tracking dot (on by default; also any face button), and whether to apply the calibration.
# Calibrate hides the cubes and shows 9 targets; look at each and press the right trigger.
# The mean yaw/pitch offset (head-local) is then removed from the gaze, saved, and reloaded next time.
# Each calibration overwrites the previous files; "Clear calibration" deletes them.

const Gaze = preload("res://levels/eye_tracking_source.gd")
const GazeMath = preload("res://levels/eye_tracking_math.gd")
const CALIBRATION_PATH := "user://eye_calibration.json"
const RESULTS_PATH := "user://eye_tracking_accuracy.json"
const IDLE := Color("4a5a68")
const LOOKED := Color("ffb347")
const SELECTED := Color("45e08a")
const YAWS := [-20.0, -10.0, 0.0, 10.0, 20.0]
const PITCHES := [-10.0, 0.0, 10.0]
const RADIUS := 2.0
const HIT_DEG := 4.5
const DWELL_SECONDS := 0.8
const WINDOW_MSEC := 400
const MIN_SAMPLES := 8
# Centre first, then the corners and edges.
const TARGETS := [[0.0, 0.0], [-20.0, 12.0], [20.0, 12.0], [-20.0, -12.0], [20.0, -12.0], [0.0, 12.0], [0.0, -12.0], [-20.0, 0.0], [20.0, 0.0]]

var gaze
var arena: Node3D
var cube_root: Node3D
var cubes: Array[MeshInstance3D] = []
var materials: Array[StandardMaterial3D] = []
var dwell: Array[float] = []
var reticle: MeshInstance3D
var target: MeshInstance3D
var show_dot := true
var placed := false
var recent_dirs: Array[Vector3] = []
var looked := -1

var calibrating := false
var step := 0
var samples: Array = []  # {msec, origin, dir, head}
var results: Array = []
var calibration := {}    # offset_yaw, offset_pitch, error_before, error_after
var use_calibration := true
var status := ""

func build() -> void:
	title = "Eye tracking cubes"
	gaze = Gaze.new(origin, cam)
	panel.add_button(&"calibrate", "")
	panel.add_button(&"dot", "")
	panel.add_button(&"use_calibration", "")
	panel.add_button(&"clear_calibration", "Clear calibration")
	arena = Node3D.new()
	add_child(arena)
	cube_root = Node3D.new()
	arena.add_child(cube_root)
	for pitch in PITCHES:
		for yaw in YAWS:
			var material := glow_material(IDLE)
			cubes.append(make_box(cube_root, Vector3.ONE * 0.18, GazeMath.from_yaw_pitch_deg(Vector2(yaw, pitch)) * RADIUS, material))
			materials.append(material)
			dwell.append(0.0)
	reticle = _sphere(0.02, Color.WHITE)
	reticle.material_override.no_depth_test = true
	add_child(reticle)
	target = _sphere(0.012, Color("ff4466"))
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.035
	torus.outer_radius = 0.042
	ring.mesh = torus
	ring.rotation_degrees.x = 90
	ring.material_override = flat_material(Color.WHITE)
	target.add_child(ring)
	target.visible = false
	arena.add_child(target)
	_load_calibration()
	_update_buttons()
	if head_is_tracked():
		_place()

func _sphere(radius: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	mesh.material_override = flat_material(color)
	return mesh

func _place() -> void:
	arena.global_transform = home_frame()
	placed = true

func on_recentered() -> void:
	_place()

func _update_buttons() -> void:
	panel.set_button_text(&"dot", "Eye dot: ON" if show_dot else "Eye dot: OFF")
	panel.set_button_text(&"calibrate", "Cancel calibration" if calibrating else "Calibrate")
	if calibration.is_empty():
		panel.set_button_text(&"use_calibration", "Calibration: none")
	else:
		panel.set_button_text(&"use_calibration", "Calibration: ON" if use_calibration else "Calibration: OFF")
	gaze.offset = Vector2(calibration["offset_yaw"], calibration["offset_pitch"]) if use_calibration and not calibration.is_empty() else Vector2.ZERO

func on_button(id: StringName) -> void:
	if id == &"dot":
		show_dot = not show_dot
	elif id == &"calibrate":
		if calibrating:
			_end_calibration("Calibration cancelled.")
		else:
			calibrating = true
			step = 0
			results.clear()
			status = ""
	elif id == &"use_calibration" and not calibration.is_empty():
		use_calibration = not use_calibration
	elif id == &"clear_calibration":
		_clear_calibration()
	_update_buttons()

func on_face_button(_hand: int) -> void:
	if not calibrating:
		on_button(&"dot")

func on_trigger(hand: int) -> void:
	if calibrating and hand == 1:
		_record()

func _end_calibration(message: String) -> void:
	calibrating = false
	status = message
	_update_buttons()

func _record() -> void:
	var now := Time.get_ticks_msec()
	var target_world := arena.to_global(GazeMath.from_yaw_pitch_deg(Vector2(TARGETS[step][0], TARGETS[step][1])) * RADIUS)
	var gaze_local: Array[Vector3] = []
	var target_local: Array[Vector3] = []
	for sample in samples:
		if now - int(sample["msec"]) <= WINDOW_MSEC:
			var head_inverse: Basis = (sample["head"] as Basis).inverse()
			gaze_local.append(head_inverse * sample["dir"])
			target_local.append(head_inverse * (target_world - sample["origin"]))
	if gaze_local.size() < MIN_SAMPLES:
		status = "Only %d eye samples; is eye tracking on?" % gaze_local.size()
		return
	var mean_gaze := GazeMath.mean_direction(gaze_local)
	var mean_target := GazeMath.mean_direction(target_local)
	var bias := GazeMath.yaw_pitch_deg(mean_gaze) - GazeMath.yaw_pitch_deg(mean_target)
	results.append({
		"target_yaw": TARGETS[step][0], "target_pitch": TARGETS[step][1],
		"bias_yaw": bias.x, "bias_pitch": bias.y,
		"error_deg": GazeMath.angle_deg(mean_gaze, mean_target),
		"jitter_deg": GazeMath.dispersion_deg(gaze_local), "samples": gaze_local.size(),
		"gaze_local": [mean_gaze.x, mean_gaze.y, mean_gaze.z], "target_local": [mean_target.x, mean_target.y, mean_target.z],
	})
	log_line("target %d: error %.2f bias (%+.2f,%+.2f) jitter %.2f" % [step, results[-1]["error_deg"], bias.x, bias.y, results[-1]["jitter_deg"]])
	status = ""
	step += 1
	if step >= TARGETS.size():
		_finish_calibration()

func _finish_calibration() -> void:
	var offset := Vector2.ZERO
	for entry in results:
		offset += Vector2(entry["bias_yaw"], entry["bias_pitch"])
	offset /= results.size()
	var before: Array = []
	var after: Array = []
	for entry in results:
		var g: Array = entry["gaze_local"]
		var t: Array = entry["target_local"]
		var gaze_local := Vector3(g[0], g[1], g[2])
		var target_local := Vector3(t[0], t[1], t[2])
		before.append(GazeMath.angle_deg(gaze_local, target_local))
		var corrected := GazeMath.apply_offset(gaze_local, offset)
		entry["corrected_error_deg"] = GazeMath.angle_deg(corrected, target_local)
		after.append(entry["corrected_error_deg"])
	calibration = {
		"offset_yaw": offset.x, "offset_pitch": offset.y,
		"error_before": GazeMath.summarize(before)["mean"], "error_after": GazeMath.summarize(after)["mean"],
		"time": Time.get_unix_time_from_system(),
	}
	_save(CALIBRATION_PATH, calibration)
	_save(RESULTS_PATH, {"calibration": calibration, "targets": results, "radius_m": RADIUS})
	log_line("calibrated: offset (%+.2f,%+.2f); mean error %.2f -> %.2f deg" % [offset.x, offset.y, calibration["error_before"], calibration["error_after"]])
	use_calibration = true
	_end_calibration("Calibrated. Mean error %.2f -> %.2f deg." % [calibration["error_before"], calibration["error_after"]])

func _save(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func _clear_calibration() -> void:
	for path in [CALIBRATION_PATH, RESULTS_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	calibration = {}
	use_calibration = true
	if calibrating:
		calibrating = false
	status = "Calibration cleared."
	log_line("calibration cleared")

func _load_calibration() -> void:
	if not FileAccess.file_exists(CALIBRATION_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CALIBRATION_PATH))
	if parsed is Dictionary and parsed.has("offset_yaw") and parsed.has("offset_pitch"):
		calibration = parsed

func on_frame(delta: float) -> void:
	if not placed and head_is_tracked():
		_place()
	gaze.update()
	var now := Time.get_ticks_msec()
	if gaze.valid:
		samples.append({"msec": now, "origin": gaze.gaze_origin, "dir": gaze.raw_dir, "head": cam.global_transform.basis.orthonormalized()})
		recent_dirs.append(gaze.gaze_dir)
		if recent_dirs.size() > 30:
			recent_dirs.pop_front()
	while samples.size() > 0 and now - int(samples[0]["msec"]) > 1000:
		samples.pop_front()
	cube_root.visible = not calibrating
	target.visible = calibrating
	if calibrating:
		target.position = GazeMath.from_yaw_pitch_deg(Vector2(TARGETS[step][0], TARGETS[step][1])) * RADIUS
	looked = -1
	if gaze.valid and not calibrating:
		var best := HIT_DEG
		for index in range(cubes.size()):
			var angle := GazeMath.angle_deg(gaze.gaze_dir, cubes[index].global_position - gaze.gaze_origin)
			if angle <= best:
				best = angle
				looked = index
	for index in range(cubes.size()):
		dwell[index] = dwell[index] + delta if index == looked else 0.0
		var color := IDLE
		if index == looked:
			color = SELECTED if dwell[index] >= DWELL_SECONDS else LOOKED
		materials[index].albedo_color = color
		materials[index].emission = color
		cubes[index].scale = Vector3.ONE * (1.2 if index == looked else 1.0)
	# The dot would bias calibration, so it is hidden while calibrating.
	reticle.visible = show_dot and gaze.valid and not calibrating
	if reticle.visible:
		var distance := RADIUS
		if looked >= 0:
			distance = gaze.gaze_origin.distance_to(cubes[looked].global_position)
		reticle.global_position = gaze.gaze_origin + gaze.gaze_dir.normalized() * distance
	var lines: Array[String] = []
	if calibrating:
		lines.append("# Calibrating")
		lines.append("Look at the target and press the right trigger to confirm.")
		lines.append("- Target %d of %d" % [step + 1, TARGETS.size()])
	else:
		lines.append("Look at a cube: it turns orange, then green after %.1f s." % DWELL_SECONDS)
		lines.append("# Status")
		lines.append("- Looking at: %s" % (("cube %d" % looked) if looked >= 0 else "nothing"))
		lines.append("- Jitter: %.2f deg" % GazeMath.dispersion_deg(recent_dirs))
	lines.append("- Eye data: %s" % ("yes" if gaze.valid else "NO"))
	lines.append("# Calibration")
	if calibration.is_empty():
		lines.append("- None yet")
	else:
		lines.append("- Offset yaw %+.2f, pitch %+.2f deg (%s)" % [calibration["offset_yaw"], calibration["offset_pitch"], "applied" if use_calibration else "off"])
	if status != "":
		lines.append("~ " + status)
	show_lines(lines)
