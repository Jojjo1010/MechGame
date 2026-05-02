extends Node3D

enum Type { XP, GOLD, XP_BIG, XP_HUGE, GOLD_BIG, GOLD_HUGE }

const ATTRACT_RADIUS := 5.5   # drone starts pulling the pickup in
const COLLECT_RADIUS := 0.9   # actually collected
const FLY_SPEED      := 10.0
const BOB_SPEED      := 2.2
const BOB_AMP        := 0.18

# XP gem tier values, in ascending order. queue_xp() pays out a pile as the
# fewest sprites possible by greedy-decomposing into HUGE → BIG → SMALL.
const XP_HUGE_VAL := 50
const XP_BIG_VAL  := 10

# Gold tier values. Smaller than XP because per-kill gold drops are smaller
# (1 from a normal kill, 3 from an elite); 25 / 5 / 1 lets the BIG and HUGE
# tiers actually appear in clusters of just a few elite kills.
const GOLD_HUGE_VAL := 25
const GOLD_BIG_VAL  := 5

# Spatial bucket for queue_xp / queue_gold consolidation. Kills within this
# radius collapse into one pile; cross-screen kills stay separate.
const _PICKUP_BUCKET_SIZE := 3.0
const _PICKUP_FLUSH_DELAY := 0.10

var type:  Type = Type.XP
var value: int  = 1

var _drone:     Node3D = null
var _base_y:    float  = 0.0
var _age:       float  = 0.0
var _attracted: bool   = false

# Procedural pixel-art textures for the pickup sprites. Built once on first
# request and reused — pickups pile up by the dozens at high waves and
# re-baking the image per pickup is wasted work.
static var _xp_texture:        ImageTexture = null
static var _xp_big_texture:    ImageTexture = null
static var _xp_huge_texture:   ImageTexture = null
static var _gold_texture:      ImageTexture = null
static var _gold_big_texture:  ImageTexture = null
static var _gold_huge_texture: ImageTexture = null

# queue_xp / queue_gold accumulators. Entries shape: { value: int,
# weighted_pos: Vector3, weight: float, parent: Node }. Keyed by integer grid
# cell so simultaneous kills in different parts of the field don't collapse
# into one pile.
static var _xp_pending:           Dictionary = {}
static var _xp_flush_scheduled:   bool       = false
static var _gold_pending:         Dictionary = {}
static var _gold_flush_scheduled: bool       = false

static func spawn(p_type: Type, p_value: int, world_pos: Vector3, parent: Node) -> void:
	var inst := Node3D.new()
	inst.set_script(load("res://scenes/pickups/Pickup.gd"))
	inst.set_meta("_ptype",  p_type)
	inst.set_meta("_pvalue", p_value)
	inst.set_meta("_pos",    world_pos)  # position set inside _ready before _base_y is captured
	parent.add_child(inst)

# Drop-in replacement for `spawn(Type.XP, ...)` that batches kills happening
# within _XP_FLUSH_DELAY into the fewest gem sprites possible. Late-game AOE
# clears used to spawn N small gems (one per kill) — this collapses each
# spatial cluster into a HUGE/BIG/SMALL pile. The flush runs on a single
# SceneTreeTimer per window, regardless of how many enemies queued during it.
static func queue_xp(amount: int, world_pos: Vector3, parent: Node) -> void:
	if amount <= 0 or parent == null:
		return
	var key := Vector3i(
		roundi(world_pos.x / _PICKUP_BUCKET_SIZE),
		roundi(world_pos.y / _PICKUP_BUCKET_SIZE),
		roundi(world_pos.z / _PICKUP_BUCKET_SIZE)
	)
	var bucket: Dictionary
	if _xp_pending.has(key):
		bucket = _xp_pending[key]
	else:
		bucket = {"value": 0, "weighted_pos": Vector3.ZERO, "weight": 0.0, "parent": parent}
		_xp_pending[key] = bucket
	bucket["value"]        = int(bucket["value"]) + amount
	bucket["weighted_pos"] = (bucket["weighted_pos"] as Vector3) + world_pos * float(amount)
	bucket["weight"]       = float(bucket["weight"]) + float(amount)
	bucket["parent"]       = parent
	if not _xp_flush_scheduled:
		_xp_flush_scheduled = true
		var tree := parent.get_tree()
		if tree == null:
			# No tree (parent was already detached); flush synchronously rather
			# than leaking the queued XP forever.
			_flush_xp()
			return
		tree.create_timer(_PICKUP_FLUSH_DELAY).timeout.connect(_flush_xp)

