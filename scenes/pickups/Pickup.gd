extends Node3D

enum Type { XP, GOLD, XP_BIG }

const ATTRACT_RADIUS := 5.5   # drone starts pulling the pickup in
const COLLECT_RADIUS := 0.9   # actually collected
const FLY_SPEED      := 10.0
const BOB_SPEED      := 2.2
const BOB_AMP        := 0.18

var type:  Type = Type.XP
var value: int  = 1

var _drone:     Node3D = null
var _base_y:    float  = 0.0
var _age:       float  = 0.0
var _attracted: bool   = false

# Procedural pixel-art textures for the pickup sprites. Built once on first
# request and reused — pickups pile up by the dozens at high waves and
# re-baking the image per pickup is wasted work.
static var _xp_texture:     ImageTexture = null
static var _xp_big_texture: ImageTexture = null
static var _gold_texture:   ImageTexture = null

static func spawn(p_type: Type, p_value: int, world_pos: Vector3, parent: Node) -> void:
	var inst := Node3D.new()
	inst.set_script(load("res://scenes/pickups/Pickup.gd"))
	inst.set_meta("_ptype",  p_type)
	inst.set_meta("_pvalue", p_value)
	inst.set_meta("_pos",    world_pos)  # position set inside _ready before _base_y is captured
	parent.add_child(inst)

func _ready() -> void:
	add_to_group("pickups")
	type  = get_meta("_ptype",  Type.XP)
	value = get_meta("_pvalue", 1)
	# Apply position now so _base_y is captured correctly
	var spawn_pos: Vector3 = get_meta("_pos", Vector3.ZERO)
	global_position = spawn_pos
	_base_y = spawn_pos.y
	_build_mesh()
	_add_blob_shadow()
	var drones := get_tree().get_nodes_in_group("drones")
	if not drones.is_empty():
		_drone = drones[0] as Node3D

func _add_blob_shadow() -> void:
	var disc := MeshInstance3D.new()
	var cyl  := CylinderMesh.new()
	cyl.top_radius    = 0.28
	cyl.bottom_radius = 0.28
	cyl.height        = 0.01
	disc.mesh        = cyl
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.40)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	# Offset downward so the disc sits on the ground regardless of spawn height
	disc.position = Vector3(0.0, -_base_y + 0.02, 0.0)
	add_child(disc)

func _build_mesh() -> void:
	if type == Type.XP:
		_build_xp_sprite()
	elif type == Type.XP_BIG:
		_build_xp_big_sprite()
	else:
		_build_gold_sprite()

	# No OmniLight: pickups accumulate uncollected on the ground at higher
	# waves, and Forward+ cluster cost scales with active light count. The
	# unshaded sprite gives them their visible glow.

func _build_xp_sprite() -> void:
	if _xp_texture == null:
		_xp_texture = _make_xp_texture()
	var sprite := Sprite3D.new()
	sprite.texture        = _xp_texture
	sprite.pixel_size     = 0.040
	sprite.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded         = false
	# ALPHA_CUT_DISCARD gives crisp pixel-art edges and lets the sprite write
	# depth properly so it sorts cleanly against other geometry.
	sprite.alpha_cut      = SpriteBase3D.ALPHA_CUT_DISCARD
	# HDR modulate pushes the bright purple past the bloom threshold so it
	# glows the way the old emissive 3D mesh did.
	sprite.modulate       = Color(1.6, 1.3, 2.0, 1.0)
	add_child(sprite)

# Hand-painted 12×16 diamond gem: outline ring + light highlight in the upper-
# left quadrant + body + a single white sparkle pixel. Generated procedurally
# so the project stays asset-free.
static func _make_xp_texture() -> ImageTexture:
	const W: int = 12
	const H: int = 16
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx: float = float(W - 1) * 0.5
	var cy: float = float(H - 1) * 0.5
	var rx: float = cx
	var ry: float = cy

	var c_outline := Color(0.18, 0.0, 0.28, 1.0)
	var c_body    := Color(0.72, 0.22, 0.98, 1.0)
	var c_light   := Color(0.95, 0.62, 1.00, 1.0)

	for y in H:
		for x in W:
			var nx: float = abs(float(x) - cx) / rx
			var ny: float = abs(float(y) - cy) / ry
			var d: float  = nx + ny
			if d > 1.0:
				continue
			if d > 0.78:
				img.set_pixel(x, y, c_outline)
			elif x <= int(cx) and y <= int(cy):
				img.set_pixel(x, y, c_light)
			else:
				img.set_pixel(x, y, c_body)

	# Single white sparkle in the highlight zone for that gem-shimmer cue
	img.set_pixel(int(cx) - 2, int(cy) - 3, Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)

func _build_xp_big_sprite() -> void:
	if _xp_big_texture == null:
		_xp_big_texture = _make_xp_big_texture()
	var sprite := Sprite3D.new()
	sprite.texture        = _xp_big_texture
	# Bigger world footprint AND brighter modulate so the player can tell at a
	# glance that a big gem is sitting on the ground vs a stack of smalls.
	sprite.pixel_size     = 0.048
	sprite.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded         = false
	sprite.alpha_cut      = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.modulate       = Color(2.4, 1.5, 2.6, 1.0)
	add_child(sprite)

