extends CanvasLayer

# Full-screen "Press any input..." overlay. Listens at PROCESS_MODE_ALWAYS so it
# works while the tree is paused. First valid event closes and emits captured;
# Esc / B-button cancels.

signal captured(event: InputEvent)
signal cancelled

const PANEL_PAD := 32

func open(prompt_text: String) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 80
	_build(prompt_text)

func _build(prompt_text: String) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	var bd := UITheme.COLOR_DEEP
	bd.a = 0.85
	backdrop.color = bd
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := PanelContainer.new()
	var sb := UITheme.panel_stylebox(UITheme.COLOR_BORDER_BRIGHT)
	sb.bg_color              = UITheme.COLOR_PANEL
	sb.set_corner_radius_all(16)
	sb.content_margin_left   = PANEL_PAD * 2
	sb.content_margin_right  = PANEL_PAD * 2
	sb.content_margin_top    = PANEL_PAD
	sb.content_margin_bottom = PANEL_PAD
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.PAD_M)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	var heading := Label.new()
	heading.text = prompt_text.to_upper()
	UITheme.style_heading(heading, UITheme.FONT_HEADING_M, UITheme.COLOR_TEXT_PRIMARY)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(heading)

	var hint := Label.new()
	hint.text = "PRESS ANY KEY OR BUTTON  •  ESC TO CANCEL"
	UITheme.style_label_caps(hint, UITheme.FONT_BODY, UITheme.COLOR_TEXT_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if k.keycode == KEY_ESCAPE:
			cancelled.emit()
			get_viewport().set_input_as_handled()
			queue_free()
			return
		captured.emit(event)
		get_viewport().set_input_as_handled()
		queue_free()
		return
	if event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		if not b.pressed:
			return
		captured.emit(event)
		get_viewport().set_input_as_handled()
		queue_free()
		return
	if event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if not m.pressed:
			return
		captured.emit(event)
		get_viewport().set_input_as_handled()
		queue_free()
		return