static func _flush_xp() -> void:
	var snapshot: Dictionary = _xp_pending
	_xp_pending = {}
	_xp_flush_scheduled = false
	for key in snapshot:
		var bucket: Dictionary = snapshot[key]
		var parent: Node = bucket.get("parent")
		if parent == null or not is_instance_valid(parent):
			continue
		var weight: float = float(bucket["weight"])
		if weight <= 0.0:
			continue
		var center: Vector3 = (bucket["weighted_pos"] as Vector3) / weight
		_spawn_xp_pile(int(bucket["value"]), center, parent)

# Greedy decompose into HUGE → BIG → SMALL. SMALL absorbs the remainder as a
# single variable-value gem (it already supports any 1+ value), so a 47-XP
# pile is 4 BIG (40) + 1 SMALL (7), not 7 individual SMALLs.
static func _spawn_xp_pile(value: int, center: Vector3, parent: Node) -> void:
	if value <= 0:
		return
	var huge_count: int = value / XP_HUGE_VAL
	var rem: int        = value - huge_count * XP_HUGE_VAL
	var big_count: int  = rem / XP_BIG_VAL
	rem                -= big_count * XP_BIG_VAL
	for i in huge_count:
		var off := Vector3(randf_range(-1.4, 1.4), 0.5, randf_range(-1.4, 1.4))
		spawn(Type.XP_HUGE, XP_HUGE_VAL, center + off, parent)
	for i in big_count:
		var off := Vector3(randf_range(-1.2, 1.2), 0.5, randf_range(-1.2, 1.2))
		spawn(Type.XP_BIG, XP_BIG_VAL, center + off, parent)
	if rem > 0:
		var off := Vector3(randf_range(-0.8, 0.8), 0.5, randf_range(-0.8, 0.8))
		spawn(Type.XP, rem, center + off, parent)

# queue_gold mirrors queue_xp — separate pending dict so XP and gold piles
# don't collide in the same spatial bucket. Same flush-delay semantics:
# 100 ms after the first push, all queued gold from this window pays out
# at the bucket's weighted center.
static func queue_gold(amount: int, world_pos: Vector3, parent: Node) -> void:
	if amount <= 0 or parent == null:
		return
	var key := Vector3i(
		roundi(world_pos.x / _PICKUP_BUCKET_SIZE),
		roundi(world_pos.y / _PICKUP_BUCKET_SIZE),
		roundi(world_pos.z / _PICKUP_BUCKET_SIZE)
	)
	var bucket: Dictionary
	if _gold_pending.has(key):
		bucket = _gold_pending[key]
	else:
		bucket = {"value": 0, "weighted_pos": Vector3.ZERO, "weight": 0.0, "parent": parent}
		_gold_pending[key] = bucket
	bucket["value"]        = int(bucket["value"]) + amount
	bucket["weighted_pos"] = (bucket["weighted_pos"] as Vector3) + world_pos * float(amount)
	bucket["weight"]       = float(bucket["weight"]) + float(amount)
	bucket["parent"]       = parent
	if not _gold_flush_scheduled:
		_gold_flush_scheduled = true
		var tree := parent.get_tree()
		if tree == null:
			_flush_gold()
			return
		tree.create_timer(_PICKUP_FLUSH_DELAY).timeout.connect(_flush_gold)

static func _flush_gold() -> void:
	var snapshot: Dictionary = _gold_pending
	_gold_pending = {}
	_gold_flush_scheduled = false
	for key in snapshot:
		var bucket: Dictionary = snapshot[key]
		var parent: Node = bucket.get("parent")
		if parent == null or not is_instance_valid(parent):
			continue
		var weight: float = float(bucket["weight"])
		if weight <= 0.0:
			continue
		var center: Vector3 = (bucket["weighted_pos"] as Vector3) / weight
		_spawn_gold_pile(int(bucket["value"]), center, parent)

