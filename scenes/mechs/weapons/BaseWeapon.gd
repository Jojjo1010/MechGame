extends Node3D

signal charge_changed(value: float)  # 0.0 = just fired, 1.0 = ready

const SHOOT_RANGE := 22.0

var weapon_name:    String = "WEAPON"
var _mech:          Node3D = null
var _mech_color:    Color  = Color.WHITE
var _cooldown_timer: float = 0.0   # counts down from get_ult_cooldown() to 0
var _fire_timer:    float  = 0.0
var _drone_nearby:  bool   = false

# ── Upgrade multipliers (modified by level-up cards) ─────────────────────────
var damage_mult:            float = 1.0
var fire_rate_mult:         float = 1.0   # >1 = faster
var range_mult:             float = 1.0
var projectile_count_bonus: int   = 0     # Gun: extra bullets, Beam: extra bounces
var dot_dps:                float = 0.0   # damage-over-time applied on hit
var knockback_force:        float = 0.0   # impulse magnitude on hit (0 = none)
var splash_radius:          float = 0.0   # secondary AOE radius around hit (0 = none)
var slow_mult:              float = 1.0   # 1.0 = no slow, 0.5 = half speed
var slow_duration:          float = 0.0   # seconds the slow lasts
# Headshot (Gun) — number of upgrade stacks taken; 0 = off, 3 = every shot crits
var headshot_count:         int   = 0
# Withering (Garlic) — per-stack damage bonus on enemies hit by consecutive pulses
var withering_per_stack:    float = 0.0
# Bulwark (Garlic) — fraction of damage reduced for mechs inside the aura
var bulwark_dmg_reduction:  float = 0.0
# Hollow Rounds (Gun rare) — how many additional enemies a single bullet pierces
var pierce_count:           int   = 0
# Sanctuary (Garlic rare) — HP per second restored to mechs inside the aura
var aura_regen_per_sec:     float = 0.0
const DOT_DURATION:         float = 3.0
const SPLASH_DAMAGE_FRAC:   float = 0.5   # splash deals 50% of base damage
const BASE_KNOCKBACK:       float = 4.0   # small baseline kick every weapon hit applies
const CRIT_MULT:            float = 6.0   # Headshot crit damage multiplier
const WITHER_REFRESH_SEC:   float = 1.5   # how long wither stacks linger after a pulse

# Ready-state ring (floating [E] label removed — panel button handles that)
var _ready_ring: MeshInstance3D     = null
var _ring_mat:   StandardMaterial3D = null
var _ring_tween: Tween              = null

func setup(mech: Node3D) -> void:
	_mech = mech
	var col: Variant = mech.get("_base_color")
	_mech_color = col as Color if col != null else Color.WHITE
	_fire_timer = randf_range(0.0, _effective_fire_period())
	_build_ready_visuals()
	_on_setup()
	# Start 60 % into the first cooldown so first ult arrives sooner
	_cooldown_timer = get_ult_cooldown() * 0.6
	charge_changed.emit(get_charge())

func _on_setup() -> void:
	pass

# ── Override per weapon ───────────────────────────────────────────────────────

func get_fire_rate() -> float:
	return 1.0

func get_ult_cooldown() -> float:
	return 12.0

func _effective_fire_period() -> float:
	return get_fire_rate() / maxf(fire_rate_mult, 0.01)

func _effective_shoot_range() -> float:
	return SHOOT_RANGE * range_mult

# ── Per-frame tick ────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _mech == null or not _mech.is_alive:
		return

	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = _effective_fire_period()
		_passive_fire()

	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
		charge_changed.emit(get_charge())
		if _cooldown_timer <= 0.0:
			_on_became_ready()

# ── Actions ───────────────────────────────────────────────────────────────────

func _passive_fire() -> void:
	pass

func activate_ult() -> bool:
	if not is_ready():
		return false
	_reset_cooldown()
	_fire_ult()
	return true

func _fire_ult() -> void:
	pass

# Called by subclasses that override activate_ult (e.g. GunWeapon aiming mode)
func _reset_cooldown() -> void:
	_cooldown_timer = get_ult_cooldown()
	charge_changed.emit(0.0)
	_on_ult_consumed()

# ── State queries ─────────────────────────────────────────────────────────────

func get_charge() -> float:
	var cd := get_ult_cooldown()
	if cd <= 0.0:
		return 1.0
	return 1.0 - (_cooldown_timer / cd)

func is_ready() -> bool:
	return _cooldown_timer <= 0.0

func notify_drone_nearby(nearby: bool) -> void:
	_drone_nearby = nearby

# ── Ready / consumed hooks ────────────────────────────────────────────────────

func _on_became_ready() -> void:
	_show_ring()
	if is_instance_valid(_mech):
		AudioManager.play("ult_ready", _mech.global_position, -4.0)

