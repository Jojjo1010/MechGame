extends Node3D

const BurstVFX     = preload("res://scenes/vfx/BurstVFX.gd")
const HealthBar3D  = preload("res://scenes/ui/HealthBar3D.gd")
const DamageNumber = preload("res://scenes/ui/DamageNumber.gd")
const Pickup       = preload("res://scenes/pickups/Pickup.gd")
const OUTLINE_SHADER = preload("res://scenes/vfx/mech_outline.gdshader")
const EnemyGridCS    = preload("res://scenes/enemies/EnemyGrid.gd")

const SPEED := 4.5
const ATTACK_RANGE := 1.4
const ATTACK_DAMAGE := 8.0
const ATTACK_INTERVAL := 1.0

# Separation: enemies push each other apart when too close
const SEPARATION_RADIUS := 1.3   # start pushing when closer than this (world units)
const SEPARATION_STRENGTH := 3.0 # multiplier on sep vector when blended with move dir

@export var max_health: float = 40.0
# Tutorial dummy: stationary, doesn't chase, doesn't attack mechs. Still takes
# damage / DOT / wither / knockback so the player can practice the ult on it.
@export var is_dummy:   bool  = false

const FLASH_DURATION := 0.10

# Wave scaling — set by WaveSpawner before add_child so Enemy._ready can
# apply HP/visual scaling in one place. Skipped for tutorial dummies.
#   • HP curve grows linearly from wave 1, capped — gentle so player upgrades
#     stay ahead of enemy HP.
#   • Three visual tiers band the curve so the toughening *reads*: same
#     enemy mesh, deeper red as the run progresses.
#   • Elites override tier visuals with a gold/magenta palette and are
#     notably tougher — they read as priority targets.
const HP_PER_WAVE   := 0.014   # +1.4% HP per wave (linear, before cap)
const HP_MULT_CAP   := 1.40    # reaches the cap around wave 30
const ELITE_HP_MULT := 2.0
const ELITE_SCALE   := 1.10

var wave_number: int  = 1
var is_elite:    bool = false

var health: float = max_health
var attack_timer: float = 0.0
var target_mech: Node3D = null
var _health_bar: Node3D = null
var _mesh_instances: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D = null
var _knockback_vel: Vector3 = Vector3.ZERO

# Damage-over-time
var _dot_dps:        float = 0.0
var _dot_remaining:  float = 0.0
var _dot_tick_timer: float = 0.0
const DOT_TICK_INTERVAL := 0.5

# Slow debuff: movement multiplier with timer
var _slow_mult:      float = 1.0
var _slow_remaining: float = 0.0

# Wither stacks (Garlic Withering upgrade): per-enemy escalating multiplier
const WITHER_MAX_STACKS := 3
var _wither_stacks:    int   = 0
var _wither_remaining: float = 0.0
var _wither_pips:      Label3D = null

# Damage-number coalescing. The first hit shows immediately; subsequent hits
# within DMG_COALESCE_WINDOW accumulate into a single combined number. This
# stops late-game burn / napalm / splash / aura ticks from drawing dozens of
# overlapping numbers per enemy. is_crit OR-fold means a crit anywhere in the
# window upgrades the combined visual to the crit treatment.
const DMG_COALESCE_WINDOW := 0.12
var _dmg_pending:      float = 0.0
var _dmg_pending_crit: bool  = false
var _dmg_coalesce_cd:  float = 0.0

signal enemy_died()

func _ready() -> void:
	add_to_group("enemies")
	if not is_dummy:
		_apply_wave_scaling()
	health = max_health
	var base_scale: float = 0.6 * (ELITE_SCALE if is_elite else 1.0)
	scale = Vector3(base_scale, base_scale, base_scale)
	# Build shared white overlay material for hit flash
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.albedo_color   = Color.WHITE
	_flash_mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.emission_enabled = true
	_flash_mat.emission       = Color.WHITE
	_flash_mat.emission_energy_multiplier = 1.5
	for child in find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_mesh_instances.append(mi)
	_add_permanent_outline()
	_add_blob_shadow(0.5, 2.5)
	# HP bar — hidden until first hit
	_health_bar = Node3D.new()
	_health_bar.set_script(HealthBar3D)
	_health_bar.position = Vector3(0.0, 2.9, 0.0)
	_health_bar.visible = false
	add_child(_health_bar)

