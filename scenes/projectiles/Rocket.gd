extends Node3D

# Rockets travel on a parabolic arc from launch to a fixed landing point. The
# target XZ is sampled at launch (enemy position or, for ult, the drone's
# committed strike spot); the rocket commits to that point and explodes there
# regardless of whether the original target moved. Mid-air enemy contact also
# triggers detonation.
const HORIZONTAL_SPEED   := 16.0   # governs flight time over horizontal distance
const HIT_RADIUS         := 0.9
const PEAK_HEIGHT_FRAC   := 0.32   # arc apex above midpoint = horiz dist × this
const PEAK_HEIGHT_MIN    := 1.8
const PEAK_HEIGHT_MAX    := 6.5
const ULT_PEAK_BONUS     := 7.0    # ult lobs from way overhead
const MIN_FLIGHT_TIME    := 0.40
const SAFETY_LIFETIME    := 6.0    # belt-and-braces cleanup

const BurstVFX      = preload("res://scenes/vfx/BurstVFX.gd")
const NAPALM_SCRIPT := preload("res://scenes/projectiles/NapalmZone.gd")

var _start_pos:    Vector3 = Vector3.ZERO
var _end_pos:      Vector3 = Vector3.ZERO
var _peak_height:  float   = 0.0
var _flight_time:  float   = 0.0
var _age:          float   = 0.0
var _is_ult:       bool    = false
var _ult_splash:   float   = 0.0   # >0 only on the ult shot — overrides weapon splash for the boom
var _base_damage:  float   = 50.0
var _source_weapon: Node3D = null
var _last_pos:     Vector3 = Vector3.ZERO
# Cluster + napalm fields are sampled at impact, not on launch, so upgrades
# taken between launch and arrival still apply.
var _cluster_count:   int   = 0
var _napalm_burn_dps: float = 0.0
var _napalm_radius:   float = 0.0
var _napalm_duration: float = 0.0
var _mesh_node:    MeshInstance3D = null

func launch(from: Vector3, to: Vector3, source_weapon: Node3D, base_damage: float, is_ult: bool = false, ult_splash: float = 0.0) -> void:
	_start_pos     = from
	_end_pos       = to
	_source_weapon = source_weapon
	_base_damage   = base_damage
	_is_ult        = is_ult
	_ult_splash    = ult_splash
	var horiz := Vector2(to.x - from.x, to.z - from.z).length()
	_flight_time = maxf(horiz / HORIZONTAL_SPEED, MIN_FLIGHT_TIME)
	_peak_height = clampf(horiz * PEAK_HEIGHT_FRAC, PEAK_HEIGHT_MIN, PEAK_HEIGHT_MAX)
	if _is_ult:
		_peak_height += ULT_PEAK_BONUS
	if source_weapon != null:
		_cluster_count   = int(source_weapon.get("cluster_count"))
		_napalm_burn_dps = float(source_weapon.get("napalm_burn_dps"))
		_napalm_radius   = float(source_weapon.get("napalm_radius"))
		_napalm_duration = float(source_weapon.get("napalm_duration"))
	global_position = from
	_last_pos = from
	_build_mesh()

func _arc_pos(t: float) -> Vector3:
	var u := clampf(t, 0.0, 1.0)
	var flat := _start_pos.lerp(_end_pos, u)
	# sin(u·π) gives 0 at endpoints, 1 at u=0.5 — clean parabola.
	flat.y += _peak_height * sin(u * PI)
	return flat

func _build_mesh() -> void:
	_mesh_node = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.20 if _is_ult else 0.18
	cap.height = 1.10 if _is_ult else 0.80
	_mesh_node.mesh = cap
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Capsule's long axis is local Y; the per-frame look_at handles aim.
	_mesh_node.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.75, 0.25)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.45, 0.05)
	mat.emission_energy_multiplier = 5.5 if _is_ult else 4.0
	_mesh_node.material_override = mat
	add_child(_mesh_node)

	var light := OmniLight3D.new()
	light.light_color    = Color(1.0, 0.55, 0.15)
	light.light_energy   = 6.5 if _is_ult else 4.5
	light.omni_range     = 6.5 if _is_ult else 5.0
	light.shadow_enabled = false
	add_child(light)

func _process(delta: float) -> void:
	_age += delta
	if _age >= SAFETY_LIFETIME:
		_detonate(null)
		return

	var t := _age / _flight_time
	if t >= 1.0:
		global_position = _end_pos
		_orient_along(_end_pos - _last_pos)
		_detonate(null)
		return

	var new_pos := _arc_pos(t)
	_orient_along(new_pos - _last_pos)
	global_position = new_pos
	_last_pos       = new_pos

	# Mid-air enemy contact still detonates — passive shots usually intercept
	# the target this way; the explicit landing only matters when the target
	# moved out of the splash.
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var dist := global_position.distance_to(enemy.global_position + Vector3(0.0, 0.8, 0.0))
		if dist < HIT_RADIUS:
			_detonate(enemy)
			return

