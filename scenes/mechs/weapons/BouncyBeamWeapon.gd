extends "res://scenes/mechs/weapons/BaseWeapon.gd"

const _EnemyGrid = preload("res://scenes/enemies/EnemyGrid.gd")

const FIRE_RATE         := 1.3
const ULT_COOLDOWN      := 12.0
const DAMAGE_PER_BOUNCE := 18.0
const BOUNCES_PASSIVE   := 3
const BOUNCE_RANGE      := 8.0

# FTL-style beam ult: player picks a start point anywhere on the ground, then
# aims a fixed-length line. Beam traces between the two points, damaging
# anything the head passes.
const ULT_BEAM_LENGTH      := 12.0   # fixed beam length — second click sets direction only
const ULT_TRACE_SPEED      := 22.0   # world units per second along the line — faster sweep, more decisive
const ULT_HIT_RADIUS       := 1.3    # hitbox slightly outside the halo (1.0) so edge clips still register
const ULT_DAMAGE_PER_HIT   := 60.0

# Aim state — two-click pick: first click sets start, second click fires.
var _aiming:        bool   = false
var _aim_has_start: bool   = false
var _aim_start:     Vector3 = Vector3.ZERO
var _ground_cursor: Vector3 = Vector3.ZERO
var _mouse_moved_in_aim: bool = false   # cleared on _start_aiming, set on first mouse motion during aim — drives drone-fallback aim for keyboard-only players
var _aim_root:      Node3D = null
var _aim_start_marker:  MeshInstance3D = null
var _aim_cursor_marker: MeshInstance3D = null
var _aim_line:          MeshInstance3D = null  # core
var _aim_line_halo:     MeshInstance3D = null  # halo

func _on_setup() -> void:
	weapon_name = "BEAM"
	uses_aim_mode_ult = true

func get_fire_rate() -> float:
	return FIRE_RATE

func get_ult_cooldown() -> float:
	return ULT_COOLDOWN

func is_aim_mode() -> bool:
	return _aiming

func aim_action_text() -> String:
	if not _aiming:
		return ""
	return "FIRE LASER" if _aim_has_start else "PLACE START"

func _passive_fire() -> void:
	if tutorial_muted:
		return
	_fire_beam(BOUNCES_PASSIVE + projectile_count_bonus, 1.0)

# Override base activate_ult: enter aim mode instead of firing immediately.
# The aiming + click commit IS the windup, mirroring GunWeapon's pattern.
# Re-pressing the ult key while aiming advances through the same flow as a
# left-click — first re-press locks the start point at the cursor, second
# fires the beam — so the ult can be played from the keyboard alone.
func activate_ult() -> bool:
	if _aiming:
		if not _aim_has_start:
			_aim_start = _ground_cursor
			_aim_has_start = true
		else:
			var endpt := _fixed_endpoint(_aim_start, _ground_cursor)
			_aiming = false
			_aim_has_start = false
			_reset_cooldown()
			_destroy_preview()
			_spawn_trace(_aim_start, endpt)
		return true
	if not is_ready():
		return false
	_start_aiming()
	return true

func cancel_ult_aim() -> void:
	if _aiming:
		_cancel_aiming()

func _start_aiming() -> void:
	_aiming = true
	_aim_has_start = false
	_mouse_moved_in_aim = false
	_build_preview()

func _cancel_aiming() -> void:
	_aiming = false
	_aim_has_start = false
	_destroy_preview()

func _input(event: InputEvent) -> void:
	if not _aiming:
		return
	if event is InputEventMouseMotion:
		_mouse_moved_in_aim = true
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventKey and event.pressed and not event.echo \
				and (event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)):
		if not _aim_has_start:
			_aim_start = _ground_cursor
			_aim_has_start = true
		else:
			var endpt := _fixed_endpoint(_aim_start, _ground_cursor)
			_aiming = false
			_aim_has_start = false
			_reset_cooldown()
			_destroy_preview()
			_spawn_trace(_aim_start, endpt)
		get_viewport().set_input_as_handled()
	elif (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) \
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q):
		_cancel_aiming()
		get_viewport().set_input_as_handled()

# Compute the second-click endpoint at fixed beam length from the start point,
# in the cursor direction. Length is constant; cursor only chooses direction.
func _fixed_endpoint(start: Vector3, cursor: Vector3) -> Vector3:
	var diff: Vector3 = cursor - start
	diff.y = 0.0
	var dist := diff.length()
	if dist < 0.01:
		return start + Vector3(ULT_BEAM_LENGTH, 0.0, 0.0)
	return start + diff.normalized() * ULT_BEAM_LENGTH

