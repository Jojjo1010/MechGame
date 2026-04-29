extends Node3D

func _ready():
	_setup_sky()
	_setup_sun()
	_setup_grass_floor()
	_setup_mech()
	_setup_camera()


func _setup_sky():
	var env = Environment.new()

	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.45, 0.85)
	sky_mat.sky_horizon_color = Color(0.7, 0.85, 1.0)
	sky_mat.ground_bottom_color = Color(0.15, 0.3, 0.1)
	sky_mat.ground_horizon_color = Color(0.4, 0.6, 0.3)
	sky_mat.sun_angle_max = 30.0

	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.006
	env.fog_light_color = Color(0.8, 0.9, 1.0)
	env.glow_enabled = true
	env.glow_intensity = 0.3
	$WorldEnvironment.environment = env

func _setup_sun():
	$Sun.light_color = Color(1.0, 0.95, 0.8)
	$Sun.light_energy = 2.5
	$Sun.shadow_enabled = true
	$Sun.rotation_degrees = Vector3(-55, 45, 0)
	$FillLight.light_color = Color(0.5, 0.7, 1.0)
	$FillLight.light_energy = 0.5

func _setup_grass_floor():
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.45, 0.15)
	mat.roughness = 0.95
	$Floor/Mesh.material_override = mat

	var plane = PlaneMesh.new()
	plane.size = Vector2(200, 200)
	$Floor/Mesh.mesh = plane

func _setup_mech():
	# CongaGoober was dragged directly onto Main in the editor
	var mech = get_node_or_null("CongaGoober")
	if mech == null:
		push_warning("CongaGoober not found in scene.")
		return

	# Scale to a reasonable height (~4 units = ~4 metres)
	var aabb = _get_aabb(mech)
	if aabb.size.y > 0:
		var s = 4.0 / aabb.size.y
		mech.scale = Vector3.ONE * s

	# Place at origin, sitting on floor
	aabb = _get_aabb(mech)
	mech.position = Vector3(0, -aabb.position.y, 0)

func _setup_camera():
	var cam = $Camera3D
	cam.position = Vector3(0, 5, 14)
	cam.look_at(Vector3(0, 2, 0))
	cam.fov = 60.0

func _get_aabb(node: Node) -> AABB:
	var result = AABB()
	var first = true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a = mi.transform * mi.get_aabb()
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result