# Same greedy decompose pattern as XP, just with gold tier values.
static func _spawn_gold_pile(value: int, center: Vector3, parent: Node) -> void:
	if value <= 0:
		return
	var huge_count: int = value / GOLD_HUGE_VAL
	var rem: int        = value - huge_count * GOLD_HUGE_VAL
	var big_count: int  = rem / GOLD_BIG_VAL
	rem                -= big_count * GOLD_BIG_VAL
	for i in huge_count:
		var off := Vector3(randf_range(-1.4, 1.4), 0.5, randf_range(-1.4, 1.4))
		spawn(Type.GOLD_HUGE, GOLD_HUGE_VAL, center + off, parent)
	for i in big_count:
		var off := Vector3(randf_range(-1.2, 1.2), 0.5, randf_range(-1.2, 1.2))
		spawn(Type.GOLD_BIG, GOLD_BIG_VAL, center + off, parent)
	if rem > 0:
		var off := Vector3(randf_range(-0.8, 0.8), 0.5, randf_range(-0.8, 0.8))
		spawn(Type.GOLD, rem, center + off, parent)

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
	elif type == Type.XP_HUGE:
		_build_xp_huge_sprite()
	elif type == Type.GOLD_BIG:
		_build_gold_big_sprite()
	elif type == Type.GOLD_HUGE:
		_build_gold_huge_sprite()
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

func _build_xp_huge_sprite() -> void:
	if _xp_huge_texture == null:
		_xp_huge_texture = _make_xp_huge_texture()
	var sprite := Sprite3D.new()
	sprite.texture        = _xp_huge_texture
	# Bigger again than XP_BIG so a HUGE gem reads as the premium drop at a
	# glance even when sitting next to BIG / SMALL piles.
	sprite.pixel_size     = 0.058
	sprite.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded         = false
	sprite.alpha_cut      = SpriteBase3D.ALPHA_CUT_DISCARD
	# Cyan modulate, pushed into HDR so bloom catches it. Distinct from the
	# purple SMALL/BIG tier so the player can spot HUGEs in a pickup pile.
	sprite.modulate       = Color(1.4, 2.4, 3.0, 1.0)
	add_child(sprite)

# 20×24 cyan diamond, three sparkles. Same Manhattan-distance profile as the
# smaller gems so the silhouette family reads consistently — only the size and
# hue change between tiers.
static func _make_xp_huge_texture() -> ImageTexture:
	const W: int = 20
	const H: int = 24
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx: float = float(W - 1) * 0.5
	var cy: float = float(H - 1) * 0.5
	var rx: float = cx
	var ry: float = cy

	var c_outline := Color(0.0,  0.20, 0.32, 1.0)
	var c_body    := Color(0.30, 0.85, 1.00, 1.0)
	var c_light   := Color(0.85, 1.00, 1.00, 1.0)

	for y in H:
		for x in W:
			var nx: float = abs(float(x) - cx) / rx
			var ny: float = abs(float(y) - cy) / ry
			var d: float  = nx + ny
			if d > 1.0:
				continue
			if d > 0.85:
				img.set_pixel(x, y, c_outline)
			elif x <= int(cx) and y <= int(cy):
				img.set_pixel(x, y, c_light)
			else:
				img.set_pixel(x, y, c_body)

	# Three sparkles — the hierarchy across tiers is 1 / 2 / 3, so HUGE reads as
	# the biggest payday on the floor.
	img.set_pixel(int(cx) - 4, int(cy) - 5, Color(1.0, 1.0, 1.0, 1.0))
	img.set_pixel(int(cx) - 2, int(cy) - 3, Color(1.0, 1.0, 1.0, 1.0))
	img.set_pixel(int(cx) + 1, int(cy) - 1, Color(1.0, 1.0, 1.0, 1.0))
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

