extends Node3D
# Collider for one controller: a sphere around the controller's front tip (along the grip pose's -Z
# axis). Other code asks "does this hand touch X?" through XRSupport.hand_touches_*(), which runs a
# physics shape query against this hand's layer. The sphere is drawn translucent while
# frame_lab/debug/show_controller_colliders is on.

const TIP := Vector3(0, 0, -0.07) # sphere centre, relative to the grip pose
const RADIUS := 0.045
const DEBUG_SETTING := "frame_lab/debug/show_controller_colliders"

var layer := 1

func _ready() -> void:
	var area := Area3D.new()
	area.collision_layer = layer
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	area.position = TIP
	add_child(area)
	var collider := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	collider.shape = sphere
	area.add_child(collider)
	if ProjectSettings.get_setting(DEBUG_SETTING, false):
		var view := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = RADIUS
		mesh.height = RADIUS * 2.0
		view.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.3, 0.9, 1.0, 0.22)
		view.material_override = material
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		area.add_child(view)
