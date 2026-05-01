extends Control

# 3D mech carousel: a turntable with N mechs standing on it, a spotlight
# pointing at the front position. Spinning the turntable cycles which mech
# is in the spotlight; spin lands on a chosen index.

const MECH_MODEL := preload("res://assets/CongaGoober.fbx")

const N_SLOTS     := 4
const DISK_RADIUS := 2.0
const DISK_HEIGHT := 0.18

const SPIN_REVS_DEFAULT := 3.0   # full rotations during a spin animation
const TICK_VOLUME_DB    := -16.0

var _viewport:  SubViewport = null
var _turntable: Node3D = null
var _spot:      SpotLight3D = null
var _spin_tween: Tween = null
var _colors: Array = []
var _slot_mechs: Array[Node3D] = []
var _last_tick_slot: int = -1

signal landed(idx: int)

func setup(colors: Array, view_size: Vector2) -> void:
	_colors = colors
	custom_minimum_size = view_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

func _ready() -> void:
	var vc := SubViewportContainer.new()
	vc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vc.stretch = true
	vc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vc)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(int(custom_minimum_size.x), int(custom_minimum_size.y))
	_viewport.transparent_bg = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	vc.add_child(_viewport)

	# Soft fill so the back-side mechs don't go pitch-black.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 25.0, 0.0)
	fill.light_energy = 0.45
	_viewport.add_child(fill)

	# Spotlight aimed down at the front-of-disk position. Anything that lands
	# there gets the warm "selected" pool of light.
	_spot = SpotLight3D.new()
	_spot.position = Vector3(0.0, 5.5, DISK_RADIUS + 0.5)
	_spot.rotation_degrees = Vector3(-72.0, 0.0, 0.0)
	_spot.spot_range = 9.0
	_spot.spot_angle = 22.0
	_spot.light_energy = 5.5
	_spot.light_color = Color(1.0, 0.92, 0.78)
	_viewport.add_child(_spot)

	# The disk itself.
	var disk := MeshInstance3D.new()
	var disk_mesh := CylinderMesh.new()
	disk_mesh.top_radius      = DISK_RADIUS + 0.35
	disk_mesh.bottom_radius   = DISK_RADIUS + 0.35
	disk_mesh.height          = DISK_HEIGHT
	disk_mesh.radial_segments = 32
	disk.mesh = disk_mesh
	var disk_mat := StandardMaterial3D.new()
	disk_mat.albedo_color = Color(0.07, 0.08, 0.07)
	disk_mat.metallic     = 0.7
	disk_mat.roughness    = 0.45
	disk.material_override = disk_mat
	disk.position.y = -DISK_HEIGHT * 0.5
	_viewport.add_child(disk)

	# Turntable spins; mechs are children, so they orbit with it.
	_turntable = Node3D.new()
	_viewport.add_child(_turntable)

	for i in N_SLOTS:
		var theta := float(i) / float(N_SLOTS) * TAU
		var mech := MECH_MODEL.instantiate()
		# Stop any embedded animations so the skeleton stays at rest pose.
		for ap in mech.find_children("*", "AnimationPlayer", true, false):
			ap.queue_free()
		for at in mech.find_children("*", "AnimationTree", true, false):
			at.queue_free()
		# Match the in-game scaling so the camera frame works regardless of FBX size.
		var aabb := _aabb_of(mech)
		if aabb.size.y > 0.0:
			var s_factor := 4.0 / aabb.size.y
			mech.scale = Vector3.ONE * s_factor
			aabb = _aabb_of(mech)
			mech.position.y = -aabb.position.y
		# Place around the disk.
		mech.position.x = sin(theta) * DISK_RADIUS
		mech.position.z = cos(theta) * DISK_RADIUS
		# FBX's authored front is +X. Rotate so +X points outward radially.
		mech.rotation.y = theta - PI * 0.5
		# Tint with the slot's archetype color.
		var tint: Color = _colors[i] if i < _colors.size() else Color.WHITE
		for child in mech.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi == null:
				continue
			var mat := StandardMaterial3D.new()
			mat.albedo_color = tint
			mat.roughness    = 0.75
			mat.metallic     = 0.15
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_turntable.add_child(mech)
		_slot_mechs.append(mech)

	# Camera looks down a bit at the front of the disk. Distance is far enough
	# that a 4-unit-tall mech in the front position fits the vertical FOV.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.6, DISK_RADIUS + 7.0)
	cam.rotation_degrees.x = -10.0
	cam.fov = 38.0
	cam.current = true
	_viewport.add_child(cam)

func _process(_delta: float) -> void:
	# Tick a soft "pass" sound when a fresh slot crosses into the spotlight.
	if _turntable == null or _slot_mechs.is_empty():
		return
	var current := _front_slot_index()
	if current != _last_tick_slot:
		_last_tick_slot = current
		# Don't tick on the very first frame after setup.
		if _spin_tween != null and _spin_tween.is_valid():
			AudioManager.play("ui_hover", Vector3.INF, TICK_VOLUME_DB, randf_range(0.95, 1.10))

# Spin the turntable so `target_idx` lands at the front position. Negative
# rotation direction = clockwise viewed from above; the `revs` extra rotations
# give visible spin before the deceleration.
func spin_to(target_idx: int, duration: float = 2.4, revs: float = SPIN_REVS_DEFAULT) -> void:
	if _turntable == null:
		return
	var theta_target := float(target_idx) / float(N_SLOTS) * TAU
	var target_rot := -theta_target - revs * TAU
	if _spin_tween != null:
		_spin_tween.kill()
	_spin_tween = create_tween()
	_spin_tween.tween_property(_turntable, "rotation:y", target_rot, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_spin_tween.tween_callback(func() -> void:
		AudioManager.play("repair_correct_3", Vector3.INF, -2.0, 1.0)
		landed.emit(target_idx)
	)

# Index of whichever slot is currently nearest the camera.
func _front_slot_index() -> int:
	var rot: float = _turntable.rotation.y
	# Find i such that (i/N * TAU + rot) mod TAU is closest to 0.
	var best_i := 0
	var best_d := INF
	for i in N_SLOTS:
		var theta_i := float(i) / float(N_SLOTS) * TAU
		var diff: float = fposmod(theta_i + rot, TAU)
		var dist: float = minf(diff, TAU - diff)
		if dist < best_d:
			best_d = dist
			best_i = i
	return best_i

func _aabb_of(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a := mi.transform * mi.get_aabb()
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result
