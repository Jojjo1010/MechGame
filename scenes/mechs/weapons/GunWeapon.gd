extends "res://scenes/mechs/weapons/BaseWeapon.gd"

const BULLET_SCRIPT := preload("res://scenes/projectiles/Bullet.gd")

const FIRE_RATE       := 0.8
const ULT_COOLDOWN    := 10.0
const ULT_COUNT       := 7
const ULT_SPREAD_DEG  := 44.0
const ULT_DAMAGE_MULT := 1.5
const CONE_LEN        := 9.0

var _aiming:           bool    = false
var _aim_dir:          Vector3 = Vector3.ZERO
var _aim_root:         Node3D  = null
var _aim_im:           ImmediateMesh = null
var _aim_mat:          StandardMaterial3D = null
var _gun_drone_nearby: bool    = false

func _on_setup() -> void:
	weapon_name = "GUN"
	_aim_dir = Vector3(0.0, 0.0, -1.0)

func notify_drone_nearby(nearby: bool) -> void:
	_gun_drone_nearby = nearby
	super.notify_drone_nearby(nearby)

func get_fire_rate() -> float:
	return FIRE_RATE

func get_ult_cooldown() -> float:
	return ULT_COOLDOWN

# ── Override to enter aiming mode instead of instant fire ────────────────────
func activate_ult() -> bool:
	if not is_ready():
		return false
	if _aiming:
		return false
	_start_aiming()
	return true

# ── Passive fire ─────────────────────────────────────────────────────────────
func _passive_fire() -> void:
	if _aiming:
		return   # pause passive fire while player aims
	var nearest := _nearest_enemy()
	if nearest == null:
		return
	var muzzle := _mech.global_position + Vector3(0.0, 2.0, 0.0)
	var target_pos := nearest.global_position + Vector3(0.0, 0.8, 0.0)
	var dir := (target_pos - muzzle).normalized()
	_shoot(muzzle, dir, 1.0)
	_muzzle_flash(muzzle)
	_mech.trigger_flash()
	AudioManager.play("gun_fire", muzzle, -6.0, randf_range(0.92, 1.08))

# ── Aiming mode ──────────────────────────────────────────────────────────────
func _start_aiming() -> void:
	_aiming = true
	_hide_e_label()
	_build_cone()

func _cancel_aiming() -> void:
	_aiming = false
	_destroy_cone()
	if _gun_drone_nearby and is_ready():
		_show_e_label()

func _confirm_and_fire() -> void:
	_aiming = false
	_reset_cooldown()
	_destroy_cone()

	var muzzle := _mech.global_position + Vector3(0.0, 2.0, 0.0)
	for i in ULT_COUNT:
		var t   := (float(i) / float(ULT_COUNT - 1)) - 0.5
		var dir := _aim_dir.rotated(Vector3.UP, t * deg_to_rad(ULT_SPREAD_DEG))
		_shoot(muzzle, dir, ULT_DAMAGE_MULT)
	_muzzle_flash(muzzle)
	_mech.trigger_flash()
	AudioManager.play("gun_ult", muzzle, -2.0)

# ── Input: mouse aim + click to fire ─────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not _aiming:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_and_fire()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_aiming()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	super._process(delta)

	if not _aiming or _mech == null:
		return

	# Project mouse cursor onto the ground plane at mech height
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse  := get_viewport().get_mouse_position()
	var ray_o  := camera.project_ray_origin(mouse)
	var ray_d  := camera.project_ray_normal(mouse)
	var plane_y := _mech.global_position.y
	if abs(ray_d.y) > 0.001:
		var t      := (plane_y - ray_o.y) / ray_d.y
		var target := ray_o + ray_d * t
		var diff   := target - _mech.global_position
		diff.y = 0.0
		if diff.length_squared() > 0.1:
			_aim_dir = diff.normalized()

	_update_cone()

