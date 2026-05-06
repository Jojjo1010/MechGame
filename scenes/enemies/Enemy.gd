extends Node3D

const BurstVFX     = preload("res://scenes/vfx/BurstVFX.gd")
const HealthBar3D  = preload("res://scenes/ui/HealthBar3D.gd")
const DamageNumber = preload("res://scenes/ui/DamageNumber.gd")
const Pickup       = preload("res://scenes/pickups/Pickup.gd")
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
# Shielded variant: drone has to dash through to break the overshield before
# any damage source (mech fire, splash, DOT, etc.) can land. Stamped pre-_ready
# by WaveSpawner; kept mutually exclusive with is_elite.
var is_shielded: bool = false
var _shield_active:  bool = false
var _shield_bubble:  MeshInstance3D = null
var _shield_bubble_mat: StandardMaterial3D = null
var _shield_icon:    Label3D = null
const SHIELD_HP_MULT     := 1.4   # tankier than baseline so the dash reads as a meaningful payoff
const SHIELD_SCALE       := 1.30  # bigger than a normal enemy — reads as "armored / heavy" before the bubble even shows
const SHIELD_BUBBLE_R    := 0.95  # world-space radius (in local space; inherits SHIELD_SCALE)
const SHIELD_ICON_HEIGHT := 3.4   # above the head, distinct from HP-bar slot
const SHIELD_HIT_RADIUS_BONUS := 0.5  # extra reach added to bullet + dash hit checks against shielded targets

# Public hit-radius hook used by Bullet + Drone dash. Returns the extra world-
# space reach to add on top of the projectile's own hit radius. Default is 0;
# shielded variants extend their hitbox so the dash + bullets register on the
# bigger silhouette without needing perfect aim.
func hit_radius_bonus() -> float:
	if is_shielded:
		return SHIELD_HIT_RADIUS_BONUS
	return 0.0

var health: float = max_health
var attack_timer: float = 0.0
var target_mech: Node3D = null
# Per-enemy speed jitter so a wave's spawns spread out into a natural-looking
# horde instead of moving in lockstep. Sampled once at spawn from [0.9, 1.2].
var _speed_mult: float = 1.0
# Per-enemy phase offset for the staggered retarget cadence — without it every
# enemy would re-evaluate target on the same frame and spike the cost.
var _retarget_phase: int = 0
var _health_bar: Node3D = null
var _mesh_instances: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D = null
var _knockback_vel: Vector3 = Vector3.ZERO
var _flash_remaining: float = 0.0

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
# within DMG_COALESCE_FRAMES accumulate into a single combined number that
# spawns once the counter drains. Frame-counted (not time) so visual density
# stays consistent regardless of dt jitter. is_crit OR-fold means a crit
# anywhere in the window upgrades the combined visual to the crit treatment.
const DMG_COALESCE_FRAMES := 5
var _dmg_pending:        float = 0.0
var _dmg_pending_crit:   bool  = false
var _dmg_coalesce_frames: int  = 0

signal enemy_died()

const RETARGET_INTERVAL_FRAMES := 10

func _ready() -> void:
	add_to_group("enemies")
	_retarget_phase = randi() % RETARGET_INTERVAL_FRAMES
	_speed_mult = randf_range(0.9, 1.2)
	if not is_dummy:
		_apply_wave_scaling()
	health = max_health
	var size_mult: float = 1.0
	if is_elite:
		size_mult = ELITE_SCALE
	elif is_shielded:
		size_mult = SHIELD_SCALE
	var base_scale: float = 0.6 * size_mult
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
	_add_blob_shadow(0.5, 2.5)
	# HP bar is lazy-created on first hit — splash/AOE often kills enemies
	# without ever damaging them solo, so the bar stays unbuilt for those.
	if is_shielded and not is_dummy:
		_build_shield_visual()

func _apply_wave_scaling() -> void:
	# HP: linear ramp, capped. Elites and shielded each apply a separate flat
	# multiplier — they're mutually exclusive at spawn time so only one fires.
	var hp_mult: float = minf(1.0 + HP_PER_WAVE * float(wave_number - 1), HP_MULT_CAP)
	if is_elite:
		hp_mult *= ELITE_HP_MULT
	elif is_shielded:
		hp_mult *= SHIELD_HP_MULT
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
	if is_shielded:
		# Cool steel body + cyan head — reads as "armored / coded blue, dash me"
		# against the red horde and gold elites.
		return {
			body            = Color(0.55, 0.62, 0.72),
			head            = Color(0.30, 0.78, 0.95),
			emission        = Color(0.30, 0.85, 1.00),
			emission_energy = 1.1,
		}
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
	if _dmg_coalesce_frames > 0:
		_dmg_coalesce_frames -= 1
		if _dmg_coalesce_frames <= 0 and _dmg_pending > 0.0:
			# Flush what piled up during the cooldown. If something was queued
			# we restart the counter so a sustained burst keeps coalescing
			# instead of falling back to spawn-per-hit.
			_spawn_damage_number(_dmg_pending, _dmg_pending_crit)
			_dmg_pending = 0.0
			_dmg_pending_crit = false
			_dmg_coalesce_frames = DMG_COALESCE_FRAMES

	_tick_flash(delta)

	if _knockback_vel.length_squared() > 0.01:
		_knockback_vel = _knockback_vel.lerp(Vector3.ZERO, 10.0 * delta)
		global_position += _knockback_vel * delta

	if _dot_remaining > 0.0:
		_dot_remaining -= delta
		_dot_tick_timer -= delta
		if _dot_tick_timer <= 0.0:
			_dot_tick_timer = DOT_TICK_INTERVAL
			take_damage(_dot_dps * DOT_TICK_INTERVAL, false, false)
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

	# Refresh target on a staggered cadence, but always immediately if the
	# current one is gone — otherwise kills leave enemies frozen for ~10 frames.
	if _target_dead_or_missing() or (Engine.get_process_frames() + _retarget_phase) % RETARGET_INTERVAL_FRAMES == 0:
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
		position += move_dir * SPEED * _speed_mult * _slow_mult * delta
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

