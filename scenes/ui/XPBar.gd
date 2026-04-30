extends CanvasLayer

const BAR_H      := 30.0   # unused for height now, kept for reference
const PAD_SIDE   := 5.0
const PAD_VERT   := 22.0   # generous top/bottom breathing room
const FONT_SIZE  := 32

var _bar_bg:   ColorRect
var _bar_fg:   ColorRect
var _lv_label: Label

func _ready() -> void:
	layer = 5
	_build()
	RunManager.xp_changed.connect(_on_xp_changed)
	RunManager.level_up.connect(_on_level_up)
	_refresh(RunManager.xp, RunManager.xp_to_next)

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var total_h := BAR_H + PAD_VERT * 2   # = 62 px

	# Semi-transparent background strip
	_bar_bg = ColorRect.new()
	_bar_bg.color        = Color(0.06, 0.04, 0.12, 0.70)
	_bar_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_bg.offset_left   = 0.0
	_bar_bg.offset_top    = 0.0
	_bar_bg.offset_right  = 0.0
	_bar_bg.offset_bottom = total_h
	_bar_bg.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bar_bg)

	# Purple fill — full height of the background, only inset on left/right
	_bar_fg = ColorRect.new()
	_bar_fg.color        = Color(0.70, 0.25, 1.00, 0.82)
	_bar_fg.position     = Vector2(PAD_SIDE, 0.0)
	_bar_fg.size         = Vector2(0.0, total_h)
	_bar_fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bar_fg)

	# Level label — vertically centred across the full strip height
	_lv_label = Label.new()
	_lv_label.text = "LV 1"
	_lv_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_lv_label.add_theme_color_override("font_color",          Color(1.0, 1.0, 1.0, 1.0))
	_lv_label.add_theme_color_override("font_outline_color",  Color(0.0, 0.0, 0.0, 1.0))
	_lv_label.add_theme_constant_override("outline_size",     3)
	_lv_label.add_theme_color_override("font_shadow_color",   Color(0.0, 0.0, 0.0, 0.90))
	_lv_label.add_theme_constant_override("shadow_offset_x",  2)
	_lv_label.add_theme_constant_override("shadow_offset_y",  2)
	_lv_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_lv_label.offset_left          = 0.0
	_lv_label.offset_top           = 0.0
	_lv_label.offset_right         = 0.0
	_lv_label.offset_bottom        = total_h
	_lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lv_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_lv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_lv_label)

func _refresh(current: int, needed: int) -> void:
	await get_tree().process_frame
	var full_w: float = _bar_bg.size.x - PAD_SIDE * 2
	var t: float = clampf(float(current) / float(needed), 0.0, 1.0)
	_bar_fg.size.x = full_w * t

func _on_xp_changed(current: int, needed: int) -> void:
	_refresh(current, needed)

func _on_level_up(new_level: int) -> void:
	_lv_label.text = "LV %d" % new_level
	_refresh(0, RunManager.xp_to_next)
	var tw := create_tween()
	tw.tween_property(_bar_fg, "color", Color(0.95, 0.80, 1.0, 0.95), 0.10)
	tw.tween_property(_bar_fg, "color", Color(0.70, 0.25, 1.00, 0.82), 0.30)
