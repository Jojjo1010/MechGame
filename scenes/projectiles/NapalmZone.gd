extends Node3D

const TICK_INTERVAL := 0.5

var _burn_dps:    float = 0.0
var _radius:      float = 0.0
var _duration:    float = 0.0
var _age:         float = 0.0
var _tick_timer:  float = 0.0
var _disc_mat:    StandardMaterial3D = null

func setup(dps: float, radius: float, duration: float) -> void:
	_burn_dps = dps
	_radius   = radius
	_duration = duration
	_build_visual()
	_pulse()

func _build_visual() -> void:
	var disc := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius  = 0.0
	torus.outer_radius  = _radius
	torus.rings         = 48
	torus.ring_segments = 8
	disc.mesh = torus
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.albedo_color               = Color(1.0, 0.5, 0.1, 0.45)
	_disc_mat.emission_enabled           = true
	_disc_mat.emission                   = Color(1.0, 0.4, 0.05)
	_disc_mat.emission_energy_multiplier = 3.5
	_disc_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = _disc_mat
	disc.position.y = 0.05
	add_child(disc)

func _pulse() -> void:
	if _disc_mat == null:
		return
	var tw := create_tween().set_loops()
	tw.tween_property(_disc_mat, "emission_energy_multiplier", 5.5, 0.35).set_ease(Tween.EASE_OUT)
	tw.tween_property(_disc_mat, "emission_energy_multiplier", 3.0, 0.35).set_ease(Tween.EASE_IN)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		# Quick fade-out before freeing
		if _disc_mat != null:
			var tw := create_tween()
			tw.tween_property(_disc_mat, "albedo_color:a", 0.0, 0.25)
			tw.tween_callback(queue_free)
		else:
			queue_free()
		set_process(false)
		return
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = TICK_INTERVAL
		_tick_damage()

func _tick_damage() -> void:
	var dmg := _burn_dps * TICK_INTERVAL
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to(e.global_position) <= _radius:
			e.take_damage(dmg)