# `mode_scale` is the ult-vs-passive firepower factor (1.0 passive, ULT_DAMAGE_MULT
# for the ult). The global upgrade multiplier is applied separately by _apply_hit.
# Damage is *deferred* into the per-segment tween callbacks so each enemy takes
# the hit when the beam visually reaches it — without that, fast enemies died
# before the bounce visual landed.
func _fire_beam(max_bounces: int, mode_scale: float) -> void:
	var first := _nearest_enemy()
	if first == null:
		return
	var origin := _mech.global_position + Vector3(0.0, 2.0, 0.0)
	AudioManager.play("beam_fire", origin, -6.0, randf_range(0.95, 1.05))
	var points: Array[Vector3] = [origin]
	var targets: Array[Node3D] = []      # parallel to segments — targets[i] is the enemy hit on segment i
	var hit: Array[Node3D] = []
	var current: Node3D = first
	for _i in max_bounces:
		if not is_instance_valid(current):
			break
		var hit_pos := current.global_position + Vector3(0.0, 0.8, 0.0)
		points.append(hit_pos)
		targets.append(current)
		hit.append(current)
		current = _find_bounce_target(current.global_position, hit)
	_draw_beam(points, targets, mode_scale)
	_mech.trigger_flash()

func _find_bounce_target(from_pos: Vector3, exclude: Array[Node3D]) -> Node3D:
	var best: Node3D = null
	var best_dist := BOUNCE_RANGE * range_mult
	_EnemyGrid.ensure_fresh(get_tree())
	for e in _EnemyGrid.query(from_pos, best_dist):
		if not is_instance_valid(e):
			continue
		if e in exclude:
			continue
		var d := from_pos.distance_to(e.global_position)
		if d < best_dist:
			best_dist = d
			best = e
	return best

func _draw_beam(points: Array[Vector3], targets: Array[Node3D] = [], mode_scale: float = 1.0) -> void:
	if points.size() < 2:
		return

	const BEAM_SPEED := 20.0   # world units / second — slow enough that each bounce reads

	# ── Traveling head sphere ──────────────────────────────
	var head := MeshInstance3D.new()
	var sph  := SphereMesh.new()
	sph.radius = 0.20
	sph.height = 0.40
	head.mesh = sph
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color              = Color(1.0, 1.0, 1.0, 1.0)
	hmat.emission_enabled          = true
	hmat.emission                  = Color(0.4, 0.82, 1.0)
	hmat.emission_energy_multiplier = 20.0
	hmat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.no_depth_test             = true
	hmat.render_priority           = 10
	head.material_override = hmat
	get_tree().current_scene.add_child(head)
	head.global_position = points[0]

	# Chain one tween step per segment:
	# head moves to next point → segment + impact + damage applied on arrival
	var tw := head.create_tween()
	for i in points.size() - 1:
		var seg_a: Vector3 = points[i]
		var seg_b: Vector3 = points[i + 1]
		var seg_idx := i
		var dur := seg_a.distance_to(seg_b) / BEAM_SPEED
		tw.tween_property(head, "global_position", seg_b, dur).set_trans(Tween.TRANS_LINEAR)
		tw.tween_callback(func() -> void:
			_spawn_segment(seg_a, seg_b)
			_spawn_impact(seg_b)
			# Damage lands *now*, when the beam visibly arrives at this enemy.
			if seg_idx < targets.size():
				var target: Node3D = targets[seg_idx]
				if is_instance_valid(target):
					var dir := seg_b - seg_a
					_apply_hit(target, DAMAGE_PER_BOUNCE * mode_scale, target.global_position, dir)
			AudioManager.play("beam_bounce", seg_b, -10.0, randf_range(0.9, 1.15))
		)

	# Flash head out when done
	tw.tween_property(hmat, "albedo_color:a", 0.0, 0.07)
	tw.tween_callback(head.queue_free)

