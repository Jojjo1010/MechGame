extends CanvasLayer

# Floating "LEFT CLICK" prompt that follows the drone in screen space while a
# weapon is in an aim/mark mode (GUN cone aim, ROCKET strike marker). Tells the
# player how to commit the action without overlapping the world-space aim VFX.

const VERT_OFFSET   := -72.0   # pixels above the drone's projected position
const FADE_TIME     := 0.15
const PANEL_PAD_H   := 12.0
const PANEL_PAD_V   := 6.0
const ROW_SEP       := 8
const ICON_SIZE     := Vector2(20.0, 30.0)

var _root:        Control
var _panel:       PanelContainer
var _drone:       Node3D = null
var _camera:      Camera3D = null
var _fade_tween:  Tween
var _shown:       bool = false

func setup(drone: Node3D, cam: Camera3D) -> void:
	_drone = drone
	_camera = cam

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.panel_stylebox()
	sb.set_corner_radius_all(12)
	sb.content_margin_left   = PANEL_PAD_H
	sb.content_margin_right  = PANEL_PAD_H
	sb.content_margin_top    = PANEL_PAD_V
	sb.content_margin_bottom = PANEL_PAD_V
	_panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	# Mouse glyph tinted hot pink (commit/action color) — same icon class the
	# ControlsLegend uses, kept consistent so the player learns one visual.
	var mouse := MouseIcon.new()
	mouse.custom_minimum_size = ICON_SIZE
	mouse.body_color = UITheme.COLOR_ACCENT_HOT
	mouse.accent     = UITheme.COLOR_ACCENT_HOT
	mouse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mouse)

	var lbl := Label.new()
	lbl.text = "LEFT CLICK"
	UITheme.style_label_caps(lbl, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_TEXT_PRIMARY)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	_root.modulate.a = 0.0
	_root.visible    = false

func _process(_delta: float) -> void:
	if not _shown or _drone == null or _camera == null:
		return
	if not is_instance_valid(_drone) or not is_instance_valid(_camera):
		return
	var screen_pos: Vector2 = _camera.unproject_position(_drone.global_position)
	var sz: Vector2 = _panel.size
	_panel.position = Vector2(screen_pos.x - sz.x * 0.5, screen_pos.y + VERT_OFFSET)

func set_hint_visible(on: bool) -> void:
	if _shown == on or _root == null:
		return
	_shown = on
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	if on:
		_root.visible = true
		_fade_tween.tween_property(_root, "modulate:a", 1.0, FADE_TIME)
	else:
		_fade_tween.tween_property(_root, "modulate:a", 0.0, FADE_TIME)
		_fade_tween.tween_callback(func() -> void:
			if is_instance_valid(_root):
				_root.visible = false)