func _apply_wave_scaling() -> void:
	# HP: linear ramp, capped. Elites are an additional flat multiplier on top.
	var hp_mult: float = minf(1.0 + HP_PER_WAVE * float(wave_number - 1), HP_MULT_CAP)
	if is_elite:
		hp_mult *= ELITE_HP_MULT
	max_health *= hp_mult

	# Visual: replace the body/head material_overrides with tier-tinted (or
	# elite-styled) ones. Tier index bands waves 1-10 / 11-20 / 21-30 so the
	# darkening reads as discrete steps rather than an invisible gradient.
	var body_mi: MeshInstance3D = get_node_or_null("Body") as MeshInstance3D
	var head_mi: MeshInstance3D = get_node_or_null("Head") as MeshInstance3D
	if body_mi == null or head_mi == null:
		return
	var palette: Dictionary = _palette_for(wave_number, is_elite)
	body_mi.material_override = _make_body_mat(palette.body)
	head_mi.material_override = _make_head_mat(palette.head, palette.emission, palette.emission_energy)

func _palette_for(wave: int, elite: bool) -> Dictionary:
	if elite:
		# Gold body + hot-magenta head with a stronger glow — reads instantly
		# as "different / priority target" against the red palette.
		return {
			body            = Color(0.85, 0.62, 0.15),
			head            = Color(0.95, 0.20, 0.65),
			emission        = Color(1.00, 0.30, 0.85),
			emission_energy = 1.4,
		}
	var tier: int = clampi((wave - 1) / 10, 0, 2)
	match tier:
		1:
			return {  # mid-run: deeper red, slight purple shift
				body            = Color(0.65, 0.12, 0.18),
				head            = Color(0.50, 0.08, 0.13),
				emission        = Color(0.95, 0.10, 0.30),
				emission_energy = 0.9,
			}
		2:
			return {  # late: near-black with hot rim emission
				body            = Color(0.40, 0.06, 0.18),
				head            = Color(0.30, 0.05, 0.15),
				emission        = Color(1.00, 0.20, 0.45),
				emission_energy = 1.2,
			}
		_:
			return {  # early: matches the .tscn defaults
				body            = Color(0.85, 0.20, 0.15),
				head            = Color(0.70, 0.15, 0.10),
				emission        = Color(1.00, 0.10, 0.00),
				emission_energy = 0.8,
			}

