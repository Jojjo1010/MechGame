extends CanvasLayer

signal repair_completed(mech: Node3D)

const SEQ_LEN    := 4
const KEY_LABELS := ["W", "A", "S", "D"]
const KEY_DIRS   := ["UP", "LEFT", "DOWN", "RIGHT"]
const ARROW_CHARS := ["↑", "←", "↓", "→"]   # W A S D
const KEY_CODES  := [KEY_W, KEY_A, KEY_S, KEY_D]

const BOX_W := 90.0
const BOX_H := 90.0
const BOX_GAP := 14.0

var _mech:     Node3D = null
var _drone:    Node3D = null
var _sequence: Array[int] = []
var _step:     int = 0
var _boxes:    Array[PanelContainer] = []
var _box_labels: Array[Label] = []
var _shake_tween: Tween = null
var _root: Control = null

# Drone work animation
var _work_timer:  float = 0.0
var _spark_timer: float = 0.0
var _work_light:  OmniLight3D = null

# Repair arm
var _repair_arm:     Node3D = null
var _welder_mat:     StandardMaterial3D = null   # tip glow, flickered each frame
var _scanner_node:   Node3D = null               # second arm tip (GLB or procedural disc), spun each frame
var _arm_spin:       float = 0.0

func start(mech: Node3D, drone: Node3D) -> void:
	_mech  = mech
	_drone = drone
	_drone.repair_locked = true
	_generate_sequence()
	_build_ui()
	layer = 20

	# Snap drone to a working position just beside the mech
	var work_pos := mech.global_position + Vector3(1.6, 2.2, 0.3)
	var tw := drone.create_tween()
	tw.tween_property(drone, "global_position", work_pos, 0.28).set_ease(Tween.EASE_OUT)

	# Blue-white work light mounted on the drone
	_work_light = OmniLight3D.new()
	_work_light.light_color    = Color(0.55, 0.85, 1.0)
	_work_light.light_energy   = 5.0
	_work_light.omni_range     = 4.0
	_work_light.shadow_enabled = false
	drone.add_child(_work_light)
	_create_repair_arm()

