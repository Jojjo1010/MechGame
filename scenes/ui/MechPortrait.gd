extends PanelContainer

# Reusable mech portrait. Bakes a single rendered frame of the CongaGoober
# mech (tinted with the archetype color) into an ImageTexture and displays it
# as a static TextureRect — guaranteed never to animate. Cached per (size,
# color) for the session.

const MECH_MODEL := preload("res://assets/CongaGoober.fbx")

static var _cache: Dictionary = {}

var _mech_color: Color = Color.WHITE
var _size_px:    float = 96.0
var _border_w:   float = 4.0
var _texture_rect: TextureRect = null
var _style:        StyleBoxFlat = null

func setup(color: Color, size_px: float, border_w: float = 4.0) -> void:
	_mech_color = color
	_size_px    = size_px
	_border_w   = border_w
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_style = StyleBoxFlat.new()
	_style.bg_color = UITheme.COLOR_PANEL
	_style.set_corner_radius_all(8)
	_style.set_border_width_all(int(_border_w))
	_style.border_color = UITheme.COLOR_DEEP
	add_theme_stylebox_override("panel", _style)

	_texture_rect = TextureRect.new()
	_texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_texture_rect)

	var inner_px := int(_size_px - _border_w * 2.0)
	var key := "%d|%s" % [inner_px, _mech_color.to_html(false)]
	if _cache.has(key):
		_texture_rect.texture = _cache[key]
	else:
		_bake(inner_px, key)

# Tweak the panel's border color/width — used by the picker to highlight the
# rolled target during the slot-machine animation.
func set_highlight(border_color: Color, width: int = 4) -> void:
	if _style == null:
		return
	_style.border_color = border_color
	_style.set_border_width_all(width)

func _bake(px: int, cache_key: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
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
	mech_visual.rotation_degrees.y = 180.0
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

	# Eye-level on the head/upper body. Mech is ~4 units tall with its base
	# at y=0; face sits around y≈3.2.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.2, 2.4)
	cam.rotation_degrees.x = 0.0
	cam.fov = 28.0
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

func _aabb_of(node: Node) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a := mi.transform * mi.get_aabb()
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result