# 16×20 fat diamond — wider, brighter highlight, two sparkles. The big gem
# carries 10 XP at once, so it should read as a noticeable upgrade over the
# small one.
static func _make_xp_big_texture() -> ImageTexture:
	const W: int = 16
	const H: int = 20
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx: float = float(W - 1) * 0.5
	var cy: float = float(H - 1) * 0.5
	var rx: float = cx
	var ry: float = cy

	var c_outline := Color(0.22, 0.0, 0.36, 1.0)
	var c_body    := Color(0.78, 0.30, 1.00, 1.0)
	var c_light   := Color(1.00, 0.78, 1.00, 1.0)

	for y in H:
		for x in W:
			var nx: float = abs(float(x) - cx) / rx
			var ny: float = abs(float(y) - cy) / ry
			var d: float  = nx + ny
			if d > 1.0:
				continue
			if d > 0.82:
				img.set_pixel(x, y, c_outline)
			elif x <= int(cx) and y <= int(cy):
				img.set_pixel(x, y, c_light)
			else:
				img.set_pixel(x, y, c_body)

	# Two sparkles — premium-loot cue.
	img.set_pixel(int(cx) - 3, int(cy) - 4, Color(1.0, 1.0, 1.0, 1.0))
	img.set_pixel(int(cx) - 1, int(cy) - 2, Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)

func _build_gold_sprite() -> void:
	if _gold_texture == null:
		_gold_texture = _make_gold_texture()
	var sprite := Sprite3D.new()
	sprite.texture        = _gold_texture
	sprite.pixel_size     = 0.040
	sprite.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded         = false
	sprite.alpha_cut      = SpriteBase3D.ALPHA_CUT_DISCARD
	# HDR push so the gold body crosses the bloom threshold and reads as a
	# warm, glowing coin rather than a flat sticker.
	sprite.modulate       = Color(1.7, 1.4, 0.7, 1.0)
	add_child(sprite)

# 12×12 round coin: dark amber outline, bright gold body, pale yellow highlight
# in the upper-left, single sparkle pixel. Uses Euclidean distance for a
# circle profile (the XP gem uses Manhattan distance for a diamond profile).
static func _make_gold_texture() -> ImageTexture:
	const W: int = 12
	const H: int = 12
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx: float = float(W - 1) * 0.5
	var cy: float = float(H - 1) * 0.5
	var r:  float = float(W) * 0.5

	var c_outline := Color(0.40, 0.18, 0.0,  1.0)
	var c_body    := Color(1.00, 0.78, 0.10, 1.0)
	var c_light   := Color(1.00, 0.95, 0.55, 1.0)

	for y in H:
		for x in W:
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			var d:  float = sqrt(dx * dx + dy * dy) / r
			if d > 1.0:
				continue
			if d > 0.78:
				img.set_pixel(x, y, c_outline)
			elif x <= int(cx) and y <= int(cy):
				img.set_pixel(x, y, c_light)
			else:
				img.set_pixel(x, y, c_body)

	# Single white sparkle in the highlight zone — same shimmer cue the gem uses.
	img.set_pixel(int(cx) - 2, int(cy) - 2, Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)

func _process(delta: float) -> void:
	_age += delta

	if not is_instance_valid(_drone):
		_bob(delta)
		return

	var dist: float = global_position.distance_to(_drone.global_position)

	if dist < COLLECT_RADIUS:
		_collect()
		return

	# Once a pickup is attracted it *commits* — keeps chasing the drone even
	# if a dash carries them past ATTRACT_RADIUS, so the collect isn't dropped.
	if not _attracted and dist < ATTRACT_RADIUS:
		_attracted = true

	if _attracted:
		var dir := (_drone.global_position - global_position)
		dir.y = 0.0
		dir = dir.normalized()
		# Speed boost for close-range pickups; clamped so post-dash chase still
		# moves at base speed instead of stalling out negative.
		var boost: float = clampf((ATTRACT_RADIUS - dist) / ATTRACT_RADIUS, 0.0, 1.0)
		var speed: float = FLY_SPEED * (1.0 + boost)
		global_position += dir * speed * delta
		global_position.y = lerpf(global_position.y, _drone.global_position.y, 6.0 * delta)
	else:
		_bob(delta)

func _bob(_delta: float) -> void:
	global_position.y = _base_y + sin(_age * BOB_SPEED) * BOB_AMP

func _collect() -> void:
	if type == Type.XP or type == Type.XP_BIG:
		RunManager.add_xp(value)
		AudioManager.play("xp_collect", global_position, -8.0, randf_range(0.95, 1.1))
	else:
		RunManager.add_gold(value)
		AudioManager.play("gold_collect", global_position, -6.0)
	queue_free()
