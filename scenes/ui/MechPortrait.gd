extends Control

# Reusable mech portrait. The rectangular frame stays at the panel size; the
# baked mech texture is taller and extends above the frame so the head pops
# out into the surrounding area. Frozen single-frame render — never animates.
# Cached per (bake_w, bake_h, color) for the session.

const MECH_MODEL := preload("res://assets/CongaGoober.fbx")

# Pop-out mode: texture is rendered LARGER than the layout footprint and
# bottom-centered so the head extends above and shoulders to the sides.
# pop_out=false renders the mech inside the layout with no overflow — used
# for the picker's "stage" view where the panel already gives the mech room.
const POP_HEIGHT_RATIO := 1.9
const POP_WIDTH_RATIO  := 1.35

static var _cache: Dictionary = {}

var _mech_color: Color = Color.WHITE
var _size_px:    float = 96.0
var _border_w:   float = 4.0
var _pop_out:    bool  = true
var _frame:        PanelContainer = null
var _style:        StyleBoxFlat = null
var _texture_rect: TextureRect = null

func setup(color: Color, size_px: float, border_w: float = 4.0, pop_out: bool = true) -> void:
	_mech_color = color
	_size_px    = size_px
	_border_w   = border_w
	_pop_out    = pop_out
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

func _ready() -> void:
	# Frame: invisible by default — only used by set_highlight() so the picker
	# can ring the rolled portrait. UltBar never highlights, so it shows the
	# mech with no rectangle behind.
	_frame = PanelContainer.new()
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0, 0, 0, 0)
	_style.set_corner_radius_all(8)
	_style.set_border_width_all(0)
	_style.border_color = Color(0, 0, 0, 0)
	_frame.add_theme_stylebox_override("panel", _style)
	add_child(_frame)

	# Texture sizing. Pop-out: bigger than the layout footprint, bottom-centered
	# so the head extends above. Non-pop-out: same as layout, mech fully inside.
	var w_ratio: float = POP_WIDTH_RATIO if _pop_out else 1.0
	var h_ratio: float = POP_HEIGHT_RATIO if _pop_out else 1.0
	var tex_w := _size_px * w_ratio
	var tex_h := _size_px * h_ratio
	_texture_rect = TextureRect.new()
	_texture_rect.size      = Vector2(tex_w, tex_h)
	_texture_rect.position  = Vector2((_size_px - tex_w) * 0.5, _size_px - tex_h)
	_texture_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_texture_rect)

	var bake_w := int(tex_w)
	var bake_h := int(tex_h)
	var key := "%d|%d|%s" % [bake_w, bake_h, _mech_color.to_html(false)]
	if _cache.has(key):
		_texture_rect.texture = _cache[key]
	else:
		_bake(bake_w, bake_h, key)

# Tweak the frame's border color/width — used by the picker to highlight the
# rolled target during the slot-machine animation.
func set_highlight(border_color: Color, width: int = 4) -> void:
	if _style == null:
		return
	_style.border_color = border_color
	_style.set_border_width_all(width)

func _bake(bake_w: int, bake_h: int, cache_key: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(bake_w, bake_h)
	vp.transparent_bg = true
	vp.handle_input_locally = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.own_world_3d = true
	add_child(vp)

	var mech_visual := MECH_MODEL.instantiate()
	# Drop any AnimationPlayer/AnimationTree before adding to the tree so
	# autoplay never starts and the skeleton stays at rest pose.
	for ap in mech_visual.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	for at in mech_visual.find_children("*", "AnimationTree", true, false):
		at.queue_free()

	var aabb := _aabb_of(mech_visual)
	if aabb.size.y > 0.0:
		var s_factor := 4.0 / aabb.size.y
		mech_visual.scale = Vector3.ONE * s_factor
		aabb = _aabb_of(mech_visual)
		mech_visual.position.y = -aabb.position.y
	# Authored front of the FBX is +X (in-game Mech rotates -90° to face -Z, the
	# march direction). Camera looks toward -Z, so we want +X → +Z, i.e. +90°.
	mech_visual.rotation_degrees.y = 90.0
	vp.add_child(mech_visual)

	# Tint with the archetype color — same params as Mech.set_color() so the
	# portrait reads as the same mech as the in-game one.
	for child in mech_visual.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _mech_color
		mat.roughness    = 0.75
		mat.metallic     = 0.15
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Single soft key light from upper-front-right.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25.0, 35.0, 0.0)
	light.light_energy = 1.0
	vp.add_child(light)

	# Frame the whole mech vertically (head at top, body filling middle, base
	# near bottom). Mech is 4u tall, base at y=0. With FOV 32° and z=7.0, the
	# vertical extent of view is 2*7*tan(16°) ≈ 4.0u — perfect fit.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.0, 7.0)
	cam.rotation_degrees.x = 0.0
	cam.fov = 32.0
	cam.current = true
	vp.add_child(cam)

	# Wait two frames so the viewport's UPDATE_ONCE has actually rendered.
	await get_tree().process_frame
	await get_tree().process_frame
	var img := vp.get_texture().get_image()
	var tex := ImageTexture.create_from_image(img)
	vp.queue_free()

	_cache[cache_key] = tex
	if is_instance_valid(_texture_rect):
		_texture_rect.texture = tex

func _aabb_of(root: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
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