func _spawn_segment(a: Vector3, b: Vector3) -> void:
	var dist := a.distance_to(b)
	if dist < 0.01:
		return
	var mid := (a + b) * 0.5
	var up  := (b - a) / dist
	# Build basis so capsule Y-axis points along the beam direction
	var ref      := Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var right    := up.cross(ref).normalized()
	var fwd      := right.cross(up).normalized()
	var seg_basis := Basis(right, up, -fwd)

	# ── Bright core ────────────────────────────────────────
	var core := MeshInstance3D.new()
	var cc   := CapsuleMesh.new()
	cc.radius          = 0.07
	cc.height          = dist
	cc.radial_segments = 6
	cc.rings           = 1
	core.mesh = cc
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color              = Color(0.85, 0.97, 1.0, 1.0)
	cmat.emission_enabled          = true
	cmat.emission                  = Color(0.25, 0.70, 1.0)
	cmat.emission_energy_multiplier = 12.0
	cmat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.no_depth_test             = true
	cmat.render_priority           = 9
	core.material_override = cmat
	get_tree().current_scene.add_child(core)
	core.global_position          = mid
	core.global_transform.basis   = seg_basis

	# ── Soft glow halo ──────────────────────────────────────
	var halo := MeshInstance3D.new()
	var hc   := CapsuleMesh.new()
	hc.radius          = 0.22
	hc.height          = dist
	hc.radial_segments = 6
	hc.rings           = 1
	halo.mesh = hc
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color              = Color(0.15, 0.55, 1.0, 0.30)
	hmat.emission_enabled          = true
	hmat.emission                  = Color(0.1, 0.40, 1.0)
	hmat.emission_energy_multiplier = 3.0
	hmat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.no_depth_test             = true
	hmat.render_priority           = 8
	halo.material_override = hmat
	get_tree().current_scene.add_child(halo)
	halo.global_position        = mid
	halo.global_transform.basis = seg_basis

	# Fade both out together
	var tw := core.create_tween()
	tw.tween_property(cmat, "albedo_color:a", 0.0, 0.38)
	tw.tween_callback(core.queue_free)
	var htw := halo.create_tween()
	htw.tween_property(hmat, "albedo_color:a", 0.0, 0.38)
	htw.tween_callback(halo.queue_free)

func _spawn_impact(pos: Vector3) -> void:
	var sphere := MeshInstance3D.new()
	var sph    := SphereMesh.new()
	sph.radius = 0.25
	sph.height = 0.50
	sphere.mesh = sph
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var smat := StandardMaterial3D.new()
	smat.albedo_color              = Color(0.6, 0.92, 1.0, 1.0)
	smat.emission_enabled          = true
	smat.emission                  = Color(0.2, 0.60, 1.0)
	smat.emission_energy_multiplier = 8.0
	smat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material_override = smat
	get_tree().current_scene.add_child(sphere)
	sphere.global_position = pos
	var tw := sphere.create_tween()
	tw.tween_property(sphere, "scale", Vector3(2.2, 2.2, 2.2), 0.08).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(smat, "albedo_color:a", 0.0, 0.28)
	tw.tween_callback(sphere.queue_free)

# ── FTL beam ult: two-click line trace ───────────────────────────────────────

func _process(delta: float) -> void:
	super._process(delta)
	if not _aiming or _mech == null or not is_instance_valid(_mech):
		return
	_ground_cursor = _aim_cursor_pos()
	_update_preview()

# Mouse projection while the player has been moving the mouse in this aim
# session; drone-tracked otherwise so keyboard-only / gamepad players still
# get a usable aim direction by steering the drone over the target.
func _aim_cursor_pos() -> Vector3:
	var plane_y := _mech.global_position.y
	var camera := get_viewport().get_camera_3d()
	if camera != null and _mouse_moved_in_aim:
		var mouse  := get_viewport().get_mouse_position()
		var ray_o  := camera.project_ray_origin(mouse)
		var ray_d  := camera.project_ray_normal(mouse)
		if abs(ray_d.y) > 0.001:
			var t := (plane_y - ray_o.y) / ray_d.y
			var p := ray_o + ray_d * t
			p.y = plane_y
			return p
	var drone := get_tree().get_first_node_in_group("drones") as Node3D
	if drone != null and is_instance_valid(drone):
		return Vector3(drone.global_position.x, plane_y, drone.global_position.z)
	return _mech.global_position

