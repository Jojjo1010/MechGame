extends Node3D

const SPEED        := 14.0
const HEIGHT       := 2.2
const TILT_AMOUNT  := 0.15
const SCREEN_MARGIN := 40.0

const MECH_SPEED   := 3.0

const DAZE_RADIUS     := 1.3   # world units — how close an enemy must be to daze the drone
const DAZE_DURATION   := 1.0   # seconds daze lasts
const DAZE_SPEED_MULT := 0.5   # fraction of normal speed while dazed
const KNOCKBACK_FORCE := 18.0  # impulse strength away from the enemy

var player_controlled: bool = false
var repair_locked: bool = false
var velocity := Vector3.ZERO
var _camera: Camera3D
var _daze_timer: float = 0.0
var _daze_mat: StandardMaterial3D = null
var _mesh_instances: Array[MeshInstance3D] = []
var _blob_shadow: MeshInstance3D = null
var _blob_shadow_mat: StandardMaterial3D = null

func _ready() -> void:
	add_to_group("drones")
	position.y = HEIGHT

	# Collect meshes for daze overlay
	for child in find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi:
			_mesh_instances.append(mi)

	_add_blob_shadow()
	AudioManager.play_loop_on("drone_hum_loop", self, -22.0)

	# Red-tint overlay applied while dazed
	_daze_mat = StandardMaterial3D.new()
	_daze_mat.albedo_color  = Color(1.0, 0.15, 0.15, 0.55)
	_daze_mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	_daze_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_daze_mat.render_priority = 5

func _add_blob_shadow() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius      = 0.52
	cyl.bottom_radius   = 0.52
	cyl.height          = 0.01
	cyl.radial_segments = 16
	_blob_shadow_mat = StandardMaterial3D.new()
	_blob_shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.40)
	_blob_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blob_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blob_shadow_mat.no_depth_test = false
	_blob_shadow = MeshInstance3D.new()
	_blob_shadow.mesh              = cyl
	_blob_shadow.material_override = _blob_shadow_mat
	_blob_shadow.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_blob_shadow)

func _process(delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return

	# Blob shadow: keep it pinned to ground level, fade with height
	if is_instance_valid(_blob_shadow) and _blob_shadow_mat != null:
		_blob_shadow.global_position = Vector3(global_position.x, 0.04, global_position.z)
		var h := maxf(global_position.y, 0.1)
		_blob_shadow_mat.albedo_color.a = clampf(0.42 / (h * 0.38 + 0.6), 0.05, 0.42)

	if not player_controlled:
		return

	if repair_locked:
		position.z -= MECH_SPEED * delta   # keep marching with mechs, block player input
		return

	# Check for enemy contacts → daze
	_check_enemy_contact()

	# Tick daze down
	var was_dazed := _daze_timer > 0.0
	_daze_timer = maxf(0.0, _daze_timer - delta)
	if was_dazed and _daze_timer <= 0.0:
		_set_daze_visual(false)

	var dazed := _daze_timer > 0.0
	var effective_speed := SPEED * (DAZE_SPEED_MULT if dazed else 1.0)

	# Always march with the mech line, but slow it during daze so knockback can push through
	position.z -= MECH_SPEED * (DAZE_SPEED_MULT if dazed else 1.0) * delta

	var cam_fwd   := _cam_forward()
	var cam_right := _cam_right()

	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input += cam_fwd
	if Input.is_key_pressed(KEY_S): input -= cam_fwd
	if Input.is_key_pressed(KEY_A): input -= cam_right
	if Input.is_key_pressed(KEY_D): input += cam_right

	if input.length() > 0.0:
		input = input.normalized()

	if dazed:
		# Ignore player input — let knockback decay naturally so it can push from any direction
		velocity = velocity.lerp(Vector3.ZERO, 4.0 * delta)
	else:
		velocity = velocity.lerp(input * effective_speed, 10.0 * delta)
	position += velocity * delta
	position.y = HEIGHT

	_resolve_mech_collisions()
	_clamp_to_viewport()

	if velocity.length() > 0.1:
		var tilt_target := Vector3(velocity.z, 0.0, -velocity.x) * TILT_AMOUNT
		rotation = rotation.lerp(tilt_target, 8.0 * delta)
	else:
		rotation = rotation.lerp(Vector3.ZERO, 8.0 * delta)

func _check_enemy_contact() -> void:
	if _daze_timer > 0.0:
		return  # already dazed, don't reset timer per-frame
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var e := enemy as Node3D
		if e == null or not is_instance_valid(e):
			continue
		var diff: Vector3 = global_position - e.global_position
		diff.y = 0.0
		if diff.length() < DAZE_RADIUS:
			_trigger_daze(diff)
			return

func _trigger_daze(away_dir: Vector3) -> void:
	_daze_timer = DAZE_DURATION
	_set_daze_visual(true)
	AudioManager.play("drone_daze", global_position, -4.0)
	# Kick the drone away from the enemy — override current velocity with knockback
	var kb_dir := away_dir if away_dir.length_squared() > 0.001 else Vector3(1.0, 0.0, 0.0)
	velocity = kb_dir.normalized() * KNOCKBACK_FORCE

func _set_daze_visual(on: bool) -> void:
	for mi in _mesh_instances:
		if is_instance_valid(mi):
			mi.material_overlay = _daze_mat if on else null

# Camera's -Z axis projected onto XZ = screen-forward in world space
func _cam_forward() -> Vector3:
	if _camera == null:
		return Vector3(-1.0, 0.0, -1.0).normalized()
	var fwd := -_camera.global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.001 else Vector3(-1.0, 0.0, -1.0).normalized()

# Camera's +X axis projected onto XZ = screen-right in world space
func _cam_right() -> Vector3:
	if _camera == null:
		return Vector3(1.0, 0.0, -1.0).normalized()
	var right := _camera.global_transform.basis.x
	right.y = 0.0
	return right.normalized() if right.length_squared() > 0.001 else Vector3(1.0, 0.0, -1.0).normalized()

func _resolve_mech_collisions() -> void:
	const MECH_RADIUS  := 1.4
	const DRONE_RADIUS := 0.5
	const MIN_DIST     := MECH_RADIUS + DRONE_RADIUS
	for mech in get_tree().get_nodes_in_group("mechs"):
		var diff := Vector3(global_position.x - mech.global_position.x, 0.0, global_position.z - mech.global_position.z)
		var dist := diff.length()
		if dist < MIN_DIST and dist > 0.001:
			global_position += diff.normalized() * (MIN_DIST - dist)

func _clamp_to_viewport() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.y == 0.0:
		return
	var screen_pos := _camera.unproject_position(global_position)
	var clamped := Vector2(
		clampf(screen_pos.x, SCREEN_MARGIN, vp_size.x - SCREEN_MARGIN),
		clampf(screen_pos.y, SCREEN_MARGIN, vp_size.y - SCREEN_MARGIN)
	)
	if clamped.is_equal_approx(screen_pos):
		return
	var cam_forward := -_camera.global_transform.basis.z
	var depth := (global_position - _camera.global_position).dot(cam_forward)
	var world_clamped := _camera.project_position(clamped, depth)
	global_position.x = world_clamped.x
	global_position.z = world_clamped.z