func _build_gold_big_sprite() -> void:
	if _gold_big_texture == null:
		_gold_big_texture = _make_gold_big_texture()
	var sprite := Sprite3D.new()
	sprite.texture        = _gold_big_texture
	sprite.pixel_size     = 0.048
	sprite.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded         = false
	sprite.alpha_cut      = SpriteBase3D.ALPHA_CUT_DISCARD
	# Brighter amber than SMALL — same hue family, but pushed higher into HDR
	# so a stack of BIG coins reads distinctly hotter than a stack of smalls.
	sprite.modulate       = Color(2.1, 1.6, 0.7, 1.0)
	add_child(sprite)

# 16×16 fat coin: same Euclidean-circle profile as SMALL, two sparkles.
static func _make_gold_big_texture() -> ImageTexture:
	const W: int = 16
	const H: int = 16
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx: float = float(W - 1) * 0.5
	var cy: float = float(H - 1) * 0.5
	var r:  float = float(W) * 0.5

	var c_outline := Color(0.45, 0.20, 0.0,  1.0)
	var c_body    := Color(1.00, 0.82, 0.14, 1.0)
	var c_light   := Color(1.00, 0.97, 0.65, 1.0)

	for y in H:
		for x in W:
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			var d:  float = sqrt(dx * dx + dy * dy) / r
			if d > 1.0:
				continue
			if d > 0.82:
				img.set_pixel(x, y, c_outline)
			elif x <= int(cx) and y <= int(cy):
				img.set_pixel(x, y, c_light)
			else:
				img.set_pixel(x, y, c_body)

	img.set_pixel(int(cx) - 3, int(cy) - 3, Color(1.0, 1.0, 1.0, 1.0))
	img.set_pixel(int(cx) - 1, int(cy) - 1, Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)

func _build_gold_huge_sprite() -> void:
	if _gold_huge_texture == null:
		_gold_huge_texture = _make_gold_huge_texture()
	var sprite := Sprite3D.new()
	sprite.texture        = _gold_huge_texture
	sprite.pixel_size     = 0.058
	sprite.billboard      = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded         = false
	sprite.alpha_cut      = SpriteBase3D.ALPHA_CUT_DISCARD
	# Hot copper-orange modulate. Same logic as XP_HUGE going cyan from the
	# purple smalls — the HUGE tier needs its own hue so it pops out of a
	# pile of regular gold without relying on size alone.
	sprite.modulate       = Color(2.6, 1.5, 0.5, 1.0)
	add_child(sprite)

# 20×20 large coin in a richer copper-orange palette, three sparkles.
static func _make_gold_huge_texture() -> ImageTexture:
	const W: int = 20
	const H: int = 20
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx: float = float(W - 1) * 0.5
	var cy: float = float(H - 1) * 0.5
	var r:  float = float(W) * 0.5

	var c_outline := Color(0.50, 0.18, 0.0,  1.0)
	var c_body    := Color(1.00, 0.58, 0.16, 1.0)
	var c_light   := Color(1.00, 0.88, 0.45, 1.0)

	for y in H:
		for x in W:
			var dx: float = float(x) - cx
			var dy: float = float(y) - cy
			var d:  float = sqrt(dx * dx + dy * dy) / r
			if d > 1.0:
				continue
			if d > 0.85:
				img.set_pixel(x, y, c_outline)
			elif x <= int(cx) and y <= int(cy):
				img.set_pixel(x, y, c_light)
			else:
				img.set_pixel(x, y, c_body)

	img.set_pixel(int(cx) - 4, int(cy) - 4, Color(1.0, 1.0, 1.0, 1.0))
	img.set_pixel(int(cx) - 2, int(cy) - 2, Color(1.0, 1.0, 1.0, 1.0))
	img.set_pixel(int(cx) + 1, int(cy) - 1, Color(1.0, 1.0, 1.0, 1.0))
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
	if type == Type.XP or type == Type.XP_BIG or type == Type.XP_HUGE:
		RunManager.add_xp(value)
		AudioManager.play("xp_collect", global_position, -8.0, randf_range(0.95, 1.1))
	else:
		# All GOLD_* tiers fall through here.
		RunManager.add_gold(value)
		AudioManager.play("gold_collect", global_position, -6.0)
	queue_free()