func _create_repair_arm() -> void:
	_repair_arm = Node3D.new()
	_drone.add_child(_repair_arm)

	# Try loading Kenney Space Kit GLB assets.
	# They auto-import the first time you open the Godot editor after placing them in assets/.
	var scanner_scene := load("res://assets/repair_tools/machine_wireless.glb") as PackedScene
	var end_scene     := load("res://assets/repair_tools/pipe_end.glb")         as PackedScene

	# ── Arm geometry constants ────────────────────────────────────
	const ARM_LEN   := 0.85
	const ARM_TILT  := -35.0
	const ARM2_LEN  := 0.55
	const ARM2_TILT := -18.0

	# ── Welding arm shaft (always procedural — Kenney pipes are room-scale) ──
	var arm_cyl := CylinderMesh.new()
	arm_cyl.top_radius      = 0.038
	arm_cyl.bottom_radius   = 0.038
	arm_cyl.height          = ARM_LEN
	arm_cyl.radial_segments = 6
	var arm_mat := StandardMaterial3D.new()
	arm_mat.albedo_color = Color(0.28, 0.32, 0.40)
	arm_mat.metallic     = 0.90
	arm_mat.roughness    = 0.20
	var arm_mi := MeshInstance3D.new()
	arm_mi.mesh              = arm_cyl
	arm_mi.material_override = arm_mat
	arm_mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm_mi.rotation.z        = deg_to_rad(ARM_TILT)
	_repair_arm.add_child(arm_mi)

	# Glowing collar ring where welding arm meets drone body
	var collar_cyl := CylinderMesh.new()
	collar_cyl.top_radius      = 0.072
	collar_cyl.bottom_radius   = 0.072
	collar_cyl.height          = 0.065
	collar_cyl.radial_segments = 10
	var collar_mat := StandardMaterial3D.new()
	collar_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	collar_mat.emission_enabled           = true
	collar_mat.emission                   = Color(0.10, 0.70, 0.95)
	collar_mat.emission_energy_multiplier = 3.5
	collar_mat.albedo_color               = Color(0.20, 0.72, 0.90)
	var collar_mi := MeshInstance3D.new()
	collar_mi.mesh              = collar_cyl
	collar_mi.material_override = collar_mat
	collar_mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	collar_mi.rotation.z        = deg_to_rad(ARM_TILT)
	_repair_arm.add_child(collar_mi)

	# ── Welding tip ───────────────────────────────────────────────
	# Tip position = bottom of arm after rotation.z = ARM_TILT
	var half     := ARM_LEN * 0.5
	var tilt_rad := deg_to_rad(ARM_TILT)
	var tip_pos  := Vector3(half * sin(tilt_rad), -half * cos(tilt_rad), 0.0)
	var tip_node := Node3D.new()
	tip_node.position = tip_pos
	_repair_arm.add_child(tip_node)

	# Kenney pipe_end as the nozzle cap (scaled to drone proportions)
	if end_scene != null:
		var end_inst := end_scene.instantiate() as Node3D
		end_inst.scale    = Vector3.ONE * 0.055
		end_inst.rotation = Vector3(0.0, 0.0, deg_to_rad(ARM_TILT - 90.0))
		tip_node.add_child(end_inst)

	# Glowing sphere at the welding core (always present, layered over the cap)
	_welder_mat = StandardMaterial3D.new()
	_welder_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_welder_mat.emission_enabled           = true
	_welder_mat.emission                   = Color(0.20, 0.88, 1.00)
	_welder_mat.emission_energy_multiplier = 9.0
	_welder_mat.albedo_color               = Color(0.55, 0.95, 1.00)
	var tip_sph := SphereMesh.new()
	tip_sph.radius = 0.068; tip_sph.height = 0.136
	tip_sph.radial_segments = 8; tip_sph.rings = 4
	var tip_mi := MeshInstance3D.new()
	tip_mi.mesh              = tip_sph
	tip_mi.material_override = _welder_mat
	tip_mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tip_node.add_child(tip_mi)

	# ── Scanner arm shaft (second, shorter arm) ───────────────────
	var arm2_cyl := CylinderMesh.new()
	arm2_cyl.top_radius      = 0.030
	arm2_cyl.bottom_radius   = 0.030
	arm2_cyl.height          = ARM2_LEN
	arm2_cyl.radial_segments = 6
	var arm2_mat := StandardMaterial3D.new()
	arm2_mat.albedo_color = Color(0.28, 0.32, 0.40)
	arm2_mat.metallic     = 0.90
	arm2_mat.roughness    = 0.20
	var arm2_mi := MeshInstance3D.new()
	arm2_mi.mesh              = arm2_cyl
	arm2_mi.material_override = arm2_mat
	arm2_mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arm2_mi.rotation.z        = deg_to_rad(ARM2_TILT)
	arm2_mi.rotation.x        = deg_to_rad(-20.0)
	_repair_arm.add_child(arm2_mi)

	# ── Scanner head at tip of second arm ─────────────────────────
	var half2    := ARM2_LEN * 0.5
	var tilt2    := deg_to_rad(ARM2_TILT)
	var tip2_pos := Vector3(half2 * sin(tilt2), -half2 * cos(tilt2), -0.20)
	var tip2_node := Node3D.new()
	tip2_node.position = tip2_pos
	_repair_arm.add_child(tip2_node)
	_scanner_node = tip2_node   # spun in _process

	if scanner_scene != null:
		# Kenney machine_wireless — small antenna/sensor device, scaled to drone size
		var sc_inst := scanner_scene.instantiate() as Node3D
		sc_inst.scale = Vector3.ONE * 0.075
		tip2_node.add_child(sc_inst)
	else:
		# Procedural fallback: spinning green disc
		var ring_disc := CylinderMesh.new()
		ring_disc.top_radius      = 0.12
		ring_disc.bottom_radius   = 0.12
		ring_disc.height          = 0.018
		ring_disc.radial_segments = 14
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.emission_enabled           = true
		ring_mat.emission                   = Color(0.20, 1.00, 0.45)
		ring_mat.emission_energy_multiplier = 5.0
		ring_mat.albedo_color               = Color(0.30, 1.00, 0.55, 0.80)
		ring_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
		var ring_mi := MeshInstance3D.new()
		ring_mi.mesh              = ring_disc
		ring_mi.material_override = ring_mat
		ring_mi.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tip2_node.add_child(ring_mi)