# ── Cone mesh ─────────────────────────────────────────────────────────────────
func _build_cone() -> void:
	_aim_root = Node3D.new()
	get_tree().current_scene.add_child(_aim_root)

	_aim_im  = ImmediateMesh.new()
	_aim_mat = StandardMaterial3D.new()
	_aim_mat.albedo_color              = Color(0.35, 0.70, 1.0, 0.28)
	_aim_mat.emission_enabled          = true
	_aim_mat.emission                  = Color(0.2, 0.55, 1.0)
	_aim_mat.emission_energy_multiplier = 2.5
	_aim_mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	_aim_mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_mat.cull_mode                 = BaseMaterial3D.CULL_DISABLED
	_aim_mat.no_depth_test             = true
	_aim_mat.render_priority           = 7

	var mi := MeshInstance3D.new()
	mi.mesh              = _aim_im
	mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _aim_mat
	_aim_root.add_child(mi)

	# Two glowing edge lines as thin capsules (left = -1, right = +1)
	for side: int in [-1, 1]:
		var edge := MeshInstance3D.new()
		var cap  := CapsuleMesh.new()
		cap.radius          = 0.05
		cap.height          = CONE_LEN
		cap.radial_segments = 5
		cap.rings           = 1
		edge.mesh        = cap
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var emat := StandardMaterial3D.new()
		emat.albedo_color              = Color(0.6, 0.88, 1.0, 0.92)
		emat.emission_enabled          = true
		emat.emission                  = Color(0.3, 0.65, 1.0)
		emat.emission_energy_multiplier = 6.0
		emat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
		emat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
		emat.no_depth_test             = true
		emat.render_priority           = 8
		edge.material_override = emat
		edge.set_meta("side", side)
		_aim_root.add_child(edge)

func _update_cone() -> void:
	if _aim_root == null or not is_instance_valid(_aim_root):
		return

	var origin := _mech.global_position + Vector3(0.0, 0.15, 0.0)
	var half   := deg_to_rad(ULT_SPREAD_DEG * 0.5)
	const SEGS := 16

	# Rebuild filled fan
	_aim_im.clear_surfaces()
	_aim_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGS:
		var a0 := lerpf(-half, half, float(i)     / float(SEGS))
		var a1 := lerpf(-half, half, float(i + 1) / float(SEGS))
		var p0 := origin + _aim_dir.rotated(Vector3.UP, a0) * CONE_LEN
		var p1 := origin + _aim_dir.rotated(Vector3.UP, a1) * CONE_LEN
		_aim_im.surface_add_vertex(origin)
		_aim_im.surface_add_vertex(p0)
		_aim_im.surface_add_vertex(p1)
	_aim_im.surface_end()

	# Orient edge capsules along their respective edges
	for child in _aim_root.get_children():
		if not (child is MeshInstance3D) or not child.has_meta("side"):
			continue
		var side: int    = child.get_meta("side") as int
		var edge_dir     := _aim_dir.rotated(Vector3.UP, half * side)
		var mid_pos      := origin + edge_dir * (CONE_LEN * 0.5)
		var ref          := Vector3.FORWARD if abs(edge_dir.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
		var right        := edge_dir.cross(ref).normalized()
		var fwd          := right.cross(edge_dir).normalized()
		child.global_position        = mid_pos
		child.global_transform.basis = Basis(right, edge_dir, -fwd)

func _destroy_cone() -> void:
	if is_instance_valid(_aim_root):
		_aim_root.queue_free()
	_aim_root = null
	_aim_im   = null
	_aim_mat  = null

# ── Bullet + flash helpers ───────────────────────────────────────────────────
func _shoot(from: Vector3, dir: Vector3, dmg_mult: float) -> void:
	var b := Node3D.new()
	b.set_script(BULLET_SCRIPT)
	get_tree().current_scene.add_child(b)
	b.launch(from, dir, dmg_mult)

func _muzzle_flash(pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sph   := SphereMesh.new()
	sph.radius = 0.45
	sph.height = 0.9
	flash.mesh = sph
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color              = Color(1.0, 0.9, 0.4)
	mat.emission_enabled          = true
	mat.emission                  = Color(1.0, 0.7, 0.1)
	mat.emission_energy_multiplier = 6.0
	mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = mat
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos
	var light := OmniLight3D.new()
	light.light_color    = Color(1.0, 0.65, 0.1)
	light.light_energy   = 8.0
	light.omni_range     = 5.0
	light.shadow_enabled = false
	flash.add_child(light)
	var tw := flash.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.10)
	tw.tween_callback(flash.queue_free)
