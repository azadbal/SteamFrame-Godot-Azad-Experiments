extends SceneTree
# Adds the eye gaze pose action and the XR_EXT_eye_gaze_interaction profile to the existing action map.
# Idempotent. Run from the project directory:
#   Godot --headless --xr-mode off --path . --script res://tools/add_eye_gaze_action.gd

const MAP_PATH := "res://openxr_action_map.tres"
const PROFILE_PATH := "/interaction_profiles/ext/eye_gaze_interaction"
const BINDING_PATH := "/user/eyes_ext/input/gaze_ext/pose"

func _initialize() -> void:
	var action_map := load(MAP_PATH) as OpenXRActionMap
	var action_set: OpenXRActionSet = action_map.get_action_sets()[0]
	var action: OpenXRAction = null
	for existing in action_set.actions:
		if existing.resource_name == "eye_pose":
			action = existing
	if action == null:
		action = OpenXRAction.new()
		action.resource_name = "eye_pose"
		action.localized_name = "Eye Pose"
		action.action_type = OpenXRAction.OPENXR_ACTION_POSE
		action.toplevel_paths = PackedStringArray(["/user/eyes_ext"])
		var actions := action_set.actions.duplicate()
		actions.append(action)
		action_set.actions = actions
	var profile: OpenXRInteractionProfile = null
	for existing in action_map.get_interaction_profiles():
		if existing.interaction_profile_path == PROFILE_PATH:
			profile = existing
	if profile == null:
		profile = OpenXRInteractionProfile.new()
		profile.interaction_profile_path = PROFILE_PATH
		var binding := OpenXRIPBinding.new()
		binding.action = action
		binding.binding_path = BINDING_PATH
		profile.bindings = [binding]
		action_map.add_interaction_profile(profile)
	var error := ResourceSaver.save(action_map, MAP_PATH)
	print("Eye gaze action map saved: ", error, "; profiles: ", action_map.get_interaction_profile_count())
	quit(error)
