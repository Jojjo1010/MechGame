extends Node3D

const SPEED := 2.5
const ATTACK_RANGE := 1.4
const ATTACK_DAMAGE := 8.0
const ATTACK_INTERVAL := 1.0

@export var max_health: float = 40.0

var health: float = max_health
var attack_timer: float = 0.0
var target_mech: Node3D = null

signal enemy_died()

func _ready() -> void:
	add_to_group("enemies")
	health = max_health

func _process(delta: float) -> void:
	_find_target()

	if target_mech == null:
		return

	var dist := global_position.distance_to(target_mech.global_position)

	if dist > ATTACK_RANGE:
		var dir := (target_mech.global_position - global_position)
		dir.y = 0.0
		dir = dir.normalized()
		position += dir * SPEED * delta
		# Face target
		if dir.length() > 0.01:
			rotation.y = atan2(dir.x, dir.z)
	else:
		attack_timer -= delta
		if attack_timer <= 0.0:
			attack_timer = ATTACK_INTERVAL
			if target_mech.has_method("take_damage"):
				target_mech.take_damage(ATTACK_DAMAGE)

func _find_target() -> void:
	var mechs := get_tree().get_nodes_in_group("mechs")
	var nearest: Node3D = null
	var min_dist := INF
	for m in mechs:
		var d := global_position.distance_to(m.global_position)
		if d < min_dist:
			min_dist = d
			nearest = m
	target_mech = nearest

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	if health <= 0.0:
		enemy_died.emit()
		queue_free()
