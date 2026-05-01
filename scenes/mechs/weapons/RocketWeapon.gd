extends "res://scenes/mechs/weapons/BaseWeapon.gd"

const ROCKET_SCRIPT := preload("res://scenes/projectiles/Rocket.gd")
const BurstVFX      = preload("res://scenes/vfx/BurstVFX.gd")

const FIRE_RATE         := 1.6
const ULT_COOLDOWN      := 12.0
const BASE_DAMAGE       := 75.0    # high-impact slow rocket — splash catches the still ones
const INNATE_SPLASH     := 4.0     # passive rocket splash radius (also scaled by Bigger Boom upgrade)
const ULT_DAMAGE_MULT   := 7.0     # single big rocket — devastating hit
const ULT_SPLASH_RADIUS := 7.0     # matches the marker ring

var _marking:    bool   = false
var _ring_root:  Node3D = null
var _marker_mat:   StandardMaterial3D = null
var _marker_tween: Tween  = null

func _on_setup() -> void:
	weapon_name = "ROCKET"
	# Built-in splash so every rocket explodes — Bigger Boom upgrade scales this.
	splash_radius = INNATE_SPLASH

func is_aim_mode() -> bool:
	return _marking

func aim_action_text() -> String:
	return "STRIKE" if _marking else ""

func get_fire_rate() -> float:
	return FIRE_RATE

func get_ult_cooldown() -> float:
	return ULT_COOLDOWN

# ── Passive ───────────────────────────────────────────────────────────────────

func _passive_fire() -> void:
	var nearest := _nearest_enemy()
	if nearest == null:
		return
	var muzzle := _mech.global_position + Vector3(0.0, 1.6, 0.0)
	var target_pos := nearest.global_position + Vector3(0.0, 0.0, 0.0)
	_launch_rocket(muzzle, target_pos, BASE_DAMAGE, false, 0.0)
	_muzzle_flash(muzzle)
	_mech.trigger_flash()
	AudioManager.play("gun_fire", muzzle, -2.0, randf_range(0.65, 0.78))

# ── Ult: targeted strike on the drone ────────────────────────────────────────
# First press → enter marking mode (ring follows the drone). Left-click commits
# the strike at the drone's current position; right-click cancels with no
# cooldown spent. Pressing E again while marking also commits.

func activate_ult() -> bool:
	if _marking:
		_commit_strike()
		return true
	if not is_ready():
		return false
	_start_marking()
	return true

func _start_marking() -> void:
	if _marking:
		return
	var drone := _get_drone()
	if drone == null:
		# No drone in scene — fall back to firing at the mech's nearest enemy so
		# the press isn't silently consumed.
		_fire_strike(_mech.global_position + Vector3(0.0, 0.0, -6.0))
		_reset_cooldown()
		return
	_marking = true
	_hide_e_label()
	_build_ring(drone)

func _commit_strike() -> void:
	if not _marking:
		return
	var drone := _get_drone()
	var target := drone.global_position if drone != null else _mech.global_position
	target.y = 0.0
	_marking = false
	_destroy_ring()
	_reset_cooldown()
	_fire_strike(target)

func _cancel_marking() -> void:
	if not _marking:
		return
	_marking = false
	_destroy_ring()

func _fire_strike(target: Vector3) -> void:
	if _mech == null or not is_instance_valid(_mech) or not _mech.is_alive:
		return
	var muzzle := _mech.global_position + Vector3(0.0, 1.6, 0.0)
	# Orbital drop: the rocket appears in the sky above the marked spot and
	# falls nearly straight down — reads cleanly without an across-the-map arc.
	# Slight XZ offset gives the dive a tiny diagonal so it's not pure vertical.
	var sky_origin := target + Vector3(0.6, 25.0, 0.6)
	_launch_rocket(sky_origin, target, BASE_DAMAGE * ULT_DAMAGE_MULT, true, ULT_SPLASH_RADIUS)
	# Flash on the firing mech anyway — it's the "called in the strike" cue.
	_ult_muzzle_flash(muzzle, (target - muzzle).normalized())
	_mech.trigger_flash()
	AudioManager.play("gun_ult", muzzle, -1.0, 0.85)

