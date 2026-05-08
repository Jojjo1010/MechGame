extends Control

# Reusable mech portrait. The rectangular frame stays at the panel size; the
# baked mech texture is taller and extends above the frame so the head pops
# out into the surrounding area. Frozen single-frame render — never animates.
# Cached per (bake_w, bake_h, weapon_name) for the session — different
# archetypes get different models, so the cache key has to include weapon.
#
# The model + tint colour are looked up from MechArchetypes — pass the
# weapon name and the right mech shape and tint follow automatically.

# Pop-out mode: texture is rendered LARGER than the layout footprint and
# bottom-centered so the head extends above and shoulders to the sides.
# pop_out=false renders the mech inside the layout with no overflow — used
# for the picker's "stage" view where the panel already gives the mech room.
const POP_HEIGHT_RATIO := 1.9
const POP_WIDTH_RATIO  := 1.35

static var _cache: Dictionary = {}

var _weapon_name: String = "GUN"
var _mech_color:  Color  = Color.WHITE
var _size_px:     float  = 96.0
var _border_w:    float  = 4.0
var _pop_out:     bool   = true
# Default 90° matches the original behavior — mech front (+X authored) rotates
# to face the camera. Pass 0.0 for a side profile with front pointing +X
# (screen right), 180.0 for front pointing -X (screen left).
var _facing_deg:  float  = 90.0
var _frame:        PanelContainer = null
var _style:        StyleBoxFlat = null
var _texture_rect: TextureRect = null

# `weapon_name` is the only identity hook — model and tint are pulled from
# MechArchetypes so swapping a model in one place updates every portrait.
func setup(weapon_name: String, size_px: float, border_w: float = 4.0, pop_out: bool = true, facing_deg: float = 90.0) -> void:
	_weapon_name = weapon_name
	_mech_color  = MechArchetypes.color_for(weapon_name)
	_size_px     = size_px
	_border_w    = border_w
	_pop_out     = pop_out
	_facing_deg  = facing_deg
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
	# Cache key includes weapon_name because each archetype has its own model;
	# bake_w / bake_h cover layout variants; facing_deg covers parade vs portrait.
	var key := "%s|%d|%d|%d" % [_weapon_name, bake_w, bake_h, int(round(_facing_deg))]
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

	var mech_visual := MechArchetypes.model_for(_weapon_name).instantiate()
	# Drop any AnimationPlayer/AnimationTree before adding to the tree so
	# autoplay never starts and the skeleton stays at rest pose.
	for ap in mech_visual.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	for at in mech_visual.find_children("*", "AnimationTree", true, false):
		at.queue_free()

	var aabb := _aabb_of(mech_visual)
	if aabb.size.y > 0.0:
		# Scale to 3.6u so a 4u-tall view region has 0.4u of headroom — the
		# Triangle/ARC mech sits taller in its silhouette (pointed crown) and
		# was clipping when scaled to fill the full 4u.
		var s_factor := 3.6 / aabb.size.y
		mech_visual.scale = Vector3.ONE * s_factor
		aabb = _aabb_of(mech_visual)
		mech_visual.position.y = -aabb.position.y
	# Authored front of the FBX is +X (in-game Mech rotates -90° to face -Z, the
	# march direction). Camera looks toward -Z, so 90° puts the front toward
	# the camera; 0° / 180° give side-profile silhouettes.
	mech_visual.rotation_degrees.y = _facing_deg
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

	# Frame the upper portion of the mech (head + body, feet cropped). Mech is
	# 3.6u tall (base at y=0). With FOV 32° and z=7.0 the vertical extent of
	# view is ~4.0u; centering it at y=2.5 means the visible region runs y=0.5
	# to y=4.5 — feet (y=0..0.4) drop off the bottom, head (y=3.6) sits with
	# 0.9u of headroom so the Triangle's crown doesn't clip.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.5, 7.0)
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