func _target_dead_or_missing() -> bool:
	if target_mech == null or not is_instance_valid(target_mech):
		return true
	return target_mech.get("is_alive") == false

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

func _ensure_health_bar() -> void:
	if is_instance_valid(_health_bar):
		return
	_health_bar = Node3D.new()
	_health_bar.set_script(HealthBar3D)
	_health_bar.position = Vector3(0.0, 2.9, 0.0)
	add_child(_health_bar)

func _flash_hit() -> void:
	if _flash_remaining <= 0.0:
		for mi in _mesh_instances:
			if is_instance_valid(mi):
				mi.material_overlay = _flash_mat
	_flash_remaining = FLASH_DURATION

func _tick_flash(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return
	_flash_remaining -= delta
	if _flash_remaining <= 0.0:
		for mi in _mesh_instances:
			if is_instance_valid(mi):
				mi.material_overlay = null

# `show_number=false` suppresses the floating damage number for this hit. Used
# by indirect damage (splash secondaries, DOT ticks, napalm, Garlic/Rocket ult
# AOEs) so a single rocket impact doesn't paint 5+ numbers across the cluster.
# Direct bullet/primary hits leave it true so per-shot feedback survives.
func take_damage(amount: float, is_crit: bool = false, show_number: bool = true) -> void:
	# Overshield absorbs every damage source — direct hits, splash, DOT, aura
	# pulses. Drone dash calls break_shield() instead, which removes _shield_active
	# and lets subsequent damage land normally.
	if _shield_active:
		return
	health = maxf(0.0, health - amount)
	_flash_hit()
	# Killing blows skip the bar — the enemy is about to queue_free anyway.
	if health > 0.0:
		_ensure_health_bar()
		_health_bar.set_fraction(health / max_health)
	if show_number:
		if _dmg_coalesce_frames <= 0:
			_spawn_damage_number(amount, is_crit)
			_dmg_coalesce_frames = DMG_COALESCE_FRAMES
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

	# Gold drops route through queue_gold so an elite swarm collapses into a
	# few BIG/HUGE coins at the cluster center instead of N×3 SMALL coins.
	if is_elite:
		Pickup.queue_gold(3, global_position, scene)
	elif is_shielded:
		Pickup.queue_gold(2, global_position, scene)   # mid-tier reward — between normal and elite
	elif randf() < 0.35:
		Pickup.queue_gold(1, global_position, scene)

# ── Shielded variant ─────────────────────────────────────────────────────────

func is_shielded_active() -> bool:
	return _shield_active

# Drone-dash entry point. Pops the bubble + icon, spawns a cyan break burst,
# and flips _shield_active so subsequent damage lands. Idempotent — second
# dash through the same enemy in one pass is a no-op.
func break_shield() -> void:
	if not _shield_active:
		return
	_shield_active = false
	if is_instance_valid(_shield_bubble):
		_shield_bubble.queue_free()
	_shield_bubble = null
	_shield_bubble_mat = null
	if is_instance_valid(_shield_icon):
		_shield_icon.queue_free()
	_shield_icon = null
	BurstVFX.spawn(global_position + Vector3(0.0, 1.0, 0.0),
		Color(0.4, 0.85, 1.0), 28, 8.5, 0.55, get_tree().current_scene)
	AudioManager.play("bullet_impact", global_position, -3.0, 1.6)

func _build_shield_visual() -> void:
	# Translucent cyan bubble around the body — sized larger than the enemy AABB
	# so it reads as a "force-field shell" rather than a tinted skin.
	_shield_bubble = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = SHIELD_BUBBLE_R
	sph.height = SHIELD_BUBBLE_R * 2.0
	_shield_bubble.mesh = sph
	_shield_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield_bubble_mat = StandardMaterial3D.new()
	_shield_bubble_mat.albedo_color = Color(0.30, 0.85, 1.00, 0.32)
	_shield_bubble_mat.emission_enabled = true
	_shield_bubble_mat.emission = Color(0.20, 0.70, 1.00)
	_shield_bubble_mat.emission_energy_multiplier = 2.0
	_shield_bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shield_bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shield_bubble.material_override = _shield_bubble_mat
	_shield_bubble.position = Vector3(0.0, 1.0, 0.0)   # roughly chest-level
	add_child(_shield_bubble)

	# Floating shield-icon glyph above the head — telegraphs "this one needs the
	# dash" before the player even sees the bubble against busy backgrounds.
	_shield_icon = Label3D.new()
	_shield_icon.text = "🛡"
	_shield_icon.font_size = 56
	_shield_icon.outline_size = 12
	_shield_icon.modulate = Color(0.40, 0.90, 1.00)
	_shield_icon.outline_modulate = Color(0.0, 0.05, 0.15, 1.0)
	_shield_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_shield_icon.no_depth_test = true
	_shield_icon.position = Vector3(0.0, SHIELD_ICON_HEIGHT, 0.0)
	add_child(_shield_icon)

	_shield_active = true
