extends Node3D

const CubeScript = preload("res://scripts/grabbable.gd")
const Tests = preload("res://tests/self_test.gd")
const COOL := Color("65d7ec")
const WARM := Color("ffba73")
@onready var interactions = $Interactions
@onready var hands: Array[XRController3D] = [$XROrigin3D/LeftHand, $XROrigin3D/RightHand]
var xr: OpenXRInterface
var desktop := false
var testing := false
var accent: StandardMaterial3D
var state_label: Label3D
var status_time := 0.0
var desktop_distance := 2.0

func _ready() -> void:
	testing = "--self-test" in OS.get_cmdline_user_args()
	desktop = "--desktop" in OS.get_cmdline_user_args()
	_build_room()
	interactions.button_position = $TouchButton.global_position
	interactions.button_toggled.connect(_set_mood)
	interactions.grabbed.connect(_haptic)
	_set_mood(false)
	if testing:
		set_physics_process(false)
		Tests.run(self)
		return
	if desktop:
		$DesktopCamera.look_at(Vector3(0, 0.85, -0.55))
		$DesktopCamera.make_current()
		interactions.set_focused(true)
		_start_audio()
		print("[FieldLab] DESKTOP PREVIEW: mouse drag cubes; hover button to touch. This is not an XR session.")
		return
	xr = XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr == null or not xr.is_initialized():
		push_error("[FieldLab] OpenXR unavailable. Native VR requires a working runtime. For an explicit preview use --xr-mode off -- --desktop.")
		get_tree().quit(2)
		return
	get_viewport().use_xr = true
	get_viewport().physics_object_picking = false
	_start_audio()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	xr.session_begun.connect(func(): print("[FieldLab] session begun"))
	xr.session_focussed.connect(func(): _focus(true))
	xr.session_visible.connect(func(): _focus(false))
	xr.session_synchronized.connect(func(): _focus(false))
	xr.session_stopping.connect(_stop_session)
	xr.session_loss_pending.connect(_stop_session)
	xr.instance_exiting.connect(func(): get_tree().quit())
	_focus(xr.get_session_state() == OpenXRInterface.SESSION_STATE_FOCUSED)
	print("[FieldLab] OpenXR initialized; renderer=%s; physics=90Hz; reference=stage; session=%s" % [RenderingServer.get_current_rendering_method(), xr.get_session_state()])

func _focus(value: bool) -> void:
	interactions.set_focused(value)
	for cube in interactions.cubes:
		var audio := cube.get_node_or_null("Tone") as AudioStreamPlayer3D
		if audio != null:
			audio.stream_paused = not value
	print("[FieldLab] focus=%s; held objects released on loss" % value)

func _stop_session() -> void:
	_focus(false)
	print("[FieldLab] session stopping; exiting")
	get_tree().quit()

func _start_audio() -> void:
	for cube in interactions.cubes:
		var audio := cube.get_node_or_null("Tone") as AudioStreamPlayer3D
		if audio != null:
			audio.play()

func _exit_tree() -> void:
	for cube in interactions.cubes:
		var audio := cube.get_node_or_null("Tone") as AudioStreamPlayer3D
		if audio != null:
			audio.stop()
			audio.stream = null
	# Godot queues stop/fade-out on its audio thread; let that thread release
	# playback references before the engine tears down the audio driver.
	if not testing:
		OS.delay_msec(50)

func _physics_process(delta: float) -> void:
	var touches: Array[Vector3] = []
	if desktop:
		var camera: Camera3D = $DesktopCamera
		var mouse := get_viewport().get_mouse_position()
		var origin := camera.project_ray_origin(mouse)
		var direction := camera.project_ray_normal(mouse)
		var grip := 1.0 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0.0
		if grip > 0.5 and not interactions.squeezed[0]:
			var nearest := INF
			for cube in interactions.cubes:
				var along: float = (cube.global_position - origin).dot(direction)
				if along > 0.0 and cube.global_position.distance_to(origin + direction * along) < 0.12 and along < nearest:
					nearest = along
			if nearest < INF:
				desktop_distance = nearest
		var point := origin + direction * desktop_distance
		interactions.update_hand(0, true, Transform3D(Basis.IDENTITY, point), grip, delta)
		if absf(direction.y) > 0.001:
			var along: float = (interactions.button_position.y - origin.y) / direction.y
			if along > 0.0:
				touches.append(origin + direction * along)
	else:
		for index in range(2):
			var hand := hands[index]
			var tracked := hand.get_is_active() and hand.get_has_tracking_data()
			hand.visible = tracked
			var grip := _grab_strength(hand) if tracked else 0.0
			interactions.update_hand(index, tracked, hand.global_transform, grip, delta)
			if tracked:
				touches.append(hand.global_position)
	interactions.update_touch(touches)
	for cube in interactions.cubes:
		if cube.reset_if_outside():
			print("[FieldLab] reset %s" % cube.name)
	status_time += delta
	if status_time >= 10.0:
		status_time = 0.0
		print("[FieldLab] status mode=%s focus=%s tracked=%s/%s held=%s/%s fps=%d" % ["desktop" if desktop else "OpenXR", interactions.focused, hands[0].get_is_active(), hands[1].get_is_active(), interactions.held[0] != null, interactions.held[1] != null, Engine.get_frames_per_second()])

