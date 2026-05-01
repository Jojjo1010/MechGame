extends CanvasLayer

# Left-side controls list. Migrated to the OW-style design system: hex key
# chips, hairline cyan panel border, uppercase tracked headings.
# Single-character keys render in a HexIcon; multi-char (WASD, Space, Scroll)
# fall back to a soft pill so the text fits without truncating.

const HexIcon  = preload("res://scenes/ui/style/HexIcon.gd")
const UITheme  = preload("res://scenes/ui/style/UITheme.gd")

const ENTRIES := [
	{key = "WASD",   action = "Move drone"},
	{key = "Space",  action = "Dash"},
	{key = "E",      action = "Mech ultimate"},
	{key = "F",      action = "Repair"},
	{key = "Q",      action = "Camera angle"},
	{key = "Scroll", action = "Zoom"},
]

const ROW_GAP   := 10
const HEX_SIZE  := 44.0
const PILL_H    := 36.0

func _ready() -> void:
	layer = 10

	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	var root := PanelContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_stylebox_override("panel", UITheme.panel_stylebox(UITheme.COLOR_BORDER_HAIR))
	anchor.add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", ROW_GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)

	# Heading: cyan-accented uppercase title with a hairline divider beneath.
	var title := Label.new()
	title.text = "Controls"
	UITheme.style_label_caps(title, UITheme.FONT_HEADING_M, UITheme.COLOR_TEXT_PRIMARY)
	col.add_child(title)
	col.add_child(_make_divider())

	for entry in ENTRIES:
		col.add_child(_make_row(entry.key, entry.action))

	# Vertical-center the panel in the screen
	await get_tree().process_frame
	root.position = Vector2(20.0, (anchor.size.y - root.size.y) * 0.5)

func _make_divider() -> Control:
	# 1.5 px cyan hairline that spans the full panel width.
	var bar := ColorRect.new()
	bar.color               = UITheme.COLOR_ACCENT_CYAN
	bar.custom_minimum_size = Vector2(0.0, UITheme.HAIR_DIVIDER_H)
	bar.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return bar

func _make_row(key_text: String, action_text: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	hbox.add_child(_make_key_chip(key_text))

	var lbl := Label.new()
	lbl.text = action_text
	UITheme.style_body(lbl, UITheme.COLOR_TEXT_SECONDARY)
	lbl.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)
	return hbox

# Single-char keys get a HexIcon; multi-char render as a hairline pill since
# letters like "WASD" don't fit cleanly inside a hex.
func _make_key_chip(text: String) -> Control:
	if text.length() == 1:
		var hex := HexIcon.new()
		hex.custom_minimum_size = Vector2(HEX_SIZE, HEX_SIZE)
		hex.set_label(text, 22, UITheme.COLOR_ACCENT_CYAN)
		hex.set_accent(UITheme.COLOR_ACCENT_CYAN)
		hex.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return hex
	# Multi-char pill — same treatment, rectangular
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.custom_minimum_size = Vector2(0.0, PILL_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color            = UITheme.COLOR_PANEL_ALPHA
	sb.border_color        = UITheme.COLOR_ACCENT_CYAN
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.border_width_top    = 2
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(4)
	sb.content_margin_left   = 14
	sb.content_margin_right  = 14
	sb.content_margin_top    = 4
	sb.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text.to_upper()
	UITheme.style_label_caps(lbl, 18, UITheme.COLOR_ACCENT_CYAN)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	return chip
