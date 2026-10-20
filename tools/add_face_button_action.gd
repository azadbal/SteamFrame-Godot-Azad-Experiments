extends SceneTree
# Adds a "face_button" boolean action, bound to every face button, to the existing action map.
# Frame controller: right A/B/X/Y and left d-pad clicks. Oculus Touch fallback: A/B and X/Y.
# Idempotent. Run from the project directory:
#   Godot --headless --xr-mode off --path . --script res://tools/add_face_button_action.gd

const MAP_PATH := "res://openxr_action_map.tres"
const BINDINGS := {
	"/interaction_profiles/valve/frame_controller_valve": [
		"/user/hand/right/input/a/click", "/user/hand/right/input/b/click",
		"/user/hand/right/input/x/click", "/user/hand/right/input/y/click",
		"/user/hand/left/input/dpad_up/click", "/user/hand/left/input/dpad_down/click",
		"/user/hand/left/input/dpad_left/click", "/user/hand/left/input/dpad_right/click",
	],
	"/interaction_profiles/oculus/touch_controller": [
		"/user/hand/right/input/a/click", "/user/hand/right/input/b/click",
		"/user/hand/left/input/x/click", "/user/hand/left/input/y/click",
	],
}

func _initialize() -> void:
	var action_map := load(MAP_PATH) as OpenXRActionMap
	var action_set: OpenXRActionSet = action_map.get_action_sets()[0]
	var action: OpenXRAction = null
	for existing in action_set.actions:
		if existing.resource_name == "face_button":
			action = existing
	if action == null:
		action = OpenXRAction.new()
		action.resource_name = "face_button"
		action.localized_name = "Face Button"
		action.action_type = OpenXRAction.OPENXR_ACTION_BOOL
		action.toplevel_paths = PackedStringArray(["/user/hand/left", "/user/hand/right"])
		var actions := action_set.actions.duplicate()
		actions.append(action)
		action_set.actions = actions
	for profile in action_map.get_interaction_profiles():
		if not BINDINGS.has(profile.interaction_profile_path):
			continue
		var bindings: Array = profile.bindings.duplicate()
		var existing_paths: Array[String] = []
		for binding in bindings:
			if binding.action == action:
				existing_paths.append(binding.binding_path)
		for path in BINDINGS[profile.interaction_profile_path]:
			if not path in existing_paths:
				var binding := OpenXRIPBinding.new()
				binding.action = action
				binding.binding_path = path
				bindings.append(binding)
		profile.bindings = bindings
	var error := ResourceSaver.save(action_map, MAP_PATH)
	print("Face button action map saved: ", error)
	quit(error)
