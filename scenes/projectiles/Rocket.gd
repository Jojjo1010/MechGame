extends Node3D

const SPEED      := 14.0
const HIT_RADIUS := 0.9
const LIFETIME   := 4.0

const BurstVFX = preload("res://scenes/vfx/BurstVFX.gd")
const NAPALM_SCRIPT := preload("res://scenes/projectiles/NapalmZone.gd")

var direction := Vector3.ZERO
var _age:           float  = 0.0
var _base_damage:   float  = 50.0
var _source_weapon: Node3D = null
# Cluster offsets are sampled at impact, not on launch, so the source weapon's
# stat reflects upgrades taken between launch and arrival.
var _cluster_count:   int  = 0
var _napalm_burn_dps: float = 0.0
var _napalm_radius:   float = 0.0
var _napalm_duration: float = 0.0

func launch(from: Vector3, dir: Vector3, source_weapon: Node3D, base_damage: float) -> void:
	global_position = from
	direction = dir.normalized()
	_source_weapon = source_weapon
	_base_damage = base_damage
	if source_weapon != null:
		_cluster_count   = int(source_weapon.get("cluster_count"))
		_napalm_burn_dps = float(source_weapon.get("napalm_burn_dps"))
		_napalm_radius   = float(source_weapon.get("napalm_radius"))
		_napalm_duration = float(source_weapon.get("napalm_duration"))
	_build_mesh()

func _build_mesh() -> void:
	var mi  := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.18
	cap.height = 0.80
	mi.mesh = cap
	# Capsule's long axis is Y; rotate so it points along travel direction.
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.75, 0.25)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.45, 0.05)
	mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Aim the whole rocket along its travel direction
	if direction.length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)

	var light := OmniLight3D.new()
	light.light_color    = Color(1.0, 0.55, 0.15)
	light.light_energy   = 4.5
	light.omni_range     = 5.0
	light.shadow_enabled = false
	add_child(light)

func _process(delta: float) -> void:
	global_position += direction * SPEED * delta
	_age += delta
	if _age >= LIFETIME:
		_detonate(null)
		return

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var dist := global_position.distance_to(enemy.global_position + Vector3(0.0, 0.8, 0.0))
		if dist < HIT_RADIUS:
			_detonate(enemy)
			return

func _detonate(primary: Object) -> void:
	var hit_pos := global_position
	if is_instance_valid(_source_weapon):
		if primary != null and is_instance_valid(primary):
			_source_weapon._apply_hit(primary, _base_damage, hit_pos, direction)
		else:
			# Mid-air timeout: still detonate, splash any nearby enemies.
			var nearby: Array = _source_weapon._enemies_in_radius(hit_pos, maxf(_source_weapon.splash_radius, 1.0))
			for e in nearby:
				_source_weapon._apply_hit(e, _base_damage, hit_pos, (e.global_position - hit_pos).normalized())
	# Cluster: three offset micro-detonations in a triangle around the impact.
	if _cluster_count > 0 and is_instance_valid(_source_weapon):
		_spawn_cluster(hit_pos)
	# Napalm: persistent ground zone.
	if _napalm_burn_dps > 0.0 and _napalm_radius > 0.0:
		_spawn_napalm(hit_pos)

	BurstVFX.spawn(hit_pos, Color(1.0, 0.6, 0.15), 32, 8.5, 0.55, get_tree().current_scene)
	AudioManager.play("garlic_ult", hit_pos, -10.0, randf_range(1.05, 1.18))
	queue_free()

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