func _make_body_mat(albedo: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness    = 0.7
	m.metallic     = 0.2
	return m

func _make_head_mat(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color                  = albedo
	m.emission_enabled              = true
	m.emission                      = emission
	m.emission_energy_multiplier    = energy
	return m

func _add_permanent_outline() -> void:
	for src in _mesh_instances:
		if not is_instance_valid(src) or src.mesh == null:
			continue
		var ol := MeshInstance3D.new()
		ol.mesh = src.mesh
		ol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := ShaderMaterial.new()
		sm.shader = OUTLINE_SHADER
		sm.set_shader_parameter("outline_color", Color(0.0, 0.0, 0.0, 1.0))
		sm.set_shader_parameter("outline_size", 0.08)
		ol.material_override = sm
		src.add_child(ol)
		ol.transform = Transform3D.IDENTITY

func _add_shadow_decal(width: float, depth: float, char_height: float) -> void:
	const SUN_Y_DEG := 42.0
	const SUN_ELEV  := 38.0
	var offset_dist := char_height / tan(deg_to_rad(SUN_ELEV)) * 0.28
	var shadow_dir  := Vector3(-sin(deg_to_rad(SUN_Y_DEG)), 0.0, -cos(deg_to_rad(SUN_Y_DEG)))

	# Reuse the same shared texture from Mech if available
	var grad := Gradient.new()
	grad.add_point(0.0, Color(0.0, 0.0, 0.0, 0.65))
	grad.add_point(1.0, Color(0.0, 0.0, 0.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill      = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to   = Vector2(1.0, 0.5)
	tex.width     = 64
	tex.height    = 64

	var decal := Decal.new()
	decal.texture_albedo = tex
	decal.size           = Vector3(width, 6.0, depth)
	decal.albedo_mix     = 0.7
	decal.position       = shadow_dir * offset_dist + Vector3(0.0, 3.0, 0.0)
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
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position   = shadow_dir * shadow_len * 0.16 + Vector3(0.0, 0.02, 0.0)
	disc.rotation.y = -deg_to_rad(SUN_Y_DEG)
	disc.scale      = Vector3(1.0, 1.0, 1.2)
	add_child(disc)

func apply_knockback(impulse: Vector3) -> void:
	_knockback_vel = impulse

# Increment wither stacks (capped) and refresh the decay timer. Returns the new
# stack count so the calling weapon can compute its damage multiplier.
func apply_wither(refresh_duration: float) -> int:
	_wither_stacks    = mini(_wither_stacks + 1, WITHER_MAX_STACKS)
	_wither_remaining = refresh_duration
	_update_wither_visual()
	return _wither_stacks

func _update_wither_visual() -> void:
	if _wither_stacks <= 0:
		if is_instance_valid(_wither_pips):
			_wither_pips.queue_free()
			_wither_pips = null
		return
	if _wither_pips == null or not is_instance_valid(_wither_pips):
		_wither_pips = Label3D.new()
		_wither_pips.font_size  = 64
		_wither_pips.outline_size = 8
		_wither_pips.outline_modulate = Color(0.0, 0.05, 0.0, 1.0)
		_wither_pips.modulate = Color(0.55, 1.0, 0.35, 1.0)
		_wither_pips.billboard       = BaseMaterial3D.BILLBOARD_ENABLED
		_wither_pips.no_depth_test   = true
		_wither_pips.render_priority = 9
		_wither_pips.position = Vector3(0.0, 3.4, 0.0)
		add_child(_wither_pips)
	# Skull-like pip glyphs; one bullet per stack
	_wither_pips.text = "•".repeat(_wither_stacks)
	# Tint shifts darker green as stacks rise
	var t := float(_wither_stacks) / float(WITHER_MAX_STACKS)
	_wither_pips.modulate = Color(0.55 - 0.30 * t, 1.0, 0.35 - 0.20 * t, 1.0)

func apply_dot(dps: float, duration: float) -> void:
	# Refresh duration and keep the strongest dps stack
	_dot_dps       = maxf(_dot_dps, dps)
	_dot_remaining = maxf(_dot_remaining, duration)
	if _dot_tick_timer <= 0.0:
		_dot_tick_timer = DOT_TICK_INTERVAL

func _damage_number_color(is_crit: bool) -> Color:
	if is_crit:
		return Color(1.0, 0.95, 0.25)         # bright yellow for crits
	if _wither_stacks > 0:
		return Color(0.55, 1.0, 0.35)         # green for wither-amped hits
	return Color(1.0, 0.92, 0.15)             # default

func apply_slow(mult: float, duration: float) -> void:
	# Keep the strongest slow (smaller mult = stronger), refresh duration
	_slow_mult      = minf(_slow_mult, mult)
	_slow_remaining = maxf(_slow_remaining, duration)

func _spawn_damage_number(amount: float, is_crit: bool) -> void:
	DamageNumber.spawn(amount, global_position + Vector3(0.0, 2.2, 0.0),
		get_tree().current_scene, _damage_number_color(is_crit), is_crit)

func _process(delta: float) -> void:
	if _dmg_coalesce_cd > 0.0:
		_dmg_coalesce_cd -= delta
		if _dmg_coalesce_cd <= 0.0:
			_dmg_coalesce_cd = 0.0
			# Flush whatever piled up during the cooldown. If something is
			# pending, restart the window so a sustained DOT/aura keeps
			# coalescing instead of going back to spawn-per-hit.
			if _dmg_pending > 0.0:
				_spawn_damage_number(_dmg_pending, _dmg_pending_crit)
				_dmg_pending = 0.0
				_dmg_pending_crit = false
				_dmg_coalesce_cd = DMG_COALESCE_WINDOW

	if _knockback_vel.length_squared() > 0.01:
		_knockback_vel = _knockback_vel.lerp(Vector3.ZERO, 10.0 * delta)
		global_position += _knockback_vel * delta

	if _dot_remaining > 0.0:
		_dot_remaining -= delta
		_dot_tick_timer -= delta
		if _dot_tick_timer <= 0.0:
			_dot_tick_timer = DOT_TICK_INTERVAL
			take_damage(_dot_dps * DOT_TICK_INTERVAL)
		if _dot_remaining <= 0.0:
			_dot_dps = 0.0

	if _slow_remaining > 0.0:
		_slow_remaining -= delta
		if _slow_remaining <= 0.0:
			_slow_mult = 1.0

	# Wither decay: stacks reset entirely when the timer expires (escape window)
	if _wither_remaining > 0.0:
		_wither_remaining -= delta
		if _wither_remaining <= 0.0:
			_wither_stacks = 0
			_update_wither_visual()

	# Tutorial dummies stand still and don't attack — they exist purely as
	# practice targets. Damage / DOT / wither still apply (handled above) so
	# the player's ult lands the same way it would on a real enemy.
	if is_dummy:
		return

	_find_target()

	var sep := _get_separation()

	if target_mech == null:
		# No mech to chase — still spread out
		position += sep * SEPARATION_STRENGTH * delta
		return

	var dist := global_position.distance_to(target_mech.global_position)

	if dist > ATTACK_RANGE:
		var dir := (target_mech.global_position - global_position)
		dir.y = 0.0
		dir = dir.normalized()
		# Blend target direction with separation so enemies spread around each other
		var move_dir := dir + sep * SEPARATION_STRENGTH
		if move_dir.length() > 0.01:
			move_dir = move_dir.normalized()
		position += move_dir * SPEED * _slow_mult * delta
		# Face movement direction
		if move_dir.length() > 0.01:
			rotation.y = atan2(move_dir.x, move_dir.z)
	else:
		# In attack range: still push apart so they ring the mech instead of stacking
		position += sep * SEPARATION_STRENGTH * delta
		attack_timer -= delta
		if attack_timer <= 0.0:
			attack_timer = ATTACK_INTERVAL
			if target_mech.has_method("take_damage"):
				target_mech.take_damage(ATTACK_DAMAGE)

func _get_separation() -> Vector3:
	# Query the EnemyGrid instead of the full enemies group — at high enemy
	# counts the tree-wide O(N²) scan was the dominant frame cost. The grid
	# is rebuilt at most once per frame (lazy on first call).
	EnemyGridCS.ensure_fresh(get_tree())
	var sep := Vector3.ZERO
	for enemy in EnemyGridCS.query(global_position, SEPARATION_RADIUS):
		var e := enemy as Node3D
		if e == null or e == self or not is_instance_valid(e):
			continue
		var diff: Vector3 = global_position - e.global_position
		diff.y = 0.0
		var dist := diff.length()
		if dist < SEPARATION_RADIUS and dist > 0.001:
			# Stronger push the closer they are
			sep += diff.normalized() * (SEPARATION_RADIUS - dist) / SEPARATION_RADIUS
	return sep

func _find_target() -> void:
	var mechs := get_tree().get_nodes_in_group("mechs")
	var nearest: Node3D = null
	var min_dist := INF
	for m in mechs:
		# Skip dead mechs so enemies retarget after a kill instead of swinging
		# at the corpse.
		var alive: Variant = m.get("is_alive")
		if alive != null and not alive:
			continue
		var d := global_position.distance_to(m.global_position)
		if d < min_dist:
			min_dist = d
			nearest = m
	target_mech = nearest

func _flash_hit() -> void:
	for mi in _mesh_instances:
		if is_instance_valid(mi):
			mi.material_overlay = _flash_mat
	var tw := create_tween()
	tw.tween_interval(FLASH_DURATION)
	tw.tween_callback(func() -> void:
		for mi in _mesh_instances:
			if is_instance_valid(mi):
				mi.material_overlay = null)

func take_damage(amount: float, is_crit: bool = false) -> void:
	health = maxf(0.0, health - amount)
	_flash_hit()
	if is_instance_valid(_health_bar):
		_health_bar.visible = true
		_health_bar.set_fraction(health / max_health)
	if _dmg_coalesce_cd <= 0.0:
		_spawn_damage_number(amount, is_crit)
		_dmg_coalesce_cd = DMG_COALESCE_WINDOW
	else:
		_dmg_pending += amount
		if is_crit:
			_dmg_pending_crit = true
	if health <= 0.0:
		# Flush whatever was queued so the killing blow's full damage lands at
		# the corpse rather than disappearing with the freed enemy.
		if _dmg_pending > 0.0:
			_spawn_damage_number(_dmg_pending, _dmg_pending_crit)
			_dmg_pending = 0.0
			_dmg_pending_crit = false
		enemy_died.emit()
		RunManager.notify_kill()
		BurstVFX.spawn(
			global_position + Vector3(0.0, 1.0, 0.0),
			Color(0.9, 0.15, 0.05), 22, 7.0, 0.55,
			get_tree().current_scene
		)
		AudioManager.play("enemy_death", global_position, -4.0, randf_range(0.9, 1.1))
		_spawn_pickups()
		queue_free()

func _spawn_pickups() -> void:
	var scene := get_tree().current_scene
	# Total XP for the kill — same averages as before (3 normal, 6 elite). The
	# XP is queued, not spawned directly: queue_xp batches kills inside one
	# 3 m bucket over a ~100 ms window and pays the consolidated total out as
	# the fewest gems possible (HUGE 50 / BIG 10 / SMALL remainder). An AOE
	# clear of 30 enemies × 3 XP = 90 XP collapses to ~1 HUGE + 4 BIG (5
	# sprites) instead of 30 small gems.
	var xp_total: int = randi_range(5, 7) if is_elite else randi_range(2, 4)
	Pickup.queue_xp(xp_total, global_position, scene)

	if is_elite:
		# Guaranteed multi-coin gold drop on elites.
		for i in 3:
			var off := Vector3(randf_range(-0.8, 0.8), 0.5, randf_range(-0.8, 0.8))
			Pickup.spawn(Pickup.Type.GOLD, 1, global_position + off, scene)
	elif randf() < 0.35:
		var off := Vector3(randf_range(-0.6, 0.6), 0.5, randf_range(-0.6, 0.6))
		Pickup.spawn(Pickup.Type.GOLD, 1, global_position + off, scene)
