extends Node3D

const MECH_SCENE  := preload("res://scenes/mechs/Mech.tscn")
const DRONE_SCENE := preload("res://scenes/drones/Drone.tscn")

const GUN_WEAPON_SCRIPT     := preload("res://scenes/mechs/weapons/GunWeapon.gd")
const GARLIC_WEAPON_SCRIPT  := preload("res://scenes/mechs/weapons/GarlicWeapon.gd")
const BEAM_WEAPON_SCRIPT    := preload("res://scenes/mechs/weapons/BouncyBeamWeapon.gd")
const ROCKET_WEAPON_SCRIPT  := preload("res://scenes/mechs/weapons/RocketWeapon.gd")
const ULT_BAR_SCRIPT        := preload("res://scenes/ui/UltBar.gd")
const REPAIR_MINIGAME_SCRIPT := preload("res://scenes/ui/RepairMinigame.gd")
const UPGRADE_PICKER_SCRIPT := preload("res://scenes/ui/UpgradePicker.gd")
const DEATH_SCREEN_SCRIPT   := preload("res://scenes/ui/DeathScreen.gd")
const WIN_SCREEN_SCRIPT     := preload("res://scenes/ui/WinScreen.gd")
const DRONE_HINT_SCRIPT     := preload("res://scenes/ui/DroneHiddenHint.gd")
const LEFT_CLICK_HINT_SCRIPT := preload("res://scenes/ui/LeftClickHint.gd")
const PAUSE_MENU_SCRIPT     := preload("res://scenes/ui/PauseMenu.gd")

const CAM_OFFSET  := Vector3(16.0, 16.0, 16.0)
const CAM_SMOOTH  := 4.0
const CAM_SIZE    := 14.0

const CAM_ZOOM_MIN  := 6.0
const CAM_ZOOM_MAX  := 32.0
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
var _ult_bar:        CanvasLayer = null
var _upgrade_picker: CanvasLayer = null
var _repair_active: bool = false
var _alive_mechs:   int  = 0
var _run_ended:     bool = false

# Drone-hidden hint state — shown when a mech is between camera and drone.
const DRONE_HIDE_THRESH_PX := 70.0   # screen-space mech↔drone distance below which we count occlusion
const DRONE_HIDE_REVEAL    := 0.4    # seconds occluded before hint appears
const DRONE_HIDE_DISMISS   := 0.25   # seconds clear before hint fades back out
var _drone_hint:        CanvasLayer = null
var _left_click_hint:   CanvasLayer = null
var _drone_hidden_t:    float = 0.0
var _drone_clear_t:     float = 0.0
var _drone_hint_shown:  bool  = false

func _ready() -> void:
	# Persistent autoloads carry state across scene reloads — wipe per-run state.
	get_tree().paused = false
	RunManager.reset_run()
	_setup_camera()
	_setup_environment()
	_spawn_mech_line(SaveData.unlocked_mech_slots)
	_spawn_drone()
	wave_spawner.setup(enemies_root)
	mech_options.setup(camera)
	mech_options.repair_pressed.connect(_on_mech_repair_pressed)
	_spawn_controls_legend()
	_spawn_xp_bar()
	_spawn_gold_counter()
	_spawn_ult_bar()
	_spawn_upgrade_picker()
	_spawn_drone_hint()
	_spawn_left_click_hint()
	RunManager.run_won.connect(_on_run_won)
	AudioManager.play_music("bgm_main", -12.0)

func _spawn_drone_hint() -> void:
	_drone_hint = CanvasLayer.new()
	_drone_hint.set_script(DRONE_HINT_SCRIPT)
	add_child(_drone_hint)

func _spawn_left_click_hint() -> void:
	_left_click_hint = CanvasLayer.new()
	_left_click_hint.set_script(LEFT_CLICK_HINT_SCRIPT)
	add_child(_left_click_hint)
	if not drones.is_empty() and is_instance_valid(drones[0]):
		_left_click_hint.setup(drones[0], camera)

