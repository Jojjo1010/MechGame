extends CanvasLayer

# Left-side controls list. Each row uses a chip that mimics the actual input —
# real keyboard caps for letter keys, a 4-key WASD cluster, a wide shift key,
# and a procedural mouse icon for scroll. Reads at a glance: players see the
# input, not an abstract label.

const ENTRIES := [
	{key = "MOVEMENT", icon = "move",   action = "Move drone"},
	{key = "Shift",    icon = "dash",   action = "Dash"},
	{key = "Scroll",   icon = "zoom",   action = "Zoom"},
]

# All spacing/size values follow the 8 px design system. Type scale uses its
# own modular ladder (16/20/24/28/32) and is defined separately. Key-cap
# sizing lives in KeyChip — referenced here, not duplicated.
const ROW_GAP    := 32   # between rows — 4× ROW_SEP creates clear grouping
const ROW_SEP    := 8    # chip ↔ icon ↔ label inside a row
const MOUSE_W    := 32.0
const MOUSE_H    := 48.0
const ICON_SIZE  := 32.0
# Type scale aligned to 8 px (UITheme): 32/24/16 → heading / label / body.
const TITLE_FONT  := UITheme.FONT_HEADING_M  # 32
const ACTION_FONT := UITheme.FONT_LABEL_CAPS # 24
const KEY_FONT    := UITheme.FONT_LABEL_CAPS # 24 — same tier as action labels
const SHIFT_FONT  := UITheme.FONT_BODY       # 16
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

	# Bare list — no panel, no border, no title. Just the rows of chip + icon + label.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", ROW_GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.position = Vector2(20.0, XP_BAR_BOTTOM + PANEL_TOP_GAP)
	anchor.add_child(col)

	for entry in ENTRIES:
		col.add_child(_make_row(entry.key, entry.icon, entry.action))

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

	# Without the panel backdrop the legend sits over the world — push everything
	# to white with a black outline so it stays legible against any terrain.
	var icon := ActionIcon.new()
	icon.action_id            = icon_id
	icon.accent               = UITheme.COLOR_TEXT_PRIMARY
	icon.custom_minimum_size  = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_vertical  = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon)

	var lbl := Label.new()
	lbl.text = action_text
	lbl.add_theme_font_size_override("font_size", ACTION_FONT)
	lbl.add_theme_color_override("font_color",      UITheme.COLOR_TEXT_PRIMARY)
	lbl.add_theme_constant_override("outline_size", 0)
	lbl.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)
	return hbox

# Picks the chip type that matches the actual input.
func _make_chip(key_text: String) -> Control:
	match key_text:
		"MOVEMENT": return KeyChip.make_movement_cluster(KEY_FONT)
		"Shift":    return KeyChip.make_key_cap("SHIFT",   KeyChip.SHIFT_W, KeyChip.SHIFT_H, SHIFT_FONT)
		"Scroll":   return _make_mouse_chip()
		_:          return KeyChip.make_key_cap(key_text, KeyChip.KEY_SIZE, KeyChip.KEY_SIZE, KEY_FONT)

func _make_mouse_chip() -> Control:
	var m := MouseIcon.new()
	m.custom_minimum_size = Vector2(MOUSE_W, MOUSE_H)
	m.body_color = UITheme.COLOR_TEXT_PRIMARY
	m.accent     = UITheme.COLOR_TEXT_PRIMARY
	return m
