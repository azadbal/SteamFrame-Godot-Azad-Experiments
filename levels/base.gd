extends Node3D
# Shared XR rig, floating tool panel and session handling for the hub and experiment levels.
# Levels extend this file and override build(), on_frame(), on_trigger(), on_button(), on_recentered().
# The options panel always has Passthrough and Return to hub (the hub turns it into "Quit app") on
# the right; levels add their own options on the left with panel.add_button().
# Content is placed relative to home_frame(), the forward direction captured once at launch.

const HUB_SCENE := "res://levels/hub.tscn"
const ToolPanel = preload("res://levels/tool_panel.gd")
const XRSupport = preload("res://levels/xr_support.gd")
const BACKGROUND := Color("101923")

var title := "Level"
var origin: XROrigin3D
var cam: XRCamera3D
var hands: Array[XRController3D] = []
var xr: OpenXRInterface
var env: Environment
var floor_node: Node3D
var panel
var in_xr := false
var focused := false

var _was_trigger := [false, false]
var _was_face := [false, false]
var _recenter_in := -1.0
var _desktop_camera: Camera3D

func _ready() -> void:
	_build_rig()
	_setup_xr()
	panel = ToolPanel.new()
	panel.setup(hands, cam)
	add_child(panel)
	panel.add_button(&"back", "Return to hub", &"right")
	panel.add_button(&"passthrough", XRSupport.passthrough_label(), &"right")
	panel.pressed.connect(_on_panel_pressed)
	build()
	refresh_passthrough()
	log_line("ready; xr=%s" % in_xr)

# --- Overridables -----------------------------------------------------------

func build() -> void:
	pass

func on_frame(_delta: float) -> void:
	pass

func on_trigger(_hand: int) -> void:
	pass

func on_face_button(_hand: int) -> void:
	pass

# Runs at the start of each physics frame, before trigger and face-button handlers.
func before_input() -> void:
	pass

func on_button(_id: StringName) -> void:
	pass

# Called after the user recentres with the system button; re-place head-relative content here.
func on_recentered() -> void:
	pass

func go_back() -> void:
	get_tree().change_scene_to_file.call_deferred(HUB_SCENE)

# --- Rig ---------------------------------------------------------------------

func _build_rig() -> void:
	origin = XROrigin3D.new()
	origin.name = "XROrigin3D"
	add_child(origin)
	cam = XRCamera3D.new()
	cam.name = "XRCamera3D"
	cam.near = 0.03
	origin.add_child(cam)
	for side in [&"left_hand", &"right_hand"]:
		var hand := XRController3D.new()
		hand.name = String(side)
		hand.tracker = side
		hand.pose = &"grip"
		hand.show_when_tracked = true
		origin.add_child(hand)
		XRSupport.attach_controller_model(hand)
		XRSupport.attach_controller_collider(hand, hands.size())
		hands.append(hand)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9ebbcf")
	env.ambient_light_energy = 0.8
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	floor_node = make_box(self, Vector3(6, 0.02, 6), Vector3(0, -0.01, 0), flat_material(Color("17232f")))

func _setup_xr() -> void:
	xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr != null and xr.is_initialized():
		in_xr = true
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		xr.session_focussed.connect(_set_focus.bind(true))
		xr.session_visible.connect(_set_focus.bind(false))
		xr.session_synchronized.connect(_set_focus.bind(false))
		xr.session_stopping.connect(_quit)
		xr.session_loss_pending.connect(_quit)
		xr.instance_exiting.connect(_quit)
		xr.pose_recentered.connect(_on_pose_recentered)
		focused = xr.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED
	else:
		# No runtime (for example a Windows smoke test): keep running with a plain camera.
		focused = true
		origin.position = Vector3(0, 1.6, 0)
		_desktop_camera = Camera3D.new()
		add_child(_desktop_camera)
		_desktop_camera.position = Vector3(0, 1.6, 0)
		_desktop_camera.make_current()
		push_warning("[%s] OpenXR is not running; desktop fallback has no tracking." % title)

func _set_focus(value: bool) -> void:
	focused = value
	log_line("focus=%s" % value)

func _quit() -> void:
	get_tree().quit()

func _on_pose_recentered() -> void:
	# The new reference space applies from the next frames; wait briefly before reading the head.
	_recenter_in = 0.25

func _on_panel_pressed(id: StringName) -> void:
	if id == &"back":
		go_back()
	elif id == &"passthrough":
		XRSupport.set_passthrough(not XRSupport.passthrough_on())
		refresh_passthrough()
		log_line("passthrough=%s" % XRSupport.passthrough_on())
	else:
		on_button(id)

func refresh_passthrough() -> void:
	XRSupport.apply_passthrough(get_viewport(), env, BACKGROUND, [floor_node])
	panel.set_button_text(&"passthrough", XRSupport.passthrough_label())

func show_lines(lines: Array[String]) -> void:
	panel.set_info(title, lines)

# --- Per-frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	if not panel.placed and head_is_tracked():
		panel.place_default()
	if _recenter_in >= 0.0:
		_recenter_in -= delta
		if _recenter_in < 0.0:
			XRSupport.capture_home(cam)
			panel.place_default()
			on_recentered()
	on_frame(delta)

func _physics_process(_delta: float) -> void:
	before_input()
	for index in range(2):
		var hand := hands[index]
		var tracked := hand.get_is_active() and hand.get_has_tracking_data()
		var trigger := tracked and (hand.is_button_pressed("trigger_click") or hand.get_float("trigger") > 0.8)
		if focused and trigger and not _was_trigger[index] and not panel.uses_hand(index):
			on_trigger(index)
		_was_trigger[index] = trigger
		var face := tracked and hand.is_button_pressed("face_button")
		if focused and face and not _was_face[index]:
			on_face_button(index)
		_was_face[index] = face

# --- Helpers -----------------------------------------------------------------

func log_line(message: String) -> void:
	print("[%s] %s" % [title, message])

func flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material

func glow_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.45
	return material

func make_box(parent: Node3D, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = position
	parent.add_child(mesh)
	return mesh

func make_label(parent: Node3D, text: String, position: Vector3, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.001
	label.modulate = color
	label.position = position
	label.shaded = false
	label.outline_size = 0
	parent.add_child(label)
	return label

# Head-height frame facing the launch direction; the same in every level until a system recentre.
func home_frame() -> Transform3D:
	return XRSupport.home_frame(cam)

func head_is_tracked() -> bool:
	return not in_xr or (focused and cam.global_position.y > 0.3)


func hand_tracked(index: int) -> bool:
	return hands[index].get_is_active() and hands[index].get_has_tracking_data()
