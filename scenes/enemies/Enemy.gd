extends Node3D

const BurstVFX = preload("res://scenes/vfx/BurstVFX.gd")

const SPEED := 4.5
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
	for child in find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_shadow_decal(1.2, 1.8, 2.5)

func _add_shadow_decal(width: float, depth: float, char_height: float) -> void:
	const SUN_Y_DEG := 42.0
	const SUN_ELEV  := 38.0
	var offset_dist := char_height / tan(deg_to_rad(SUN_ELEV)) * 0.3
	var shadow_dir  := Vector3(-sin(deg_to_rad(SUN_Y_DEG)), 0.0, -cos(deg_to_rad(SUN_Y_DEG)))

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
	decal.albedo_mix     = 0.65
	decal.position       = shadow_dir * offset_dist + Vector3(0.0, 1.5, 0.0)
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
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.38)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position   = shadow_dir * shadow_len * 0.35 + Vector3(0.0, 0.02, 0.0)
	disc.rotation.y = -deg_to_rad(SUN_Y_DEG)
	disc.scale      = Vector3(1.0, 1.0, 1.4)
	add_child(disc)

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
		BurstVFX.spawn(
			global_position + Vector3(0.0, 1.0, 0.0),
			Color(0.9, 0.15, 0.05), 22, 7.0, 0.55,
			get_tree().current_scene
		)
		queue_free()
