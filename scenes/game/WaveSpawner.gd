extends Node

const ENEMY_SCENE    := preload("res://scenes/enemies/Enemy.tscn")
const SPAWN_RADIUS_MIN := 22.0  # floor for the dynamic radius — at min zoom we still want a reasonable approach distance
const SPAWN_MARGIN     := 6.0   # extra padding past the visible edge so spawns never pop in on-screen
const BASE_ENEMIES   := 5
const WAVE_INTERVAL  := 12.0
const SPAWN_SPREAD   := 4.0    # seconds over which a wave staggers its spawns

const FINAL_CHECK_INTERVAL := 0.5

# Elite spawn ramp. 0% chance below ELITE_START_WAVE, scaling linearly to
# ELITE_MAX_CHANCE by ELITE_RAMP_END so late-run waves contain a sprinkle of
# gold/magenta priority targets without ever feeling like an elite swarm.
const ELITE_START_WAVE := 5
const ELITE_RAMP_END   := 30
const ELITE_MAX_CHANCE := 0.15

# Shielded variant — drone has to dash through to break the bubble before any
# damage lands. Spawns in groups of 2-4 every 2-3 waves once the player has
# their bearings (wave >= 5).
const SHIELD_START_WAVE     := 5
const SHIELD_INTERVAL_MIN   := 2
const SHIELD_INTERVAL_MAX   := 3
const SHIELD_GROUP_MIN      := 2
const SHIELD_GROUP_MAX      := 3
var _waves_since_shielded:  int = 0
var _next_shielded_interval: int = 2

# ── Spawn patterns ────────────────────────────────────────────────────────────
# Each wave picks a pattern that decides where its enemies appear. Solves two
# things at once: damage no longer funnels onto the lead mech (different
# patterns shift the "nearest" target across the line), and the run feels
# varied wave-to-wave instead of always-encircle.
#
# Tier B unlock — patterns enter the pool as the run progresses, so wave 1 can
# never roll a rear/pincer the player isn't yet equipped to read.
enum Pattern { ENCIRCLE, FRONT_WEDGE, LEFT_FLANK, RIGHT_FLANK, REAR_ASSAULT, PINCER }

const ENCIRCLE_ARC      := 2.0 * PI        # full 360° — symmetric around the line midpoint so every mech catches the same share. The 240° fan we used before was forward-biased and quietly recreated the lead-mech damage tilt.
const FRONT_WEDGE_ARC   := PI / 3.0        # 60° narrow cone ahead of lead
const REAR_ASSAULT_ARC  := PI / 3.0        # 60° narrow cone behind rear mech
# Flanks don't use an arc — they string spawns along the whole line length so
# a flank wave reads as a wall sweeping past the column. Each enemy still picks
# its own nearest mech, so damage distributes by spawn-Z geometry alone.
const FLANK_Z_PADDING   := 2.0             # meters past lead/rear so the wall doesn't clamp at the ends

# Named waves — fixed pattern + count multiplier + banner subtitle. Override
# the tier roll so the milestone reads as a designed moment rather than a roll.
const NAMED_WAVES := {
	10: {pattern = Pattern.LEFT_FLANK, subtitle = "FLANK ASSAULT", count_mult = 1.5},
	20: {pattern = Pattern.PINCER,     subtitle = "PINCER",        count_mult = 1.5},
	30: {pattern = Pattern.ENCIRCLE,   subtitle = "LAST STAND",    count_mult = 1.5},
}

# Banner is the only "telegraph" we ship — names the wave so the player knows
# what's coming before the spawns appear. Subtitle is empty on regular waves.
signal wave_announced(number: int, title: String, subtitle: String)

var _current_pattern: int = Pattern.ENCIRCLE

# Debug override — set via PauseMenu's pattern buttons. Beats both named-wave
# assignments and the tier roller so a tester can sample any pattern on any
# wave. One-shot: clears as soon as the wave it targets fires.
var _forced_pattern: int = -1

var enemies_container: Node3D
var wave_number: int = 0
var timer: float = 3.0

# Set true once the final (WIN_WAVE) wave has spawned. Spawning halts; the
# spawner polls the enemies group on FINAL_CHECK_INTERVAL until empty, then
# emits RunManager.run_won and stops checking.
var _final_wave_spawned: bool = false
var _final_check_timer:  float = 0.0
var _win_emitted:        bool = false

func setup(p_enemies_container: Node3D) -> void:
	enemies_container = p_enemies_container

# Debug: force the next wave to use a specific pattern, and fire it now so the
# tester doesn't have to wait out WAVE_INTERVAL. Pass any Pattern enum value.
func force_next_pattern(p: int) -> void:
	_forced_pattern = p
	timer = 0.0

