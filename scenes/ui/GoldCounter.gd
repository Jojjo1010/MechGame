extends CanvasLayer

const MARGIN     := Vector2(20.0, 88.0)   # XP bar is 74px tall + 14px gap
const COIN_SIZE  := 36.0
const FONT_SIZE  := 28
const BG_H       := 48.0
const PAD_LEFT   := 14.0
const PAD_RIGHT  := 18.0

var _label:    Label
var _coin_panel: Panel
var _root:     Control

func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Dark pill background — sized after label is known
	var bg := ColorRect.new()
	bg.color        = Color(0.08, 0.06, 0.01, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.name         = "BG"
	_root.add_child(bg)

	# Circular gold coin using a Panel + round StyleBoxFlat
	_coin_panel = Panel.new()
	_coin_panel.size     = Vector2(COIN_SIZE, COIN_SIZE)
	_coin_panel.position = Vector2(PAD_LEFT, (BG_H - COIN_SIZE) * 0.5)
	_coin_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin_style := StyleBoxFlat.new()
	coin_style.bg_color = Color(1.0, 0.82, 0.08)
	coin_style.set_corner_radius_all(int(COIN_SIZE * 0.5))   # full radius = circle
	coin_style.border_width_left   = 3
	coin_style.border_width_right  = 3
	coin_style.border_width_top    = 3
	coin_style.border_width_bottom = 3
	coin_style.border_color = Color(0.85, 0.60, 0.02)
	_coin_panel.add_theme_stylebox_override("panel", coin_style)
	_root.add_child(_coin_panel)

	# "$" label centred inside the coin
	var coin_label := Label.new()
	coin_label.text = "$"
	coin_label.add_theme_font_size_override("font_size", 18)
	coin_label.add_theme_color_override("font_color", Color(0.65, 0.42, 0.0))
	coin_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coin_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	coin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_panel.add_child(coin_label)

	# Amount
	_label = Label.new()
	_label.text = "0"
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color",         Color(1.0, 0.92, 0.30))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_label.add_theme_constant_override("outline_size",    3)
	_label.add_theme_color_override("font_shadow_color",  Color(0.0, 0.0, 0.0, 0.85))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.position     = Vector2(PAD_LEFT + COIN_SIZE + 10.0, (BG_H - FONT_SIZE - 6.0) * 0.5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_label)

	await get_tree().process_frame
	_resize_and_place()
	RunManager.gold_changed.connect(_on_gold_changed)

func _resize_and_place() -> void:
	var w := PAD_LEFT + COIN_SIZE + 10.0 + maxf(_label.size.x, 30.0) + PAD_RIGHT
	var bg := _root.get_node("BG") as ColorRect
	if bg:
		bg.size = Vector2(w, BG_H)
	_root.size = Vector2(w, BG_H)
	var vp := get_viewport().get_visible_rect()
	_root.position = Vector2(vp.size.x - w - MARGIN.x, MARGIN.y)

func _on_gold_changed(total: int) -> void:
	_label.text = str(total)
	await get_tree().process_frame
	_resize_and_place()
	# Bounce coin
	var tw := create_tween()
	tw.tween_property(_coin_panel, "scale", Vector2(1.35, 1.35), 0.07).set_ease(Tween.EASE_OUT)
	tw.tween_property(_coin_panel, "scale", Vector2(1.0,  1.0),  0.12).set_ease(Tween.EASE_IN)
