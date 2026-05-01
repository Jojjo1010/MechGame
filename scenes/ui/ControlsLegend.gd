extends CanvasLayer

# Left-side controls list. Each row uses a chip that mimics the actual input —
# real keyboard caps for letter keys, a 4-key WASD cluster, a wide spacebar,
# and a procedural mouse icon for scroll. Reads at a glance: players see the
# input, not an abstract label.

const ENTRIES := [
	{key = "WASD",   icon = "move",   action = "Move drone"},
	{key = "Space",  icon = "dash",   action = "Dash"},
	{key = "E",      icon = "ult",    action = "Mech ultimate"},
	{key = "F",      icon = "repair", action = "Repair"},
	{key = "Q",      icon = "camera", action = "Camera angle"},
	{key = "Scroll", icon = "zoom",   action = "Zoom"},
]

# All spacing/size values follow the 8 px design system. Type scale uses its
# own modular ladder (16/20/24/28/32) and is defined separately.
const ROW_GAP    := 32   # between rows — 4× ROW_SEP creates clear grouping
const ROW_SEP    := 8    # chip ↔ icon ↔ label inside a row
const KEY_SIZE   := 40.0 # 5×8
const KEY_GAP    := 4    # half-step
const SPACE_W    := 128.0
const SPACE_H    := 32.0
const MOUSE_W    := 32.0
const MOUSE_H    := 48.0
const ICON_SIZE  := 32.0
# Type scale aligned to 8 px (UITheme): 32/24/16 → heading / label / body.
const TITLE_FONT  := UITheme.FONT_HEADING_M  # 32
const ACTION_FONT := UITheme.FONT_LABEL_CAPS # 24
const KEY_FONT    := UITheme.FONT_LABEL_CAPS # 24 — same tier as action labels
const SPACE_FONT  := UITheme.FONT_BODY       # 16
const PANEL_PAD_H := 24.0
const PANEL_PAD_V := 32.0   # generous top/bottom breathing room
const PANEL_CORNER_R := 16   # rounded — gentle, not pill-shaped
# Top XP/level strip is 64 px (8×8) — owned by XPBar. 24 px gap below.
const XP_BAR_BOTTOM := 64.0
const PANEL_TOP_GAP := 24.0

func _ready() -> void:
	layer = 10

	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	var root := PanelContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color              = UITheme.COLOR_PANEL_ALPHA
	sb.border_color          = UITheme.COLOR_BORDER_HAIR
	sb.border_width_left     = int(UITheme.PANEL_BORDER_W)
	sb.border_width_right    = int(UITheme.PANEL_BORDER_W)
	sb.border_width_top      = int(UITheme.PANEL_BORDER_W)
	sb.border_width_bottom   = int(UITheme.PANEL_BORDER_W)
	sb.set_corner_radius_all(PANEL_CORNER_R)
	sb.content_margin_left   = PANEL_PAD_H
	sb.content_margin_right  = PANEL_PAD_H
	sb.content_margin_top    = PANEL_PAD_V
	sb.content_margin_bottom = PANEL_PAD_V
	root.add_theme_stylebox_override("panel", sb)
	anchor.add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", ROW_GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)

	var title := Label.new()
	title.text = "Controls"
	UITheme.style_label_caps(title, TITLE_FONT, UITheme.COLOR_TEXT_PRIMARY)
	col.add_child(title)
	col.add_child(_make_divider())

	for entry in ENTRIES:
		col.add_child(_make_row(entry.key, entry.icon, entry.action))

	# Anchor the panel at a fixed gap below the XP bar. Independent of panel
	# height, so resizing the contents won't move the panel relative to the bar.
	root.position = Vector2(20.0, XP_BAR_BOTTOM + PANEL_TOP_GAP)

func _make_divider() -> Control:
	# Hairline neutral divider — not lime; lime is reserved for key chips.
	var bar := ColorRect.new()
	bar.color                 = UITheme.COLOR_BORDER_HAIR
	bar.custom_minimum_size   = Vector2(0.0, UITheme.HAIR_DIVIDER_H)
	bar.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return bar

func _make_row(key_text: String, icon_id: String, action_text: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", ROW_SEP)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var chip := _make_chip(key_text)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(chip)

	# Action icon is supporting iconography, not a highlight — neutral grey so
	# the eye lands on the lime key chip first, then reads the icon as context.
	var icon := ActionIcon.new()
	icon.action_id            = icon_id
	icon.accent               = UITheme.COLOR_TEXT_SECONDARY
	icon.custom_minimum_size  = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	var lbl := Label.new()
	lbl.text = action_text
	lbl.add_theme_font_size_override("font_size", ACTION_FONT)
	lbl.add_theme_color_override("font_color",         UITheme.COLOR_TEXT_SECONDARY)
	lbl.add_theme_color_override("font_outline_color", UITheme.COLOR_OUTLINE)
	lbl.add_theme_constant_override("outline_size",    UITheme.OUTLINE_BODY)
	lbl.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)
	return hbox

# Picks the chip type that matches the actual input.
func _make_chip(key_text: String) -> Control:
	match key_text:
		"WASD":   return _make_wasd_cluster()
		"Space":  return _make_key_cap("SPACE", SPACE_W, SPACE_H, SPACE_FONT)
		"Scroll": return _make_mouse_chip()
		_:        return _make_key_cap(key_text, KEY_SIZE, KEY_SIZE, KEY_FONT)

# Two-row keyboard cluster: W centered above the A/S/D row.
func _make_wasd_cluster() -> Control:
	var grid := GridContainer.new()
	grid.columns      = 3
	grid.add_theme_constant_override("h_separation", KEY_GAP)
	grid.add_theme_constant_override("v_separation", KEY_GAP)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(_make_key_spacer())
	grid.add_child(_make_key_cap("W", KEY_SIZE, KEY_SIZE, KEY_FONT))
	grid.add_child(_make_key_spacer())
	grid.add_child(_make_key_cap("A", KEY_SIZE, KEY_SIZE, KEY_FONT))
	grid.add_child(_make_key_cap("S", KEY_SIZE, KEY_SIZE, KEY_FONT))
	grid.add_child(_make_key_cap("D", KEY_SIZE, KEY_SIZE, KEY_FONT))
	return grid

func _make_key_spacer() -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(KEY_SIZE, KEY_SIZE)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

# Single keyboard key cap: dark fill, lime hairline border with a slightly
# thicker bottom edge to imply the key's beveled lip.
func _make_key_cap(text: String, w: float, h: float, font_size: int) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	cap.custom_minimum_size  = Vector2(w, h)
	var sb := StyleBoxFlat.new()
	sb.bg_color            = UITheme.COLOR_PANEL_ALPHA
	sb.border_color        = UITheme.COLOR_ACCENT_LIME
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.border_width_top    = 2
	sb.border_width_bottom = 4
	sb.set_corner_radius_all(4)
	cap.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text.to_upper()
	UITheme.style_label_caps(lbl, font_size, UITheme.COLOR_ACCENT_LIME)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	cap.add_child(lbl)
	return cap

func _make_mouse_chip() -> Control:
	var m := MouseIcon.new()
	m.custom_minimum_size = Vector2(MOUSE_W, MOUSE_H)
	return m
