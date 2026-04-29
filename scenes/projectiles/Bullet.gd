extends Node3D

const SPEED      := 24.0
const DAMAGE     := 20.0
const HIT_RADIUS := 0.8
const LIFETIME   := 3.5

const BurstVFX = preload("res://scenes/vfx/BurstVFX.gd")

var direction := Vector3.ZERO
var _age      := 0.0

func launch(from: Vector3, dir: Vector3) -> void:
	global_position = from
	direction = dir.normalized()
	_build_mesh()

func _build_mesh() -> void:
	var mi  := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.18
	sph.height = 0.36
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.0)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.1)
	light.light_energy = 2.5
	light.omni_range = 3.0
	light.shadow_enabled = false
	add_child(light)

func _process(delta: float) -> void:
	global_position += direction * SPEED * delta
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var dist := global_position.distance_to(enemy.global_position + Vector3(0.0, 0.8, 0.0))
		if dist < HIT_RADIUS:
			enemy.take_damage(DAMAGE)
			BurstVFX.spawn(global_position, Color(1.0, 0.65, 0.1), 14, 5.0, 0.35, get_tree().current_scene)
			queue_free()
			return
