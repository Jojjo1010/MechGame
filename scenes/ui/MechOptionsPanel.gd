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
var _ult_badge_lbl:     Label = null   # the "E" / "R" inside the key chip
# Subtitle shown when the ult isn't ready / when it's ready. Both switch to
# remote-trigger phrasing for the ROCKET mech so the prompt always advertises
# the global R control rather than the proximity-bound default.
var _ult_subtitle_idle:  String = "Press to activate"
var _ult_subtitle_ready: String = "Ready!"
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
	# 260 px gives enough horizontal room for the ROCKET prompt's longer
	# "trigger from anywhere" subtitle without the ult button's clip_contents
	# truncating the text. clip_contents has to stay on so the charge-fill
	# strip doesn't visually leak past the button's rounded corners.
	_panel.custom_minimum_size = Vector2(260.0, 0.0)
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	# ── Ultimate button ───────────────────────────────────────────────────────
	var ult_pkg := _build_action_button("E", Color(0.90, 0.88, 0.80, 1.0), 58.0, "Ultimate", "Press to activate")
	_ult_btn          = ult_pkg.btn
	_btn_normal_style = ult_pkg.normal
	_btn_hover_style  = ult_pkg.hover  # _process recolours these on ready/not-ready
	_ult_action_lbl   = ult_pkg.action_lbl
	_ult_subtitle_lbl = ult_pkg.sub_lbl
	_ult_badge_lbl    = ult_pkg.badge_lbl
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
	var repair_pkg := _build_action_button("F", Color(1.00, 0.78, 0.35, 1.0), 52.0, "Repair", "Damaged mech")
	_repair_btn              = repair_pkg.btn
	_repair_btn_normal_style = repair_pkg.normal
	_repair_action_lbl       = repair_pkg.action_lbl
	_repair_sub_lbl          = repair_pkg.sub_lbl
	_repair_btn.visible      = false
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
# Builds the ult/repair action button: dark-fill Button with hover/pressed
# styles, a square key chip on the left, and an action+subtitle text column on
# the right. Returns a Dictionary so callers can grab whichever refs they need
# (caller stores `normal`/`hover` only when _process needs to recolour them).
func _build_action_button(badge_text: String, badge_color: Color, height: float, action_text: String, sub_text: String) -> Dictionary:
	var btn := Button.new()
	btn.text                = ""        # custom content drawn below
	btn.flat                = false
	btn.clip_contents       = true      # keeps charge fill inside bounds
	btn.custom_minimum_size = Vector2(0.0, height)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.05, 0.04, 0.09, 0.86)
	normal.set_border_width_all(0)
	normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.12, 0.10, 0.22, 0.92)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed_style := normal.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.03, 0.02, 0.06, 0.96)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 0)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	var badge := _make_key_badge(badge_text, badge_color, height)
	hbox.add_child(badge)
	var badge_lbl := badge.get_child(0) as Label

	var text_col := VBoxContainer.new()
	text_col.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	text_col.add_theme_constant_override("separation", 1)
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  14)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    0)
	margin.add_theme_constant_override("margin_bottom", 0)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	hbox.add_child(margin)
	margin.add_child(text_col)

	var action_lbl := Label.new()
	action_lbl.text = action_text
	action_lbl.add_theme_font_size_override("font_size", 20)
	action_lbl.add_theme_color_override("font_color",      Color(1.0, 1.0, 1.0, 0.95))
	action_lbl.add_theme_constant_override("outline_size", 0)
	action_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(action_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = sub_text
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60, 0.85))
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(sub_lbl)

	return {
		"btn":        btn,
		"normal":     normal,
		"hover":      hover,
		"action_lbl": action_lbl,
		"sub_lbl":    sub_lbl,
		"badge_lbl":  badge_lbl,
	}

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
		name_str = w.weapon_name
	_ult_action_lbl.text = name_str
	# Every mech's ult fires globally via its line-position digit (1 = front,
	# 4 = back). The panel just surfaces the right digit on the chip; Game._input
	# owns the actual key press so the badge here is informational only.
	_ult_subtitle_idle  = "Triggers from anywhere"
	_ult_subtitle_ready = "Ready — fires anywhere"
	if _ult_badge_lbl != null:
		_ult_badge_lbl.text = _line_digit_for(_target_mech)
	_ult_subtitle_lbl.text = _ult_subtitle_idle
	if _ult_btn != null and is_instance_valid(_ult_btn):
		_ult_btn.visible = true

# The mechs group lingers dead corpses during the death-fall, so we can't
# use group order — Game.gd's mechs array is the live ordering.
func _line_digit_for(mech: Node3D) -> String:
	var p := get_parent()
	if p == null or not p.has_method("mech_line_index"):
		return "1"
	var idx: int = int(p.call("mech_line_index", mech))
	if idx < 0:
		return "1"
	return str(idx + 1)

func _on_ult_pressed() -> void:
	AudioManager.play("ui_click")
	_fire_ult()

func _on_repair_pressed() -> void:
	AudioManager.play("ui_click")
	_fire_repair()

func _input(event: InputEvent) -> void:
	if not _enabled or not _panel.visible:
		return
	# Ult firing is owned globally by Game._input via keys 1–4 (front → back),
	# so the panel only handles the local F-repair shortcut and the ult button
	# remains clickable via _on_ult_pressed for mouse-only players.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
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
			_ult_subtitle_lbl.text = _ult_subtitle_ready
	else:
		_btn_normal_style.bg_color = Color(0.05, 0.04, 0.09, 0.86)
		_btn_hover_style.bg_color  = Color(0.12, 0.10, 0.22, 0.92)
		_ult_action_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
		if _ult_subtitle_lbl != null:
			_ult_subtitle_lbl.text = _ult_subtitle_idle

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
