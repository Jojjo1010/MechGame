extends Node3D

const MECH_SCENE  := preload("res://scenes/mechs/Mech.tscn")
const DRONE_SCENE := preload("res://scenes/drones/Drone.tscn")

const GUN_WEAPON_SCRIPT     := preload("res://scenes/mechs/weapons/GunWeapon.gd")
const GARLIC_WEAPON_SCRIPT  := preload("res://scenes/mechs/weapons/GarlicWeapon.gd")
const BEAM_WEAPON_SCRIPT    := preload("res://scenes/mechs/weapons/BouncyBeamWeapon.gd")
const ULT_BAR_SCRIPT        := preload("res://scenes/ui/UltBar.gd")
const REPAIR_MINIGAME_SCRIPT := preload("res://scenes/ui/RepairMinigame.gd")

const CAM_OFFSET  := Vector3(16.0, 16.0, 16.0)
const CAM_SMOOTH  := 4.0
const CAM_SIZE    := 14.0

const CAM_ZOOM_MIN  := 6.0
const CAM_ZOOM_MAX  := 24.0
const CAM_ZOOM_STEP := 1.5

# Available isometric views (toggle with Q)
const CAM_VIEWS: Array[Vector3] = [
	Vector3( 16.0, 16.0,  16.0),   # default  (front-right)
	Vector3(-16.0, 16.0,  16.0),   # left side (front-left)
]

var _cam_zoom:           float   = CAM_ZOOM_MAX
var _cam_view_idx:       int     = 0
var _cam_offset_current: Vector3 = CAM_VIEWS[0]
var _cam_offset_target:  Vector3 = CAM_VIEWS[0]

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

var mechs:    Array[Node3D] = []
var drones:   Array[Node3D] = []
var _weapons: Array[Node3D] = []
var _ult_bar: CanvasLayer = null
var _repair_active: bool = false

func _ready() -> void:
	_setup_camera()
	_setup_environment()
	_spawn_mech_line(3)
	_spawn_drone()
	wave_spawner.setup(enemies_root)
	mech_options.setup(camera)
	mech_options.repair_pressed.connect(_on_mech_repair_pressed)
	_spawn_controls_legend()
	_spawn_xp_bar()
	_spawn_gold_counter()
	_spawn_ult_bar()
	AudioManager.play_music("bgm_main", -12.0)

func _spawn_controls_legend() -> void:
	var legend := CanvasLayer.new()
	legend.set_script(preload("res://scenes/ui/ControlsLegend.gd"))
	add_child(legend)

func _spawn_xp_bar() -> void:
	var bar := CanvasLayer.new()
	bar.set_script(preload("res://scenes/ui/XPBar.gd"))
	add_child(bar)

func _spawn_gold_counter() -> void:
	var counter := CanvasLayer.new()
	counter.set_script(preload("res://scenes/ui/GoldCounter.gd"))
	add_child(counter)

func _spawn_ult_bar() -> void:
	_ult_bar = CanvasLayer.new()
	_ult_bar.set_script(ULT_BAR_SCRIPT)
	add_child(_ult_bar)
	_ult_bar.setup(_weapons, MECH_COLORS)

func _input(event: InputEvent) -> void:
	# Zoom with scroll wheel
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_zoom = clampf(_cam_zoom - CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_zoom = clampf(_cam_zoom + CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
	# Toggle camera angle with Q
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_cam_view_idx = (_cam_view_idx + 1) % CAM_VIEWS.size()
			_cam_offset_target = CAM_VIEWS[_cam_view_idx]

func _process(delta: float) -> void:
	_follow_camera(delta)
	_check_drone_proximity()

# --- Camera ---

func _setup_camera() -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAM_ZOOM_MAX
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

	# Smooth zoom
	camera.size = lerpf(camera.size, _cam_zoom, CAM_SMOOTH * delta)

	# Smooth angle transition — interpolate offset then re-orient
	_cam_offset_current = _cam_offset_current.lerp(_cam_offset_target, CAM_SMOOTH * delta)
	camera.position = _cam_offset_current
	camera.look_at(camera_rig.global_position, Vector3.UP)

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
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_density = 0.005
	env.glow_enabled = true
	env.glow_intensity = 0.35
	world_env.environment = env

	sun.light_color = Color(1.0, 0.94, 0.78)
	sun.light_energy = 1.3
	sun.shadow_enabled = false
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

	# Notify each mech's weapon whether the drone is nearby
	for mech in mechs:
		var w := mech.get("weapon") as Node3D
		if w != null and w.has_method("notify_drone_nearby"):
			w.notify_drone_nearby(mech == closest)

func _on_mech_repair_pressed(_mech: Node3D) -> void:
	_try_start_repair()

func _try_start_repair() -> void:
	if _repair_active or drones.is_empty():
		return
	var drone := drones[0]
	for mech in mechs:
		if not mech.has_method("needs_repair"):
			continue
		if not mech.needs_repair():
			continue
		var diff := drone.global_position - mech.global_position
		diff.y = 0.0
		if diff.length() > DRONE_INTERACT_RADIUS:
			continue
		# Start repair minigame
		_repair_active = true
		var mg := CanvasLayer.new()
		mg.set_script(REPAIR_MINIGAME_SCRIPT)
		add_child(mg)
		mg.start(mech, drone)
		mg.repair_completed.connect(_on_repair_completed)
		mg.tree_exited.connect(func() -> void: _repair_active = false)
		return

func _on_repair_completed(_mech: Node3D) -> void:
	_repair_active = false

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
		var weapon_scripts := [GUN_WEAPON_SCRIPT, GARLIC_WEAPON_SCRIPT, BEAM_WEAPON_SCRIPT]
		var w := Node3D.new()
		w.set_script(weapon_scripts[i % weapon_scripts.size()])
		mech.attach_weapon(w)
		_weapons.append(w)

func _spawn_drone() -> void:
	var drone: Node3D = DRONE_SCENE.instantiate()
	drone.position = Vector3(3.5, 2.2, 0.0)
	drone.player_controlled = true
	drones_root.add_child(drone)
	drones.append(drone)
