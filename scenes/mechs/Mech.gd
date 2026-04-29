extends Node3D

const SPEED := 3.0
const MECH_SPACING := 2.5

@export var max_health: float = 100.0
@export var is_lead: bool = false

var health: float = max_health
var leader: Node3D = null
var ability_active: bool = true

signal health_changed(current: float, maximum: float)
signal mech_died()

func _ready() -> void:
	add_to_group("mechs")
	health = max_health

func _process(delta: float) -> void:
	if not ability_active:
		return

	if is_lead:
		position.z -= SPEED * delta
	elif leader != null:
		# Follow at fixed spacing behind leader
		var target := leader.global_position + leader.global_transform.basis.z * MECH_SPACING
		var diff := target - global_position
		diff.y = 0.0
		if diff.length() > 0.05:
			global_position += diff.normalized() * SPEED * delta

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		mech_died.emit()
		_on_died()

func repair(amount: float) -> void:
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)

func set_burning(on: bool) -> void:
	# Placeholder — visual feedback when burning
	ability_active = not on

func _on_died() -> void:
	ability_active = false
	# Dim the mesh to show the mech is down
	for child in find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi and mi.material_override:
			(mi.material_override as StandardMaterial3D).albedo_color = Color(0.3, 0.3, 0.3)
