extends Node3D

signal hit_enemy

const SPEED      := 24.0
const DAMAGE     := 20.0
const HIT_RADIUS := 0.8
# Sized to cover SHOOT_RANGE / SPEED with buffer for range upgrades. Going
# longer wastes per-frame grid queries on bullets already past any target.
const LIFETIME   := 1.4

const BurstVFX    = preload("res://scenes/vfx/BurstVFX.gd")
const EnemyGridCS = preload("res://scenes/enemies/EnemyGrid.gd")

var direction := Vector3.ZERO
var _age:           float  = 0.0
var _base_damage:   float  = DAMAGE   # pre-multiplied by ult-vs-passive factor
var _source_weapon: Node3D = null
var _is_crit:       bool   = false
var _is_ult:        bool   = false   # ult bullets render bigger and knock back harder
var _bonus_knockback: float = 0.0
# Hollow Rounds: extra enemies the bullet can pass through before despawning.
# Each pierce keeps the bullet flying; _hit_enemies prevents re-hitting the same target.
var _pierce_remaining: int = 0
var _hit_enemies: Array = []

func launch(from: Vector3, dir: Vector3, source_weapon: Node3D, base_damage: float = DAMAGE, is_crit: bool = false, is_ult: bool = false, bonus_knockback: float = 0.0, pierce: int = 0) -> void:
	global_position = from
	direction = dir.normalized()
	_source_weapon = source_weapon
	_base_damage = base_damage
	_is_crit = is_crit
	_is_ult  = is_ult
	_bonus_knockback = bonus_knockback
	_pierce_remaining = pierce
	_build_mesh()

func _build_mesh() -> void:
	var mi  := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.18
	sph.height = 0.36
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	# Crit bullets glow yellow-white so the player sees the kill-shot coming.
	if _is_crit:
		mat.albedo_color = Color(1.0, 1.0, 0.6)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.95, 0.2)
		mat.emission_energy_multiplier = 8.0
		sph.radius = 0.30
		sph.height = 0.60
	elif _is_ult:
		# Ult bullets read as fat orange tracer rounds — bigger silhouette so a
		# sweeping cone of them is visible at a glance.
		mat.albedo_color = Color(1.0, 0.85, 0.4)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.05)
		mat.emission_energy_multiplier = 6.0
		sph.radius = 0.34
		sph.height = 0.68
	else:
		# Tint passive bullets with the firing mech's archetype color so the
		# trace reads back to the source. Brighten the albedo for visibility.
		var tint: Color = Color(1.0, 0.85, 0.3)
		if _source_weapon != null and is_instance_valid(_source_weapon):
			var mc: Variant = _source_weapon.get("_mech_color")
			if mc != null:
				tint = mc as Color
		mat.albedo_color = tint.lerp(Color.WHITE, 0.45)
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 4.0
	mi.material_override = mat
	# Disable shadow casting on bullets entirely — at high waves there can be
	# 50+ bullets in flight from 3 mechs simultaneously, and per-bullet shadow
	# rendering compounds with cluster-build cost. Bullets move too fast for
	# shadow detail to read anyway.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	# No bullet OmniLights at all — the bullet's emissive material gives the
	# visible glow. With 3 GUN mechs each capable of firing 9–30 ult bullets
	# per cast simultaneously, light count was the dominant Forward+ cost.

func _process(delta: float) -> void:
	global_position += direction * SPEED * delta
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return

	# Query the spatial grid instead of scanning the whole enemies group every
	# frame — at high enemy/bullet counts the O(B*E) tree scan dominates.
	# Pad the query by 0.6 so shielded enemies (whose hit_radius_bonus widens
	# their effective hitbox up to +0.5) aren't excluded from the candidate set.
	EnemyGridCS.ensure_fresh(get_tree())
	for enemy in EnemyGridCS.query(global_position, HIT_RADIUS + 0.6):
		if not is_instance_valid(enemy):
			continue
		if enemy in _hit_enemies:
			continue
		var dist := global_position.distance_to(enemy.global_position + Vector3(0.0, 0.8, 0.0))
		var effective_radius: float = HIT_RADIUS
		if enemy.has_method("hit_radius_bonus"):
			effective_radius += float(enemy.call("hit_radius_bonus"))
		if dist < effective_radius:
			_hit_enemies.append(enemy)
			if is_instance_valid(_source_weapon):
				_source_weapon._apply_hit(enemy, _base_damage, global_position, direction, _is_crit, _bonus_knockback)
			else:
				enemy.take_damage(_base_damage, _is_crit)
			if _is_crit:
				BurstVFX.spawn(global_position, Color(1.0, 0.95, 0.3), 28, 9.0, 0.55, get_tree().current_scene)
				AudioManager.play("bullet_impact", global_position, -2.0, 1.6)
			elif _is_ult:
				BurstVFX.spawn(global_position, Color(1.0, 0.7, 0.2), 22, 7.5, 0.45, get_tree().current_scene)
				AudioManager.play("bullet_impact", global_position, -4.0, randf_range(0.85, 1.0))
			else:
				BurstVFX.spawn(global_position, Color(1.0, 0.65, 0.1), 14, 5.0, 0.35, get_tree().current_scene)
				AudioManager.play("bullet_impact", global_position, -8.0, randf_range(0.92, 1.1))
			hit_enemy.emit()
			if _pierce_remaining > 0:
				_pierce_remaining -= 1
				return
			queue_free()
			return