func _open_pause_menu() -> void:
	var menu := CanvasLayer.new()
	menu.set_script(PAUSE_MENU_SCRIPT)
	add_child(menu)

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
	_ult_bar.setup(_weapons, _archetype_colors())

func _spawn_upgrade_picker() -> void:
	_upgrade_picker = CanvasLayer.new()
	_upgrade_picker.set_script(UPGRADE_PICKER_SCRIPT)
	add_child(_upgrade_picker)
	_upgrade_picker.setup(_weapons, _archetype_colors())

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
		elif event.keycode == KEY_ESCAPE:
			# Game._input only fires while unpaused (PROCESS_MODE_INHERIT) — so
			# this path can't open a pause menu over the upgrade picker / death
			# screen / repair minigame, all of which already pause the tree.
			_open_pause_menu()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_follow_camera(delta)
	_check_drone_proximity()
	_check_drone_visibility(delta)

# Show a hint when a mech is roughly between the camera and the drone in
# screen-space — that's when "the drone is hard to see" actually happens, not
# in world-space distance terms. Hysteresis on both edges keeps it from blinking
# every frame as the drone drifts past a mech.
func _check_drone_visibility(delta: float) -> void:
	if _drone_hint == null or drones.is_empty() or camera == null:
		return
	var occluded := _is_drone_screen_occluded(drones[0])
	if occluded:
		_drone_hidden_t += delta
		_drone_clear_t   = 0.0
		if not _drone_hint_shown and _drone_hidden_t >= DRONE_HIDE_REVEAL:
			_drone_hint_shown = true
			_drone_hint.set_hint_visible(true)
	else:
		_drone_clear_t  += delta
		_drone_hidden_t  = 0.0
		if _drone_hint_shown and _drone_clear_t >= DRONE_HIDE_DISMISS:
			_drone_hint_shown = false
			_drone_hint.set_hint_visible(false)

func _is_drone_screen_occluded(drone: Node3D) -> bool:
	if not is_instance_valid(drone) or not camera.is_position_in_frustum(drone.global_position):
		return false
	var drone_screen := camera.unproject_position(drone.global_position)
	var cam_pos      := camera.global_position
	var drone_dist   := cam_pos.distance_to(drone.global_position)
	for mech in mechs:
		if not is_instance_valid(mech):
			continue
		var mech_dist := cam_pos.distance_to(mech.global_position)
		if mech_dist >= drone_dist - 0.3:
			continue   # mech is behind or roughly even with the drone — can't occlude
		# Sample mech at chest height since that's where the silhouette is widest
		var mech_screen := camera.unproject_position(mech.global_position + Vector3(0.0, 1.6, 0.0))
		if mech_screen.distance_to(drone_screen) < DRONE_HIDE_THRESH_PX:
			return true
	return false

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
	sun.shadow_enabled = true
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
	var any_aiming := false
	var action_text := ""
	for mech in mechs:
		var w := mech.get("weapon") as Node3D
		if w != null and w.has_method("notify_drone_nearby"):
			w.notify_drone_nearby(mech == closest)
		if w != null and w.has_method("is_aim_mode") and w.is_aim_mode():
			any_aiming = true
			if w.has_method("aim_action_text"):
				action_text = w.aim_action_text()
	if _left_click_hint != null:
		_left_click_hint.set_hint_visible(any_aiming)
		if any_aiming:
			_left_click_hint.set_action_text(action_text)

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
		# Brief HP-immunity so a 1-HP mech can't die before the minigame helps.
		if mech.has_method("start_repair_grace"):
			mech.start_repair_grace(1.5)
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

# Build a parallel color array for `_weapons` using archetype tints. Lets
# legacy UI scripts (UltBar / UpgradePicker) keep their (weapons, colors)
# setup signature without baking in MECH_COLORS-by-line-position.
func _archetype_colors() -> Array:
	var colors: Array = []
	for w in _weapons:
		if w == null:
			colors.append(Color.WHITE)
		else:
			colors.append(MechArchetypes.color_for(String(w.weapon_name)))
	return colors

