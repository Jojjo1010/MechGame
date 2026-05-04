extends CanvasLayer

signal repair_pressed(mech: Node3D)

var _camera: Camera3D
var _target_mech: Node3D = null
var _panel: PanelContainer
var _ult_btn: Button = null
var _repair_btn: Button = null
var _charge_fill: ColorRect = null
var _line: Line2D = null
# Tutorial gate: when false, proximity notifications and key input are ignored
# and the panel stays hidden. Lets the tutorial keep this UI off-screen during
# the WASD/CAMERA/SHIFT phases and only surface it once the player is being
# taught ult / repair.
var _enabled: bool = true

# Label refs needed for runtime colour/text updates
var _ult_action_lbl:    Label = null
var _ult_subtitle_lbl:  Label = null
var _ult_badge_lbl:     Label = null   # the "E" inside the key chip
var _repair_action_lbl: Label = null   # "Repair" / "Cooling Down"
var _repair_sub_lbl:    Label = null   # "Damaged mech" / countdown
var _repair_charge_fill: ColorRect = null   # bottom strip recharge bar

# StyleBox refs needed for readiness colour changes
var _btn_normal_style:        StyleBoxFlat = null
var _btn_hover_style:         StyleBoxFlat = null
var _repair_btn_normal_style: StyleBoxFlat = null

# ─────────────────────────────────────────────────────────────────────────────
func setup(camera: Camera3D) -> void:
	_camera = camera
	_build_ui()
	_panel.hide()