func _process(delta: float) -> void:
	if not is_instance_valid(_drone) or not is_instance_valid(_mech):
		return
	if _step >= SEQ_LEN:
		return

	_work_timer += delta

	# Keep drone locked beside the mech as it marches forward, with a bob
	var bob := sin(_work_timer * 8.0) * 0.10
	_drone.global_position = _mech.global_position + Vector3(1.6, 2.2 + bob, 0.3)

	# Tilt drone toward mech to sell "working on it"
	_drone.rotation.z = lerp(_drone.rotation.z, -0.22, 8.0 * delta)

	# Flicker the work light
	if is_instance_valid(_work_light):
		_work_light.light_energy = randf_range(4.0, 6.5)

	# Animate repair arm tools
	if _welder_mat != null:
		_welder_mat.emission_energy_multiplier = randf_range(7.0, 12.0)
	if is_instance_valid(_scanner_node):
		_arm_spin += delta * 4.5
		_scanner_node.rotation.y = _arm_spin

	# Sparks
	_spark_timer -= delta
	if _spark_timer <= 0.0:
		_spark_timer = randf_range(0.055, 0.11)
		_spawn_repair_spark()

func _spawn_repair_spark() -> void:
	var p   := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius          = randf_range(0.03, 0.07)
	sph.height          = sph.radius * 2.0
	sph.radial_segments = 4
	sph.rings           = 1
	p.mesh        = sph
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(1.0, randf_range(0.6, 1.0), randf_range(0.0, 0.3), 1.0)
	mat.emission_enabled           = true
	mat.emission                   = Color(1.0, 0.75, 0.1)
	mat.emission_energy_multiplier = 10.0
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test              = true
	mat.render_priority            = 9
	p.material_override = mat
	get_tree().current_scene.add_child(p)

	var origin := _mech.global_position + Vector3(
		randf_range(-0.4, 0.4), randf_range(1.0, 2.5), randf_range(-0.4, 0.4))
	p.global_position = origin

	var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.0), randf_range(-1.0, 1.0)).normalized()
	var dur := randf_range(0.15, 0.35)
	var tw  := p.create_tween()
	tw.tween_property(p, "global_position", origin + dir * randf_range(0.5, 1.8), dur)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.tween_callback(p.queue_free)
	AudioManager.play("drone_repair_spark", origin, -18.0, randf_range(0.85, 1.2))

func _cleanup_work_visuals() -> void:
	if is_instance_valid(_work_light):
		_work_light.queue_free()
		_work_light = null
	if is_instance_valid(_repair_arm):
		_repair_arm.queue_free()
		_repair_arm = null
	_welder_mat   = null
	_scanner_node = null
	if is_instance_valid(_drone):
		_drone.rotation.z = 0.0

func _generate_sequence() -> void:
	_sequence = [0, 1, 2, 3]
	_sequence.shuffle()
	_step = 0

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var total_w := BOX_W * SEQ_LEN + BOX_GAP * (SEQ_LEN - 1)
	var panel_w := total_w + 60.0
	var panel_h := BOX_H + 110.0

	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect()
	var px  := (vp.size.x - panel_w) * 0.5
	var py  := vp.size.y * 0.62

	# Dark backdrop panel
	var bg := ColorRect.new()
	bg.color        = Color(0.04, 0.03, 0.08, 0.90)
	bg.size         = Vector2(panel_w, panel_h)
	bg.position     = Vector2(px, py)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	# Title
	var title := Label.new()
	title.text = "REPAIR SEQUENCE"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.65, 0.1, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 1)
	title.add_theme_constant_override("shadow_offset_y", 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size         = Vector2(panel_w, 36.0)
	title.position     = Vector2(px, py + 10.0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(title)

	# Hint
	var hint := Label.new()
	hint.text = "use  W A S D"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.75))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.size         = Vector2(panel_w, 24.0)
	hint.position     = Vector2(px, py + panel_h - 28.0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(hint)

	# Key boxes
	_boxes.clear()
	_box_labels.clear()
	var boxes_x := px + (panel_w - total_w) * 0.5
	var boxes_y := py + 46.0

	for i in SEQ_LEN:
		var bx := boxes_x + i * (BOX_W + BOX_GAP)

		var box := PanelContainer.new()
		box.size     = Vector2(BOX_W, BOX_H)
		box.position = Vector2(bx, boxes_y)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.10, 0.08, 0.18, 1.0)
		style.set_corner_radius_all(8)
		style.border_width_left   = 3
		style.border_width_right  = 3
		style.border_width_top    = 3
		style.border_width_bottom = 3
		style.border_color = Color(0.35, 0.28, 0.55, 1.0)
		box.add_theme_stylebox_override("panel", style)
		_root.add_child(box)
		_boxes.append(box)

		var lbl := Label.new()
		lbl.text = ARROW_CHARS[_sequence[i]]
		lbl.add_theme_font_size_override("font_size", 42)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 1.0))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(lbl)
		_box_labels.append(lbl)

	_highlight_step(0)

