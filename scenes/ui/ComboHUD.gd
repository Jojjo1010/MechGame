extends CanvasLayer

# Top-center combo badge. Listens to RunManager.combo_changed and shows the
# current stack count + a decay bar that drains visibly. Hidden at 0 stacks.
#
# Stack tint escalates white → yellow → orange → red so the player feels the
# heat without needing to read the number.

const TINTS := [
	Color(0.95, 0.95, 0.95, 1.0),   # 0 stacks (hidden anyway)
	Color(1.00, 0.95, 0.55, 1.0),   # 1
	Color(1.00, 0.65, 0.20, 1.0),   # 2
	Color(1.00, 0.30, 0.20, 1.0),   # 3
]

const PADDING_X := 22
const PADDING_Y := 12
const FONT      := 30
const BAR_W     := 130.0
const BAR_H     := 6.0

var _root:    Control = null
var _panel:   PanelContainer = null
var _panel_bg: StyleBoxFlat = null
var _label:   Label = null
var _bar_bg:  ColorRect = null
var _bar_fg:  ColorRect = null
var _stacks:  int   = 0
var _decay_t: float = 0.0
var _pulse_tween: Tween = null

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top    = 70.0
	center.offset_bottom = 70.0
	center.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_bg = StyleBoxFlat.new()
	_panel_bg.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	_panel_bg.set_corner_radius_all(8)
	_panel_bg.content_margin_left   = PADDING_X
	_panel_bg.content_margin_right  = PADDING_X
	_panel_bg.content_margin_top    = PADDING_Y
	_panel_bg.content_margin_bottom = PADDING_Y
	_panel_bg.border_width_bottom   = 3
	_panel_bg.border_color          = TINTS[1]
	_panel.add_theme_stylebox_override("panel", _panel_bg)
	center.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)

	_label = Label.new()
	_label.text = "1× COMBO"
	_label.add_theme_font_size_override("font_size", FONT)
	_label.add_theme_color_override("font_color", TINTS[1])
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_label)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.1, 0.1, 0.1, 0.85)
	_bar_bg.custom_minimum_size = Vector2(BAR_W, BAR_H)
	col.add_child(_bar_bg)

	_bar_fg = ColorRect.new()
	_bar_fg.color = TINTS[1]
	_bar_fg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_bg.add_child(_bar_fg)

	_root.modulate.a = 0.0
	_root.visible    = false

	if RunManager.has_signal("combo_changed"):
		RunManager.combo_changed.connect(_on_combo_changed)

func _process(delta: float) -> void:
	if _stacks <= 0:
		return
	# Drain bar smoothly toward 0 over COMBO_DURATION; a fresh kill resets it to 1.0
	_decay_t = maxf(0.0, _decay_t - delta / RunManager.COMBO_DURATION)
	if _bar_fg != null:
		_bar_fg.size.x = BAR_W * _decay_t
	# When the runtime decides the run has decayed (combo_changed fires at 0),
	# fade-out is handled in the signal; here we just animate the bar.

func _on_combo_changed(stacks: int) -> void:
	_stacks = stacks
	if stacks <= 0:
		_fade_out()
		return
	_decay_t = 1.0
	var tint: Color = TINTS[mini(stacks, TINTS.size() - 1)]
	_label.text = "%d× COMBO" % stacks
	_label.add_theme_color_override("font_color", tint)
	if _bar_fg != null:
		_bar_fg.color = tint
	if _panel_bg != null:
		_panel_bg.border_color = tint
	_show_and_punch()

func _show_and_punch() -> void:
	_root.visible = true
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_parallel()
	_pulse_tween.tween_property(_root, "modulate:a", 1.0, 0.10)
	_pulse_tween.tween_property(_panel, "scale", Vector2(1.18, 1.18), 0.06).from(Vector2.ONE)
	_pulse_tween.chain().tween_property(_panel, "scale", Vector2.ONE, 0.10)

func _fade_out() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(_root, "modulate:a", 0.0, 0.20)
	_pulse_tween.tween_callback(func() -> void:
		if is_instance_valid(_root):
			_root.visible = false)
