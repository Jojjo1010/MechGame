extends Node3D

const SPEED         := 3.0
const MECH_SPACING  := 4.5

const BURN_THRESHOLD      := 0.45   # fraction at which mech starts burning
const BURN_DAMAGE_PER_SEC := 2.0

const HealthBar3D   := preload("res://scenes/ui/HealthBar3D.gd")
const DamageNumber  := preload("res://scenes/ui/DamageNumber.gd")

@export var max_health: float = 100.0
@export var is_lead: bool = false

var health: float = max_health
var leader: Node3D = null
var ability_active: bool = true
var is_alive: bool = true
var weapon: Node3D = null
var _is_burning:        bool          = false
var _burn_light:        OmniLight3D   = null
var _fire_particles:    GPUParticles3D = null
var _burn_audio:        AudioStreamPlayer3D = null
var _burn_damage_timer: float         = 1.0
var _flash_timer: float = 0.0
var _repair_grace_timer: float = 0.0   # brief HP-immunity window when F is pressed, so the mech can't die before the minigame helps
var _ult_flash_timer: float = 0.0
var _ult_flash_color: Color = Color.WHITE
const ULT_FLASH_DURATION := 0.35
var _base_color: Color = Color.WHITE
var _mesh_instances: Array[MeshInstance3D] = []
var _health_bar: Node3D = null
var _bulwark_reduction: float = 0.0   # 0..1, refreshed each frame from nearby Garlic auras
var _bulwark_bubble: MeshInstance3D = null
var _bulwark_bubble_mat: StandardMaterial3D = null
var _selection_ring: MeshInstance3D = null
var _selection_ring_mat: StandardMaterial3D = null
var _selection_pulse_tween: Tween = null
var _model_base_y: float = 0.0
var _bob_time: float = 0.0
var _step_pitch_base: float = 1.0   # randomized per mech so the conga line has variety

const FLASH_DURATION := 0.12
const BOB_FREQ  := 9.0   # rad/s  (~1.4 steps/sec)
const BOB_AMP   := 0.38  # world units vertical travel
const LEAN_AMP  := 0.12  # radians (~7°) forward/back tilt

# Death + corpse + jump-over choreography
const CORPSE_LINGER := 6.0   # seconds the body stays on the ground before freeing
const FALL_DURATION := 0.55  # how long the mech takes to topple
const JUMP_HEIGHT   := 1.4   # peak Y offset added to the model when arcing over a corpse
const JUMP_WINDOW   := 1.2   # half-width (Z meters) of the jump arc around a corpse
const JUMP_LANE_TOL := 1.5   # only jump over corpses within this lateral distance

signal health_changed(current: float, maximum: float)
signal mech_died()

func _ready() -> void:
	add_to_group("mechs")
	health = max_health
	_scale_model()
	_add_blob_shadow(0.75, 4.0)
	# Stagger bob phase by line position so mechs don't all bounce in sync
	_bob_time = position.z * 0.55
	# Each mech in the line gets its own pitch so steps form a chord, not a unison
	_step_pitch_base = randf_range(0.85, 1.15)
	# HP bar
	_health_bar = Node3D.new()
	_health_bar.set_script(HealthBar3D)
	_health_bar.position = Vector3(0.0, 4.9, 0.0)
	add_child(_health_bar)



func _scale_model() -> void:
	var model := get_node_or_null("Model")
	if model == null:
		return
	var aabb := _get_aabb(model)
	if aabb.size.y > 0.0:
		var s := 4.0 / aabb.size.y
		model.scale = Vector3.ONE * s
		aabb = _get_aabb(model)
		model.position.y = -aabb.position.y
	model.rotation_degrees.y = -90.0
	_model_base_y = model.position.y

