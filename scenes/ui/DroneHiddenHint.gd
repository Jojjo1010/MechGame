extends CanvasLayer

# Palette duplicated from ControlsLegend so the chip reads as part of the same
# UI family without a cross-file dependency.

const BG_COLOR    := Color(0.0,  0.0,  0.0,  0.65)
const TEXT_COLOR  := Color(1.0,  1.0,  1.0,  0.95)
const CHIP_BG     := Color(0.90, 0.88, 0.80, 1.0)
const CHIP_FG     := Color(0.08, 0.06, 0.04, 1.0)
const ACCENT      := Color(1.0,  0.95, 0.55, 1.0)

const PADDING_X   := 18
const PADDING_Y   := 10
const CHIP_H      := 30.0
const CHIP_PAD_X  := 12.0
const CHIP_FONT   := 18
const TEXT_FONT   := 18

var _root: Control = null
var _panel: PanelContainer = null
var _fade_tween: Tween = null

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top    = 24.0
	center.offset_bottom = 24.0
	center.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = BG_COLOR
	bg.set_corner_radius_all(8)
	bg.content_margin_left   = PADDING_X
	bg.content_margin_right  = PADDING_X
	bg.content_margin_top    = PADDING_Y
	bg.content_margin_bottom = PADDING_Y
	_panel.add_theme_stylebox_override("panel", bg)
	center.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	var pre := Label.new()
	pre.text = "DRONE HIDDEN — press"
	pre.add_theme_font_size_override("font_size", TEXT_FONT)
	pre.add_theme_color_override("font_color",          TEXT_COLOR)
	pre.add_theme_color_override("font_outline_color",  Color(0.0, 0.0, 0.0, 0.85))
	pre.add_theme_constant_override("outline_size",     2)
	pre.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	row.add_child(pre)

	row.add_child(_make_chip("Q"))

	var post := Label.new()
	post.text = "to shift camera"
	post.add_theme_font_size_override("font_size", TEXT_FONT)
	post.add_theme_color_override("font_color",          ACCENT)
	post.add_theme_color_override("font_outline_color",  Color(0.0, 0.0, 0.0, 0.85))
	post.add_theme_constant_override("outline_size",     2)
	post.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	row.add_child(post)

	_root.modulate.a = 0.0
	_root.visible    = false

func _make_chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = CHIP_BG
	st.set_corner_radius_all(5)
	st.content_margin_left   = CHIP_PAD_X
	st.content_margin_right  = CHIP_PAD_X
	st.content_margin_top    = 2.0
	st.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", st)
	chip.custom_minimum_size = Vector2(CHIP_H, CHIP_H)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", CHIP_FONT)
	lbl.add_theme_color_override("font_color", CHIP_FG)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	return chip

func set_hint_visible(on: bool) -> void:
	if _root == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	if on:
		_root.visible = true
		_fade_tween.tween_property(_root, "modulate:a", 1.0, 0.18)
	else:
		_fade_tween.tween_property(_root, "modulate:a", 0.0, 0.18)
		_fade_tween.tween_callback(func() -> void:
			if is_instance_valid(_root):
				_root.visible = false)
