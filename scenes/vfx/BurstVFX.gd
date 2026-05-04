extends Node

# Pooled one-shot GPUParticles3D burst. Active count capped so peak combat can't
# spawn dozens of fresh particle pipelines per frame; ParticleProcessMaterial
# cached by quantized (color, speed, count) so the shader compile happens once
# per visual variant instead of once per shot.
const MAX_ACTIVE := 16

static var _active_count: int = 0
static var _shared_mesh:  SphereMesh = null
static var _shared_mat:   StandardMaterial3D = null
static var _proc_cache:   Dictionary = {}   # int key → ParticleProcessMaterial

# Game._ready calls this on each new run — _active_count is static, so a scene
# reload while bursts are mid-flight would otherwise leave the counter stuck
# high and silently drop bursts in the next run.
static func reset_active_count() -> void:
	_active_count = 0

static func spawn(pos: Vector3, color: Color, count: int, speed: float, lifetime: float, scene_root: Node) -> void:
	if _active_count >= MAX_ACTIVE:
		return
	if _shared_mesh == null:
		_build_shared_mesh()

	var proc := _get_proc_material(color, speed, count)

	var p := GPUParticles3D.new()
	p.one_shot        = true
	p.explosiveness   = 1.0
	p.amount          = count
	p.lifetime        = lifetime
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	p.process_material = proc
	p.draw_pass_1      = _shared_mesh

	scene_root.add_child(p)
	p.global_position = pos
	p.emitting = true
	_active_count += 1

	# WeakRef + lambda instead of bind(p): if the scene reloads before this
	# fires, the bound GPUParticles3D reference goes stale and Godot's strict
	# Callable bind throws "Cannot convert argument 1 from Object to Object"
	# trying to pass a freed Object as a typed param. Capturing through a
	# weakref sidesteps that — we can null-check inside the lambda safely.
	var ref := weakref(p)
	scene_root.get_tree().create_timer(lifetime + 0.5).timeout.connect(
		func() -> void:
			_active_count = maxi(0, _active_count - 1)
			var alive: Variant = ref.get_ref()
			if alive != null and is_instance_valid(alive):
				(alive as Node).queue_free()
	)

static func _build_shared_mesh() -> void:
	_shared_mesh = SphereMesh.new()
	_shared_mesh.radius          = 0.1
	_shared_mesh.height          = 0.2
	_shared_mesh.radial_segments = 4
	_shared_mesh.rings           = 2
	_shared_mat = StandardMaterial3D.new()
	_shared_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shared_mat.vertex_color_use_as_albedo = true
	_shared_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shared_mesh.surface_set_material(0, _shared_mat)

# Cache key packs each component into a byte slot so the lookup is an int
# dictionary hit rather than a fresh String allocation on every spawn.
static func _get_proc_material(color: Color, speed: float, count: int) -> ParticleProcessMaterial:
	var key := int(color.r * 10) \
		| (int(color.g * 10) << 8) \
		| (int(color.b * 10) << 16) \
		| (int(speed)       << 24) \
		| (count            << 32)
	var proc: ParticleProcessMaterial = _proc_cache.get(key)
	if proc != null:
		return proc
	proc = ParticleProcessMaterial.new()
	proc.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.15
	proc.spread                 = 180.0
	proc.initial_velocity_min   = speed * 0.5
	proc.initial_velocity_max   = speed
	proc.gravity                = Vector3(0.0, -6.0, 0.0)
	proc.scale_min              = 0.12
	proc.scale_max              = 0.22
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors  = PackedColorArray([
		color,
		Color(color.r, color.g, color.b, 0.8),
		Color(color.r, color.g, color.b, 0.0),
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	proc.color_ramp = grad_tex
	_proc_cache[key] = proc
	return proc
