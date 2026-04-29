extends Node

const ENEMY_SCENE := preload("res://scenes/enemies/Enemy.tscn")
const SPAWN_RADIUS := 22.0
const BASE_ENEMIES := 5
const WAVE_INTERVAL := 12.0

var enemies_container: Node3D
var wave_number: int = 0
var timer: float = 3.0  # short delay before first wave

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

	var count := BASE_ENEMIES + (wave_number - 1) * 2
	var center := _get_line_center()

	for i in count:
		var angle := randf() * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS
		var enemy: Node3D = ENEMY_SCENE.instantiate()
		enemies_container.add_child(enemy)
		enemy.global_position = center + offset

func _get_line_center() -> Vector3:
	var mechs := get_tree().get_nodes_in_group("mechs")
	if mechs.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for m in mechs:
		c += m.global_position
	return c / mechs.size()
