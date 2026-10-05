extends RefCounted

static func run(lab: Node3D) -> void:
	var interaction = lab.get_node("Interactions")
	var cube = interaction.cubes[0]
	var floating = interaction.cubes[1]
	var failures: Array[String] = []
	interaction.set_focused(true)
	var pose := Transform3D(Basis.IDENTITY, cube.global_position)
	interaction.update_hand(0, true, pose, 0.0, 0.01)
	interaction.update_hand(0, true, pose, 1.0, 0.01)
	check(cube.held_by == 0, "squeeze acquires nearby cube", failures)
	interaction.update_hand(1, true, pose, 1.0, 0.01)
	check(cube.held_by == 0 and interaction.held[1] == null, "single-hand ownership", failures)
	for index in range(12):
		pose.origin.x += 0.01
		pose.basis = Basis(Vector3.UP, 0.01 * (index + 1))
		interaction.update_hand(0, true, pose, 1.0, 0.01)
	pose.origin.x += 0.01
	pose.basis = Basis(Vector3.UP, 0.13)
	interaction.update_hand(0, true, pose, 0.0, 0.01)
	check(cube.held_by == -1 and not cube.freeze, "release restores physics", failures)
	check(cube.linear_velocity.x > 0.8 and cube.linear_velocity.x < 1.2, "smoothed throw velocity", failures)
	check(cube.angular_velocity.y > 0.8 and cube.angular_velocity.y < 1.2, "smoothed angular velocity", failures)
	pose = Transform3D(Basis.IDENTITY, floating.global_position)
	interaction.update_hand(0, true, pose, 1.0, 0.01)
	pose.origin += Vector3(0.3, 0.1, 0)
	interaction.update_hand(0, true, pose, 1.0, 0.01)
	interaction.update_hand(0, true, pose, 0.0, 0.01)
	check(floating.freeze and floating.linear_velocity == Vector3.ZERO and floating.global_position.is_equal_approx(pose.origin), "sound cube stays where released", failures)
	var button: Vector3 = interaction.button_position
	interaction.update_touch([button])
	check(interaction.warm, "touch toggles", failures)
	interaction.update_touch([button, button])
	interaction.update_touch([button])
	check(interaction.warm, "both hands must leave before retrigger", failures)
	interaction.update_touch([])
	interaction.update_touch([button])
	check(not interaction.warm, "fresh contact retriggers", failures)
	pose = Transform3D(Basis.IDENTITY, cube.global_position)
	interaction.update_hand(0, true, pose, 1.0, 0.01)
	interaction.set_focused(false)
	check(cube.held_by == -1 and cube.linear_velocity == Vector3.ZERO and cube.angular_velocity == Vector3.ZERO, "focus loss releases safely", failures)
	interaction.update_hand(0, true, pose, 1.0, 0.01)
	interaction.update_touch([])
	interaction.update_touch([button])
	check(cube.held_by == -1 and not interaction.warm, "unfocused input blocked", failures)
	interaction.set_focused(true)
	interaction.update_hand(0, true, pose, 1.0, 0.01)
	check(cube.held_by == -1, "focus return requires fresh squeeze", failures)
	cube.global_position = Vector3(0, -2, 0)
	check(cube.reset_if_outside() and cube.global_transform == cube.home, "fallen cube resets", failures)
	# Exercise the real XRController3D input boundary with trigger-only input.
	var tracker := XRControllerTracker.new()
	tracker.type = XRServer.TRACKER_CONTROLLER
	tracker.name = &"left_hand"
	XRServer.add_tracker(tracker)
	tracker.set_input(&"grip", 0.0)
	tracker.set_input(&"grip_click", false)
	tracker.set_input(&"trigger", 0.0)
	tracker.set_input(&"trigger_click", false)
	pose = cube.global_transform
	interaction.update_hand(0, true, pose, lab._grab_strength(lab.hands[0]), 0.01)
	tracker.set_input(&"trigger", 1.0)
	interaction.update_hand(0, true, pose, lab._grab_strength(lab.hands[0]), 0.01)
	check(cube.held_by == 0, "index trigger alone grabs through XRController3D", failures)
	tracker.set_input(&"trigger", 0.0)
	interaction.update_hand(0, true, pose, lab._grab_strength(lab.hands[0]), 0.01)
	check(cube.held_by == -1, "index trigger release drops cube", failures)
	XRServer.remove_tracker(tracker)
	if failures.is_empty():
		print("[FieldLab] SELF-TEST PASS: ownership, linear/angular throw, floating audio cube, touch debounce, focus safety, reset, XR trigger grab/release")
	else:
		for failure in failures:
			push_error("[FieldLab] SELF-TEST FAIL: " + failure)
	lab.get_tree().quit(0 if failures.is_empty() else 1)

static func check(condition: bool, description: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(description)
