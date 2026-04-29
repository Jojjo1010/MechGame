extends Node3D

const SPEED := 14.0
const HEIGHT := 2.2
const TILT_AMOUNT := 0.15
const SCREEN_MARGIN := 40.0  # pixels from edge

# Isometric movement vectors (camera is at 45° Y angle)
const DIR_FORWARD := Vector3(-1.0, 0.0, -1.0)
const DIR_BACK    := Vector3( 1.0, 0.0,  1.0)
const DIR_LEFT    := Vector3(-1.0, 0.0,  1.0)
const DIR_RIGHT   := Vector3( 1.0, 0.0, -1.0)

var player_controlled: bool = false
var velocity := Vector3.ZERO
var _camera: Camera3D

func _ready() -> void:
	add_to_group("drones")
	position.y = HEIGHT

func _process(delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return

	if not player_controlled:
		return

	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input += DIR_FORWARD
	if Input.is_key_pressed(KEY_S):
		input += DIR_BACK
	if Input.is_key_pressed(KEY_A):
		input += DIR_LEFT
	if Input.is_key_pressed(KEY_D):
		input += DIR_RIGHT

	if input.length() > 0.0:
		input = input.normalized()

	velocity = velocity.lerp(input * SPEED, 10.0 * delta)
	position += velocity * delta
	position.y = HEIGHT

	_resolve_mech_collisions()
	_clamp_to_viewport()

	if velocity.length() > 0.1:
		var tilt_target := Vector3(velocity.z, 0.0, -velocity.x) * TILT_AMOUNT
		rotation = rotation.lerp(tilt_target, 8.0 * delta)
	else:
		rotation = rotation.lerp(Vector3.ZERO, 8.0 * delta)

func _resolve_mech_collisions() -> void:
	const MECH_RADIUS := 1.4
	const DRONE_RADIUS := 0.5
	const MIN_DIST := MECH_RADIUS + DRONE_RADIUS
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