func _on_ult_consumed() -> void:
	_hide_ring()
	if is_instance_valid(_mech) and _mech.has_method("ult_fired"):
		_mech.ult_fired(_mech_color)

# ── Ring visuals ──────────────────────────────────────────────────────────────

func _show_ring() -> void:
	if _ready_ring == null or not is_instance_valid(_ready_ring):
		return
	_ready_ring.visible = true
	if _ring_tween != null:
		_ring_tween.kill()
	_ring_tween = _ready_ring.create_tween().set_loops()
	_ring_tween.tween_property(_ring_mat, "albedo_color:a", 0.70, 0.50)
	_ring_tween.tween_property(_ring_mat, "albedo_color:a", 0.15, 0.50)

func _hide_ring() -> void:
	if _ring_tween != null:
		_ring_tween.kill()
		_ring_tween = null
	if _ready_ring == null or not is_instance_valid(_ready_ring):
		return
	_ring_mat.albedo_color.a = 0.0
	_ready_ring.visible = false

# Stubs kept for GunWeapon compatibility (it still calls these in _cancel_aiming)
func _show_e_label() -> void:
	pass

func _hide_e_label() -> void:
	pass

# ── Build ring ────────────────────────────────────────────────────────────────

func _build_ready_visuals() -> void:
	_ready_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius  = 1.30
	torus.outer_radius  = 1.75
	torus.rings         = 48
	torus.ring_segments = 12
	_ready_ring.mesh = torus
	_ready_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color               = Color(_mech_color.r, _mech_color.g, _mech_color.b, 0.0)
	_ring_mat.emission_enabled           = true
	_ring_mat.emission                   = _mech_color
	_ring_mat.emission_energy_multiplier = 4.0
	_ring_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ready_ring.material_override = _ring_mat
	_ready_ring.position.y = 0.12
	_ready_ring.visible    = false
	add_child(_ready_ring)

# ── Enemy helpers ─────────────────────────────────────────────────────────────

func _nearest_enemy() -> Node3D:
	var nearest: Node3D = null
	var min_dist := _effective_shoot_range()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d := _mech.global_position.distance_to(e.global_position)
		if d < min_dist:
			min_dist = d
			nearest = e
	return nearest

func _nearest_from(from_pos: Vector3) -> Node3D:
	var nearest: Node3D = null
	var min_dist := _effective_shoot_range()
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		var d := from_pos.distance_to(e.global_position)
		if d < min_dist:
			min_dist = d
			nearest = e
	return nearest

func _enemies_in_radius(center: Vector3, radius: float) -> Array:
	var result: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if center.distance_to(e.global_position) <= radius:
			result.append(e)
	return result

# ── Damage helper ─────────────────────────────────────────────────────────────
# Applies a hit to an enemy with all configured effects: damage (× damage_mult ×
# wither), DOT, slow, knockback, splash. `hit_dir` is the incoming direction;
# used for knockback. Splash uses SPLASH_DAMAGE_FRAC of the primary damage.
# `is_crit` flags the hit as a Headshot for the damage-number visual.
func _apply_hit(enemy: Object, base_damage: float, hit_pos: Vector3, hit_dir: Vector3 = Vector3.ZERO, is_crit: bool = false, bonus_knockback: float = 0.0) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var wither_mult := 1.0
	# Withering: refresh stacks on every pulse this enemy gets, scale damage with the post-refresh count.
	if withering_per_stack > 0.0 and enemy.has_method("apply_wither"):
		var stacks: int = enemy.apply_wither(WITHER_REFRESH_SEC)
		wither_mult = 1.0 + withering_per_stack * float(stacks)
	var dmg := base_damage * damage_mult * wither_mult
	enemy.take_damage(dmg, is_crit)
	if dot_dps > 0.0 and enemy.has_method("apply_dot"):
		enemy.apply_dot(dot_dps, DOT_DURATION)
	if slow_duration > 0.0 and slow_mult < 1.0 and enemy.has_method("apply_slow"):
		enemy.apply_slow(slow_mult, slow_duration)
	if enemy.has_method("apply_knockback"):
		var dir := hit_dir
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			enemy.apply_knockback(dir.normalized() * (BASE_KNOCKBACK + knockback_force + bonus_knockback))
	if splash_radius > 0.0:
		var splash_dmg := dmg * SPLASH_DAMAGE_FRAC
		for other in _enemies_in_radius(hit_pos, splash_radius):
			if other == enemy or not is_instance_valid(other):
				continue
			other.take_damage(splash_dmg)
			if dot_dps > 0.0 and other.has_method("apply_dot"):
				other.apply_dot(dot_dps, DOT_DURATION)
