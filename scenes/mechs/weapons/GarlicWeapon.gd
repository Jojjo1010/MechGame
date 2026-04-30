extends "res://scenes/mechs/weapons/BaseWeapon.gd"

const FIRE_RATE       := 0.65
const ULT_COOLDOWN    := 14.0
const AURA_RADIUS     := 4.5
const DAMAGE_PER_TICK := 10.0
const ULT_RADIUS      := 9.0
const ULT_DAMAGE      := 45.0
const KNOCKBACK_FORCE := 22.0

var _aura_ring: MeshInstance3D = null

func _on_setup() -> void:
	weapon_name = "GARLIC"
	_build_aura_ring()

func _build_aura_ring() -> void:
	_aura_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = AURA_RADIUS - 0.15
	torus.outer_radius = AURA_RADIUS + 0.15
	torus.rings = 48
	torus.ring_segments = 12
	_aura_ring.mesh = torus
	_aura_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 1.0, 0.35, 0.30)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.9, 0.1)
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aura_ring.material_override = mat
	_aura_ring.position.y = 0.15
	add_child(_aura_ring)

func get_fire_rate() -> float:
	return FIRE_RATE

func get_ult_cooldown() -> float:
	return ULT_COOLDOWN

func _passive_fire() -> void:
	var enemies := _enemies_in_radius(_mech.global_position, AURA_RADIUS)
	if enemies.is_empty():
		return
	for e in enemies:
		e.take_damage(DAMAGE_PER_TICK)
	_pulse_ring()
	AudioManager.play("garlic_pulse", _mech.global_position, -12.0)

func _pulse_ring() -> void:
	if _aura_ring == null or not is_instance_valid(_aura_ring):
		return
	var tw := _aura_ring.create_tween()
	tw.tween_property(_aura_ring, "scale", Vector3(1.1, 1.0, 1.1), 0.06).set_ease(Tween.EASE_OUT)
	tw.tween_property(_aura_ring, "scale", Vector3(1.0, 1.0, 1.0), 0.20).set_ease(Tween.EASE_IN)

func _fire_ult() -> void:
	var enemies := _enemies_in_radius(_mech.global_position, ULT_RADIUS)
	for e in enemies:
		e.take_damage(ULT_DAMAGE)
		if e.has_method("apply_knockback"):
			var diff: Vector3 = e.global_position - _mech.global_position
			diff.y = 0.0
			if diff.length_squared() > 0.001:
				e.apply_knockback(diff.normalized() * KNOCKBACK_FORCE)
	_spawn_shockwave()
	AudioManager.play("garlic_ult", _mech.global_position, -2.0)

func _spawn_shockwave() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.1
	torus.outer_radius = 0.55
	torus.rings = 64
	torus.ring_segments = 14
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 1.0, 0.4, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.2)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	get_tree().current_scene.add_child(ring)
	ring.global_position = _mech.global_position + Vector3(0.0, 0.4, 0.0)
	var target_scale := Vector3(ULT_RADIUS * 2.2, 1.0, ULT_RADIUS * 2.2)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", target_scale, 0.42).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.42)
	tw.tween_callback(ring.queue_free)