func _build_preview() -> void:
	_aim_root = Node3D.new()
	get_tree().current_scene.add_child(_aim_root)

	_aim_cursor_marker = _build_marker(Color(1.00, 0.25, 0.18, 0.85), 0.45)
	_aim_root.add_child(_aim_cursor_marker)

	_aim_start_marker = _build_marker(Color(1.00, 0.45, 0.35, 0.9), 0.40)
	_aim_start_marker.visible = false
	_aim_root.add_child(_aim_start_marker)

	# Layered preview matching the fired laser visual: soft halo + bright core.
	# Halo radius == ULT_HIT_RADIUS so the player aims at the actual hitbox.
	_aim_line_halo = MeshInstance3D.new()
	var halo_cap := CapsuleMesh.new()
	halo_cap.radius = 1.0
	halo_cap.height = 1.0
	halo_cap.radial_segments = 10
	halo_cap.rings = 1
	_aim_line_halo.mesh = halo_cap
	_aim_line_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo_mat := StandardMaterial3D.new()
	halo_mat.albedo_color              = Color(0.80, 0.05, 0.02, 0.35)
	halo_mat.emission_enabled          = true
	halo_mat.emission                  = Color(1.00, 0.05, 0.02)
	halo_mat.emission_energy_multiplier = 2.5
	halo_mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.no_depth_test             = true
	halo_mat.render_priority           = 8
	_aim_line_halo.material_override = halo_mat
	_aim_line_halo.visible = false
	_aim_root.add_child(_aim_line_halo)

	_aim_line = MeshInstance3D.new()
	var core_cap := CapsuleMesh.new()
	core_cap.radius = 0.30
	core_cap.height = 1.0
	core_cap.radial_segments = 10
	core_cap.rings = 1
	_aim_line.mesh = core_cap
	_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color              = Color(0.90, 0.10, 0.05, 1.0)
	core_mat.emission_enabled          = true
	core_mat.emission                  = Color(1.00, 0.05, 0.02)
	core_mat.emission_energy_multiplier = 4.0
	core_mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.no_depth_test             = true
	core_mat.render_priority           = 9
	_aim_line.material_override = core_mat
	_aim_line.visible = false
	_aim_root.add_child(_aim_line)

	_update_preview()

