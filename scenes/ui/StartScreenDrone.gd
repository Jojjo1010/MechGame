extends SubViewportContainer

# 3D mascot version of the in-game drone for the start screen. Mirrors the
# Drone.tscn palette (cyan emissive sphere + darker cyan equator ring) but
# adds two eye-pivots on the front face — the in-game drone has no face, but
# the title-screen mascot needs one. The whole drone tilts toward the cursor
# and the pupils track within their sockets, so the lean and the gaze read as
# one motion instead of just floating eyeballs.

const BODY_COLOR := Color(0.10, 0.80, 1.00)
const RING_COLOR := Color(0.05, 0.40, 0.60)
const PUPIL_DARK := Color(0.04, 0.10, 0.16)

const TILT_MAX_DEG    := 12.0
const TILT_RANGE_PX   := 600.0   # cursor distance at which tilt reaches max
const PUPIL_TRACK_3D  := 0.035   # eye-dot offset in eye-local units
const PUPIL_RANGE_PX  := 240.0
const DRIFT_AMP_X     := 0.030
const DRIFT_AMP_Y     := 0.022
const DRIFT_FREQ_X    := 0.70
const DRIFT_FREQ_Y    := 1.05
const PUPIL_REST_Z    := 0.020   # forward offset of the eye-dot in pivot space

const VIEWPORT_SIZE := Vector2i(280, 220)

var _drone_root:  Node3D
var _pupil_l:     MeshInstance3D
var _pupil_r:     MeshInstance3D
var _t:           float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(VIEWPORT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	# Random phase so the hover drift doesn't always start at the same spot
	# whenever the title screen reloads.
	_t = randf() * TAU
	_build()

func _build() -> void:
	var vp := SubViewport.new()
	vp.size = VIEWPORT_SIZE
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)

	var sun := DirectionalLight3D.new()
	# Pitch down + yaw right so the light lands on the upper-left of the body
	# from the camera's POV — gives the eye-whites soft shading instead of the
	# pure-flat read they'd have under emission alone.
	sun.rotation = Vector3(deg_to_rad(-30.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.1
	vp.add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 2.4)
	cam.fov = 35.0
	vp.add_child(cam)

	_drone_root = Node3D.new()
	vp.add_child(_drone_root)

	_build_body(_drone_root)
	_build_ring(_drone_root)
	# Eye Y must clear the equator ring (ring extends y=±0.04, eye radius 0.11)
	# — at y=0.04 the bottom of each eye sat inside the ring and got clipped.
	# 0.18 puts the eye bottom (~0.07) safely above the ring top (0.04).
	var eye_l := _build_eye(_drone_root, Vector3(-0.13, 0.18, 0.40))
	var eye_r := _build_eye(_drone_root, Vector3( 0.13, 0.18, 0.40))
	_pupil_l = _build_pupil(eye_l)
	_pupil_r = _build_pupil(eye_r)

func _build_body(parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.40
	sph.height = 0.80
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BODY_COLOR
	mat.emission_enabled = true
	mat.emission = BODY_COLOR
	mat.emission_energy_multiplier = 1.4
	mat.metallic = 0.7
	mat.roughness = 0.15
	mi.material_override = mat
	parent.add_child(mi)

func _build_ring(parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius    = 0.55
	cyl.bottom_radius = 0.55
	cyl.height        = 0.08
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = RING_COLOR
	mat.emission_enabled = true
	mat.emission = RING_COLOR
	mat.emission_energy_multiplier = 0.8
	mat.metallic = 0.4
	mat.roughness = 0.4
	mi.material_override = mat
	parent.add_child(mi)

func _build_eye(parent: Node3D, pos: Vector3) -> Node3D:
	# Eye is just a pivot — no white sclera. The dark dot returned by
	# _build_pupil reads as the whole eye, which is much cuter than a glossy
	# sphere catching specular like a glass globe.
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	return pivot

func _build_pupil(eye_pivot: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	# Smaller dot. Was 0.05 with a 0.11 sclera around it; without the sclera
	# it's still readable at half that.
	sph.radius = 0.045
	sph.height = 0.090
	mi.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PUPIL_DARK
	# Unshaded + matte so the directional sun doesn't spec-highlight the dot
	# into a mini-globe — keeps the read flat, cartoon-style.
	mat.metallic     = 0.0
	mat.roughness    = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.0, PUPIL_REST_Z)
	eye_pivot.add_child(mi)
	return mi

func _process(delta: float) -> void:
	_t += delta
	var mouse := get_viewport().get_mouse_position()
	var center := global_position + size * 0.5
	var sd := mouse - center

	# Body tilt: pitch on cursor's vertical offset, yaw on horizontal. Sign of
	# pitch is positive-down because in 3D the sphere's +Z (face) tilts toward
	# -Y when rotation.x is positive — i.e. the face leans down toward a cursor
	# below the drone, which is what feels right.
	var tx_amt: float = clampf(sd.y / TILT_RANGE_PX, -1.0, 1.0)
	var ty_amt: float = clampf(sd.x / TILT_RANGE_PX, -1.0, 1.0)
	_drone_root.rotation = Vector3(
		deg_to_rad(tx_amt * TILT_MAX_DEG),
		deg_to_rad(ty_amt * TILT_MAX_DEG),
		0.0
	)

	# Hover drift on top of tilt — keeps the body subtly alive even when the
	# cursor is parked and tilt is zero.
	_drone_root.position = Vector3(
		sin(_t * DRIFT_FREQ_X) * DRIFT_AMP_X,
		sin(_t * DRIFT_FREQ_Y) * DRIFT_AMP_Y,
		0.0
	)

	# Pupils track cursor inside the eye sockets. Eye sockets are children of
	# _drone_root so they already tilt with the body — pupil offset is added
	# on top in eye-local space, giving a layered look at where each eye is
	# pointing relative to the body's lean.
	var dist := sd.length()
	var pupil_amt: float = clampf(dist / PUPIL_RANGE_PX, 0.0, 1.0)
	var dir := Vector2.ZERO
	if dist > 0.001:
		dir = sd / dist
	var po := Vector3(
		dir.x * PUPIL_TRACK_3D,
		-dir.y * PUPIL_TRACK_3D,
		0.0
	) * pupil_amt
	var rest := Vector3(0.0, 0.0, PUPIL_REST_Z)
	_pupil_l.position = rest + po
	_pupil_r.position = rest + po
