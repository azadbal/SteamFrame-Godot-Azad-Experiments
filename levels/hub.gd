extends "res://levels/base.gd"
# Main scene. Level picker in front of the launch direction; touch a level with a controller and
# pull that controller's trigger. The options panel shows what the runtime supports and has
# Passthrough and Quit app.

const CUBE_LAB := "res://levels/cube_lab.tscn"
const LEVELS := [
	["Eye tracking cubes", "res://levels/eye_tracking_cubes.tscn"],
	["Cube lab", CUBE_LAB],
]
const BUTTON_HALF := Vector3(0.13, 0.065, 0.015)
const TOUCH_MARGIN := 0.005
const BUTTON_SPACING := 0.3
const ROW_Y := -0.1 # below eye level
const REPORT_PATH := "user://capability_report.txt"

var arena: Node3D
var buttons: Array[Node3D] = []
var plates: Array[StandardMaterial3D] = []
var touched := [-1, -1]
var placed := false
var report: Array[String] = []

func _ready() -> void:
	# Cube lab owns the self-test and desktop preview flags; the build script passes them to the main scene.
	var args := OS.get_cmdline_user_args()
	if "--self-test" in args or "--desktop" in args:
		set_process(false)
		set_physics_process(false)
		get_tree().change_scene_to_file.call_deferred(CUBE_LAB)
		return
	super._ready()

func build() -> void:
	title = "Azad's Steam Frame Experiments"
	panel.set_button_text(&"back", "Quit app")
	arena = Node3D.new()
	add_child(arena)
	make_label(arena, "LEVELS", Vector3(0, ROW_Y + 0.1, -0.55), 26, Color("9ebbcf"))
	for index in range(LEVELS.size()):
		var button := Node3D.new()
		button.position = Vector3((index - (LEVELS.size() - 1) * 0.5) * BUTTON_SPACING, ROW_Y, -0.55)
		arena.add_child(button)
		var plate := glow_material(Color("334553"))
		make_box(button, Vector3(0.26, 0.13, 0.03), Vector3.ZERO, plate)
		make_label(button, LEVELS[index][0], Vector3(0, 0, 0.02), 26, Color.WHITE)
		button.set_meta("scene", LEVELS[index][1])
		buttons.append(button)
		plates.append(plate)
	_make_report()
	if head_is_tracked():
		_place()

func _place() -> void:
	arena.global_transform = home_frame()
	placed = true

func on_recentered() -> void:
	_place()

func _make_report() -> void:
	report.clear()
	report.append("# Runtime")
	if not in_xr:
		report.append("- OpenXR is not running (desktop fallback).")
	else:
		var info: Dictionary = xr.get_system_info()
		report.append("- %s %s" % [info.get("XRRuntimeName", "?"), info.get("XRRuntimeVersion", "?")])
		report.append("- Eye gaze: %s | Foveation: %s" % ["yes" if xr.is_eye_gaze_interaction_supported() else "no", "yes" if xr.is_foveation_supported() else "no"])
		var names: Array[String] = []
		for mode in xr.get_supported_environment_blend_modes():
			names.append(["OPAQUE", "ADDITIVE", "ALPHA_BLEND"][clampi(mode, 0, 2)])
		report.append("- Blend modes: %s" % ", ".join(names))
		report.append("- Refresh rate: %d Hz" % roundi(xr.get_display_refresh_rate()))
		# Per-eye render target, scaled by the viewport's 3D render scale.
		var target := Vector2(xr.get_render_target_size()) * get_viewport().scaling_3d_scale
		report.append("- Render resolution: %d x %d per eye" % [roundi(target.x), roundi(target.y)])
	for line in report:
		log_line(line.trim_prefix("# ").trim_prefix("- "))
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(report))
		file.close()

func go_back() -> void:
	get_tree().quit()

func on_trigger(hand: int) -> void:
	if touched[hand] >= 0:
		get_tree().change_scene_to_file.call_deferred(buttons[touched[hand]].get_meta("scene"))

# Physics shape queries belong in physics frames, before the base class reads the triggers.
func before_input() -> void:
	for hand in range(2):
		touched[hand] = -1
		if hand_tracked(hand) and not panel.uses_hand(hand):
			var nearest := INF
			for index in range(buttons.size()):
				if XRSupport.hand_touches_box(self, hand, buttons[index].global_transform, BUTTON_HALF, TOUCH_MARGIN):
					var distance := hands[hand].global_position.distance_to(buttons[index].global_position)
					if distance < nearest:
						nearest = distance
						touched[hand] = index

func on_frame(_delta: float) -> void:
	if not placed and head_is_tracked():
		_place()
	for index in range(buttons.size()):
		var hot: bool = touched[0] == index or touched[1] == index
		plates[index].albedo_color = Color("ffba73") if hot else Color("334553")
		plates[index].emission = plates[index].albedo_color
	show_lines(report)