func _build_marker(color: Color, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius  = radius - 0.07
	torus.outer_radius  = radius
	torus.rings         = 32
	torus.ring_segments = 6
	mi.mesh = torus
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color              = color
	mat.emission_enabled          = true
	mat.emission                  = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = 5.0
	mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test             = true
	mat.render_priority           = 9
	mi.material_override = mat
	return mi

func _update_preview() -> void:
	if _aim_root == null or not is_instance_valid(_aim_root):
		return
	if not _aim_has_start:
		# State 1: pick start anywhere on the ground.
		if _aim_cursor_marker != null:
			_aim_cursor_marker.visible = true
			_aim_cursor_marker.global_position = _ground_cursor + Vector3(0.0, 0.05, 0.0)
		if _aim_start_marker != null:
			_aim_start_marker.visible = false
		if _aim_line != null:
			_aim_line.visible = false
		if _aim_line_halo != null:
			_aim_line_halo.visible = false
		return
	# State 2: start fixed; cursor only chooses direction at fixed length.
	var endpt := _fixed_endpoint(_aim_start, _ground_cursor)
	if _aim_start_marker != null:
		_aim_start_marker.visible = true
		_aim_start_marker.global_position = _aim_start + Vector3(0.0, 0.05, 0.0)
	if _aim_cursor_marker != null:
		_aim_cursor_marker.visible = true
		_aim_cursor_marker.global_position = endpt + Vector3(0.0, 0.05, 0.0)
	var line_a := _aim_start + Vector3(0.0, 0.4, 0.0)
	var line_b := endpt + Vector3(0.0, 0.4, 0.0)
	if _aim_line != null:
		_orient_capsule_between(_aim_line, line_a, line_b)
		_aim_line.visible = true
	if _aim_line_halo != null:
		_orient_capsule_between(_aim_line_halo, line_a, line_b)
		_aim_line_halo.visible = true

func _destroy_preview() -> void:
	if is_instance_valid(_aim_root):
		_aim_root.queue_free()
	_aim_root = null
	_aim_start_marker = null
	_aim_cursor_marker = null
	_aim_line = null
	_aim_line_halo = null

# Position + scale a capsule mesh so its endpoints are at `a` and `b`.
# Uses a fresh CapsuleMesh sized to the segment (height = distance) and a basis
# rotating local Y onto the segment direction.
func _orient_capsule_between(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dist: float = a.distance_to(b)
	if dist < 0.01:
		mi.visible = false
		return
	var cap := mi.mesh as CapsuleMesh
	if cap != null:
		cap.height = dist
	var mid := (a + b) * 0.5
	var up: Vector3 = (b - a) / dist
	var ref: Vector3 = Vector3.FORWARD if abs(up.dot(Vector3.FORWARD)) < 0.95 else Vector3.RIGHT
	var right: Vector3 = up.cross(ref).normalized()
	var fwd: Vector3 = right.cross(up).normalized()
	mi.global_position = mid
	mi.global_transform.basis = Basis(right, up, -fwd)

# Beam fires: layered laser look — wide soft halo + thin white-hot core grow
# from start to end as a hot head sphere races along. After the head arrives
# the full beam holds briefly then fades. Each enemy hit at most once when the
# head sweeps past them.
func _spawn_trace(start_pos: Vector3, end_pos: Vector3) -> void:
	var diff: Vector3 = end_pos - start_pos
	diff.y = 0.0
	var dist := diff.length()
	if dist < 0.01:
		return
	var dir := diff.normalized()
	var duration := dist / ULT_TRACE_SPEED

	var beam_y: float = _mech.global_position.y + 0.5
	var a := Vector3(start_pos.x, beam_y, start_pos.z)
	var b := Vector3(end_pos.x,   beam_y, end_pos.z)

	# Match aim-line dimensions; bump emission energy so the fired beam reads
	# as the aim line "lit up" — punchier glow during its short visible window.
	var halo := MeshInstance3D.new()
	var halo_cap := CapsuleMesh.new()
	halo_cap.radius = 1.0
	halo_cap.height = 1.0
	halo_cap.radial_segments = 10
	halo_cap.rings = 1
	halo.mesh = halo_cap
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo_mat := StandardMaterial3D.new()
	halo_mat.albedo_color              = Color(0.80, 0.05, 0.02, 0.45)
	halo_mat.emission_enabled          = true
	halo_mat.emission                  = Color(1.00, 0.05, 0.02)
	halo_mat.emission_energy_multiplier = 5.0
	halo_mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.no_depth_test             = true
	halo_mat.render_priority           = 8
	halo.material_override = halo_mat
	get_tree().current_scene.add_child(halo)

	var core := MeshInstance3D.new()
	var core_cap := CapsuleMesh.new()
	core_cap.radius = 0.30
	core_cap.height = 1.0
	core_cap.radial_segments = 10
	core_cap.rings = 1
	core.mesh = core_cap
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color              = Color(0.90, 0.10, 0.05, 1.0)
	core_mat.emission_enabled          = true
	core_mat.emission                  = Color(1.00, 0.05, 0.02)
	core_mat.emission_energy_multiplier = 8.0
	core_mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.no_depth_test             = true
	core_mat.render_priority           = 9
	core.material_override = core_mat
	get_tree().current_scene.add_child(core)

	# Head sphere — bigger than the passive head so the leading edge reads
	# against the wider beam without getting visually swallowed by the halo.
	var head := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.42
	sph.height = 0.84
	head.mesh = sph
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color              = Color(1.00, 0.20, 0.10, 1.0)
	hmat.emission_enabled          = true
	hmat.emission                  = Color(1.00, 0.10, 0.05)
	hmat.emission_energy_multiplier = 6.0
	hmat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.no_depth_test             = true
	hmat.render_priority           = 10
	head.material_override = hmat
	get_tree().current_scene.add_child(head)
	head.global_position = a

	if _mech.has_method("trigger_flash"):
		_mech.trigger_flash()
	AudioManager.play("beam_fire", _mech.global_position, -1.0, 0.65)

	var hit_set: Dictionary = {}

	# FTL-style draw: beam grows from start point along to head as it sweeps.
	var on_advance := func(u: float) -> void:
		var head_pos := a.lerp(b, u)
		head.global_position = head_pos
		_orient_capsule_between(core, a, head_pos)
		_orient_capsule_between(halo, a, head_pos)
		_check_trace_hits(head_pos, dir, hit_set)

	var tw := head.create_tween()
	tw.tween_method(on_advance, 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR)
	# Hold the fully-drawn laser briefly so the player can read it.
	tw.tween_interval(0.70)
	tw.tween_property(core_mat, "albedo_color:a", 0.0, 0.55)
	tw.parallel().tween_property(core_mat, "emission_energy_multiplier", 0.0, 0.55)
	tw.parallel().tween_property(halo_mat, "albedo_color:a", 0.0, 0.55)
	tw.parallel().tween_property(halo_mat, "emission_energy_multiplier", 0.0, 0.55)
	tw.parallel().tween_property(hmat, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(core.queue_free)
	tw.tween_callback(halo.queue_free)
	tw.tween_callback(head.queue_free)

func _check_trace_hits(head_pos: Vector3, _dir: Vector3, hit_set: Dictionary) -> void:
	_EnemyGrid.ensure_fresh(get_tree())
	for e in _EnemyGrid.query(head_pos, ULT_HIT_RADIUS):
		if not is_instance_valid(e):
			continue
		var id: int = e.get_instance_id()
		if hit_set.has(id):
			continue
		var diff: Vector3 = e.global_position - head_pos
		diff.y = 0.0
		if diff.length() > ULT_HIT_RADIUS:
			continue
		hit_set[id] = true
		_apply_hit(e, ULT_DAMAGE_PER_HIT, e.global_position, diff)