# Debug: jump the wave counter so the next spawn lands on `target`. Existing
# enemies are not removed (use the KILL ALL ENEMIES debug for that). Resets the
# end-of-run flags so jumping backwards from WIN_WAVE re-arms spawning.
func set_wave(target: int) -> void:
	if target < 1:
		return
	wave_number = target - 1
	RunManager.wave = wave_number
	_final_wave_spawned = false
	_final_check_timer  = 0.0
	_win_emitted        = false
	timer = 0.0

func _process(delta: float) -> void:
	if _final_wave_spawned:
		_final_check_timer -= delta
		if _final_check_timer <= 0.0:
			_final_check_timer = FINAL_CHECK_INTERVAL
			if not _win_emitted and get_tree().get_nodes_in_group("enemies").is_empty():
				_win_emitted = true
				RunManager.emit_run_won()
		return
	timer -= delta
	if timer <= 0.0:
		timer = WAVE_INTERVAL
		_spawn_wave()

func _spawn_wave() -> void:
	wave_number += 1
	RunManager.start_wave(wave_number)
	AudioManager.play("wave_start")

	var named: Dictionary = NAMED_WAVES.get(wave_number, {})
	var count_mult: float = float(named.get("count_mult", 1.0))
	var subtitle: String  = String(named.get("subtitle", ""))
	if _forced_pattern >= 0:
		# Debug override: skip named-wave bonuses so the tester sees the pattern in
		# isolation rather than on top of the milestone +50% count.
		_current_pattern = _forced_pattern
		_forced_pattern  = -1
		subtitle   = ""
		count_mult = 1.0
	elif named.has("pattern"):
		_current_pattern = int(named.pattern)
	else:
		_current_pattern = _roll_pattern(wave_number)
	wave_announced.emit(wave_number, "WAVE %d" % wave_number, subtitle)

	var count := int(round(float(BASE_ENEMIES + (wave_number - 1) * 2) * count_mult))
	var interval := SPAWN_SPREAD / float(count)

	for i in count:
		get_tree().create_timer(i * interval).timeout.connect(_spawn_one)

	# Shielded group: piggybacks on the wave's pattern. Counter rolls a fresh
	# 2..3 interval after each group fires, so the cadence varies wave-to-wave.
	if wave_number >= SHIELD_START_WAVE:
		_waves_since_shielded += 1
		if _waves_since_shielded >= _next_shielded_interval:
			_waves_since_shielded = 0
			_next_shielded_interval = randi_range(SHIELD_INTERVAL_MIN, SHIELD_INTERVAL_MAX)
			var group_size := randi_range(SHIELD_GROUP_MIN, SHIELD_GROUP_MAX)
			# Stagger inside the same SPAWN_SPREAD window so shielded enemies
			# arrive interleaved with the regular wave instead of in a bolus.
			for i in group_size:
				get_tree().create_timer(float(i) * (SPAWN_SPREAD / float(group_size))).timeout.connect(_spawn_shielded_one)

	if wave_number >= RunManager.WIN_WAVE:
		# Final wave: stop spawning. Wait until after the staggered spawns finish
		# (+1s grace) before we start polling for an empty field, so we don't
		# trigger the win mid-spawn.
		_final_wave_spawned = true
		_final_check_timer  = SPAWN_SPREAD + 1.0

func _roll_pattern(wave: int) -> int:
	var pool: Array[int] = [Pattern.ENCIRCLE, Pattern.FRONT_WEDGE]
	if wave >= 5:
		pool.append(Pattern.LEFT_FLANK)
		pool.append(Pattern.RIGHT_FLANK)
	if wave >= 15:
		pool.append(Pattern.REAR_ASSAULT)
		pool.append(Pattern.PINCER)
	return pool[randi() % pool.size()]

func _spawn_one() -> void:
	var pos := _spawn_position_for_pattern(_current_pattern)
	var enemy: Node3D = ENEMY_SCENE.instantiate()
	# Stamp wave + elite flag before add_child so Enemy._ready can apply scaling
	# in one place rather than restamping after the fact.
	enemy.wave_number = wave_number
	enemy.is_elite    = _roll_elite()
	enemies_container.add_child(enemy)
	enemy.global_position = pos

# Same shape as _spawn_one but stamps is_shielded instead. Mutually exclusive
# with elite — both flags drive priority-target visuals and we don't want them
# stacking on the same enemy.
func _spawn_shielded_one() -> void:
	var pos := _spawn_position_for_pattern(_current_pattern)
	var enemy: Node3D = ENEMY_SCENE.instantiate()
	enemy.wave_number = wave_number
	enemy.is_shielded = true
	enemies_container.add_child(enemy)
	enemy.global_position = pos