func _orient_along(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	# Orient the whole rocket node — the capsule's local 90° X-rotation set in
	# _build_mesh already aligns its long axis with parent's forward (-Z).
	look_at(global_position + dir.normalized(), Vector3.UP)

func _detonate(primary: Object) -> void:
	var hit_pos := global_position
	if _is_ult:
		_apply_ult_blast(hit_pos)
	elif is_instance_valid(_source_weapon):
		var hit_dir := (_end_pos - _start_pos)
		hit_dir.y = 0.0
		if hit_dir.length_squared() > 0.001:
			hit_dir = hit_dir.normalized()
		if primary != null and is_instance_valid(primary):
			_source_weapon._apply_hit(primary, _base_damage, hit_pos, hit_dir)
		else:
			# Ground impact at end of arc — splash whatever's nearby so a wide miss still rewards the shot.
			var nearby: Array = _source_weapon._enemies_in_radius(hit_pos, maxf(_source_weapon.splash_radius, 1.0))
			for e in nearby:
				_source_weapon._apply_hit(e, _base_damage, hit_pos, (e.global_position - hit_pos).normalized())

	if _cluster_count > 0 and is_instance_valid(_source_weapon):
		_spawn_cluster(hit_pos)
	if _napalm_burn_dps > 0.0 and _napalm_radius > 0.0:
		_spawn_napalm(hit_pos)

	_spawn_explosion_vfx(hit_pos)
	queue_free()

func _apply_ult_blast(center: Vector3) -> void:
	if not is_instance_valid(_source_weapon):
		return
	# Bypass _apply_hit so the weapon's innate splash_radius doesn't re-cascade
	# (every enemy hit would re-splash its neighbors). The marker ring promised
	# a fixed kill radius — apply the dmg directly inside it.
	var dmg := _base_damage * float(_source_weapon.get("damage_mult"))
	for e in _source_weapon._enemies_in_radius(center, _ult_splash):
		if not is_instance_valid(e):
			continue
		e.take_damage(dmg, true)
		if e.has_method("apply_knockback"):
			var dir: Vector3 = e.global_position - center
			dir.y = 0.0
			if dir.length_squared() < 0.001:
				dir = Vector3.FORWARD
			e.apply_knockback(dir.normalized() * 18.0)

func _spawn_explosion_vfx(pos: Vector3) -> void:
	var scene := get_tree().current_scene
	if _is_ult:
		BurstVFX.spawn(pos, Color(1.0, 0.65, 0.18), 72, 13.0, 0.85, scene)
		BurstVFX.spawn(pos + Vector3(0.0, 0.4, 0.0), Color(1.0, 0.85, 0.35), 28, 9.0, 0.55, scene)
		_spawn_blast_flash(pos, 1.9, 28.0, 14.0)
		AudioManager.play("garlic_ult", pos, -2.0, 0.85)
		AudioManager.play("gun_ult",    pos, -4.0, 0.70)
	else:
		BurstVFX.spawn(pos, Color(1.0, 0.6, 0.15), 32, 8.5, 0.55, scene)
		_spawn_blast_flash(pos, 1.0, 14.0, 7.0)
		AudioManager.play("garlic_ult", pos, -10.0, randf_range(1.05, 1.18))

func _spawn_blast_flash(pos: Vector3, sphere_radius: float, light_energy: float, light_range: float) -> void:
	var flash := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = sphere_radius
	sph.height = sphere_radius * 2.0
	flash.mesh = sph
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.75, 0.30)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.55, 0.08)
	mat.emission_energy_multiplier = 14.0
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = mat
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos
	var light := OmniLight3D.new()
	light.light_color    = Color(1.0, 0.65, 0.18)
	light.light_energy   = light_energy
	light.omni_range     = light_range
	light.shadow_enabled = false
	flash.add_child(light)
	var tw := flash.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.32)
	tw.parallel().tween_property(flash, "scale", Vector3.ONE * 1.65, 0.32)
	tw.tween_callback(flash.queue_free)

func _spawn_cluster(center: Vector3) -> void:
	var cluster_dmg := _base_damage * 0.5
	var splash := maxf(_source_weapon.splash_radius * 0.7, 1.5)
	var offset_dist := splash * 0.6
	for i in _cluster_count:
		var ang := TAU * float(i) / float(_cluster_count)
		var off := Vector3(cos(ang), 0.0, sin(ang)) * offset_dist
		var sub_pos := center + off
		for e in _source_weapon._enemies_in_radius(sub_pos, splash):
			_source_weapon._apply_hit(e, cluster_dmg, sub_pos, (e.global_position - sub_pos).normalized())
		BurstVFX.spawn(sub_pos, Color(1.0, 0.7, 0.2), 14, 5.5, 0.40, get_tree().current_scene)

func _spawn_napalm(center: Vector3) -> void:
	var zone := Node3D.new()
	zone.set_script(NAPALM_SCRIPT)
	get_tree().current_scene.add_child(zone)
	zone.global_position = center
	zone.setup(_napalm_burn_dps, _napalm_radius, _napalm_duration)
