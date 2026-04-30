extends CanvasLayer

# Left-side controls list, styled to match MechOptionsPanel key chips:
# cream-coloured square chip with bold dark letter + action label beside it.

const ENTRIES := [
	{key = "WASD",   action = "Move drone"},
	{key = "Space",  action = "Dash"},
	{key = "E",      action = "Mech ultimate"},
	{key = "F",      action = "Repair"},
	{key = "Q",      action = "Camera angle"},
	{key = "Scroll", action = "Zoom"},
]

const BG_COLOR    := Color(0.0,  0.0,  0.0,  0.55)
const TEXT_COLOR  := Color(1.0,  1.0,  1.0,  0.95)
const CHIP_BG     := Color(0.90, 0.88, 0.80, 1.0)
const CHIP_FG     := Color(0.08, 0.06, 0.04, 1.0)

const PADDING        := 18
const ROW_GAP        := 8
const ROW_H          := 38.0
const CHIP_H         := 30.0
const CHIP_PAD_X     := 12.0
const CHIP_FONT      := 18
const ACTION_FONT    := 18
const TITLE_FONT     := 24

func _ready() -> void:
	layer = 10

	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	var root := PanelContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = BG_COLOR
	bg_style.set_corner_radius_all(8)
	bg_style.content_margin_left   = PADDING
	bg_style.content_margin_right  = PADDING
	bg_style.content_margin_top    = PADDING
	bg_style.content_margin_bottom = PADDING
	root.add_theme_stylebox_override("panel", bg_style)
	anchor.add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", ROW_GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)

	var title := Label.new()
	title.text = "CONTROLS"
	title.add_theme_color_override("font_color",         Color(1.0, 0.95, 0.55, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("outline_size",    2)
	title.add_theme_font_size_override("font_size",      TITLE_FONT)
	col.add_child(title)

	for entry in ENTRIES:
		col.add_child(_make_row(entry.key, entry.action))

	# Vertical-center the panel in the screen
	await get_tree().process_frame
	root.position = Vector2(20.0, (anchor.size.y - root.size.y) * 0.5)

func _make_row(key_text: String, action_text: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	hbox.add_child(_make_chip(key_text))

	var lbl := Label.new()
	lbl.text = action_text
	lbl.add_theme_font_size_override("font_size", ACTION_FONT)
	lbl.add_theme_color_override("font_color",          TEXT_COLOR)
	lbl.add_theme_color_override("font_outline_color",  Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size",     2)
	lbl.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)
	return hbox

func _make_chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = CHIP_BG
	style.set_corner_radius_all(5)
	style.content_margin_left   = CHIP_PAD_X
	style.content_margin_right  = CHIP_PAD_X
	style.content_margin_top    = 2.0
	style.content_margin_bottom = 2.0
	chip.add_theme_stylebox_override("panel", style)

	# Square minimum for single-character keys; wider chips auto-size to text.
	if text.length() == 1:
		chip.custom_minimum_size = Vector2(CHIP_H, CHIP_H)
	else:
		chip.custom_minimum_size = Vector2(0.0, CHIP_H)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", CHIP_FONT)
	lbl.add_theme_color_override("font_color", CHIP_FG)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	return chip
