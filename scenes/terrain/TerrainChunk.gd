extends Node3D

const CHUNK_SIZE := 24.0
const MECH_CORRIDOR := 4.5  # half-width of clear zone around X=0

func build(cx: int, cz: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cx * 73856093 ^ cz * 19349663)

	var origin := Vector3(cx * CHUNK_SIZE, 0.0, cz * CHUNK_SIZE)

	_add_floor(origin)

	var prop_count := rng.randi_range(18, 30)
	for _i in prop_count:
		var lx := rng.randf_range(-CHUNK_SIZE * 0.5, CHUNK_SIZE * 0.5)
		var lz := rng.randf_range(-CHUNK_SIZE * 0.5, CHUNK_SIZE * 0.5)
		var wx := origin.x + lx
		if absf(wx) < MECH_CORRIDOR:
			continue
		var pos := Vector3(wx, 0.0, origin.z + lz)
		var roll := rng.randf()
		if roll < 0.30:
			_add_tree(pos, rng)
		elif roll < 0.55:
			_add_bush(pos, rng)
		elif roll < 0.75:
			_add_rock(pos, rng)
		else:
			_add_flowers(pos, rng)

func _add_floor(origin: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(CHUNK_SIZE, CHUNK_SIZE)
	mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.42, 0.24)
	mat.roughness = 0.95
	mi.material_override = mat
	mi.position = origin
	add_child(mi)

func _add_tree(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var trunk_h := rng.randf_range(1.2, 2.5)
	var canopy_r := rng.randf_range(0.7, 1.4)

	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.height = trunk_h
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.18
	trunk.mesh = cyl
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.38, 0.24, 0.12)
	tm.roughness = 1.0
	trunk.material_override = tm
	trunk.position = pos + Vector3(0.0, trunk_h * 0.5, 0.0)
	add_child(trunk)

	var canopy := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = canopy_r
	sph.height = canopy_r * 2.0
	canopy.mesh = sph
	var cm := StandardMaterial3D.new()
	var g := rng.randf_range(0.30, 0.55)
	cm.albedo_color = Color(rng.randf_range(0.05, 0.18), g, rng.randf_range(0.05, 0.15))
	cm.roughness = 0.9
	canopy.material_override = cm
	canopy.position = pos + Vector3(0.0, trunk_h + canopy_r * 0.7, 0.0)
	add_child(canopy)

func _add_bush(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(0.25, 0.55)
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = r
	sph.height = r * 2.0
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(rng.randf_range(0.05, 0.15), rng.randf_range(0.28, 0.45), rng.randf_range(0.04, 0.12))
	mat.roughness = 1.0
	mi.material_override = mat
	mi.position = pos + Vector3(0.0, r * 0.6, 0.0)
	add_child(mi)

func _add_rock(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	var sx := rng.randf_range(0.2, 0.55)
	var sy := rng.randf_range(0.15, 0.35)
	var sz := rng.randf_range(0.2, 0.55)
	box.size = Vector3(sx, sy, sz)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	var v := rng.randf_range(0.38, 0.60)
	mat.albedo_color = Color(v, v, v * 0.95)
	mat.roughness = 0.85
	mi.material_override = mat
	mi.position = pos + Vector3(0.0, sy * 0.5, 0.0)
	mi.rotation.y = rng.randf() * TAU
	add_child(mi)

func _add_flowers(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(2, 5)
	for _i in count:
		var ox := rng.randf_range(-0.4, 0.4)
		var oz := rng.randf_range(-0.4, 0.4)
		var stem_h := rng.randf_range(0.18, 0.38)

		var stem := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.height = stem_h
		cyl.top_radius = 0.02
		cyl.bottom_radius = 0.02
		stem.mesh = cyl
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.18, 0.52, 0.12)
		stem.material_override = sm
		stem.position = pos + Vector3(ox, stem_h * 0.5, oz)
		add_child(stem)

		var head := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.07
		sph.height = 0.14
		head.mesh = sph
		var hm := StandardMaterial3D.new()
		var hue := rng.randf()
		hm.albedo_color = Color.from_hsv(hue, 0.9, 1.0)
		head.material_override = hm
		head.position = pos + Vector3(ox, stem_h + 0.06, oz)
		add_child(head)
