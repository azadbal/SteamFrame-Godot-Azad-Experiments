extends RefCounted
# Helpers shared by the hub, the eye tracking level and the cube lab.

# --- Home frame ----------------------------------------------------------------
# The forward direction is captured once, the first time the head is tracked after launch, and
# reused by every level so content does not move when you change level. A system-button recentre
# captures it again. Stored on Engine so it survives scene changes.
const HOME_KEY := &"frame_lab_home"

static func has_home() -> bool:
	return Engine.has_meta(HOME_KEY)

# Head-height frame at the head's XZ, facing the head's horizontal forward direction.
static func capture_home(head: Node3D) -> Transform3D:
	var view := head.global_transform
	var forward := -view.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.001 else Vector3.FORWARD
	var home := Transform3D(Basis.looking_at(forward, Vector3.UP), view.origin)
	Engine.set_meta(HOME_KEY, home)
	return home

static func home_frame(head: Node3D) -> Transform3D:
	return Engine.get_meta(HOME_KEY) if has_home() else capture_home(head)

# --- Controller colliders -----------------------------------------------------------
# Each controller carries a capsule collider (see controller_collider.gd) on its own physics layer,
# so a shape query can tell which hand touches what. Hand index 0 is left, 1 right.
const HAND_LAYERS := [1 << 19, 1 << 20] # physics layers 20 and 21

static func attach_controller_collider(hand: XRController3D, index: int) -> void:
	var collider: Node3D = load("res://levels/controller_collider.gd").new()
	collider.name = "ControllerCollider"
	collider.layer = HAND_LAYERS[index]
	hand.add_child(collider)

# True when hand `index` overlaps `shape` placed at `shape_transform`. Call from physics frames.
static func hand_touches_shape(context: Node3D, index: int, shape: Shape3D, shape_transform: Transform3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = shape_transform.orthonormalized()
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.collision_mask = HAND_LAYERS[index]
	return not context.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

# True when hand `index` overlaps a box (centre transform, half extents) grown by `margin`.
static func hand_touches_box(context: Node3D, index: int, box_transform: Transform3D, half_extents: Vector3, margin := 0.0) -> bool:
	var box := BoxShape3D.new()
	box.size = (half_extents + Vector3.ONE * margin) * 2.0
	return hand_touches_shape(context, index, box, box_transform)

# --- Passthrough -------------------------------------------------------------------
# Passthrough is the runtime's ALPHA_BLEND environment mode. The mode lives on the OpenXR
# interface, so it carries over when the level changes.
static func openxr() -> OpenXRInterface:
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	return xr if xr != null and xr.is_initialized() else null

static func passthrough_available() -> bool:
	var xr := openxr()
	return xr != null and XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in xr.get_supported_environment_blend_modes()

static func passthrough_on() -> bool:
	var xr := openxr()
	return xr != null and xr.environment_blend_mode == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND

static func set_passthrough(on: bool) -> bool:
	var xr := openxr()
	if xr == null:
		return false
	return xr.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND if on else XRInterface.XR_ENV_BLEND_MODE_OPAQUE)

static func passthrough_label() -> String:
	if not passthrough_available():
		return "Passthrough: n/a"
	return "Passthrough: ON" if passthrough_on() else "Passthrough: OFF"

# Alpha blend shows the room only where the frame is transparent, so clear to alpha 0 and hide the floor.
static func apply_passthrough(viewport: Viewport, env: Environment, opaque_color: Color, floor_nodes: Array) -> void:
	var on := passthrough_on()
	viewport.transparent_bg = on
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0) if on else opaque_color
	for node in floor_nodes:
		(node as Node3D).visible = not on

# --- Controller models -------------------------------------------------------------
# Shows the runtime's controller model (XR_EXT_render_model) on a hand.
static func attach_controller_model(hand: XRController3D) -> void:
	# Without the extension (no runtime, or a runtime lacking it) the manager logs errors every frame.
	var extension: Object = Engine.get_singleton("OpenXRRenderModelExtension") if Engine.has_singleton("OpenXRRenderModelExtension") else null
	if extension == null or not extension.is_active():
		return
	var manager := OpenXRRenderModelManager.new()
	manager.tracker = OpenXRRenderModelManager.RENDER_MODEL_TRACKER_LEFT_HAND if hand.tracker == &"left_hand" else OpenXRRenderModelManager.RENDER_MODEL_TRACKER_RIGHT_HAND
	manager.make_local_to_pose = "grip"
	hand.add_child(manager)
