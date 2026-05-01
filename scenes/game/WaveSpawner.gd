extends Node

const ENEMY_SCENE    := preload("res://scenes/enemies/Enemy.tscn")
const SPAWN_RADIUS_MIN := 22.0  # floor for the dynamic radius — at min zoom we still want a reasonable approach distance
const SPAWN_MARGIN     := 6.0   # extra padding past the visible edge so spawns never pop in on-screen
const BASE_ENEMIES   := 5
const WAVE_INTERVAL  := 12.0
const SPAWN_SPREAD   := 4.0    # seconds over which a wave staggers its spawns

var enemies_container: Node3D
var wave_number: int = 0
var timer: float = 3.0

func setup(p_enemies_container: Node3D) -> void:
	enemies_container = p_enemies_container

func _process(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		timer = WAVE_INTERVAL
		_spawn_wave()

func _spawn_wave() -> void:
	wave_number += 1
	RunManager.start_wave(wave_number)
	AudioManager.play("wave_start")

	var count := BASE_ENEMIES + (wave_number - 1) * 2
	var interval := SPAWN_SPREAD / float(count)

	for i in count:
		get_tree().create_timer(i * interval).timeout.connect(_spawn_one)

func _spawn_one() -> void:
	var center := _get_spawn_reference()
	# Mechs march in -Z. In angle space (cos→X, sin→Z) the forward direction
	# is -PI/2. A ±2PI/3 window gives a 240° arc covering front and both sides
	# while excluding the ~120° cone directly behind the conga line.
	var angle := -PI / 2.0 + randf_range(-2.0 * PI / 3.0, 2.0 * PI / 3.0)
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * _spawn_radius()
	var enemy: Node3D = ENEMY_SCENE.instantiate()
	enemies_container.add_child(enemy)
	enemy.global_position = center + offset

# Spawn distance scales with the orthographic camera size + viewport aspect so
# enemies always pop in just past the visible edge — regardless of zoom level
# or monitor (ultrawide sees ~50% more world horizontally than the design
# machine, and the radius needs to follow).
func _spawn_radius() -> float:
	var cam := get_viewport().get_camera_3d()
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if cam == null or cam.projection != Camera3D.PROJECTION_ORTHOGONAL or vp_size.y <= 0.0:
		return SPAWN_RADIUS_MIN
	var aspect: float = vp_size.x / vp_size.y
	var visible_half: float = cam.size * maxf(1.0, aspect) * 0.5
	return maxf(SPAWN_RADIUS_MIN, visible_half + SPAWN_MARGIN)

# Use the lead mech as the reference so front-spawned enemies actually land
# ahead of the line rather than behind the average position.
func _get_spawn_reference() -> Vector3:
	var mechs := get_tree().get_nodes_in_group("mechs")
	if mechs.is_empty():
		return Vector3.ZERO
	var lead: Node3D = null
	var min_z := INF
	for m in mechs:
		var mn := m as Node3D
		if mn == null:
			continue
		if mn.global_position.z < min_z:
			min_z = mn.global_position.z
			lead = mn
	return lead.global_position if lead else Vector3.ZERO
