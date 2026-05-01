extends Node3D

const BurstVFX = preload("res://scenes/vfx/BurstVFX.gd")

const SPEED        := 14.0
const HEIGHT       := 2.2
const TILT_AMOUNT  := 0.15
const SCREEN_MARGIN := 40.0

const MECH_SPEED   := 3.0

const DAZE_RADIUS     := 1.3   # world units — how close an enemy must be to daze the drone
const DAZE_DURATION   := 1.0   # seconds daze lasts
const DAZE_SPEED_MULT := 0.5   # fraction of normal speed while dazed
const KNOCKBACK_FORCE := 18.0  # impulse strength away from the enemy

const DASH_FORCE     := 40.0    # ~2.85× walk speed — clearly faster, not a teleport
const DASH_DURATION  := 0.12    # short burst (4.8u of travel at design aspect)
const DASH_DURATION_MAX := 0.18 # cap on the per-aspect bump for ultrawides
const DASH_DESIGN_ASPECT := 1.6 # 2880×1800 — the design machine's aspect
const DASH_IFRAMES_GRACE := 0.18 # daze-immune grace tacked on after dash ends
const DASH_COOLDOWN  := 0.7     # snappy — re-dash twice per second-ish, not rationed
const DASH_HIT_RADIUS    := 1.6     # enemies inside this get punched through
const DASH_DAMAGE        := 18.0    # damage per enemy passed through (one hit per dash)
const DASH_KNOCKBACK     := 24.0    # impulse magnitude on enemies passed through
const DASH_GHOST_PERIOD  := 0.035   # seconds between afterimage spawns during dash

var player_controlled: bool = false
var repair_locked: bool = false
var velocity := Vector3.ZERO
var _camera: Camera3D
var _daze_timer: float = 0.0
var _daze_mat: StandardMaterial3D = null
var _mesh_instances: Array[MeshInstance3D] = []
var _blob_shadow: MeshInstance3D = null
var _blob_shadow_mat: StandardMaterial3D = null
var _dash_active:    float = 0.0
var _dash_cooldown:  float = 0.0
var _dash_iframe:    float = 0.0              # daze-immune window — covers dash + brief landing grace
var _dash_ghost_t:   float = 0.0
var _dash_dir:       Vector3 = Vector3.ZERO   # direction the current dash is travelling in
var _dash_hit_set:   Dictionary = {}          # enemies already punched-through in current dash
var _space_was_down: bool = false              # edge-detect for polled Space key

func _ready() -> void:
	add_to_group("drones")
	position.y = HEIGHT

	# Collect meshes for daze overlay
	for child in find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi:
			_mesh_instances.append(mi)

	_add_blob_shadow()
	_add_drone_outline()
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

# Inverted-hull outline. Shared static material so we don't allocate one
# StandardMaterial3D per mesh per drone — params never vary.
static var _OUTLINE_MAT: StandardMaterial3D = null

static func _outline_material() -> StandardMaterial3D:
	if _OUTLINE_MAT != null:
		return _OUTLINE_MAT
	var mat := StandardMaterial3D.new()
	mat.albedo_color  = Color(0.02, 0.02, 0.04, 1.0)
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode     = BaseMaterial3D.CULL_FRONT
	mat.grow          = true
	mat.grow_amount   = 0.18
	# Glow post-processing in the scene env washes out thin strokes against the
	# emissive drone body — disabling fog + tagging it as not-receive-shadows
	# keeps the silhouette readable through the bloom halo.
	mat.disable_fog              = true
	mat.disable_receive_shadows  = true
	_OUTLINE_MAT = mat
	return mat

func _add_drone_outline() -> void:
	for mi in _mesh_instances:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var ol := MeshInstance3D.new()
		ol.name = "_drone_outline"
		ol.mesh = mi.mesh
		ol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ol.material_override = _outline_material()
		mi.add_child(ol)
		ol.transform = Transform3D.IDENTITY

func _process(delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return

	# Blob shadow: keep it pinned to ground level, flat (no inheriting drone tilt),
	# and fade with height.
	if is_instance_valid(_blob_shadow) and _blob_shadow_mat != null:
		_blob_shadow.global_position = Vector3(global_position.x, 0.04, global_position.z)
		_blob_shadow.global_rotation = Vector3.ZERO
		var h := maxf(global_position.y, 0.1)
		_blob_shadow_mat.albedo_color.a = clampf(0.42 / (h * 0.38 + 0.6), 0.05, 0.42)

	if not player_controlled:
		return

	# Poll Space for dash on the rising edge. Polling instead of using the _input
	# event callback avoids cases where the engine/keyboard drops the Space-down
	# event when WASD is already held — the original symptom was "dash only fires
	# when standing still". Input.is_key_pressed reads the live key state, so it
	# works regardless of event-stream quirks.
	var space_now := Input.is_key_pressed(KEY_SPACE)
	if space_now and not _space_was_down and not repair_locked:
		_try_dash()
	_space_was_down = space_now

	if repair_locked:
		position.z -= MECH_SPEED * RunManager.line_speed_mult * delta   # keep marching with mechs, block player input
		return

	# Tick dash cooldown always (so it ticks down even while dazed)
	if _dash_cooldown > 0.0:
		_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	if _dash_iframe > 0.0:
		_dash_iframe = maxf(0.0, _dash_iframe - delta)

	# Dashing: i-frames (skip enemy contact) + steerable. Re-read WASD each
	# frame so the player can curve mid-dash; if no input, we keep the last dash
	# direction. Each enemy along the path is punched through once.
	if _dash_active > 0.0:
		_dash_active = maxf(0.0, _dash_active - delta)
		var cam_fwd2   := _cam_forward()
		var cam_right2 := _cam_right()
		var dash_input := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): dash_input += cam_fwd2
		if Input.is_key_pressed(KEY_S): dash_input -= cam_fwd2
		if Input.is_key_pressed(KEY_A): dash_input -= cam_right2
		if Input.is_key_pressed(KEY_D): dash_input += cam_right2
		if dash_input.length_squared() > 0.01:
			dash_input.y = 0.0
			_dash_dir = dash_input.normalized()
		velocity = _dash_dir * DASH_FORCE
		position.z -= MECH_SPEED * RunManager.line_speed_mult * delta
		position += velocity * delta
		position.y = HEIGHT
		# No mech collision resolution during dash — pass through allies cleanly.
		_clamp_to_viewport()
		_dash_ghost_t -= delta
		if _dash_ghost_t <= 0.0:
			_dash_ghost_t = DASH_GHOST_PERIOD
			_spawn_dash_ghost()
		_dash_punch_through()
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
	position.z -= MECH_SPEED * RunManager.line_speed_mult * (DAZE_SPEED_MULT if dazed else 1.0) * delta

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