func _highlight_step(idx: int) -> void:
	for i in _boxes.size():
		var style := _boxes[i].get_theme_stylebox("panel") as StyleBoxFlat
		if style == null:
			continue
		if i == idx:
			style.bg_color    = Color(0.20, 0.15, 0.40, 1.0)
			style.border_color = Color(1.0, 0.88, 0.25, 1.0)
			_box_labels[i].add_theme_color_override("font_color", Color(1.0, 0.95, 0.3, 1.0))
		elif i < idx:
			style.bg_color    = Color(0.06, 0.22, 0.08, 1.0)
			style.border_color = Color(0.2, 0.85, 0.3, 1.0)
			_box_labels[i].add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 1.0))
		else:
			style.bg_color    = Color(0.10, 0.08, 0.18, 1.0)
			style.border_color = Color(0.35, 0.28, 0.55, 1.0)
			_box_labels[i].add_theme_color_override("font_color", Color(0.7, 0.65, 0.85, 1.0))

func _input(event: InputEvent) -> void:
	if _mech == null or not is_instance_valid(_mech):
		_cancel()
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	for i in KEY_CODES.size():
		if key_event.keycode == KEY_CODES[i]:
			_on_key(i)
			get_viewport().set_input_as_handled()
			return

func _on_key(key_idx: int) -> void:
	if _step >= SEQ_LEN:
		return   # already succeeded, ignore stray input during fade-out
	if key_idx == _sequence[_step]:
		_step += 1
		AudioManager.play("repair_correct_%d" % _step)
		if _step >= SEQ_LEN:
			_on_success()
		else:
			_highlight_step(_step)
	else:
		AudioManager.play("repair_wrong")
		_on_wrong()

func _on_success() -> void:
	_cleanup_work_visuals()
	if is_instance_valid(_drone):
		_drone.repair_locked = false
	if is_instance_valid(_mech) and _mech.has_method("repair"):
		_mech.repair()
	repair_completed.emit(_mech)
	# Flash all boxes green then free
	for box in _boxes:
		var style := box.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.bg_color    = Color(0.08, 0.35, 0.10, 1.0)
			style.border_color = Color(0.2, 1.0, 0.3, 1.0)
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.30)
	tw.tween_callback(queue_free)

func _on_wrong() -> void:
	# Flash all boxes red, then reset to step 0
	for box in _boxes:
		var style := box.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.bg_color    = Color(0.35, 0.05, 0.05, 1.0)
			style.border_color = Color(1.0, 0.15, 0.1, 1.0)
	for lbl in _box_labels:
		lbl.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1.0))
	# Shake root
	if _shake_tween != null:
		_shake_tween.kill()
	var orig_x: float = _root.position.x
	_shake_tween = _root.create_tween()
	_shake_tween.tween_property(_root, "position:x", orig_x + 10.0, 0.04)
	_shake_tween.tween_property(_root, "position:x", orig_x - 10.0, 0.04)
	_shake_tween.tween_property(_root, "position:x", orig_x + 6.0,  0.03)
	_shake_tween.tween_property(_root, "position:x", orig_x,        0.03)
	_shake_tween.tween_callback(func() -> void:
		_step = 0
		_highlight_step(0)
	)

func _cancel() -> void:
	_cleanup_work_visuals()
	if is_instance_valid(_drone):
		_drone.repair_locked = false
	queue_free()
