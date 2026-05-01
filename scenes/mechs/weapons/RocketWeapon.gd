extends "res://scenes/mechs/weapons/BaseWeapon.gd"

const ROCKET_SCRIPT := preload("res://scenes/projectiles/Rocket.gd")

const FIRE_RATE         := 1.6
const ULT_COOLDOWN      := 12.0
const BASE_DAMAGE       := 50.0
const INNATE_SPLASH     := 3.0
const ULT_DAMAGE_MULT   := 2.0
const ULT_COUNT         := 5
const ULT_FAN_DEG       := 38.0
const ULT_RANGE         := 12.0

func _on_setup() -> void:
	weapon_name = "ROCKET"
	# Built-in splash so every rocket explodes — upgrades scale this baseline.
	splash_radius = INNATE_SPLASH

func get_fire_rate() -> float:
	return FIRE_RATE

func get_ult_cooldown() -> float:
	return ULT_COOLDOWN

func _passive_fire() -> void:
	var nearest := _nearest_enemy()
	if nearest == null:
		return
	var muzzle := _mech.global_position + Vector3(0.0, 1.6, 0.0)
	var target_pos := nearest.global_position + Vector3(0.0, 0.8, 0.0)
	var dir := (target_pos - muzzle).normalized()
	_launch_rocket(muzzle, dir, BASE_DAMAGE)
	_muzzle_flash(muzzle)
	_mech.trigger_flash()
	AudioManager.play("gun_fire", muzzle, -2.0, randf_range(0.65, 0.78))

func _fire_ult() -> void:
	var nearest := _nearest_enemy()
	var aim_dir: Vector3
	if nearest != null:
		aim_dir = (nearest.global_position - _mech.global_position)
	else:
		aim_dir = Vector3.FORWARD
	aim_dir.y = 0.0
	if aim_dir.length_squared() < 0.001:
		aim_dir = Vector3.FORWARD
	aim_dir = aim_dir.normalized()

	var muzzle := _mech.global_position + Vector3(0.0, 1.6, 0.0)
	var aim_target := _mech.global_position + aim_dir * ULT_RANGE + Vector3(0.0, 0.8, 0.0)
	var base_dir := (aim_target - muzzle).normalized()
	for i in ULT_COUNT:
		var t := (float(i) / float(maxi(ULT_COUNT - 1, 1))) - 0.5
		var d := base_dir.rotated(Vector3.UP, t * deg_to_rad(ULT_FAN_DEG))
		_launch_rocket(muzzle, d, BASE_DAMAGE * ULT_DAMAGE_MULT)
	_ult_muzzle_flash(muzzle, aim_dir)
	_mech.trigger_flash()
	AudioManager.play("gun_ult", muzzle, -1.0, 0.85)

func _launch_rocket(from: Vector3, dir: Vector3, base_damage: float) -> void:
	var r := Node3D.new()
	r.set_script(ROCKET_SCRIPT)
	get_tree().current_scene.add_child(r)
	r.launch(from, dir, self, base_damage)

func _muzzle_flash(pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.55
	sph.height = 1.10
	flash.mesh = sph
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.7, 0.25)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.45, 0.05)
	mat.emission_energy_multiplier = 8.0
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = mat
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos
	var tw := flash.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tw.tween_callback(flash.queue_free)

func _ult_muzzle_flash(pos: Vector3, dir: Vector3) -> void:
	const BurstVFX = preload("res://scenes/vfx/BurstVFX.gd")
	BurstVFX.spawn(pos + dir * 1.0, Color(1.0, 0.6, 0.15), 40, 9.5, 0.60, get_tree().current_scene)