# ── Input: commit / cancel while marking ─────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _marking:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_commit_strike()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_marking()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	super._process(delta)
	if _marking:
		# Ring is parented to the drone, so it follows automatically. If the
		# drone died mid-mark, bail out cleanly.
		if _get_drone() == null:
			_cancel_marking()

# ── Drone lookup ─────────────────────────────────────────────────────────────

func _get_drone() -> Node3D:
	var drones := get_tree().get_nodes_in_group("drones")
	for d in drones:
		if is_instance_valid(d):
			return d
	return null

# ── Marker ring ──────────────────────────────────────────────────────────────
# Thin saffron annulus on the ground at the drone's XZ. Pulses alpha so the
# player can read it through bloom and against bright floors.

func _build_ring(drone: Node3D) -> void:
	_ring_root = Node3D.new()
	drone.add_child(_ring_root)
	# Drone hovers — anchor to ground regardless of drone height.
	_ring_root.position = Vector3(0.0, -drone.global_position.y + 0.05, 0.0)

	var disc := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius  = ULT_SPLASH_RADIUS - 0.25
	torus.outer_radius  = ULT_SPLASH_RADIUS
	torus.rings         = 64
	torus.ring_segments = 8
	disc.mesh = torus
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.albedo_color               = Color(1.0, 0.66, 0.22, 0.85)
	_marker_mat.emission_enabled           = true
	_marker_mat.emission                   = Color(1.0, 0.55, 0.10)
	_marker_mat.emission_energy_multiplier = 5.5
	_marker_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.no_depth_test              = true
	_marker_mat.render_priority            = 6
	disc.material_override = _marker_mat
	_ring_root.add_child(disc)

	# Crosshair pip in the centre — thin cross of two flat capsules — so the
	# exact landing point reads even at a glance.
	for axis: Vector3 in [Vector3.RIGHT, Vector3.FORWARD]:
		var pip := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius          = 0.06
		cap.height          = ULT_SPLASH_RADIUS * 0.55
		cap.radial_segments = 6
		cap.rings           = 1
		pip.mesh = cap
		pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color               = Color(1.0, 0.70, 0.25, 0.95)
		pmat.emission_enabled           = true
		pmat.emission                   = Color(1.0, 0.55, 0.08)
		pmat.emission_energy_multiplier = 6.0
		pmat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
		pmat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.no_depth_test              = true
		pmat.render_priority            = 7
		pip.material_override = pmat
		var ref := Vector3.UP if abs(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		pip.transform.basis = Basis.looking_at(axis, ref)
		_ring_root.add_child(pip)

	_marker_tween = _ring_root.create_tween().set_loops()
	_marker_tween.tween_property(_marker_mat, "emission_energy_multiplier", 8.5, 0.35).set_ease(Tween.EASE_OUT)
	_marker_tween.tween_property(_marker_mat, "emission_energy_multiplier", 4.0, 0.35).set_ease(Tween.EASE_IN)

func _destroy_ring() -> void:
	if _marker_tween != null:
		_marker_tween.kill()
		_marker_tween = null
	if is_instance_valid(_ring_root):
		_ring_root.queue_free()
	_ring_root = null
	_marker_mat  = null

# ── Launch + flash helpers ───────────────────────────────────────────────────

func _launch_rocket(from: Vector3, to: Vector3, base_damage: float, is_ult: bool, ult_splash: float) -> void:
	var r := Node3D.new()
	r.set_script(ROCKET_SCRIPT)
	get_tree().current_scene.add_child(r)
	r.launch(from, to, self, base_damage, is_ult, ult_splash)

func _muzzle_flash(pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.55
	sph.height = 1.10
	flash.mesh = sph
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, 0.7, 0.25)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.45, 0.05)
	mat.emission_energy_multiplier = 8.0
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = mat
	get_tree().current_scene.add_child(flash)
	flash.global_position = pos
	var tw := flash.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tw.tween_callback(flash.queue_free)

func _ult_muzzle_flash(pos: Vector3, dir: Vector3) -> void:
	BurstVFX.spawn(pos + dir * 1.0, Color(1.0, 0.6, 0.15), 40, 9.5, 0.60, get_tree().current_scene)
