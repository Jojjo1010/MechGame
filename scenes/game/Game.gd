extends Node3D

const MECH_SCENE  := preload("res://scenes/mechs/Mech.tscn")
const DRONE_SCENE := preload("res://scenes/drones/Drone.tscn")

const CAM_OFFSET  := Vector3(16.0, 16.0, 16.0)
const CAM_SMOOTH  := 4.0
const CAM_SIZE    := 14.0

@onready var camera_rig:       Node3D = $CameraRig
@onready var camera:           Camera3D = $CameraRig/Camera3D
@onready var mechs_root:       Node3D = $Mechs
@onready var drones_root:      Node3D = $Drones
@onready var enemies_root:     Node3D = $Enemies
@onready var wave_spawner:     Node = $WaveSpawner
@onready var world_env:        WorldEnvironment = $WorldEnvironment
@onready var sun:              DirectionalLight3D = $Sun
@onready var mech_options:     CanvasLayer = $MechOptionsPanel

const DRONE_INTERACT_RADIUS := 5.0

var mechs:  Array[Node3D] = []
var drones: Array[Node3D] = []

func _ready() -> void:
	_setup_camera()
	_setup_environment()
	_spawn_mech_line(3)
	_spawn_drone()
	wave_spawner.setup(enemies_root)
	mech_options.setup(camera)
	mech_options.option_selected.connect(_on_mech_option)

func _process(delta: float) -> void:
	_follow_camera(delta)
	_check_drone_proximity()

# --- Camera ---

func _setup_camera() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAM_SIZE
	camera.position = CAM_OFFSET
	camera.look_at(Vector3.ZERO, Vector3.UP)

func _follow_camera(delta: float) -> void:
	if mechs.is_empty():
		return
	var center := Vector3.ZERO
	for m in mechs:
		center += m.global_position
	center /= mechs.size()
	center.y = 0.0
	center.x -= 1.0
	center.z -= 3.0
	camera_rig.global_position = camera_rig.global_position.lerp(center, CAM_SMOOTH * delta)

# --- Environment ---

func _setup_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color    = Color(0.18, 0.42, 0.82)
	sky_mat.sky_horizon_color = Color(0.65, 0.82, 1.0)
	sky_mat.ground_bottom_color   = Color(0.12, 0.28, 0.1)
	sky_mat.ground_horizon_color  = Color(0.38, 0.58, 0.28)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.005
	env.glow_enabled = true
	env.glow_intensity = 0.35
	world_env.environment = env

	sun.light_color = Color(1.0, 0.94, 0.78)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 3.5
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 60.0
	sun.directional_shadow_split_1 = 0.3
	sun.directional_shadow_blend_splits = true
	sun.rotation_degrees = Vector3(-52.0, 42.0, 0.0)

# --- Drone proximity ---

func _check_drone_proximity() -> void:
	if drones.is_empty():
		return
	var drone := drones[0]
	var closest: Node3D = null
	var closest_dist := DRONE_INTERACT_RADIUS
	for mech in mechs:
		var diff := drone.global_position - mech.global_position
		diff.y = 0.0
		var dist := diff.length()
		if dist < closest_dist:
			closest_dist = dist
			closest = mech
	mech_options.notify_proximity(closest)

func _on_mech_option(mech: Node3D, index: int) -> void:
	print("Option %d selected for mech %s" % [index, mech.name])

# --- Spawning ---

const MECH_COLORS := [
	Color(0.25, 0.55, 0.95),  # blue
	Color(0.85, 0.35, 0.20),  # orange-red
	Color(0.72, 0.20, 0.85),  # purple
]

func _spawn_mech_line(count: int) -> void:
	for i in count:
		var mech: Node3D = MECH_SCENE.instantiate()
		mech.position = Vector3(0.0, 0.0, float(i) * 2.5)
		mech.is_lead = (i == 0)
		if i > 0:
			mech.leader = mechs[i - 1]
		mechs_root.add_child(mech)
		mech.set_color(MECH_COLORS[i % MECH_COLORS.size()])
		mechs.append(mech)

func _spawn_drone() -> void:
	var drone: Node3D = DRONE_SCENE.instantiate()
	drone.position = Vector3(3.5, 2.2, 0.0)
	drone.player_controlled = true
	drones_root.add_child(drone)
	drones.append(drone)
