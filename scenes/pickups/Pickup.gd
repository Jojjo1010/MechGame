extends Node3D

enum Type { XP, GOLD }

const ATTRACT_RADIUS := 5.5   # drone starts pulling the pickup in
const COLLECT_RADIUS := 0.9   # actually collected
const FLY_SPEED      := 10.0
const BOB_SPEED      := 2.2
const BOB_AMP        := 0.18

var type:  Type = Type.XP
var value: int  = 1

var _drone:     Node3D = null
var _base_y:    float  = 0.0
var _age:       float  = 0.0
var _attracted: bool   = false

static func spawn(p_type: Type, p_value: int, world_pos: Vector3, parent: Node) -> void:
	var inst := Node3D.new()
	inst.set_script(load("res://scenes/pickups/Pickup.gd"))
	inst.set_meta("_ptype",  p_type)
	inst.set_meta("_pvalue", p_value)
	inst.set_meta("_pos",    world_pos)  # position set inside _ready before _base_y is captured
	parent.add_child(inst)

func _ready() -> void:
	add_to_group("pickups")
	type  = get_meta("_ptype",  Type.XP)
	value = get_meta("_pvalue", 1)
	# Apply position now so _base_y is captured correctly
	var spawn_pos: Vector3 = get_meta("_pos", Vector3.ZERO)
	global_position = spawn_pos
	_base_y = spawn_pos.y
	_build_mesh()
	_add_blob_shadow()
	var drones := get_tree().get_nodes_in_group("drones")
	if not drones.is_empty():
		_drone = drones[0] as Node3D

func _add_blob_shadow() -> void:
	var disc := MeshInstance3D.new()
	var cyl  := CylinderMesh.new()
	cyl.top_radius    = 0.28
	cyl.bottom_radius = 0.28
	cyl.height        = 0.01
	disc.mesh        = cyl
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.40)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	# Offset downward so the disc sits on the ground regardless of spawn height
	disc.position = Vector3(0.0, -_base_y + 0.02, 0.0)
	add_child(disc)

func _build_mesh() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true

	if type == Type.XP:
		mat.albedo_color               = Color(0.75, 0.25, 1.00)
		mat.emission                   = Color(0.55, 0.05, 0.90)
		mat.emission_energy_multiplier = 2.5
		_build_diamond(mat)
	else:
		mat.albedo_color               = Color(1.00, 0.85, 0.15)
		mat.emission                   = Color(1.00, 0.60, 0.00)
		mat.emission_energy_multiplier = 2.5
		_build_sphere(mat)

	var light := OmniLight3D.new()
	light.light_color    = Color(0.7, 0.2, 1.0) if type == Type.XP else Color(1.0, 0.75, 0.0)
	light.light_energy   = 1.2
	light.omni_range     = 2.5
	light.shadow_enabled = false
	add_child(light)

func _build_diamond(mat: StandardMaterial3D) -> void:
	# Two cones joined at the waist — classic gem/diamond silhouette
	var pivot := Node3D.new()
	add_child(pivot)

	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius    = 0.0
	top_mesh.bottom_radius = 0.22
	top_mesh.height        = 0.30
	top_mesh.radial_segments = 6   # hexagonal facets
	var top_mi := MeshInstance3D.new()
	top_mi.mesh             = top_mesh
	top_mi.position.y       = 0.15
	top_mi.material_override = mat
	top_mi.cast_shadow      = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(top_mi)

	var bot_mesh := CylinderMesh.new()
	bot_mesh.top_radius      = 0.22
	bot_mesh.bottom_radius   = 0.0
	bot_mesh.height          = 0.20
	bot_mesh.radial_segments = 6
	var bot_mi := MeshInstance3D.new()
	bot_mi.mesh              = bot_mesh
	bot_mi.position.y        = -0.10
	bot_mi.material_override = mat
	bot_mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(bot_mi)

func _build_sphere(mat: StandardMaterial3D) -> void:
	var sph := SphereMesh.new()
	sph.radius = 0.20
	sph.height = 0.40
	var mi := MeshInstance3D.new()
	mi.mesh             = sph
	mi.material_override = mat
	mi.cast_shadow      = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _process(delta: float) -> void:
	_age += delta
	# Spin the diamond on Y so the facets catch the light
	if type == Type.XP:
		var pivot := get_child(0) if get_child_count() > 0 else null
		if pivot is Node3D:
			pivot.rotation.y += delta * 2.2

	if not is_instance_valid(_drone):
		_bob(delta)
		return

	var dist: float = global_position.distance_to(_drone.global_position)

	if dist < COLLECT_RADIUS:
		_collect()
		return

	if dist < ATTRACT_RADIUS:
		_attracted = true
		var dir := (_drone.global_position - global_position)
		dir.y = 0.0
		dir = dir.normalized()
		# Accelerate as it gets closer
		var speed: float = FLY_SPEED * (1.0 + (ATTRACT_RADIUS - dist) / ATTRACT_RADIUS)
		global_position += dir * speed * delta
		global_position.y = lerpf(global_position.y, _drone.global_position.y, 6.0 * delta)
	else:
		_bob(delta)

func _bob(_delta: float) -> void:
	global_position.y = _base_y + sin(_age * BOB_SPEED) * BOB_AMP

func _collect() -> void:
	if type == Type.XP:
		RunManager.add_xp(value)
		AudioManager.play("xp_collect", global_position, -8.0, randf_range(0.95, 1.1))
	else:
		RunManager.add_gold(value)
		AudioManager.play("gold_collect", global_position, -6.0)
	queue_free()
