extends "res://scenes/mechs/weapons/BaseWeapon.gd"

const FIRE_RATE         := 1.3
const ULT_COOLDOWN      := 12.0
const DAMAGE_PER_BOUNCE := 18.0
const ULT_DAMAGE_MULT   := 2.2
const BOUNCES_PASSIVE   := 3
const BOUNCES_ULT       := 16
const BOUNCE_RANGE      := 8.0

func _on_setup() -> void:
	weapon_name = "BEAM"

func get_fire_rate() -> float:
	return FIRE_RATE

func get_ult_cooldown() -> float:
	return ULT_COOLDOWN

func _passive_fire() -> void:
	_fire_beam(BOUNCES_PASSIVE + projectile_count_bonus, 1.0)

func _fire_ult() -> void:
	_fire_beam(BOUNCES_ULT + projectile_count_bonus, ULT_DAMAGE_MULT)

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
	for e in get_tree().get_nodes_in_group("enemies"):
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
