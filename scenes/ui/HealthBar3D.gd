extends Node3D

const BAR_W := 1.4
const BAR_H := 0.14

var _fg_mesh: QuadMesh
var _fg_mat:  StandardMaterial3D
var _fg_node: MeshInstance3D

func _ready() -> void:
	# Background — centered, stays fixed
	var bg      := MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(BAR_W + 0.07, BAR_H + 0.07)
	bg.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color    = Color(0.08, 0.08, 0.08, 0.88)
	bg_mat.transparency    = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.shading_mode    = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode  = BaseMaterial3D.BILLBOARD_ENABLED
	bg_mat.no_depth_test   = true
	bg_mat.render_priority = 3
	bg.material_override   = bg_mat
	bg.cast_shadow         = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bg)

	# Foreground — same world-space origin, shifted via center_offset in mesh
	# local space so the offset stays correctly screen-aligned after billboarding.
	_fg_node = MeshInstance3D.new()
	_fg_mesh = QuadMesh.new()
	_fg_mesh.size = Vector2(BAR_W, BAR_H)
	_fg_node.mesh = _fg_mesh
	_fg_mat = StandardMaterial3D.new()
	_fg_mat.albedo_color   = Color(0.15, 0.85, 0.2)
	_fg_mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_fg_mat.no_depth_test  = true
	_fg_mat.render_priority = 4
	_fg_node.material_override = _fg_mat
	_fg_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fg_node)

func set_fraction(t: float) -> void:
	t = clampf(t, 0.0, 1.0)
	if not is_instance_valid(_fg_node):
		return

	_fg_mesh.size = Vector2(BAR_W * t, BAR_H)
	# Shift the mesh in its own local space (screen-horizontal after billboard),
	# keeping the left edge pinned to -BAR_W/2 regardless of fill amount.
	_fg_mesh.center_offset = Vector3(BAR_W * (t - 1.0) * 0.5, 0.0, 0.0)

	# green → yellow → red
	var c: Color
	if t >= 0.5:
		c = Color(0.15, 0.85, 0.2).lerp(Color(1.0, 0.85, 0.1), (1.0 - t) * 2.0)
	else:
		c = Color(1.0, 0.85, 0.1).lerp(Color(0.9, 0.1, 0.05), (0.5 - t) * 2.0)
	_fg_mat.albedo_color = c
