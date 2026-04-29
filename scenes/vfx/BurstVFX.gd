extends Node

# Spawns a one-shot GPUParticles3D burst at a world position.
static func spawn(pos: Vector3, color: Color, count: int, speed: float, lifetime: float, scene_root: Node) -> void:
	var p := GPUParticles3D.new()
	p.one_shot       = true
	p.explosiveness  = 1.0
	p.amount         = count
	p.lifetime       = lifetime
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape        = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.15
	proc.spread                = 180.0
	proc.initial_velocity_min  = speed * 0.5
	proc.initial_velocity_max  = speed
	proc.gravity               = Vector3(0.0, -6.0, 0.0)
	proc.scale_min             = 0.12
	proc.scale_max             = 0.22

	# Fade color to transparent over lifetime
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
	p.process_material = proc

	var mesh := SphereMesh.new()
	mesh.radius          = 0.1
	mesh.height          = 0.2
	mesh.radial_segments = 4
	mesh.rings           = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode             = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency             = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_set_material(0, mat)
	p.draw_pass_1 = mesh

	scene_root.add_child(p)
	p.global_position = pos
	p.emitting = true

	scene_root.get_tree().create_timer(lifetime + 0.5).timeout.connect(
		func(): if is_instance_valid(p): p.queue_free()
	)