# ─────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(220.0, 0.0)
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	# ── Ultimate button ───────────────────────────────────────────────────────
	_ult_btn = Button.new()
	_ult_btn.text                = ""        # we draw custom content below
	_ult_btn.flat                = false
	_ult_btn.clip_contents       = true      # keeps charge fill inside bounds
	_ult_btn.custom_minimum_size = Vector2(0.0, 58.0)
	_ult_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	_btn_normal_style          = StyleBoxFlat.new()
	_btn_normal_style.bg_color = Color(0.05, 0.04, 0.09, 0.86)
	_btn_normal_style.set_border_width_all(0)
	_btn_normal_style.set_corner_radius_all(6)
	_ult_btn.add_theme_stylebox_override("normal",  _btn_normal_style)

	_btn_hover_style          = _btn_normal_style.duplicate()
	_btn_hover_style.bg_color = Color(0.12, 0.10, 0.22, 0.92)
	_ult_btn.add_theme_stylebox_override("hover",   _btn_hover_style)

	var ult_pressed_style          := _btn_normal_style.duplicate()
	ult_pressed_style.bg_color      = Color(0.03, 0.02, 0.06, 0.96)
	_ult_btn.add_theme_stylebox_override("pressed", ult_pressed_style)

	# Inner layout: key chip | text column
	var ult_hbox := HBoxContainer.new()
	ult_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ult_hbox.add_theme_constant_override("separation", 0)
	ult_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ult_btn.add_child(ult_hbox)

	var ult_badge_panel := _make_key_badge("E", Color(0.90, 0.88, 0.80, 1.0), 58.0)
	ult_hbox.add_child(ult_badge_panel)
	# Store label ref so we can tint it when ready/not-ready
	_ult_badge_lbl = ult_badge_panel.get_child(0) as Label

	var ult_text_col := VBoxContainer.new()
	ult_text_col.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	ult_text_col.add_theme_constant_override("separation", 1)
	ult_text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Small left/right padding inside the text column
	var ult_margin := MarginContainer.new()
	ult_margin.add_theme_constant_override("margin_left",  14)
	ult_margin.add_theme_constant_override("margin_right",  8)
	ult_margin.add_theme_constant_override("margin_top",    0)
	ult_margin.add_theme_constant_override("margin_bottom", 0)
	ult_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ult_margin.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	ult_hbox.add_child(ult_margin)
	ult_margin.add_child(ult_text_col)

	_ult_action_lbl = Label.new()
	_ult_action_lbl.text = "Ultimate"
	_ult_action_lbl.add_theme_font_size_override("font_size", 20)
	_ult_action_lbl.add_theme_color_override("font_color",      Color(1.0, 1.0, 1.0, 0.95))
	_ult_action_lbl.add_theme_constant_override("outline_size", 0)
	_ult_action_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ult_text_col.add_child(_ult_action_lbl)

	_ult_subtitle_lbl = Label.new()
	_ult_subtitle_lbl.text = "Press to activate"
	_ult_subtitle_lbl.add_theme_font_size_override("font_size", 13)
	_ult_subtitle_lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60, 0.85))
	_ult_subtitle_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ult_text_col.add_child(_ult_subtitle_lbl)

	_ult_btn.pressed.connect(_on_ult_pressed)
	_ult_btn.mouse_entered.connect(func() -> void: AudioManager.play("ui_hover"))
	vbox.add_child(_ult_btn)

	# Charge fill — thin strip at the bottom of the ult button
	_charge_fill = ColorRect.new()
	_charge_fill.color        = Color(0.3, 0.7, 1.0, 0.90)
	_charge_fill.size         = Vector2(0.0, 4.0)
	_charge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ult_btn.add_child(_charge_fill)

	# ── Repair button ─────────────────────────────────────────────────────────
	_repair_btn = Button.new()
	_repair_btn.text                = ""
	_repair_btn.flat                = false
	_repair_btn.clip_contents       = true
	_repair_btn.custom_minimum_size = Vector2(0.0, 52.0)
	_repair_btn.visible             = false
	_repair_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	_repair_btn_normal_style          = StyleBoxFlat.new()
	_repair_btn_normal_style.bg_color = Color(0.05, 0.04, 0.09, 0.86)
	_repair_btn_normal_style.set_border_width_all(0)
	_repair_btn_normal_style.set_corner_radius_all(6)
	_repair_btn.add_theme_stylebox_override("normal",  _repair_btn_normal_style)

	var repair_hover          := _repair_btn_normal_style.duplicate()
	repair_hover.bg_color      = Color(0.12, 0.10, 0.22, 0.92)
	_repair_btn.add_theme_stylebox_override("hover",   repair_hover)

	var repair_pressed_style          := _repair_btn_normal_style.duplicate()
	repair_pressed_style.bg_color      = Color(0.03, 0.02, 0.06, 0.96)
	_repair_btn.add_theme_stylebox_override("pressed", repair_pressed_style)

	var repair_hbox := HBoxContainer.new()
	repair_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	repair_hbox.add_theme_constant_override("separation", 0)
	repair_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_repair_btn.add_child(repair_hbox)

	# Amber badge for repair to distinguish it from ult
	repair_hbox.add_child(_make_key_badge("F", Color(1.00, 0.78, 0.35, 1.0), 52.0))

	var repair_text_col := VBoxContainer.new()
	repair_text_col.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	repair_text_col.add_theme_constant_override("separation", 1)
	repair_text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var repair_margin := MarginContainer.new()
	repair_margin.add_theme_constant_override("margin_left",  14)
	repair_margin.add_theme_constant_override("margin_right",  8)
	repair_margin.add_theme_constant_override("margin_top",    0)
	repair_margin.add_theme_constant_override("margin_bottom", 0)
	repair_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	repair_margin.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	repair_hbox.add_child(repair_margin)
	repair_margin.add_child(repair_text_col)

	_repair_action_lbl = Label.new()
	_repair_action_lbl.text = "Repair"
	_repair_action_lbl.add_theme_font_size_override("font_size", 20)
	_repair_action_lbl.add_theme_color_override("font_color",      Color(1.0, 1.0, 1.0, 0.95))
	_repair_action_lbl.add_theme_constant_override("outline_size", 0)
	_repair_action_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	repair_text_col.add_child(_repair_action_lbl)

	_repair_sub_lbl = Label.new()
	_repair_sub_lbl.text = "Damaged mech"
	_repair_sub_lbl.add_theme_font_size_override("font_size", 13)
	_repair_sub_lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60, 0.85))
	_repair_sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	repair_text_col.add_child(_repair_sub_lbl)

	_repair_btn.pressed.connect(_on_repair_pressed)
	_repair_btn.mouse_entered.connect(func() -> void: AudioManager.play("ui_hover"))
	vbox.add_child(_repair_btn)

	# Recharge fill — same shape as the ult charge strip; amber to match the F
	# key badge instead of the ult's blue→yellow lerp. Width is set per-frame
	# from Game.repair_cooldown_fraction().
	_repair_charge_fill = ColorRect.new()
	_repair_charge_fill.color        = Color(1.00, 0.78, 0.35, 0.90)
	_repair_charge_fill.size         = Vector2(0.0, 4.0)
	_repair_charge_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_repair_btn.add_child(_repair_charge_fill)

	add_child(_panel)

	# Connector line from mech head to panel — hot pink to match the selection
	# outline. Full opacity, thicker than the previous near-invisible white.
	_line = Line2D.new()
	_line.width          = 2.5
	_line.default_color  = UITheme.COLOR_ACCENT_HOT
	_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_line.end_cap_mode   = Line2D.LINE_CAP_ROUND
	_line.visible        = false
	add_child(_line)

