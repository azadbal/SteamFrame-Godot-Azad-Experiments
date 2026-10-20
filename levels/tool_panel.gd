extends Node3D
# Options and info panel: floats within arm's reach to the right of the launch direction.
# Text at the top; level options bottom-left; Passthrough and Return to hub (or Quit) bottom-right.
# Text is a RichTextLabel drawn into a SubViewport, so it can have a title, section headers ("# "
# lines), bullets ("- " lines) and muted notes ("~ " lines). With frame_lab/debug/text_composition_layer
# on (the default) it is shown as an OpenXR quad composition layer: the compositor samples it at
# display resolution, so small text stays sharp, and a hole punch keeps it behind anything in front.
# The layer can trail the scene slightly during fast head turns. With the setting off, or without
# OpenXR, it is a textured quad in the scene.
# Press a button: touch it with the controller and pull that controller's trigger.
# Move the panel: touch it anywhere off the buttons (the frame lights up), squeeze the grip, carry it.
# Debug: with project setting frame_lab/debug/panel_position_save on, a "Save position" button (top
# right) stores the panel's pose relative to the launch direction for this level in
# user://panel_positions.json; while the setting is on, saved poses replace the defaults below.

signal pressed(id: StringName)

const XRSupport = preload("res://levels/xr_support.gd")
const SIZE := Vector2(0.40, 0.26)
const BUTTON_SIZE := Vector3(0.09, 0.04, 0.016)
const BUTTON_MARGIN := 0.005
const GRAB_MARGIN := 0.02
const COLUMNS := [-0.145, -0.045, 0.045, 0.145] # left pair: level options; right pair: global
const ROWS := [-0.055, -0.103]      # level options, top row first
const RIGHT_ROWS := [-0.103, 0.0]   # global buttons: Return to hub at the bottom, Passthrough well above it
const TEXT_SIZE := Vector2(SIZE.x - 0.13, 0.15) # clear of the right-hand column and the option buttons
# About 1.5x the Frame's display density at the panel's distance (0.27 m spans ~23 deg, ~400 px).
# Much larger textures get minified without mipmaps, which is what made the text shimmer.
const TEXT_PIXELS := Vector2i(640, 356)
const TITLE_FONT := 30
const BODY_FONT := 21
const HEADER_FONT := 18
const MUTED_FONT := 17
const PANEL_COLOR := Color(0.06, 0.09, 0.12)
const TEXT_COLOR := Color("e6f1f5")
const HEADER_COLOR := Color("9ebbcf")
const MUTED_COLOR := Color("8494a0")
# Poses relative to the launch direction, saved in the headset on 19 October 2026 (12 floats:
# basis x, y, z columns, then origin). The hub's pose is also used in the eye tracking level.
const HUB_POSE := [0.538473665714264, 0.0, 0.842641949653625, 0.22784212231636, 0.962749898433685, -0.145598009228706, -0.811253011226654, 0.27038985490799, 0.518415212631226, 0.591495156288147, -0.16926771402359, -0.297823339700699]
const DEFAULT_POSES := {
	"hub": HUB_POSE,
	"eye_tracking_cubes": HUB_POSE,
	"cube_lab": [0.449682265520096, 0.0, 0.893188178539276, 0.153790131211281, 0.985060155391693, -0.0774267837405205, -0.879845857620239, 0.172181323170662, 0.442964941263199, 0.674290001392365, -0.108813524246216, -0.276103347539902],
}
# Fallback for levels without a pose: 45 degrees right, 0.5 m out, 0.2 m below eye height.
const PLACE_YAW_DEG := -45.0 # negative yaw turns right
const PLACE_DISTANCE := 0.5
const PLACE_DROP := 0.2
const IDLE := Color("334553")
const HOT := Color("ffba73")
const FRAME_IDLE := Color("7f97a8")
const FRAME_HOT := Color("ffba73")
const DEBUG_SAVE_SETTING := "frame_lab/debug/panel_position_save"
const LAYER_SETTING := "frame_lab/debug/text_composition_layer"
const POSITIONS_PATH := "user://panel_positions.json"