func _get_aabb(root: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		# Walk parent chain to compose mesh→root transform; without this,
		# nested skeletal FBX hierarchies produce a wrong AABB and the model
		# is offset vertically (e.g. floats above the ground).
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

func _process(delta: float) -> void:
	if not ability_active:
		return

	var march_speed := SPEED * RunManager.line_speed_mult

	# Always keep marching, alive or dead
	if is_lead:
		position.z -= march_speed * delta
		position.x = 0.0  # lead stays on the centre lane
	elif leader != null:
		var target := leader.global_position + leader.global_transform.basis.z * MECH_SPACING
		var diff := target - global_position
		diff.y = 0.0
		if diff.length() > 0.05:
			global_position += diff.normalized() * march_speed * delta

	# Walk bob — runs while alive only
	if is_alive:
		var prev_bob := _bob_time
		_bob_time += delta * BOB_FREQ
		# Foot-strike happens when abs(sin) crosses zero, i.e. _bob_time crosses
		# a multiple of PI. Detect by floor() bucket change.
		if floor(_bob_time / PI) > floor(prev_bob / PI):
			AudioManager.play("mech_step", global_position,
				-4.0, _step_pitch_base * randf_range(0.97, 1.03))
		var model := get_node_or_null("Model")
		if model:
			# abs(sin) gives a sharp bounce-off-ground feel
			var bounce: float = abs(sin(_bob_time)) * BOB_AMP
			# Auto-jump over any corpse in our path — adds an arc on top of bob.
			var jump_y := _compute_jump_offset()
			model.position.y = _model_base_y + bounce + jump_y
			# Lean forward on downstroke, back on upstroke
			model.rotation.x = -cos(_bob_time) * LEAN_AMP

	# Only process flash while alive
	if not is_alive:
		return

	if _repair_grace_timer > 0.0:
		_repair_grace_timer = maxf(0.0, _repair_grace_timer - delta)

	if _ult_flash_timer > 0.0:
		_ult_flash_timer -= delta
		var t := _ult_flash_timer / ULT_FLASH_DURATION
		var c := _base_color.lerp(_ult_flash_color, t)
		for mi in _mesh_instances:
			if is_instance_valid(mi) and mi.material_override:
				(mi.material_override as StandardMaterial3D).albedo_color = c
		if _ult_flash_timer <= 0.0:
			for mi in _mesh_instances:
				if is_instance_valid(mi) and mi.material_override:
					(mi.material_override as StandardMaterial3D).albedo_color = _base_color
	elif _flash_timer > 0.0:
		_flash_timer -= delta
		var t := _flash_timer / FLASH_DURATION
		var c := _base_color.lerp(Color.WHITE, t * 0.85)
		for mi in _mesh_instances:
			if is_instance_valid(mi) and mi.material_override:
				(mi.material_override as StandardMaterial3D).albedo_color = c
		if _flash_timer <= 0.0:
			for mi in _mesh_instances:
				if is_instance_valid(mi) and mi.material_override:
					(mi.material_override as StandardMaterial3D).albedo_color = _base_color

	_update_bulwark_status(delta)

	# Burning tick
	if _is_burning and is_alive:
		if is_instance_valid(_burn_light):
			_burn_light.light_energy = randf_range(1.0, 2.2)
		_burn_damage_timer -= delta
		if _burn_damage_timer <= 0.0:
			_burn_damage_timer = 1.0
			take_damage(BURN_DAMAGE_PER_SEC)

const BULWARK_BUBBLE_RADIUS := 1.7
const GARLIC_AURA_RADIUS    := 4.5   # mirrors GarlicWeapon.AURA_RADIUS — checked here to avoid a circular load

# Each frame, scan all Garlic mechs and take the strongest bulwark reduction
# AND the strongest Sanctuary regen whose aura covers self. Drives:
#   • the take_damage multiplier
#   • the green protection bubble
#   • passive HP regen tick (Sanctuary rare upgrade)
func _update_bulwark_status(delta: float) -> void:
	var best_bulwark := 0.0
	var best_regen   := 0.0
	for m in get_tree().get_nodes_in_group("mechs"):
		if m == null or not is_instance_valid(m):
			continue
		var w: Variant = m.get("weapon")
		if w == null or not is_instance_valid(w):
			continue
		if String(w.get("weapon_name")) != "GARLIC":
			continue
		var br: Variant = w.get("bulwark_dmg_reduction")
		var rg: Variant = w.get("aura_regen_per_sec")
		var br_f := float(br) if br != null else 0.0
		var rg_f := float(rg) if rg != null else 0.0
		if br_f <= 0.0 and rg_f <= 0.0:
			continue
		var rm: Variant = w.get("range_mult")
		var radius: float = GARLIC_AURA_RADIUS * (float(rm) if rm != null else 1.0)
		if m.global_position.distance_to(global_position) <= radius:
			best_bulwark = maxf(best_bulwark, br_f)
			best_regen   = maxf(best_regen,   rg_f)
	_bulwark_reduction = best_bulwark
	_update_bulwark_visual()
	# Sanctuary tick: regen up to max_health while aura covers us. Burning still
	# applies on top — at threshold the regen partly offsets burn DPS.
	if best_regen > 0.0 and is_alive and health < max_health:
		health = minf(max_health, health + best_regen * delta)
		health_changed.emit(health, max_health)
		if is_instance_valid(_health_bar):
			_health_bar.set_fraction(health / max_health)

func _update_bulwark_visual() -> void:
	if _bulwark_reduction <= 0.0:
		if is_instance_valid(_bulwark_bubble):
			_bulwark_bubble.visible = false
		return
	if _bulwark_bubble == null or not is_instance_valid(_bulwark_bubble):
		_bulwark_bubble = MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = BULWARK_BUBBLE_RADIUS
		sph.height = BULWARK_BUBBLE_RADIUS * 2.0 * 1.6   # slightly elongated to wrap mech body
		_bulwark_bubble.mesh = sph
		_bulwark_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bulwark_bubble_mat = StandardMaterial3D.new()
		_bulwark_bubble_mat.albedo_color              = Color(0.3, 1.0, 0.4, 0.22)
		_bulwark_bubble_mat.emission_enabled          = true
		_bulwark_bubble_mat.emission                  = Color(0.2, 1.0, 0.3)
		_bulwark_bubble_mat.emission_energy_multiplier = 1.6
		_bulwark_bubble_mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bulwark_bubble_mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bulwark_bubble_mat.cull_mode                 = BaseMaterial3D.CULL_FRONT
		_bulwark_bubble.material_override = _bulwark_bubble_mat
		_bulwark_bubble.position = Vector3(0.0, 1.8, 0.0)
		add_child(_bulwark_bubble)
	_bulwark_bubble.visible = true
	# Pulse opacity with a quick sine so the bubble breathes
	if _bulwark_bubble_mat != null:
		var pulse := 0.18 + 0.10 * absf(sin(Time.get_ticks_msec() * 0.005))
		_bulwark_bubble_mat.albedo_color.a = pulse * (0.6 + 0.4 * _bulwark_reduction)

func attach_weapon(w: Node3D) -> void:
	weapon = w
	add_child(w)
	w.setup(self)

func trigger_flash() -> void:
	_flash_timer = FLASH_DURATION

func start_burning() -> void:
	if _is_burning:
		return
	_is_burning = true
	_burn_damage_timer = 2.0   # short grace before first burn tick
	AudioManager.play("mech_burn_ignite", global_position, -4.0)
	_burn_audio = AudioManager.play_loop_on("mech_burn_loop", self, -10.0)

	# Flickering fire light
	# Burn light sits up by the head (just below the flame base) so the mech
	# body gets the warm down-lit "torch" treatment instead of being lit from
	# the feet. Energy stays modest so the flame silhouette remains readable.
	_burn_light = OmniLight3D.new()
	_burn_light.light_color    = Color(1.0, 0.35, 0.03)
	_burn_light.light_energy   = 1.6
	_burn_light.omni_range     = 5.0
	_burn_light.shadow_enabled = false
	_burn_light.position       = Vector3(0.0, 3.5, 0.0)
	add_child(_burn_light)

	# GPU fire particles
	var pp := ParticleProcessMaterial.new()
	pp.direction              = Vector3(0.0, 1.0, 0.0)
	pp.spread                 = 22.0
	pp.initial_velocity_min   = 3.0
	pp.initial_velocity_max   = 6.0
	pp.gravity                = Vector3(0.0, 0.8, 0.0)   # slight upward drift
	pp.scale_min              = 0.6
	pp.scale_max              = 1.4
	pp.emission_shape         = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pp.emission_sphere_radius = 0.25

	# Dense black-red base for a dark silhouette where the flame overlaps the
	# mech body (lime/teal/blue tints would wash out a yellow palette), with a
	# brighter saturated orange peak so the plume above the head still reads
	# loud against the sky.
	var grad := Gradient.new()
	grad.set_color(0, Color(0.15, 0.03, 0.00, 1.0))
	grad.set_color(1, Color(0.50, 0.10, 0.00, 0.0))
	grad.add_point(0.30, Color(0.70, 0.15, 0.03, 0.95))
	grad.add_point(0.65, Color(1.00, 0.50, 0.10, 0.85))
	var gtex := GradientTexture1D.new()
	gtex.gradient = grad
	pp.color_ramp = gtex

	# Tall billboard quad — camera-facing so it always looks like a flame tongue
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.85)
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.vertex_color_use_as_albedo = true
	p_mat.billboard_mode             = BaseMaterial3D.BILLBOARD_ENABLED
	p_mat.billboard_keep_scale       = true
	p_mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	quad.material = p_mat

	_fire_particles = GPUParticles3D.new()
	_fire_particles.amount           = 32
	_fire_particles.lifetime         = 0.50
	_fire_particles.explosiveness    = 0.0
	_fire_particles.randomness       = 0.5
	_fire_particles.emitting         = true
	_fire_particles.process_material = pp
	_fire_particles.draw_pass_1      = quad
	_fire_particles.cast_shadow      = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Position above the head (mech body is ~4 u tall, scale-applied in
	# _scale_model). Particles drift upward against the sky from here, so the
	# burn state reads at a glance even when the mech is partway off-screen.
	_fire_particles.position         = Vector3(0.0, 4.0, 0.0)
	add_child(_fire_particles)

func stop_burning() -> void:
	_is_burning = false
	if is_instance_valid(_burn_light):
		_burn_light.queue_free()
		_burn_light = null
	if is_instance_valid(_fire_particles):
		_fire_particles.emitting = false
		# Let existing particles finish, then free
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_callback(_fire_particles.queue_free)
		_fire_particles = null
	if is_instance_valid(_burn_audio):
		_burn_audio.queue_free()
		_burn_audio = null

func start_repair_grace(seconds: float) -> void:
	_repair_grace_timer = maxf(_repair_grace_timer, seconds)

func repair() -> void:
	# Partial heal — repair clamps the mech up to 50 HP (not full restore), so
	# stacking repairs through a long wave still costs you something.
	var target: float = minf(50.0, max_health)
	health = maxf(health, target)
	health_changed.emit(health, max_health)
	if is_instance_valid(_health_bar):
		_health_bar.set_fraction(health / max_health)
	stop_burning()
	AudioManager.play("mech_repair_complete", global_position, -2.0)

func needs_repair() -> bool:
	return _is_burning



func start_ult_windup(color: Color, duration: float) -> void:
	# Pre-fire windup: model swells slightly + a tinted halo sphere blooms and
	# fades from the mech base, telegraphing "this mech is firing its ult NOW."
	var model := get_node_or_null("Model")
	if model:
		var base_scale: Vector3 = model.scale
		var tw := create_tween()
		tw.tween_property(model, "scale", base_scale * 1.10, duration * 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(model, "scale", base_scale, duration * 0.3).set_ease(Tween.EASE_IN)

	var halo := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.4
	sph.height = 2.8
	halo.mesh = sph
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color              = Color(color.r, color.g, color.b, 0.0)
	hmat.emission_enabled          = true
	hmat.emission                  = color
	hmat.emission_energy_multiplier = 6.0
	hmat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.material_override = hmat
	halo.position = Vector3(0.0, 1.3, 0.0)
	add_child(halo)
	var htw := halo.create_tween()
	htw.tween_property(halo, "scale", Vector3.ONE * 1.6, duration).set_ease(Tween.EASE_OUT)
	htw.parallel().tween_property(hmat, "albedo_color:a", 0.55, duration * 0.5).set_ease(Tween.EASE_OUT)
	htw.tween_property(hmat, "albedo_color:a", 0.0, duration * 0.5).set_ease(Tween.EASE_IN)
	htw.tween_callback(halo.queue_free)

	AudioManager.play("ult_ready", global_position, -6.0, 0.7)

func ult_fired(color: Color) -> void:
	# Bright color flash using mech's own color
	_ult_flash_color = Color(
		minf(1.0, color.r * 1.5 + 0.4),
		minf(1.0, color.g * 1.5 + 0.4),
		minf(1.0, color.b * 1.5 + 0.4), 1.0)
	_ult_flash_timer = ULT_FLASH_DURATION
	AudioManager.play("ult_fired", global_position, -2.0)

	# Scale pop on the model
	var model := get_node_or_null("Model")
	if model:
		var base_scale: Vector3 = model.scale
		var tw := create_tween()
		tw.tween_property(model, "scale", base_scale * 1.22, 0.07).set_ease(Tween.EASE_OUT)
		tw.tween_property(model, "scale", base_scale,         0.18).set_ease(Tween.EASE_IN)

	# Burst ring expanding from mech base
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius  = 0.1
	torus.outer_radius  = 0.55
	torus.rings         = 48
	torus.ring_segments = 12
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color              = Color(color.r, color.g, color.b, 0.9)
	mat.emission_enabled          = true
	mat.emission                  = color
	mat.emission_energy_multiplier = 8.0
	mat.transparency              = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position + Vector3(0.0, 0.3, 0.0)
	var rtw := ring.create_tween()
	rtw.tween_property(ring, "scale", Vector3(5.0, 1.0, 5.0), 0.40).set_ease(Tween.EASE_OUT)
	rtw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.40)
	rtw.tween_callback(ring.queue_free)

func take_damage(amount: float) -> void:
	# Already-dead mechs don't take more damage and don't re-emit mech_died.
	# Without this guard, enemies still wailing on the corpse would each fire
	# mech_died → run-end counter drops past zero on the first real death.
	if not is_alive:
		return
	# Repair grace: F-press grants a brief HP-immunity window so a 1-HP mech
	# can't die before the minigame even gets going. Burn DPS routes through
	# take_damage too, so it's covered automatically.
	if _repair_grace_timer > 0.0:
		return
	# Bulwark: any nearby Garlic mech with the upgrade reduces incoming damage.
	var shielded := _bulwark_reduction > 0.0
	if shielded:
		amount *= maxf(0.0, 1.0 - _bulwark_reduction)
	health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if is_instance_valid(_health_bar):
		_health_bar.set_fraction(health / max_health)
	# Shielded hits show a desaturated blue-green number so the player sees the save.
	var dmg_color := Color(0.55, 1.0, 0.7) if shielded else Color(1.0, 0.35, 0.1)
	DamageNumber.spawn(amount, global_position + Vector3(0.0, 3.8, 0.0),
		get_tree().current_scene, dmg_color)
	if shielded:
		# Bubble flash on every blocked hit so the player sees the save.
		if _bulwark_bubble_mat != null:
			_bulwark_bubble_mat.albedo_color.a = 0.55
	AudioManager.play("mech_hit", global_position, -6.0, randf_range(0.93, 1.07))
	if not _is_burning and health / max_health <= BURN_THRESHOLD:
		start_burning()
	if health <= 0.0:
		mech_died.emit()
		AudioManager.play("mech_death", global_position, 0.0)
		_on_died()

const OUTLINE_SHADER = preload("res://scenes/vfx/mech_outline.gdshader")

func set_highlighted(on: bool) -> void:
	# Cleanup any previous highlight visuals (outline meshes + ground ring + tween).
	for ol in find_children("_ol_*", "MeshInstance3D", true, false):
		ol.queue_free()
	if _selection_pulse_tween != null and _selection_pulse_tween.is_valid():
		_selection_pulse_tween.kill()
	_selection_pulse_tween = null
	if is_instance_valid(_selection_ring):
		_selection_ring.queue_free()
	_selection_ring = null
	_selection_ring_mat = null
	if not on:
		return
	# Thick hot-pink outline on each mesh — parented to the mesh so it inherits bob/lean.
	for i in _mesh_instances.size():
		var src := _mesh_instances[i]
		if not is_instance_valid(src):
			continue
		var ol := MeshInstance3D.new()
		ol.name = "_ol_%d" % i
		ol.mesh = src.mesh
		ol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := ShaderMaterial.new()
		sm.shader = OUTLINE_SHADER
		sm.set_shader_parameter("outline_color", UITheme.COLOR_ACCENT_HOT)
		# Larger than the permanent black outline (0.08) by a wide margin so the
		# pink ring sits clearly OUTSIDE the black. Depth + cull_front keep the
		# black ring visible at the inner band (closer to camera at the mesh
		# silhouette) while the pink shows in the outer band.
		sm.set_shader_parameter("outline_size", 0.34)
		ol.material_override = sm
		src.add_child(ol)
		ol.transform = Transform3D.IDENTITY
	# Ground selection ring — pinned at the mech's feet (doesn't bob with the
	# body), so it acts as a stable RTS-style anchor showing exactly which mech
	# is currently the action target.
	_selection_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius  = 1.55
	torus.outer_radius  = 1.95
	torus.rings         = 48
	torus.ring_segments = 8
	_selection_ring.mesh = torus
	_selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_ring_mat = StandardMaterial3D.new()
	_selection_ring_mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_ring_mat.albedo_color               = UITheme.COLOR_ACCENT_HOT
	_selection_ring_mat.emission_enabled           = true
	_selection_ring_mat.emission                   = UITheme.COLOR_ACCENT_HOT
	_selection_ring_mat.emission_energy_multiplier = 5.0
	_selection_ring_mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	_selection_ring.material_override = _selection_ring_mat
	_selection_ring.position = Vector3(0.0, 0.06, 0.0)
	add_child(_selection_ring)
	# Loop pulse on scale + emission so the ring breathes.
	_selection_pulse_tween = create_tween().set_loops()
	_selection_pulse_tween.tween_property(_selection_ring, "scale", Vector3(1.18, 1.0, 1.18), 0.45) \
		.set_trans(Tween.TRANS_SINE)
	_selection_pulse_tween.parallel().tween_property(_selection_ring_mat, "emission_energy_multiplier", 9.0, 0.45) \
		.set_trans(Tween.TRANS_SINE)
	_selection_pulse_tween.tween_property(_selection_ring, "scale", Vector3.ONE, 0.45) \
		.set_trans(Tween.TRANS_SINE)
	_selection_pulse_tween.parallel().tween_property(_selection_ring_mat, "emission_energy_multiplier", 4.0, 0.45) \
		.set_trans(Tween.TRANS_SINE)

static var _shadow_tex: GradientTexture2D

func _add_shadow_decal(width: float, depth: float, char_height: float) -> void:
	const SUN_Y_DEG := 42.0
	const SUN_ELEV  := 38.0
	var offset_dist := char_height / tan(deg_to_rad(SUN_ELEV)) * 0.28
	var shadow_dir  := Vector3(-sin(deg_to_rad(SUN_Y_DEG)), 0.0, -cos(deg_to_rad(SUN_Y_DEG)))

	# Build shared radial gradient texture once
	if _shadow_tex == null:
		var grad := Gradient.new()
		grad.add_point(0.0, Color(0.0, 0.0, 0.0, 0.7))
		grad.add_point(1.0, Color(0.0, 0.0, 0.0, 0.0))
		_shadow_tex = GradientTexture2D.new()
		_shadow_tex.gradient = grad
		_shadow_tex.fill = GradientTexture2D.FILL_RADIAL
		_shadow_tex.fill_from = Vector2(0.5, 0.5)
		_shadow_tex.fill_to   = Vector2(1.0, 0.5)
		_shadow_tex.width  = 128
		_shadow_tex.height = 128

	var decal := Decal.new()
	decal.texture_albedo = _shadow_tex
	decal.size           = Vector3(width, 6.0, depth)  # tall enough to reach ground from above
	decal.albedo_mix     = 0.8
	decal.position       = shadow_dir * offset_dist + Vector3(0.0, 3.0, 0.0)
	decal.rotation.y     = -deg_to_rad(SUN_Y_DEG)
	add_child(decal)

func _add_blob_shadow(radius: float, char_height: float) -> void:
	# Sun: rotation_degrees(-52, 42, 0) → 38° above horizon, 42° Y
	const SUN_Y_DEG  := 42.0
	const SUN_ELEV   := 38.0  # degrees above horizon
	var shadow_len   := char_height / tan(deg_to_rad(SUN_ELEV))
	var shadow_dir   := Vector3(-sin(deg_to_rad(SUN_Y_DEG)), 0.0, -cos(deg_to_rad(SUN_Y_DEG)))

	var disc := MeshInstance3D.new()
	var cyl  := CylinderMesh.new()
	cyl.top_radius    = radius
	cyl.bottom_radius = radius
	cyl.height        = 0.01
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Offset along shadow direction, stretched in that axis
	disc.position   = shadow_dir * shadow_len * 0.16 + Vector3(0.0, 0.02, 0.0)
	disc.rotation.y = -deg_to_rad(SUN_Y_DEG)
	disc.scale      = Vector3(1.0, 1.0, 1.2)  # slightly elongate along shadow direction
	add_child(disc)

func set_color(color: Color) -> void:
	_base_color = color
	_mesh_instances.clear()
	# Search only inside the Model subtree so shadow/highlight nodes are not affected
	var model := get_node_or_null("Model")
	if model == null:
		return
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.75
		mat.metallic = 0.15
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh_instances.append(mi)
	_add_permanent_outline()

# Permanent dark inverse-hull outline so the mech reads as a clear silhouette
# against busy environment colors. Smaller than the selection outline (0.14) so
# the hot-pink selection still visually overrides it when toggled on.
func _add_permanent_outline() -> void:
	for ol in find_children("_perm_outline", "MeshInstance3D", true, false):
		ol.queue_free()
	for src in _mesh_instances:
		if not is_instance_valid(src) or src.mesh == null:
			continue
		var ol := MeshInstance3D.new()
		ol.name = "_perm_outline"
		ol.mesh = src.mesh
		ol.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sm := ShaderMaterial.new()
		sm.shader = OUTLINE_SHADER
		sm.set_shader_parameter("outline_color", Color(0.0, 0.0, 0.0, 1.0))
		sm.set_shader_parameter("outline_size", 0.08)
		ol.material_override = sm
		src.add_child(ol)
		ol.transform = Transform3D.IDENTITY

func _on_died() -> void:
	is_alive = false
	ability_active = false
	# Stop being targeted as an ally / aura source. Joining mech_corpses lets
	# alive mechs detect us as something to jump over.
	if is_in_group("mechs"):
		remove_from_group("mechs")
	add_to_group("mech_corpses")

	# Gray out the body so the corpse reads as inert.
	for mi in _mesh_instances:
		if is_instance_valid(mi) and mi.material_override:
			var mat := mi.material_override as StandardMaterial3D
			mat.albedo_color = Color(0.35, 0.35, 0.35)
			mat.metallic = 0.1
			mat.roughness = 1.0

	# Hide the HP bar; freeze the weapon so it stops firing from a corpse.
	if is_instance_valid(_health_bar):
		_health_bar.visible = false
	if weapon != null and is_instance_valid(weapon):
		weapon.process_mode = Node.PROCESS_MODE_DISABLED

	# Fall forward — model.rotation.x toward -PI/2 tips the head along the
	# march direction. Quad ease-in for a "stiff slap" landing.
	var model := get_node_or_null("Model")
	if model != null:
		model.position.y = _model_base_y   # reset bob offset before the fall
		var fall := create_tween()
		fall.tween_property(model, "rotation:x", -PI * 0.5, FALL_DURATION) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Self-cleanup after the linger window so the line has time to walk over.
	var t := get_tree().create_timer(CORPSE_LINGER)
	t.timeout.connect(queue_free)

# Returns extra Y offset for the model so the mech arcs over any nearby corpse
# in its march path. Parabolic — peak when directly over the corpse, zero
# outside ±JUMP_WINDOW.
func _compute_jump_offset() -> float:
	var best_h := 0.0
	for c in get_tree().get_nodes_in_group("mech_corpses"):
		if not is_instance_valid(c) or c == self:
			continue
		var dz: float = global_position.z - (c as Node3D).global_position.z
		if absf(dz) > JUMP_WINDOW:
			continue
		if absf(global_position.x - (c as Node3D).global_position.x) > JUMP_LANE_TOL:
			continue
		var t := dz / JUMP_WINDOW
		var h := JUMP_HEIGHT * (1.0 - t * t)
		if h > best_h:
			best_h = h
	return best_h
