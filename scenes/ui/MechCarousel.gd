extends Control

# 3D mech carousel: a turntable with N mechs standing on it, a spotlight
# pointing at the front position. Spinning the turntable cycles which mech
# is in the spotlight; spin lands on a chosen index.

const MECH_MODEL := preload("res://assets/CongaGoober.fbx")

# Slot count is derived from the colors array passed to setup(). Dead mechs
# are dropped from the carousel between rounds, so the turntable shrinks to
# match the surviving line.
# Disk radius drives how far apart adjacent mechs sit. For N mechs the chord
# distance between adjacent slots is 2 · R · sin(π / N) — 4.0 gives ~5.7 u
# between two mechs (N=3) and ~5.3 u (N=4), comfortably past the mech body
# silhouette so they don't intersect.
const DISK_RADIUS := 4.0
const DISK_HEIGHT := 0.18
const MECH_HEIGHT := 5.5          # carousel-only scale (hero-shot, not field-sized)

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

	# Environment for the carousel viewport: flat ambient so non-spot sides of
	# the mechs are still legible, plus volumetric fog so the spotlight casts a
	# real visible column of light (theater spotlight look).
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.5
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.045
	env.volumetric_fog_albedo = Color(1.0, 0.96, 0.88)
	env.volumetric_fog_length = 32.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	# Soft directional fill so the mechs read as 3D form, not flat lit.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 25.0, 0.0)
	fill.light_energy = 0.45
	_viewport.add_child(fill)

	# Theatrical spotlight: rigged from above-front, aimed at the chosen mech's
	# torso. High energy + reduced attenuation so the beam clearly lights the
	# mech; volumetric fog above renders the visible column of light.
	_spot = SpotLight3D.new()
	_spot.position = Vector3(0.0, 9.0, DISK_RADIUS + 1.0)
	_spot.rotation_degrees = Vector3(-81.0, 0.0, 0.0)
	_spot.spot_range = 14.0
	_spot.spot_angle = 22.0
	_spot.spot_attenuation = 0.5
	_spot.light_energy = 14.0
	_spot.light_color = Color(1.0, 0.92, 0.78)
	_viewport.add_child(_spot)

	# Floor marker — a soft emissive ring on the disk under the front slot.
	# Stays put while the turntable spins, so it reads as "this is the chosen
	# slot" before/during/after the spin lands.
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.78
	ring_mesh.outer_radius = 1.05
	ring_mesh.ring_segments = 6
	ring_mesh.rings = 48
	ring.mesh = ring_mesh
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.88, 0.7)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.78, 0.45)
	ring_mat.emission_energy_multiplier = 2.4
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.position = Vector3(0.0, 0.02, DISK_RADIUS)
	_viewport.add_child(ring)

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

	var slot_count: int = _colors.size()
	for i in slot_count:
		var theta := float(i) / float(slot_count) * TAU
		var mech := MECH_MODEL.instantiate()
		# Stop any embedded animations so the skeleton stays at rest pose.
		for ap in mech.find_children("*", "AnimationPlayer", true, false):
			ap.queue_free()
		for at in mech.find_children("*", "AnimationTree", true, false):
			at.queue_free()
		# Bigger than the in-game scaling so the carousel mechs read at this
		# viewport size — they're meant to look hero-shot, not field-sized.
		var aabb := _aabb_of(mech)
		if aabb.size.y > 0.0:
			var s_factor := MECH_HEIGHT / aabb.size.y
			mech.scale = Vector3.ONE * s_factor
			aabb = _aabb_of(mech)
			mech.position.y = -aabb.position.y
		# Place around the disk.
		mech.position.x = sin(theta) * DISK_RADIUS
		mech.position.z = cos(theta) * DISK_RADIUS
		# FBX's authored front is -X (Mech.gd applies a -90° y-rotation so that
		# -X aligns with -Z, the marching direction). Rotate so -X points
		# outward radially — the front-slot mech then faces the camera.
		mech.rotation.y = theta + PI * 0.5
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

	# Camera looks down a bit at the front of the disk. Distance + FOV are
	# tuned so a MECH_HEIGHT-tall mech in the front position fits with headroom
	# above the head and the disk visible below the feet.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.2, DISK_RADIUS + 13.0)
	cam.rotation_degrees.x = -10.0
	cam.fov = 46.0
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
# rotation direction = clockwise viewed from above; each spin always covers
# between `revs` and `revs+1` full rotations relative to the *current* angle,
# so the second spin doesn't shrink to a tiny delta if the rolled target
# happens to be near the previous one.
func spin_to(target_idx: int, duration: float = 2.4, revs: float = SPIN_REVS_DEFAULT) -> void:
	if _turntable == null or _slot_mechs.is_empty():
		return
	var slot_count: int = _slot_mechs.size()
	var theta_target: float = float(target_idx) / float(slot_count) * TAU
	var current_rot: float = _turntable.rotation.y
	var target_mod: float = fposmod(-theta_target, TAU)
	var current_mod: float = fposmod(current_rot, TAU)
	var delta: float = target_mod - current_mod
	if delta > 0.0:
		delta -= TAU
	# delta ∈ (-TAU, 0]; subtract revs full turns to add the spin proper.
	var target_rot: float = current_rot + delta - revs * TAU
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
	var slot_count: int = _slot_mechs.size()
	if slot_count <= 0:
		return 0
	var rot: float = _turntable.rotation.y
	# Find i such that (i/N * TAU + rot) mod TAU is closest to 0.
	var best_i := 0
	var best_d := INF
	for i in slot_count:
		var theta_i := float(i) / float(slot_count) * TAU
		var diff: float = fposmod(theta_i + rot, TAU)
		var dist: float = minf(diff, TAU - diff)
		if dist < best_d:
			best_d = dist
			best_i = i
	return best_i

func _aabb_of(root: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# Compose the transform from mesh-local up to root-local. mi.transform
		# alone is only mesh→parent; for nested skeletal FBX hierarchies the
		# AABB shifts wildly (mech ends up floating) without this chain walk.
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		var a: AABB = t * mi.get_aabb()
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result