var hands: Array[XRController3D] = []
var head: Node3D
var placed := false

var _viewport: SubViewport
var _rich: RichTextLabel
var _redraw := 0
var _layer: OpenXRCompositionLayerQuad
var _frame_material: StandardMaterial3D
var _buttons := {}       # id -> {"node", "material", "label"}
var _left: Array[StringName] = []
var _right: Array[StringName] = []
var _hover := [&"", &""]
var _grab_offset := [null, null]
var _grabbable := [false, false]
var _was_trigger := [false, false]
var _was_grip := [false, false]
var _text := ""
var _saved_flash := 0.0

func setup(hand_nodes: Array[XRController3D], head_node: Node3D) -> void:
	hands = hand_nodes
	head = head_node

func _ready() -> void:
	var back := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SIZE
	back.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = PANEL_COLOR # opaque, to match the text layer's background
	back.material_override = material
	add_child(back)
	_frame_material = StandardMaterial3D.new()
	_frame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_frame_material.albedo_color = FRAME_IDLE
	var bar := 0.012
	for side in [-1, 1]:
		_add_bar(Vector3(SIZE.x + bar * 2, bar, bar), Vector3(0, side * (SIZE.y + bar) * 0.5, 0))
		_add_bar(Vector3(bar, SIZE.y, bar), Vector3(side * (SIZE.x + bar) * 0.5, 0, 0))
	_build_text()
	if ProjectSettings.get_setting(DEBUG_SAVE_SETTING, false):
		_make_button(&"save_position", "Save position").position = Vector3(COLUMNS[3], SIZE.y * 0.5 - BUTTON_SIZE.y * 0.5 - 0.01, BUTTON_SIZE.z * 0.5)

