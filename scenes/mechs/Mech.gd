extends Node3D

const SPEED         := 3.0
const MECH_SPACING  := 2.5
const SHOOT_RANGE   := 20.0
const SHOOT_INTERVAL := 1.2

const BULLET_SCRIPT := preload("res://scenes/projectiles/Bullet.gd")

@export var max_health: float = 100.0
@export var is_lead: bool = false

var health: float = max_health
var leader: Node3D = null
var ability_active: bool = true
var is_alive: bool = true
var _shoot_timer: float = 0.0
var _flash_timer: float = 0.0
var _base_color: Color = Color.WHITE
var _mesh_instances: Array[MeshInstance3D] = []

const FLASH_DURATION := 0.12

signal health_changed(current: float, maximum: float)
signal mech_died()

func _ready() -> void:
	add_to_group("mechs")
	health = max_health
	_scale_model()
	_add_shadow_decal(2.2, 3.2, 4.0)
	_shoot_timer = randf_range(0.0, SHOOT_INTERVAL)

func _scale_model() -> void:
	var model := get_node_or_null("Model")
	if model == null:
		return
	var aabb := _get_aabb(model)
	if aabb.size.y > 0.0:
		var s := 4.0 / aabb.size.y
		model.scale = Vector3.ONE * s
		aabb = _get_aabb(model)
		model.position.y = -aabb.position.y
	model.rotation_degrees.y = -90.0

func _get_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a := mi.transform * mi.get_aabb()
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result

func _process(delta: float) -> void:
	if not ability_active:
		return

	# Always keep marching, alive or dead
	if is_lead:
		position.z -= SPEED * delta
		position.x = 0.0  # lead stays on the centre lane
	elif leader != null:
		var target := leader.global_position + leader.global_transform.basis.z * MECH_SPACING
		var diff := target - global_position
		diff.y = 0.0
		if diff.length() > 0.05:
			global_position += diff.normalized() * SPEED * delta

	# Only shoot while alive
	if not is_alive:
		return

	_shoot_timer -= delta
	if _shoot_timer <= 0.0:
		_try_shoot()

	if _flash_timer > 0.0:
		_flash_timer -= delta
		var t := _flash_timer / FLASH_DURATION
		var c := _base_color.lerp(Color.WHITE, t * 0.85)
		for mi in _mesh_instances:
			if is_instance_valid(mi) and mi.material_override:
				(mi.material_override as StandardMaterial3D).albedo_color = c
		if _flash_timer <= 0.0:
			for mi in _mesh_instances:
				if is_instance_valid(mi) and mi.material_override:
					(mi.material_override as StandardMaterial3D).albedo_color = _base_color

func _try_shoot() -> void:
	var nearest := _nearest_enemy()
	if nearest == null:
		return
	_shoot_timer = SHOOT_INTERVAL

	var muzzle := global_position + Vector3(0.0, 2.0, 0.0)
	var target_pos := nearest.global_position + Vector3(0.0, 0.8, 0.0)
	var dir := (target_pos - muzzle).normalized()

	# Body flash
	_flash_timer = FLASH_DURATION

	# Muzzle flash
	_spawn_muzzle_flash(muzzle)

	var bullet := Node3D.new()
	bullet.set_script(BULLET_SCRIPT)
	get_tree().current_scene.add_child(bullet)
	bullet.launch(muzzle, dir)

func _spawn_muzzle_flash(pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.45
	sph.height = 0.9
	flash.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.1)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = mat
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.1)
	light.light_energy = 8.0
	light.omni_range = 5.0
	light.shadow_enabled = false
	flash.add_child(light)

	# Fade out and free after a short time using a tween
	var tween := flash.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.10)
	tween.tween_callback(flash.queue_free)

func _nearest_enemy() -> Node3D:
	var enemies := get_tree().get_nodes_in_group("enemies")
	var nearest: Node3D = null
	var min_dist := SHOOT_RANGE
	for e in enemies:
		if not is_instance_valid(e):
			continue
		var d := global_position.distance_to(e.global_position)
		if d < min_dist:
			min_dist = d
			nearest = e
	return nearest