# ─────────────────────────────────────────────────────────────────────────────
# Builds a square key chip: coloured bg + bold letter, matching the reference UI
func _make_key_badge(key_text: String, bg_color: Color, btn_height: float) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(btn_height, btn_height)   # square
	badge.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	badge.set_v_size_flags(Control.SIZE_SHRINK_CENTER)

	var style       := StyleBoxFlat.new()
	style.bg_color   = bg_color
	style.set_corner_radius_all(5)
	# No content margins — the label fills the chip via anchors
	style.content_margin_left   = 0.0
	style.content_margin_right  = 0.0
	style.content_margin_top    = 0.0
	style.content_margin_bottom = 0.0
	badge.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text                    = key_text
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1.0))
	lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter            = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)

	return badge

# ─────────────────────────────────────────────────────────────────────────────
func set_enabled(p_enabled: bool) -> void:
	_enabled = p_enabled
	if not _enabled:
		# Drop the current target and hide the UI immediately — don't wait for
		# the next proximity tick.
		if _target_mech and _target_mech.has_method("set_highlighted"):
			_target_mech.set_highlighted(false)
		_target_mech = null
		if _panel != null:
			_panel.hide()
		if _line != null:
			_line.visible = false

func notify_proximity(mech: Node3D) -> void:
	if not _enabled:
		return
	if mech == _target_mech:
		return
	if _target_mech and _target_mech.has_method("set_highlighted"):
		_target_mech.set_highlighted(false)
	_target_mech = mech
	if mech != null:
		_panel.show()
		_line.visible = true
		if mech.has_method("set_highlighted"):
			mech.set_highlighted(true)
		_refresh_btn_text()
	else:
		_panel.hide()
		_line.visible = false

func _refresh_btn_text() -> void:
	if _target_mech == null or _ult_action_lbl == null:
		return
	var w := _target_mech.get("weapon") as Node3D
	var name_str := "Ultimate"
	if w != null:
		var raw_name: Variant = w.get("weapon_name")
		if raw_name != null:
			name_str = str(raw_name)
	_ult_action_lbl.text   = name_str
	_ult_subtitle_lbl.text = "Press to activate"

func _on_ult_pressed() -> void:
	AudioManager.play("ui_click")
	_fire_ult()

func _on_repair_pressed() -> void:
	AudioManager.play("ui_click")
	_fire_repair()

func _input(event: InputEvent) -> void:
	if not _enabled or not _panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_fire_ult()
		elif event.keycode == KEY_F:
			_fire_repair()

func _fire_ult() -> void:
	if _target_mech == null:
		return
	var w := _target_mech.get("weapon") as Node3D
	if w == null or not w.has_method("activate_ult"):
		return
	var fired: bool = w.activate_ult()
	if fired:
		_flash_activated()

func _fire_repair() -> void:
	if _target_mech == null:
		return
	if not (_target_mech.has_method("needs_repair") and _target_mech.needs_repair()):
		return
	repair_pressed.emit(_target_mech)

func _flash_activated() -> void:
	var tw := _ult_btn.create_tween()
	tw.tween_property(_ult_btn, "modulate", Color(1.6, 1.8, 0.5, 1.0), 0.05)
	tw.tween_property(_ult_btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.30)

