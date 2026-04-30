extends CanvasLayer

# End-of-run overlay. Pauses the game and shows wave/gold/scrap totals,
# with buttons to retry the run or visit the garage.

const GAME_SCENE_PATH   := "res://scenes/game/Game.tscn"
const GARAGE_SCENE_PATH := "res://scenes/garage/Garage.tscn"

func show_results(waves: int, gold: int, earned_scrap: int, total_scrap: int) -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build(waves, gold, earned_scrap, total_scrap)
	# Ominous low-pitched mech death as the run-end stinger
	AudioManager.play("mech_death", Vector3.INF, -2.0, 0.65)
	get_tree().paused = true

func _build(waves: int, gold: int, earned: int, total: int) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.06, 0.85)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = "RUN OVER"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color",         Color(1.0, 0.30, 0.25, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	title.add_theme_constant_override("outline_size",    4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	col.add_child(_make_row("Waves survived",    "%d" % waves,  Color.WHITE))
	col.add_child(_make_row("Gold collected",    "%d" % gold,   Color(1.0, 0.85, 0.30)))
	col.add_child(_make_row("Scrap earned",      "+%d" % earned, Color(0.55, 1.0, 0.55)))

	var sep := ColorRect.new()
	sep.color = Color(1.0, 1.0, 1.0, 0.20)
	sep.custom_minimum_size = Vector2(360.0, 1.0)
	col.add_child(sep)

	col.add_child(_make_row("Total scrap",       "%d" % total,  Color(0.55, 1.0, 0.55)))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 12.0)
	col.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 18)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_row)

	var retry_btn  := _make_button("RETRY",  Color(0.55, 1.0, 0.55))
	var garage_btn := _make_button("GARAGE", Color(0.85, 0.70, 1.0))
	retry_btn.pressed.connect(_on_retry_pressed)
	garage_btn.pressed.connect(_on_garage_pressed)
	btn_row.add_child(retry_btn)
	btn_row.add_child(garage_btn)

func _make_row(label: String, value: String, color: Color) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(360.0, 0.0)
	hbox.add_theme_constant_override("separation", 12)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92, 1.0))
	lbl.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	hbox.add_child(lbl)

	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 22)
	val.add_theme_color_override("font_color", color)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(val)
	return hbox

func _make_button(text: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(180.0, 56.0)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	btn.add_theme_constant_override("outline_size", 2)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.05, 0.10, 0.95)
	normal.set_corner_radius_all(8)
	normal.set_border_width_all(2)
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = Color(0.12, 0.10, 0.20, 0.98)
	hover.border_color = accent
	hover.set_border_width_all(3)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.18, 0.14, 0.28, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.mouse_entered.connect(func() -> void: AudioManager.play("ui_hover"))
	return btn

func _on_retry_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func _on_garage_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().paused = false
	get_tree().change_scene_to_file(GARAGE_SCENE_PATH)