func take_damage(amount: float) -> void:
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		mech_died.emit()
		_on_died()

const OUTLINE_SHADER = preload("res://scenes/vfx/mech_outline.gdshader")

func set_highlighted(on: bool) -> void:
	# Remove any existing outline nodes
	for child in get_children():
		if child.name.begins_with("_ol_"):
			child.queue_free()
	if not on:
		return
	# Spawn one outline MeshInstance3D per model mesh using back-face inflate
	for i in _mesh_instances.size():
		var src := _mesh_instances[i]
		if not is_instance_valid(src):
			continue
		var ol := MeshInstance3D.new()
		ol.name = "_ol_%d" % i
		ol.mesh = src.mesh
		ol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := ShaderMaterial.new()
		sm.shader = OUTLINE_SHADER
		sm.set_shader_parameter("outline_color", Color(1.0, 0.95, 0.55, 1.0))
		sm.set_shader_parameter("outline_size", 0.07)
		ol.material_override = sm
		add_child(ol)
		# Match world transform of the source mesh
		ol.global_transform = src.global_transform

func _add_shadow_decal(width: float, depth: float, char_height: float) -> void:
	const SUN_Y_DEG := 42.0
	const SUN_ELEV  := 38.0
	var offset_dist := char_height / tan(deg_to_rad(SUN_ELEV)) * 0.3
	var shadow_dir  := Vector3(-sin(deg_to_rad(SUN_Y_DEG)), 0.0, -cos(deg_to_rad(SUN_Y_DEG)))

	# Build a soft radial gradient texture for the shadow
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for x in 128:
		for y in 128:
			var dx := (x - 64.0) / 64.0
			var dy := (y - 64.0) / 64.0
			var dist := sqrt(dx * dx + dy * dy)
			var alpha := pow(clampf(1.0 - dist, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
	var tex := ImageTexture.create_from_image(img)

	var decal := Decal.new()
	decal.texture_albedo = tex
	decal.size           = Vector3(width, 3.0, depth)
	decal.albedo_mix     = 0.75
	decal.position       = shadow_dir * offset_dist + Vector3(0.0, 1.5, 0.0)
	decal.rotation.y     = -deg_to_rad(SUN_Y_DEG)
	add_child(decal)

func _add_blob_shadow(radius: float, char_height: float) -> void:
	# Sun: rotation_degrees(-52, 42, 0) → 38° above horizon, 42° Y
	const SUN_Y_DEG  := 42.0
	const SUN_ELEV   := 38.0  # degrees above horizon
	var shadow_len   := char_height / tan(deg_to_rad(SUN_ELEV))
	var shadow_dir   := Vector3(-sin(deg_to_rad(SUN_Y_DEG)), 0.0, -cos(deg_to_rad(SUN_Y_DEG)))

	var disc := MeshInstance3D.new()
	var cyl  := CylinderMesh.new()
	cyl.top_radius    = radius
	cyl.bottom_radius = radius
	cyl.height        = 0.01
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.40)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Offset along shadow direction, stretched in that axis
	disc.position   = shadow_dir * shadow_len * 0.35 + Vector3(0.0, 0.02, 0.0)
	disc.rotation.y = -deg_to_rad(SUN_Y_DEG)
	disc.scale      = Vector3(1.0, 1.0, 1.5)  # elongate along shadow direction
	add_child(disc)

func set_color(color: Color) -> void:
	_base_color = color
	_mesh_instances.clear()
	# Search only inside the Model subtree so shadow/highlight nodes are not affected
	var model := get_node_or_null("Model")
	if model == null:
		return
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.6
		mat.metallic = 0.4
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		_mesh_instances.append(mi)

func repair(amount: float) -> void:
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)

func set_burning(on: bool) -> void:
	ability_active = not on

func _on_died() -> void:
	is_alive = false
	for mi in _mesh_instances:
		if is_instance_valid(mi) and mi.material_override:
			var mat := mi.material_override as StandardMaterial3D
			mat.albedo_color = Color(0.35, 0.35, 0.35)
			mat.metallic = 0.1
			mat.roughness = 1.0
