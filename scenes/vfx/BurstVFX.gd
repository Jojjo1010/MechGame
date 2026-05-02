extends Node

# Pooled one-shot GPUParticles3D burst. Late-game perf was dominated by allocating
# fresh ParticleProcessMaterial / Gradient / GradientTexture1D / SphereMesh /
# StandardMaterial3D on every bullet impact and enemy death. Two changes here:
#   1. Hard cap on concurrent active bursts. Over the cap, new spawns are dropped
#      silently — the visual was indistinguishable from the existing 20+ bursts
#      already on screen, but the GPU work was very real.
#   2. Cache the heavy resources (mesh, base material, ParticleProcessMaterial
#      keyed by quantized color/speed/count) so repeated bursts reuse the same
#      shader pipeline instead of triggering a fresh compile every shot.
const MAX_ACTIVE := 16

static var _active_count: int = 0
static var _shared_mesh:  SphereMesh = null
static var _shared_mat:   StandardMaterial3D = null
static var _proc_cache:   Dictionary = {}   # String key → ParticleProcessMaterial

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

	scene_root.get_tree().create_timer(lifetime + 0.5).timeout.connect(_on_burst_done.bind(p))

static func _on_burst_done(p: GPUParticles3D) -> void:
	_active_count = maxi(0, _active_count - 1)
	if is_instance_valid(p):
		p.queue_free()

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

# Cache key quantizes color to a 10-step palette per channel — enough granularity
# that the orange / yellow / red / blue families each get their own pipeline,
# but not so fine that every call misses the cache.
static func _get_proc_material(color: Color, speed: float, count: int) -> ParticleProcessMaterial:
	var key := "%d_%d_%d_%d_%d" % [int(color.r * 10), int(color.g * 10), int(color.b * 10), int(speed), count]
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