func _dash_duration_for_aspect() -> float:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.y <= 0.0:
		return DASH_DURATION
	var aspect: float = vp.x / vp.y
	var dur_scale: float = maxf(1.0, aspect / DASH_DESIGN_ASPECT)
	return minf(DASH_DURATION_MAX, DASH_DURATION * dur_scale)

func _try_dash() -> void:
	if _dash_cooldown > 0.0 or _dash_active > 0.0:
		return
	# Dash direction: current WASD input (camera-relative). Falls back to current
	# movement direction; if standing still, dash forward along the line of march.
	var cam_fwd   := _cam_forward()
	var cam_right := _cam_right()
	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input += cam_fwd
	if Input.is_key_pressed(KEY_S): input -= cam_fwd
	if Input.is_key_pressed(KEY_A): input -= cam_right
	if Input.is_key_pressed(KEY_D): input += cam_right
	if input.length_squared() < 0.01:
		input = velocity if velocity.length_squared() > 0.5 else cam_fwd
	input.y = 0.0
	if input.length_squared() < 0.001:
		return
	velocity = input.normalized() * DASH_FORCE
	# Bump dash duration on wider-than-design viewports so the felt distance
	# (dash-as-fraction-of-screen) stays consistent across monitors.
	var duration := _dash_duration_for_aspect()
	_dash_active   = duration
	_dash_cooldown = DASH_COOLDOWN
	_dash_iframe   = duration + DASH_IFRAMES_GRACE
	_dash_dir      = input.normalized()
	_dash_ghost_t  = 0.0
	_dash_hit_set.clear()
	# Dash breaks daze
	if _daze_timer > 0.0:
		_daze_timer = 0.0
		_set_daze_visual(false)
	# Punchy dash whoosh — reused daze sound at a high pitch + boom layer
	AudioManager.play("drone_daze", global_position, -4.0, 1.85)
	AudioManager.play("garlic_pulse", global_position, -8.0, 0.85)
	# Cyan flash burst at takeoff so the player sees the dash trigger
	BurstVFX.spawn(global_position, Color(0.4, 0.85, 1.0), 22, 7.0, 0.45, get_tree().current_scene)

# Find any enemies within DASH_HIT_RADIUS of the drone, deal damage + knockback
# once per enemy per dash, and spawn a hit-through VFX.
func _dash_punch_through() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == null or not is_instance_valid(e):
			continue
		var enemy_id := e.get_instance_id()
		if _dash_hit_set.has(enemy_id):
			continue
		var diff: Vector3 = e.global_position - global_position
		diff.y = 0.0
		if diff.length() > DASH_HIT_RADIUS:
			continue
		_dash_hit_set[enemy_id] = true
		if e.has_method("take_damage"):
			e.take_damage(DASH_DAMAGE, true)   # render as crit so the number shouts
		if e.has_method("apply_knockback"):
			# Shove enemies along dash direction (so they spray forward, readable)
			var dir := _dash_dir
			if dir.length_squared() < 0.01:
				dir = diff.normalized()
			e.apply_knockback(dir.normalized() * DASH_KNOCKBACK)
		AudioManager.play("bullet_impact", e.global_position, -4.0, 1.4)
		BurstVFX.spawn(e.global_position + Vector3(0.0, 1.0, 0.0),
			Color(0.5, 0.9, 1.0), 18, 6.5, 0.4, get_tree().current_scene)

# Spawn a faded copy of the drone's body meshes at the current pose. Each ghost
# fades out over 0.28s, creating a continuous afterimage trail behind the dash.
func _spawn_dash_ghost() -> void:
	for mi in _mesh_instances:
		if not is_instance_valid(mi) or mi.mesh == null:
			continue
		var ghost := MeshInstance3D.new()
		ghost.mesh = mi.mesh
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color              = Color(0.45, 0.85, 1.0, 0.55)
		gmat.emission_enabled          = true
		gmat.emission                  = Color(0.3, 0.7, 1.0)
		gmat.emission_energy_multiplier = 4.0
		gmat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
		gmat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
		gmat.no_depth_test             = true
		gmat.render_priority           = 7
		ghost.material_override = gmat
		get_tree().current_scene.add_child(ghost)
		ghost.global_transform = mi.global_transform
		var tw := ghost.create_tween()
		tw.tween_property(gmat, "albedo_color:a", 0.0, 0.28).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(ghost, "scale", ghost.scale * 0.6, 0.28).set_ease(Tween.EASE_OUT)
		tw.tween_callback(ghost.queue_free)

func _check_enemy_contact() -> void:
	if _daze_timer > 0.0:
		return  # already dazed, don't reset timer per-frame
	if _dash_iframe > 0.0:
		return  # post-dash grace — landing on an enemy mid-recovery shouldn't punish
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
