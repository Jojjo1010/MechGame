extends CanvasLayer

signal option_selected(mech: Node3D, index: int)

const OPTION_LABELS := ["Option A", "Option B", "Option C"]
const INTERACT_RADIUS := 5.0

var _camera: Camera3D
var _target_mech: Node3D = null
var _panel: PanelContainer
var _buttons: Array[Button] = []

func setup(camera: Camera3D) -> void:
	_camera = camera
	_build_ui()
	_panel.hide()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(300.0, 0.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	style.border_color = Color(0.4, 0.8, 1.0, 0.8)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "MECH OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.4, 0.8, 1.0, 0.4))
	vbox.add_child(sep)

	for i in OPTION_LABELS.size():
		var btn := Button.new()
		btn.text = OPTION_LABELS[i]
		btn.flat = false
		btn.custom_minimum_size = Vector2(0.0, 52.0)

		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.15, 0.3, 0.5, 0.8)
		btn_style.set_corner_radius_all(6)
		btn_style.content_margin_left = 14.0
		btn_style.content_margin_right = 14.0
		btn_style.content_margin_top = 10.0
		btn_style.content_margin_bottom = 10.0
		btn.add_theme_stylebox_override("normal", btn_style)

		var hover_style := btn_style.duplicate()
		hover_style.bg_color = Color(0.25, 0.5, 0.8, 0.9)
		btn.add_theme_stylebox_override("hover", hover_style)

		var press_style := btn_style.duplicate()
		press_style.bg_color = Color(0.1, 0.2, 0.4, 1.0)
		btn.add_theme_stylebox_override("pressed", press_style)

		btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		btn.add_theme_font_size_override("font_size", 18)

		var idx := i
		btn.pressed.connect(func(): option_selected.emit(_target_mech, idx))
		vbox.add_child(btn)
		_buttons.append(btn)

	add_child(_panel)

func notify_proximity(mech: Node3D) -> void:
	if mech == _target_mech:
		return
	if _target_mech and _target_mech.has_method("set_highlighted"):
		_target_mech.set_highlighted(false)
	_target_mech = mech
	if mech != null:
		_panel.show()
		if mech.has_method("set_highlighted"):
			mech.set_highlighted(true)
	else:
		_panel.hide()

func _process(_delta: float) -> void:
	if _target_mech == null or _camera == null or not _panel.visible:
		return

	# Project a point just above the mech's head
	var world_top := _target_mech.global_position + Vector3(0.0, 4.2, 0.0)
	var screen_pos := _camera.unproject_position(world_top)

	# Centre the panel on that screen point
	var pos := screen_pos - Vector2(_panel.size.x * 0.5, _panel.size.y)

	# Clamp so the panel stays inside the viewport with a margin
	const MARGIN := 24.0
	var vp := get_viewport().get_visible_rect()
	pos.x = clampf(pos.x, vp.position.x + MARGIN, vp.position.x + vp.size.x - _panel.size.x - MARGIN)
	pos.y = clampf(pos.y, vp.position.y + MARGIN, vp.position.y + vp.size.y - _panel.size.y - MARGIN)

	_panel.global_position = pos