func _spawn_mech_line(count: int) -> void:
	_alive_mechs = count
	var weapon_scripts := [GUN_WEAPON_SCRIPT, GARLIC_WEAPON_SCRIPT, BEAM_WEAPON_SCRIPT, ROCKET_WEAPON_SCRIPT]
	for i in count:
		var mech: Node3D = MECH_SCENE.instantiate()
		mech.position = Vector3(0.0, 0.0, float(i) * 2.5)
		mech.is_lead = (i == 0)
		if i > 0:
			mech.leader = mechs[i - 1]
		mechs_root.add_child(mech)
		mech.mech_died.connect(_on_mech_died.bind(mech))
		mechs.append(mech)
		var w := Node3D.new()
		w.set_script(weapon_scripts[i % weapon_scripts.size()])
		mech.attach_weapon(w)
		# Color follows weapon, so each archetype reads at a glance regardless of line position.
		mech.set_color(MechArchetypes.color_for(String(w.weapon_name)))
		_weapons.append(w)

func _on_mech_died(mech: Node3D) -> void:
	# Pull the dead mech off the field and re-link the conga line so survivors
	# don't try to follow a freed node. Then rebuild the UltBar so its slot
	# count matches the surviving line.
	var dead_idx := mechs.find(mech)
	if dead_idx >= 0:
		var dead_leader: Node3D = mech.leader
		var was_lead: bool = mech.is_lead
		for m in mechs:
			if m == mech or not is_instance_valid(m):
				continue
			if m.leader == mech:
				m.leader = dead_leader
				if was_lead and dead_leader == null:
					m.is_lead = true
		_weapons.remove_at(dead_idx)
		mechs.remove_at(dead_idx)
		# Mech queue_frees itself after the fall + corpse-linger sequence so the
		# conga line can jump over the body. See Mech._on_died.
		if _ult_bar != null and is_instance_valid(_ult_bar):
			_ult_bar.setup(_weapons, _archetype_colors())
		# Drop the dead mech's archetype from the upgrade picker too — no more
		# offers for a weapon that isn't on the field.
		if _upgrade_picker != null and is_instance_valid(_upgrade_picker):
			_upgrade_picker.setup(_weapons, _archetype_colors())

	_alive_mechs = maxi(0, _alive_mechs - 1)
	if _alive_mechs == 0 and not _run_ended:
		_trigger_run_end()

func _trigger_run_end() -> void:
	_run_ended = true
	# Award scrap: 1 per wave + 1 per 3 gold collected this run
	var earned := RunManager.wave + int(RunManager.gold / 3.0)
	SaveData.add_scrap(earned)
	# Show death screen overlay (it pauses the game itself)
	var screen := CanvasLayer.new()
	screen.set_script(DEATH_SCREEN_SCRIPT)
	add_child(screen)
	screen.show_results(RunManager.wave, RunManager.gold, earned, SaveData.total_scrap)

func _on_run_won() -> void:
	# WaveSpawner has stopped spawning and confirmed the field is empty.
	# Award scrap on the same formula as a death — wave will be WIN_WAVE — and
	# show the WinScreen instead of the DeathScreen. Guard with _run_ended so
	# a final-mech death the same frame can't double up.
	if _run_ended:
		return
	_run_ended = true
	var earned := RunManager.wave + int(RunManager.gold / 3.0)
	SaveData.add_scrap(earned)
	var screen := CanvasLayer.new()
	screen.set_script(WIN_SCREEN_SCRIPT)
	add_child(screen)
	screen.show_results(RunManager.wave, RunManager.gold, earned, SaveData.total_scrap)

func _spawn_drone() -> void:
	var drone: Node3D = DRONE_SCENE.instantiate()
	drone.position = Vector3(3.5, 2.2, 0.0)
	drone.player_controlled = true
	drones_root.add_child(drone)
	drones.append(drone)