func _add_bar(size: Vector3, position: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _frame_material
	mesh.position = position
	add_child(mesh)

func _build_text() -> void:
	_viewport = SubViewport.new()
	_viewport.size = TEXT_PIXELS
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	var background := ColorRect.new()
	background.color = PANEL_COLOR
	background.size = Vector2(TEXT_PIXELS)
	_viewport.add_child(background)
	_rich = RichTextLabel.new()
	_rich.bbcode_enabled = true
	_rich.scroll_active = false
	_rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rich.size = Vector2(TEXT_PIXELS)
	_rich.add_theme_font_size_override("normal_font_size", BODY_FONT)
	_rich.add_theme_font_size_override("bold_font_size", BODY_FONT)
	_rich.add_theme_color_override("default_color", TEXT_COLOR)
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = 0.6
	_rich.add_theme_font_override("bold_font", bold)
	_viewport.add_child(_rich)
	var position := Vector3(-SIZE.x * 0.5 + 0.01 + TEXT_SIZE.x * 0.5, SIZE.y * 0.5 - 0.01 - TEXT_SIZE.y * 0.5, 0.002)
	if XRSupport.openxr() != null and ProjectSettings.get_setting(LAYER_SETTING, false):
		var layer := OpenXRCompositionLayerQuad.new()
		layer.position = position
		add_child(layer)
		layer.layer_viewport = _viewport
		layer.quad_size = TEXT_SIZE
		layer.sort_order = -1 # behind the scene, seen through the hole punch
		layer.enable_hole_punch = true
		layer.alpha_blend = false
		if layer.is_natively_supported():
			_layer = layer
			# The layer's swapchain is filled whenever the viewport renders; _process only lets it
			# render while the session is visible, since frames that are never submitted would
			# leave the swapchain image acquired.
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			return
		layer.queue_free()
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = TEXT_SIZE
	quad.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _viewport.get_texture()
	quad.material_override = material
	quad.position = position
	add_child(quad)

# title is shown large. lines: "# Header", "- bullet", "~ muted note"; anything else is plain text.
func set_info(title: String, lines: Array[String]) -> void:
	var bb := "[font_size=%d][b]%s[/b][/font_size]\n" % [TITLE_FONT, _escape(title)]
	for line in lines:
		if line.begins_with("# "):
			bb += "[font_size=%d][color=#%s][b]%s[/b][/color][/font_size]\n" % [HEADER_FONT, HEADER_COLOR.to_html(false), _escape(line.substr(2).to_upper())]
		elif line.begins_with("- "):
			bb += "[indent]• %s[/indent]\n" % _escape(line.substr(2))
		elif line.begins_with("~ "):
			bb += "[font_size=%d][color=#%s]%s[/color][/font_size]\n" % [MUTED_FONT, MUTED_COLOR.to_html(false), _escape(line.substr(2))]
		else:
			bb += _escape(line) + "\n"
	if bb != _text:
		_text = bb
		_rich.text = bb
		# The label lays out on its next frame; redraw the viewport for a couple of frames after.
		_redraw = 2

func _escape(text: String) -> String:
	return text.replace("[", "[lb]")

# side: &"left" for level options (up to 4), &"right" for global buttons (up to 4, filled from the bottom-right).
func add_button(id: StringName, text: String, side := &"left") -> void:
	var node := _make_button(id, text)
	if side == &"left":
		var index := _left.size()
		_left.append(id)
		node.position = Vector3(COLUMNS[index % 2], ROWS[index / 2], BUTTON_SIZE.z * 0.5)
	else:
		# Bottom-right first, then the slot above it, then the inner column.
		var index := _right.size()
		_right.append(id)
		node.position = Vector3(COLUMNS[3 - index / 2], RIGHT_ROWS[index % 2], BUTTON_SIZE.z * 0.5)

func _make_button(id: StringName, text: String) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = BUTTON_SIZE
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = IDLE
	material.emission_enabled = true
	material.emission = IDLE
	material.emission_energy_multiplier = 0.45
	mesh.material_override = material
	node.add_child(mesh)
	var label := Label3D.new()
	label.text = text
	label.pixel_size = 0.0004
	label.font_size = 24
	label.width = (BUTTON_SIZE.x - 0.006) / label.pixel_size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.shaded = false
	label.outline_size = 0
	label.position = Vector3(0, 0, BUTTON_SIZE.z * 0.5 + 0.001)
	node.add_child(label)
	_buttons[id] = {"node": node, "material": material, "label": label}
	return node

func set_button_text(id: StringName, text: String) -> void:
	if _buttons.has(id):
		(_buttons[id]["label"] as Label3D).text = text

# True while this hand is on a button or carrying the panel, so the level should ignore it.
func uses_hand(index: int) -> bool:
	return _hover[index] != &"" or _grab_offset[index] != null

func place_default() -> void:
	if head == null:
		return
	var home := XRSupport.home_frame(head)
	var pose: Array = DEFAULT_POSES.get(_level_key(), [])
	if ProjectSettings.get_setting(DEBUG_SAVE_SETTING, false):
		pose = _load_positions().get(_level_key(), {}).get("transform", pose)
	if pose.size() == 12:
		global_transform = home * Transform3D(Vector3(pose[0], pose[1], pose[2]), Vector3(pose[3], pose[4], pose[5]), Vector3(pose[6], pose[7], pose[8]), Vector3(pose[9], pose[10], pose[11]))
		placed = true
		return
	var direction := home.basis * Basis(Vector3.UP, deg_to_rad(PLACE_YAW_DEG)) * Vector3.FORWARD
	global_position = home.origin + direction * PLACE_DISTANCE + Vector3.DOWN * PLACE_DROP
	_face(home.origin)
	placed = true

func _face(target: Vector3) -> void:
	if target.distance_to(global_position) > 0.05:
		look_at(target, Vector3.UP, true)

func _physics_process(_delta: float) -> void:
	for index in range(hands.size()):
		var hand := hands[index]
		var tracked := hand.get_is_active() and hand.get_has_tracking_data()
		var trigger := tracked and (hand.is_button_pressed("trigger_click") or hand.get_float("trigger") > 0.8)
		var grip := tracked and (hand.is_button_pressed("grip_click") or hand.get_float("grip") > 0.8)
		_hover[index] = &""
		_grabbable[index] = false
		if tracked and _grab_offset[index] == null:
			# Of the buttons the controller touches, take the one closest to the controller.
			var nearest := INF
			for id in _buttons:
				var button: Node3D = _buttons[id]["node"]
				if XRSupport.hand_touches_box(self, index, button.global_transform, BUTTON_SIZE * 0.5, BUTTON_MARGIN):
					var distance := hand.global_position.distance_to(button.global_position)
					if distance < nearest:
						nearest = distance
						_hover[index] = id
			_grabbable[index] = _hover[index] == &"" and XRSupport.hand_touches_box(self, index, global_transform, Vector3(SIZE.x * 0.5, SIZE.y * 0.5, 0.01), GRAB_MARGIN)
		if trigger and not _was_trigger[index] and _hover[index] != &"":
			if _hover[index] == &"save_position":
				_save_position()
			else:
				pressed.emit(_hover[index])
		if grip and not _was_grip[index] and _grabbable[index]:
			_grab_offset[index] = global_position - hand.global_position
		if not grip:
			_grab_offset[index] = null
		if _grab_offset[index] != null:
			global_position = hand.global_position + _grab_offset[index]
			if head != null:
				_face(head.global_position)
		_was_trigger[index] = trigger
		_was_grip[index] = grip
	for id in _buttons:
		var hot: bool = _hover[0] == id or _hover[1] == id
		var material: StandardMaterial3D = _buttons[id]["material"]
		material.albedo_color = HOT if hot else IDLE
		material.emission = material.albedo_color
	var frame_hot: bool = _grabbable[0] or _grabbable[1] or _grab_offset[0] != null or _grab_offset[1] != null
	_frame_material.albedo_color = FRAME_HOT if frame_hot else FRAME_IDLE

func _process(delta: float) -> void:
	if _layer != null:
		var xr := XRSupport.openxr()
		var visible := xr != null and xr.get_session_state() in [OpenXRInterface.SESSION_STATE_VISIBLE, OpenXRInterface.SESSION_STATE_FOCUSED]
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	elif _redraw > 0:
		_redraw -= 1
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _saved_flash > 0.0:
		_saved_flash -= delta
		if _saved_flash <= 0.0:
			set_button_text(&"save_position", "Save position")

func _level_key() -> String:
	var path := get_parent().scene_file_path if get_parent() != null else ""
	return path.get_file().get_basename() if path != "" else "unknown"

func _load_positions() -> Dictionary:
	if not FileAccess.file_exists(POSITIONS_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(POSITIONS_PATH))
	return parsed if parsed is Dictionary else {}

# Stores this panel's pose relative to the launch direction, keyed by level scene name.
func _save_position() -> void:
	if head == null:
		return
	var local := XRSupport.home_frame(head).affine_inverse() * global_transform
	var b := local.basis
	var positions := _load_positions()
	positions[_level_key()] = {
		"transform": [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, local.origin.x, local.origin.y, local.origin.z],
		"distance_m": Vector2(local.origin.x, local.origin.z).length(),
		"yaw_deg": rad_to_deg(atan2(local.origin.x, -local.origin.z)),
		"drop_m": -local.origin.y,
	}
	var file := FileAccess.open(POSITIONS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(positions, "\t"))
		file.close()
	print("[Panel] saved %s: %s" % [_level_key(), JSON.stringify(positions[_level_key()])])
	set_button_text(&"save_position", "Saved!")
	_saved_flash = 1.5

