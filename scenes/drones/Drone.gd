extends Node3D

const SPEED := 8.0
const HEIGHT := 2.2
const TILT_AMOUNT := 0.15

# Isometric movement vectors (camera is at 45° Y angle)
const DIR_FORWARD := Vector3(-1.0, 0.0, -1.0)
const DIR_BACK    := Vector3( 1.0, 0.0,  1.0)
const DIR_LEFT    := Vector3(-1.0, 0.0,  1.0)
const DIR_RIGHT   := Vector3( 1.0, 0.0, -1.0)

var player_controlled: bool = false
var velocity := Vector3.ZERO

func _ready() -> void:
	add_to_group("drones")
	position.y = HEIGHT

func _process(delta: float) -> void:
	if not player_controlled:
		return

	var input := Vector3.ZERO
	if Input.is_action_pressed("ui_up"):
		input += DIR_FORWARD
	if Input.is_action_pressed("ui_down"):
		input += DIR_BACK
	if Input.is_action_pressed("ui_left"):
		input += DIR_LEFT
	if Input.is_action_pressed("ui_right"):
		input += DIR_RIGHT

	if input.length() > 0.0:
		input = input.normalized()

	velocity = velocity.lerp(input * SPEED, 10.0 * delta)
	position += velocity * delta
	position.y = HEIGHT

	# Tilt the drone body slightly in move direction for visual feel
	if velocity.length() > 0.1:
		var tilt_target := Vector3(velocity.z, 0.0, -velocity.x) * TILT_AMOUNT
		rotation = rotation.lerp(tilt_target, 8.0 * delta)
	else:
		rotation = rotation.lerp(Vector3.ZERO, 8.0 * delta)
