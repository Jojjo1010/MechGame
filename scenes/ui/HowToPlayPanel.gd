extends CanvasLayer

# Modal overlay launched from StartScreen. Shows a one-paragraph framing of
# what the game is, followed by a list of controls. Click outside the panel,
# press the close button, or press ESC to dismiss.

const PANEL_PAD_H    := UITheme.PAD_XL * 2
const PANEL_PAD_V    := UITheme.PAD_XL * 2
const PANEL_CORNER_R := 16
const PANEL_MIN_W    := 720.0
const COL_GAP        := UITheme.PAD_L
const ROW_GAP        := UITheme.PAD_M
const KEY_CHIP_W     := 92.0
const KEY_CHIP_H     := 36.0
const BTN_W          := 224.0
const BTN_H          := 56.0
const HOVER_DUR      := 0.10

# Each row: [key/chip text, action description]. Plain strings keep this file
# decoupled from the in-game ControlsLegend chip system so the overlay can be
# spawned from a screen that doesn't load the game world.
const CONTROLS := [
	["WASD",        "Move the drone"],
	["SHIFT",       "Dash"],
	["LEFT-CLICK",  "Fire ult / confirm aim"],
	["RIGHT-CLICK", "Cycle aim mode (near a mech)"],
	["Q",           "Toggle camera angle"],
	["SCROLL",      "Zoom in / out"],
	["ESC",         "Pause"],
]

const INTRO_TEXT := "You are the drone. Three mechs march in a single line — they auto-fire, but they cannot turn. You support them: dash to draw fire, trigger ults, and approach a damaged mech to repair it. Survive 30 waves to reach the drop-off."

func _ready() -> void:
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	# Click-outside dismisses — the backdrop intercepts the click.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_MIN_W, 0.0)
	# Stop click-through into the backdrop for clicks that land on the panel.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := UITheme.panel_stylebox(UITheme.COLOR_BORDER_BRIGHT)
	sb.bg_color              = UITheme.COLOR_PANEL
	sb.set_corner_radius_all(PANEL_CORNER_R)
	sb.content_margin_left   = PANEL_PAD_H
	sb.content_margin_right  = PANEL_PAD_H
	sb.content_margin_top    = PANEL_PAD_V
	sb.content_margin_bottom = PANEL_PAD_V
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", COL_GAP)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	# Title
	var title := Label.new()
	title.text = "HOW TO PLAY"
	UITheme.style_heading(title, UITheme.FONT_HEADING_L, UITheme.COLOR_TEXT_PRIMARY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# Hairline divider
	var bar := ColorRect.new()
	bar.color                 = UITheme.COLOR_BORDER_HAIR
	bar.custom_minimum_size   = Vector2(0.0, UITheme.HAIR_DIVIDER_H)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(bar)

	# Intro paragraph — body text, secondary color, wraps to panel width.
	var intro := Label.new()
	intro.text = INTRO_TEXT
	UITheme.style_body(intro, UITheme.COLOR_TEXT_SECONDARY)
	intro.add_theme_font_size_override("font_size", UITheme.FONT_BODY * 2 - 4)  # 28 — readable at modal scale
	intro.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(intro)

	# Controls list
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", ROW_GAP)
	col.add_child(rows)
	for entry in CONTROLS:
		rows.add_child(_make_row(String(entry[0]), String(entry[1])))

	# Close button
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(close_row)
	var close_btn := _make_close_button()
	close_btn.pressed.connect(_dismiss)
	close_row.add_child(close_btn)

func _make_row(key_text: String, action_text: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UITheme.PAD_L)

	# Key chip — dark fill, lime hairline border, caps label centered.
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(KEY_CHIP_W, KEY_CHIP_H)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cs := StyleBoxFlat.new()
	cs.bg_color     = UITheme.COLOR_PANEL_ALPHA
	cs.border_color = UITheme.COLOR_BORDER_BRIGHT
	cs.set_border_width_all(2)
	cs.set_corner_radius_all(6)
	chip.add_theme_stylebox_override("panel", cs)
	var chip_lbl := Label.new()
	chip_lbl.text = key_text.to_upper()
	UITheme.style_label_caps(chip_lbl, UITheme.FONT_MICRO_CAPS, UITheme.COLOR_TEXT_PRIMARY)
	chip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(chip_lbl)
	hbox.add_child(chip)

	# Action label
	var action := Label.new()
	action.text = action_text
	UITheme.style_label_caps(action, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_TEXT_PRIMARY)
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	# style_label_caps uppercases by default — undo for readability of the
	# longer descriptive strings here.
	action.text = action_text
	hbox.add_child(action)
	return hbox

func _make_close_button() -> Button:
	var btn := Button.new()
	btn.text = "CLOSE"
	btn.custom_minimum_size = Vector2(BTN_W, BTN_H)
	btn.pivot_offset = Vector2(BTN_W * 0.5, BTN_H * 0.5)
	UITheme.apply_primary_button(btn, "CLOSE", PANEL_CORNER_R)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Hover audio + scale so the button matches the StartScreen feel.
	btn.mouse_entered.connect(func() -> void:
		AudioManager.play("ui_hover")
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(1.03, 1.03), HOVER_DUR)
	)
	btn.mouse_exited.connect(func() -> void:
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2.ONE, HOVER_DUR)
	)
	return btn

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_dismiss()

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_dismiss()

func _dismiss() -> void:
	AudioManager.play("ui_click")
	queue_free()
