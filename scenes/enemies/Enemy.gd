extends Node3D

const BurstVFX     = preload("res://scenes/vfx/BurstVFX.gd")
const HealthBar3D  = preload("res://scenes/ui/HealthBar3D.gd")
const DamageNumber = preload("res://scenes/ui/DamageNumber.gd")
const Pickup       = preload("res://scenes/pickups/Pickup.gd")

const SPEED := 4.5
const ATTACK_RANGE := 1.4
const ATTACK_DAMAGE := 8.0
const ATTACK_INTERVAL := 1.0

# Separation: enemies push each other apart when too close
const SEPARATION_RADIUS := 1.3   # start pushing when closer than this (world units)
const SEPARATION_STRENGTH := 3.0 # multiplier on sep vector when blended with move dir

@export var max_health: float = 40.0

const FLASH_DURATION := 0.10

var health: float = max_health
var attack_timer: float = 0.0
var target_mech: Node3D = null
var _health_bar: Node3D = null
var _mesh_instances: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D = null
var _knockback_vel: Vector3 = Vector3.ZERO

signal enemy_died()

func _ready() -> void:
	add_to_group("enemies")
	health = max_health
	scale = Vector3(0.6, 0.6, 0.6)
	# Build shared white overlay material for hit flash
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color   = Color.WHITE
	_flash_mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.emission_enabled = true
	_flash_mat.emission       = Color.WHITE
	_flash_mat.emission_energy_multiplier = 1.5
	for child in find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_mesh_instances.append(mi)
	_add_blob_shadow(0.5, 2.5)
	# HP bar — hidden until first hit
	_health_bar = Node3D.new()
	_health_bar.set_script(HealthBar3D)
	_health_bar.position = Vector3(0.0, 2.9, 0.0)
	_health_bar.visible = false
	add_child(_health_bar)

func _add_shadow_decal(width: float, depth: float, char_height: float) -> void:
	const SUN_Y_DEG := 42.0
	const SUN_ELEV  := 38.0
	var offset_dist := char_height / tan(deg_to_rad(SUN_ELEV)) * 0.28
	var shadow_dir  := Vector3(-sin(deg_to_rad(SUN_Y_DEG)), 0.0, -cos(deg_to_rad(SUN_Y_DEG)))

	# Reuse the same shared texture from Mech if available
	var grad := Gradient.new()
	grad.add_point(0.0, Color(0.0, 0.0, 0.0, 0.65))
	grad.add_point(1.0, Color(0.0, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill      = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to   = Vector2(1.0, 0.5)
	tex.width     = 64
	tex.height    = 64

	var decal := Decal.new()
	decal.texture_albedo = tex
	decal.size           = Vector3(width, 6.0, depth)
	decal.albedo_mix     = 0.7
	decal.position       = shadow_dir * offset_dist + Vector3(0.0, 3.0, 0.0)
	decal.rotation.y     = -deg_to_rad(SUN_Y_DEG)
	add_child(decal)

func _add_blob_shadow(radius: float, char_height: float) -> void:
	const SUN_Y_DEG := 42.0
	const SUN_ELEV  := 38.0
	var shadow_len  := char_height / tan(deg_to_rad(SUN_ELEV))
	var shadow_dir  := Vector3(-sin(deg_to_rad(SUN_Y_DEG)), 0.0, -cos(deg_to_rad(SUN_Y_DEG)))

	var disc := MeshInstance3D.new()
	var cyl  := CylinderMesh.new()
	cyl.top_radius    = radius
	cyl.bottom_radius = radius
	cyl.height        = 0.01
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position   = shadow_dir * shadow_len * 0.16 + Vector3(0.0, 0.02, 0.0)
	disc.rotation.y = -deg_to_rad(SUN_Y_DEG)
	disc.scale      = Vector3(1.0, 1.0, 1.2)
	add_child(disc)

func apply_knockback(impulse: Vector3) -> void:
	_knockback_vel = impulse

func _process(delta: float) -> void:
	if _knockback_vel.length_squared() > 0.01:
		_knockback_vel = _knockback_vel.lerp(Vector3.ZERO, 10.0 * delta)
		global_position += _knockback_vel * delta

	_find_target()

	var sep := _get_separation()

	if target_mech == null:
		# No mech to chase — still spread out
		position += sep * SEPARATION_STRENGTH * delta
		return

	var dist := global_position.distance_to(target_mech.global_position)

	if dist > ATTACK_RANGE:
		var dir := (target_mech.global_position - global_position)
		dir.y = 0.0
		dir = dir.normalized()
		# Blend target direction with separation so enemies spread around each other
		var move_dir := dir + sep * SEPARATION_STRENGTH
		if move_dir.length() > 0.01:
			move_dir = move_dir.normalized()
		position += move_dir * SPEED * delta
		# Face movement direction
		if move_dir.length() > 0.01:
			rotation.y = atan2(move_dir.x, move_dir.z)
	else:
		# In attack range: still push apart so they ring the mech instead of stacking
		position += sep * SEPARATION_STRENGTH * delta
		attack_timer -= delta
		if attack_timer <= 0.0:
			attack_timer = ATTACK_INTERVAL
			if target_mech.has_method("take_damage"):
				target_mech.take_damage(ATTACK_DAMAGE)

func _get_separation() -> Vector3:
	var sep := Vector3.ZERO
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var e := enemy as Node3D
		if e == null or e == self or not is_instance_valid(e):
			continue
		var diff: Vector3 = global_position - e.global_position
		diff.y = 0.0
		var dist := diff.length()
		if dist < SEPARATION_RADIUS and dist > 0.001:
			# Stronger push the closer they are
			sep += diff.normalized() * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
	return sep

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

func _flash_hit() -> void:
	for mi in _mesh_instances:
		if is_instance_valid(mi):
			mi.material_overlay = _flash_mat
	var tw := create_tween()
	tw.tween_interval(FLASH_DURATION)
	tw.tween_callback(func() -> void:
		for mi in _mesh_instances:
			if is_instance_valid(mi):
				mi.material_overlay = null)

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	_flash_hit()
	if is_instance_valid(_health_bar):
		_health_bar.visible = true
		_health_bar.set_fraction(health / max_health)
	DamageNumber.spawn(amount, global_position + Vector3(0.0, 2.2, 0.0),
		get_tree().current_scene, Color(1.0, 0.92, 0.15))
	if health <= 0.0:
		enemy_died.emit()
		BurstVFX.spawn(
			global_position + Vector3(0.0, 1.0, 0.0),
			Color(0.9, 0.15, 0.05), 22, 7.0, 0.55,
			get_tree().current_scene
		)
		AudioManager.play("enemy_death", global_position, -4.0, randf_range(0.9, 1.1))
		_spawn_pickups()
		queue_free()

func _spawn_pickups() -> void:
	var scene := get_tree().current_scene
	# 2–4 XP orbs scattered around death position
	for i in randi_range(2, 4):
		var off := Vector3(randf_range(-1.2, 1.2), 0.5, randf_range(-1.2, 1.2))
		Pickup.spawn(Pickup.Type.XP, 1, global_position + off, scene)
	# ~35% chance of a gold coin
	if randf() < 0.35:
		var off := Vector3(randf_range(-0.6, 0.6), 0.5, randf_range(-0.6, 0.6))
		Pickup.spawn(Pickup.Type.GOLD, 1, global_position + off, scene)