# Mechs march in -Z. In angle space (cos→X, sin→Z) "forward" is -PI/2 and
# "behind" is +PI/2. Each pattern picks its own reference point on the line so
# the spawn geometry naturally redistributes which mech is nearest.
func _spawn_position_for_pattern(pattern: int) -> Vector3:
	var radius := _spawn_radius()
	match pattern:
		Pattern.FRONT_WEDGE:
			var ref := _lead_position()
			var angle := -PI / 2.0 + randf_range(-FRONT_WEDGE_ARC * 0.5, FRONT_WEDGE_ARC * 0.5)
			return ref + Vector3(cos(angle), 0.0, sin(angle)) * radius
		Pattern.REAR_ASSAULT:
			var ref := _rear_position()
			var angle := PI / 2.0 + randf_range(-REAR_ASSAULT_ARC * 0.5, REAR_ASSAULT_ARC * 0.5)
			return ref + Vector3(cos(angle), 0.0, sin(angle)) * radius
		Pattern.LEFT_FLANK:
			return _flank_position(-1.0, radius)
		Pattern.RIGHT_FLANK:
			return _flank_position(1.0, radius)
		Pattern.PINCER:
			var side: float = -1.0 if randf() < 0.5 else 1.0
			return _flank_position(side, radius)
		_:  # ENCIRCLE — original 240° fan, but centred on the line midpoint so
			# rear mechs catch their share of front/side spawns.
			var ref := _line_midpoint()
			var angle := -PI / 2.0 + randf_range(-ENCIRCLE_ARC * 0.5, ENCIRCLE_ARC * 0.5)
			return ref + Vector3(cos(angle), 0.0, sin(angle)) * radius

# Flank: each enemy gets its own Z spread along the line, so the wave reaches
# every mech instead of clustering on whichever one we anchored to.
func _flank_position(side: float, radius: float) -> Vector3:
	var lead_z := _lead_position().z
	var rear_z := _rear_position().z
	var z := randf_range(lead_z - FLANK_Z_PADDING, rear_z + FLANK_Z_PADDING)
	var mid := _line_midpoint()
	return Vector3(mid.x + side * radius, 0.0, z)

func _roll_elite() -> bool:
	if wave_number < ELITE_START_WAVE:
		return false
	var t := clampf(
		float(wave_number - ELITE_START_WAVE) / float(ELITE_RAMP_END - ELITE_START_WAVE),
		0.0, 1.0
	)
	return randf() < t * ELITE_MAX_CHANCE

# Spawn distance scales with the orthographic camera size + viewport aspect so
# enemies always pop in just past the visible edge — regardless of zoom level
# or monitor (ultrawide sees ~50% more world horizontally than the design
# machine, and the radius needs to follow).
func _spawn_radius() -> float:
	var cam := get_viewport().get_camera_3d()
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	if cam == null or cam.projection != Camera3D.PROJECTION_ORTHOGONAL or vp_size.y <= 0.0:
		return SPAWN_RADIUS_MIN
	var aspect: float = vp_size.x / vp_size.y
	var visible_half: float = cam.size * maxf(1.0, aspect) * 0.5
	return maxf(SPAWN_RADIUS_MIN, visible_half + SPAWN_MARGIN)

# Lead = smallest Z (front of march). Rear = largest Z. Midpoint = average.
# Spawn patterns pick whichever reference makes their geometry read correctly.
func _lead_position() -> Vector3:
	var mechs := get_tree().get_nodes_in_group("mechs")
	var lead: Node3D = null
	var min_z := INF
	for m in mechs:
		var mn := m as Node3D
		if mn == null:
			continue
		if mn.global_position.z < min_z:
			min_z = mn.global_position.z
			lead = mn
	return lead.global_position if lead else Vector3.ZERO

func _rear_position() -> Vector3:
	var mechs := get_tree().get_nodes_in_group("mechs")
	var rear: Node3D = null
	var max_z := -INF
	for m in mechs:
		var mn := m as Node3D
		if mn == null:
			continue
		if mn.global_position.z > max_z:
			max_z = mn.global_position.z
			rear = mn
	return rear.global_position if rear else Vector3.ZERO

func _line_midpoint() -> Vector3:
	var mechs := get_tree().get_nodes_in_group("mechs")
	if mechs.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var n := 0
	for m in mechs:
		var mn := m as Node3D
		if mn == null:
			continue
		sum += mn.global_position
		n += 1
	return sum / float(maxi(1, n))