func _grab_strength(hand: XRController3D) -> float:
	var strength := maxf(hand.get_float("grip"), hand.get_float("trigger"))
	if hand.is_button_pressed("grip_click") or hand.is_button_pressed("trigger_click"):
		strength = 1.0
	return strength

func _haptic(hand: int) -> void:
	if not desktop and not testing and hands[hand].get_is_active():
		hands[hand].trigger_haptic_pulse("haptic", 0.0, 0.25, 0.045, 0.0)

func _set_mood(warm: bool) -> void:
	var color := WARM if warm else COOL
	accent.albedo_color = color
	accent.emission = color
	$KeyLight.light_color = Color("ffe0b5") if warm else Color("b5dfff")
	state_label.text = "AMBER / WARM" if warm else "CYAN / COOL"
	state_label.modulate = color
	if is_node_ready():
		print("[FieldLab] touch state=%s" % state_label.text)

func _material(color: Color, glow := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	material.emission_enabled = glow
	material.emission = color
	material.emission_energy_multiplier = 0.35
	return material

func _box(parent: Node3D, size: Vector3, position: Vector3, material: Material, solid := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = position
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		parent.add_child(body)
		body.position = position
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
	return mesh

func _label(parent: Node3D, text: String, position: Vector3, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.font_size = size
	label.pixel_size = 0.0015
	label.modulate = color
	label.outline_size = 0
	parent.add_child(label)
	return label

func _build_room() -> void:
	accent = _material(COOL, true)
	var dark := _material(Color("17232f"))
	var base := _material(Color("334553"))
	var white := Color("d9e9ed")
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101923")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9ebbcf")
	environment.ambient_light_energy = 0.65
	$WorldEnvironment.environment = environment
	_box($Room, Vector3(8, 0.1, 8), Vector3(0, -0.05, 0), dark, true)
	_box($Room, Vector3(1.35, 0.07, 0.72), Vector3(0, 0.74, -0.65), base, true)
	_box($Room, Vector3(1.25, 0.018, 0.012), Vector3(0, 0.78, -0.30), accent)
	for x in [-0.54, 0.54]:
		_box($Room, Vector3(0.045, 0.70, 0.5), Vector3(x, 0.35, -0.65), base)
	for x in range(-4, 5):
		_box($Room, Vector3(0.006, 0.002, 8), Vector3(x, 0.002, 0), base)
		_box($Room, Vector3(8, 0.002, 0.006), Vector3(0, 0.002, x), base)
	_box($Room, Vector3(1.72, 0.61, 0.06), Vector3(0, 1.50, -1.40), dark)
	_label($Room, "FRAME / FIELD LAB", Vector3(0, 1.69, -1.36), 47, white)
	_label($Room, "01  TRIGGER OR GRIP + THROW   /   02  MOVE THE SOUND", Vector3(0, 1.56, -1.36), 18, white)
	_label($Room, "03  TOUCH THE LIGHT SWITCH", Vector3(0, 1.49, -1.36), 19, white)
	state_label = _label($Room, "", Vector3(0, 1.34, -1.36), 27, COOL)
	_box($TouchButton, Vector3(0.18, 0.04, 0.18), Vector3(0, -0.04, 0), dark)
	_box($TouchButton, Vector3(0.13, 0.035, 0.13), Vector3.ZERO, accent)
	var touch_label := _label($TouchButton, "TOUCH", Vector3(0, 0.023, 0), 19, Color("152432"))
	touch_label.rotation_degrees.x = -90
	var colors := [Color("ed826a"), Color("e8c36a"), Color("a99de7")]
	for index in range(3):
		_make_cube("ThrowCube%d" % (index + 1), Vector3(-0.33 + index * 0.22, 0.85, -0.54), colors[index], false, 0)
		_make_cube("SoundCube%d" % (index + 1), Vector3(-0.34 + index * 0.34, 1.12, -0.62), colors[index], true, 180 + index * 90)
	for index in range(2):
		_box(hands[index], Vector3(0.055, 0.055, 0.09), Vector3.ZERO, _material(COOL if index == 0 else WARM, true))
		hands[index].visible = false

func _make_cube(title: String, position: Vector3, color: Color, floating: bool, frequency: int) -> void:
	var cube := RigidBody3D.new()
	cube.set_script(CubeScript)
	cube.name = title
	cube.floating = floating
	cube.freeze = floating
	cube.mass = 0.15
	cube.continuous_cd = true
	$Cubes.add_child(cube)
	cube.position = position
	cube.home = cube.global_transform
	var size := Vector3.ONE * (0.105 if floating else 0.095)
	_box(cube, size, Vector3.ZERO, _material(color, floating))
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	cube.add_child(collider)
	interactions.cubes.append(cube)
	if floating:
		var audio := AudioStreamPlayer3D.new()
		audio.name = "Tone"
		audio.stream = _tone(frequency)
		audio.volume_db = -22.0
		audio.unit_size = 0.35
		audio.max_distance = 4.0
		cube.add_child(audio)

func _tone(frequency: int) -> AudioStreamWAV:
	# Integer frequencies in a one-second buffer produce a seamless mono loop.
	var rate := 22050
	var data := PackedByteArray()
	data.resize(rate * 2)
	for index in range(rate):
		var phase := TAU * float(index) / rate
		var sample := (sin(phase * frequency) * 0.7 + sin(phase * frequency * 2) * 0.18) * 14000.0
		data.encode_s16(index * 2, int(sample))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = rate
	return stream
