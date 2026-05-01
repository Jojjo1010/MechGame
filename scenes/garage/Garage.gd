extends Control

# Between-runs garage: show scrap balance, offer mech-slot unlocks, start a new run.

const GAME_SCENE_PATH := "res://scenes/game/Game.tscn"

var _scrap_lbl:    Label   = null
var _slot_rows:    Array[Control] = []   # one row per slot (4th, 5th, …)

func _ready() -> void:
	_build()
	SaveData.scrap_changed.connect(_on_scrap_changed)
	SaveData.unlocks_changed.connect(_refresh_slot_rows)

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.10, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = "GARAGE"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color",      Color(1.0, 0.95, 0.75, 1.0))
	title.add_theme_constant_override("outline_size", 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_scrap_lbl = Label.new()
	_scrap_lbl.text = "Scrap: %d" % SaveData.total_scrap
	_scrap_lbl.add_theme_font_size_override("font_size", 26)
	_scrap_lbl.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	_scrap_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_scrap_lbl)

	var sep := ColorRect.new()
	sep.color = Color(1.0, 1.0, 1.0, 0.20)
	sep.custom_minimum_size = Vector2(420.0, 1.0)
	col.add_child(sep)

	var section := Label.new()
	section.text = "Mech slots"
	section.add_theme_font_size_override("font_size", 20)
	section.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92, 0.85))
	col.add_child(section)

	# Build a row for each non-starting slot index
	for slot_index in range(SaveData.STARTING_MECH_SLOTS, SaveData.MAX_MECH_SLOTS):
		var row := _make_slot_row(slot_index)
		_slot_rows.append(row)
		col.add_child(row)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 16.0)
	col.add_child(spacer)

	var start_btn := _make_button("START NEW RUN", Color(0.55, 1.0, 0.55))
	start_btn.custom_minimum_size = Vector2(280.0, 60.0)
	start_btn.pressed.connect(_on_start_run_pressed)
	col.add_child(start_btn)

func _make_slot_row(slot_index: int) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(420.0, 0.0)
	hbox.add_theme_constant_override("separation", 12)
	hbox.set_meta("slot_index", slot_index)

	var label := Label.new()
	var label_text := "Slot %d (%s mech)" % [slot_index + 1, _ordinal(slot_index + 1)]
	label.text = label_text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95, 1.0))
	label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	hbox.add_child(label)

	var cost_lbl := Label.new()
	cost_lbl.add_theme_font_size_override("font_size", 18)
	cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	cost_lbl.custom_minimum_size = Vector2(96.0, 0.0)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_lbl.set_meta("role", "cost")
	hbox.add_child(cost_lbl)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120.0, 44.0)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.set_meta("role", "btn")
	btn.pressed.connect(_on_buy_pressed.bind(slot_index))
	hbox.add_child(btn)

	_apply_slot_state(hbox, slot_index)
	return hbox

func _apply_slot_state(row: Control, slot_index: int) -> void:
	var cost_lbl: Label = null
	var btn: Button = null
	for child in row.get_children():
		if child.has_meta("role"):
			match child.get_meta("role"):
				"cost": cost_lbl = child as Label
				"btn":  btn = child as Button
	if cost_lbl == null or btn == null:
		return

	var cost := SaveData.mech_slot_cost(slot_index)
	var owned := slot_index < SaveData.unlocked_mech_slots
	var prereq_met := slot_index == SaveData.unlocked_mech_slots   # next slot to buy
	var affordable := SaveData.can_afford(cost)

	if owned:
		cost_lbl.text = ""
		btn.text = "OWNED"
		btn.disabled = true
		_style_button(btn, Color(0.55, 1.0, 0.55), true)
	elif not prereq_met:
		cost_lbl.text = "%d" % cost
		btn.text = "LOCKED"
		btn.disabled = true
		_style_button(btn, Color(0.5, 0.5, 0.55), true)
	elif not affordable:
		cost_lbl.text = "%d" % cost
		btn.text = "BUY"
		btn.disabled = true
		_style_button(btn, Color(0.55, 0.55, 0.65), true)
	else:
		cost_lbl.text = "%d" % cost
		btn.text = "BUY"
		btn.disabled = false
		_style_button(btn, Color(0.55, 1.0, 0.55), false)

func _style_button(btn: Button, accent: Color, disabled: bool) -> void:
	var alpha := 0.45 if disabled else 0.55
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.05, 0.10, 0.95)
	normal.set_corner_radius_all(6)
	normal.set_border_width_all(2)
	normal.border_color = Color(accent.r, accent.g, accent.b, alpha)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("disabled", normal)

	var hover := normal.duplicate()
	hover.bg_color = Color(0.12, 0.10, 0.20, 0.98)
	hover.border_color = accent
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.18, 0.14, 0.28, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed)

	var color := Color(0.55, 0.55, 0.60) if disabled else Color.WHITE
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_disabled_color", color)

func _make_button(text: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_constant_override("outline_size", 0)

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

func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
		_: return "%dth" % n

func _on_buy_pressed(slot_index: int) -> void:
	if slot_index != SaveData.unlocked_mech_slots:
		return   # not the next slot
	if SaveData.unlock_next_mech_slot():
		# Celebratory chime on successful unlock
		AudioManager.play("level_up")
	else:
		AudioManager.play("repair_wrong")

func _on_scrap_changed(_total: int) -> void:
	if _scrap_lbl != null:
		_scrap_lbl.text = "Scrap: %d" % SaveData.total_scrap
	_refresh_slot_rows()

func _refresh_slot_rows() -> void:
	for row in _slot_rows:
		var idx: int = int(row.get_meta("slot_index"))
		_apply_slot_state(row, idx)

func _on_start_run_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
