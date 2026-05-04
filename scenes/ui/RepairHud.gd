extends CanvasLayer

# Bottom-left HUD pill showing the repair cooldown state. Always visible so
# the player learns the gate exists and can predict when F frees up.
# Polls Game.repair_cooldown_remaining / repair_cooldown_fraction once per
# frame — same pattern MechOptionsPanel uses for its inline countdown.

const PANEL_W := 320.0
const PANEL_H := 56.0
const MARGIN_LEFT := 24.0
# Mirrors UltBar.SLOT_H / MARGIN_BOT — keeping these as local consts (not
# imports) because UltBar isn't a class_name and inheriting it just for two
# constants is heavier than the duplication.
const ULT_BAR_H   := 144.0
const ULT_BAR_BOT := 24.0
const GAP_ABOVE_ULT := 55.0
const KEY_CHIP_SIZE := 36.0
const BAR_H := 6.0

const READY_LABEL_COLOR   := Color(0.70, 1.00, 0.70, 0.92)
const COOLING_LABEL_COLOR := Color(1.00, 0.78, 0.35, 0.92)
const AMBER               := Color(1.00, 0.78, 0.35, 1.00)

var _root:       Control   = null
var _sub_lbl:    Label     = null
var _bar_bg:     ColorRect = null
var _bar_fill:   ColorRect = null
var _game:       Node      = null

func _ready() -> void:
	layer = 5
	add_to_group("tutorial_late_ui")
	_build()
	_game = get_parent()

func _build() -> void:
	_root = Control.new()
	_root.anchor_left   = 0.0
	_root.anchor_right  = 0.0
	_root.anchor_top    = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left   = MARGIN_LEFT
	_root.offset_right  = MARGIN_LEFT + PANEL_W
	# Sit above UltBar's top edge with a small breathing gap.
	_root.offset_top    = -(ULT_BAR_H + ULT_BAR_BOT + GAP_ABOVE_ULT + PANEL_H)
	_root.offset_bottom = -(ULT_BAR_H + ULT_BAR_BOT + GAP_ABOVE_ULT)
	_root.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color     = UITheme.COLOR_PANEL_ALPHA
	sb.border_color = Color(AMBER.r, AMBER.g, AMBER.b, 0.55)
	sb.set_border_width_all(int(UITheme.PANEL_BORDER_W))
	sb.set_corner_radius_all(12)
	sb.content_margin_left   = 10
	sb.content_margin_right  = 12
	sb.content_margin_top    = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	hbox.add_child(_make_key_chip("F", AMBER))

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	text_col.add_theme_constant_override("separation", 4)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_col)

	var label_row := HBoxContainer.new()
	label_row.add_theme_constant_override("separation", 8)
	label_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(label_row)

	var action_lbl := Label.new()
	action_lbl.text = "REPAIR"
	action_lbl.add_theme_font_size_override("font_size", 16)
	action_lbl.add_theme_color_override("font_color", Color.WHITE)
	action_lbl.add_theme_constant_override("outline_size", 0)
	action_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_row.add_child(action_lbl)

	_sub_lbl = Label.new()
	_sub_lbl.text = "READY"
	_sub_lbl.add_theme_font_size_override("font_size", 13)
	_sub_lbl.add_theme_color_override("font_color", READY_LABEL_COLOR)
	_sub_lbl.add_theme_constant_override("outline_size", 0)
	_sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sub_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	_sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_row.add_child(_sub_lbl)

	_bar_bg = ColorRect.new()
	_bar_bg.color = UITheme.COLOR_DEEP
	_bar_bg.custom_minimum_size = Vector2(0.0, BAR_H)
	_bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = AMBER
	_bar_fill.size  = Vector2(0.0, BAR_H)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar_fill)

func _make_key_chip(text: String, accent: Color) -> Control:
	# Mirrors MechOptionsPanel._make_key_badge — beveled-key feel via a thicker
	# bottom border. Kept local so this HUD doesn't depend on MechOptionsPanel.
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(KEY_CHIP_SIZE, KEY_CHIP_SIZE)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_PANEL_ALPHA
	style.border_color = accent
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 4
	style.set_corner_radius_all(4)
	chip.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", accent)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	return chip

func _process(_delta: float) -> void:
	if _game == null or not is_instance_valid(_game):
		return
	var cd: float = 0.0
	var cd_frac: float = 0.0
	if _game.has_method("repair_cooldown_remaining"):
		cd = float(_game.call("repair_cooldown_remaining"))
	if _game.has_method("repair_cooldown_fraction"):
		cd_frac = float(_game.call("repair_cooldown_fraction"))

	if _bar_bg != null and _bar_fill != null:
		# Width grows L→R as fraction drops 1.0 → 0.0; ready-state fully spans.
		_bar_fill.size.x = _bar_bg.size.x * (1.0 - cd_frac)

	if cd > 0.0:
		_sub_lbl.text = "%.1fs" % cd
		_sub_lbl.add_theme_color_override("font_color", COOLING_LABEL_COLOR)
	else:
		_sub_lbl.text = "READY"
		_sub_lbl.add_theme_color_override("font_color", READY_LABEL_COLOR)