# ─────────────────────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if _target_mech == null or _camera == null or not _panel.visible:
		return

	# Project above the HP bar
	var world_top  := _target_mech.global_position + Vector3(0.0, 7.2, 0.0)
	var screen_pos := _camera.unproject_position(world_top)

	# Panel: bottom-centre at screen_pos
	var pos := screen_pos - Vector2(_panel.size.x * 0.5, _panel.size.y)
	const MARGIN := 24.0
	var vp := get_viewport().get_visible_rect()
	pos.x = clampf(pos.x, vp.position.x + MARGIN,
		vp.position.x + vp.size.x - _panel.size.x - MARGIN)
	pos.y = clampf(pos.y, vp.position.y + MARGIN,
		vp.position.y + vp.size.y - _panel.size.y - MARGIN)
	_panel.global_position = pos

	# Connector line
	var mech_screen  := _camera.unproject_position(
		_target_mech.global_position + Vector3(0.0, 5.2, 0.0))
	var panel_bottom := Vector2(
		_panel.global_position.x + _panel.size.x * 0.5,
		_panel.global_position.y + _panel.size.y)
	_line.clear_points()
	_line.add_point(panel_bottom)
	_line.add_point(mech_screen)

	# ── Ult readiness ─────────────────────────────────────────────────────────
	if _ult_btn == null or _ult_action_lbl == null:
		return
	var w := _target_mech.get("weapon") as Node3D
	if w == null or not w.has_method("is_ready"):
		return

	var ult_ready: bool = w.is_ready()
	if ult_ready:
		_btn_normal_style.bg_color = Color(0.04, 0.18, 0.06, 0.86)
		_btn_hover_style.bg_color  = Color(0.08, 0.26, 0.10, 0.92)
		_ult_action_lbl.add_theme_color_override("font_color", Color(0.45, 1.0, 0.55, 1.0))
		if _ult_subtitle_lbl != null:
			_ult_subtitle_lbl.text = "Ready!"
	else:
		_btn_normal_style.bg_color = Color(0.05, 0.04, 0.09, 0.86)
		_btn_hover_style.bg_color  = Color(0.12, 0.10, 0.22, 0.92)
		_ult_action_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
		if _ult_subtitle_lbl != null:
			_ult_subtitle_lbl.text = "Press to activate"

	# ── Charge fill bar ───────────────────────────────────────────────────────
	if _charge_fill != null and is_instance_valid(_charge_fill):
		if ult_ready:
			_charge_fill.visible = false
		else:
			_charge_fill.visible = true
			var charge: float = 0.0
			if w.has_method("get_charge"):
				charge = w.get_charge()
			var btn_w := _ult_btn.size.x
			var btn_h := _ult_btn.size.y
			_charge_fill.size     = Vector2(btn_w * charge, 4.0)
			_charge_fill.position = Vector2(0.0, btn_h - 4.0)
			_charge_fill.color    = Color(0.3, 0.7, 1.0, 0.9).lerp(
				Color(1.0, 0.88, 0.1, 0.9), charge)

	# ── Repair button visibility + cooldown state ─────────────────────────────
	if _repair_btn != null and is_instance_valid(_repair_btn):
		var needs: bool = _target_mech.has_method("needs_repair") and _target_mech.needs_repair()
		_repair_btn.visible = needs
		if needs:
			# Game.gd owns the per-run cooldown — poll it so the button greys out
			# and shows a countdown + recharge bar while the gate is closed.
			var cd: float = 0.0
			var cd_frac: float = 0.0
			var p := get_parent()
			if p != null and p.has_method("repair_cooldown_remaining"):
				cd = float(p.call("repair_cooldown_remaining"))
			if p != null and p.has_method("repair_cooldown_fraction"):
				cd_frac = float(p.call("repair_cooldown_fraction"))
			if cd > 0.0:
				_repair_btn.disabled  = true
				_repair_btn.modulate  = Color(1.0, 1.0, 1.0, 0.55)
				_repair_action_lbl.text = "Cooling Down"
				_repair_sub_lbl.text    = "%.1fs" % cd
			else:
				_repair_btn.disabled  = false
				_repair_btn.modulate  = Color(1.0, 1.0, 1.0, 1.0)
				_repair_action_lbl.text = "Repair"
				_repair_sub_lbl.text    = "Damaged mech"
			# Recharge bar — width grows L→R as cd_frac drops from 1.0 to 0.0.
			# At full charge the strip spans the button; ready-state is full.
			if _repair_charge_fill != null and is_instance_valid(_repair_charge_fill):
				var btn_w: float = _repair_btn.size.x
				var btn_h: float = _repair_btn.size.y
				_repair_charge_fill.size     = Vector2(btn_w * (1.0 - cd_frac), 4.0)
				_repair_charge_fill.position = Vector2(0.0, btn_h - 4.0)
