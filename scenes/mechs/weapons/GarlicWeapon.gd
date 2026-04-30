extends "res://scenes/mechs/weapons/BaseWeapon.gd"

const FIRE_RATE       := 0.65
const ULT_COOLDOWN    := 14.0
const AURA_RADIUS     := 4.5
const DAMAGE_PER_TICK := 10.0
const ULT_RADIUS      := 12.0
const ULT_DAMAGE      := 110.0
const KNOCKBACK_FORCE := 38.0

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
	var radius := AURA_RADIUS * range_mult
	var enemies := _enemies_in_radius(_mech.global_position, radius)
	_update_aura_ring_scale()
	if enemies.is_empty():
		return
	for e in enemies:
		var radial: Vector3 = e.global_position - _mech.global_position
		_apply_hit(e, DAMAGE_PER_TICK, e.global_position, radial)
	_pulse_ring()
	AudioManager.play("garlic_pulse", _mech.global_position, -12.0)

func _update_aura_ring_scale() -> void:
	if _aura_ring == null or not is_instance_valid(_aura_ring):
		return
	# Scale ring uniformly in XZ to match range_mult, preserving Y
	var s := range_mult
	var current := _aura_ring.scale
	if absf(current.x - s) > 0.001:
		_aura_ring.scale = Vector3(s, current.y, s)

func _pulse_ring() -> void:
	if _aura_ring == null or not is_instance_valid(_aura_ring):
		return
	var base := range_mult
	var tw := _aura_ring.create_tween()
	tw.tween_property(_aura_ring, "scale", Vector3(base * 1.1, 1.0, base * 1.1), 0.06).set_ease(Tween.EASE_OUT)
	tw.tween_property(_aura_ring, "scale", Vector3(base, 1.0, base), 0.20).set_ease(Tween.EASE_IN)

func _fire_ult() -> void:
	var radius := ULT_RADIUS * range_mult
	var combo := RunManager.combo_mult()
	var enemies := _enemies_in_radius(_mech.global_position, radius)
	for e in enemies:
		e.take_damage(ULT_DAMAGE * damage_mult * combo)
		if dot_dps > 0.0 and e.has_method("apply_dot"):
			e.apply_dot(dot_dps, DOT_DURATION)
		if slow_duration > 0.0 and slow_mult < 1.0 and e.has_method("apply_slow"):
			e.apply_slow(slow_mult, slow_duration)
		if e.has_method("apply_knockback"):
			var diff: Vector3 = e.global_position - _mech.global_position
			diff.y = 0.0
			if diff.length_squared() > 0.001:
				# Ult always punches; stack any extra knockback from upgrades on top
				var force := KNOCKBACK_FORCE + knockback_force
				e.apply_knockback(diff.normalized() * force)
	_spawn_shockwave(radius)
	AudioManager.play("garlic_ult", _mech.global_position, -2.0)

func _spawn_shockwave(radius: float = ULT_RADIUS) -> void:
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
	var target_scale := Vector3(radius * 2.2, 1.0, radius * 2.2)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", target_scale, 0.42).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.42)
	tw.tween_callback(ring.queue_free)
