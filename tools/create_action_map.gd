extends SceneTree


func _initialize() -> void:
	var action_map := OpenXRActionMap.new()
	var action_set := OpenXRActionSet.new()
	action_set.resource_name = "frame_lab"
	action_set.localized_name = "Frame Lab"
	var actions: Dictionary = {}
	for specification in [["grip", 1], ["grip_click", 0], ["trigger", 1], ["trigger_click", 0], ["grip_pose", 3], ["default_pose", 3], ["haptic", 4]]:
		var action := OpenXRAction.new()
		action.resource_name = specification[0]
		action.localized_name = specification[0].capitalize()
		action.action_type = specification[1]
		action.toplevel_paths = PackedStringArray(["/user/hand/left", "/user/hand/right"])
		actions[specification[0]] = action
	action_set.actions = actions.values()
	action_map.add_action_set(action_set)
	for profile_path in ["/interaction_profiles/valve/frame_controller_valve", "/interaction_profiles/oculus/touch_controller"]:
		var profile := OpenXRInteractionProfile.new()
		profile.interaction_profile_path = profile_path
		var paths := {"grip": "input/squeeze/value", "grip_click": "input/squeeze/click" if "valve" in profile_path else "input/squeeze/value", "trigger": "input/trigger/value", "trigger_click": "input/trigger/click" if "valve" in profile_path else "input/trigger/value", "grip_pose": "input/grip/pose", "default_pose": "input/grip/pose", "haptic": "output/haptic"}
		var bindings: Array = []
		for hand in ["left", "right"]:
			for action_name in paths:
				var binding := OpenXRIPBinding.new()
				binding.action = actions[action_name]
				binding.binding_path = "/user/hand/" + hand + "/" + paths[action_name]
				bindings.append(binding)
		profile.bindings = bindings
		action_map.add_interaction_profile(profile)
	var error := ResourceSaver.save(action_map, "res://openxr_action_map.tres")
	print("Action map saved: ", error, "; profiles: ", action_map.get_interaction_profile_count())
	quit(error)
