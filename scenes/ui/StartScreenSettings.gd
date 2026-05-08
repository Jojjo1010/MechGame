extends Control

# Settings overlay shown on top of StartScreen. Resolution, music, SFX, and a
# RESET PROGRESS button that wipes meta-progression after a click-again-to-
# confirm step. Emits `closed` when the BACK button is pressed; the parent
# (StartScreen) is responsible for hiding this and re-showing its main content.

signal closed

const PANEL_PAD_H    := UITheme.PAD_XL * 2
const PANEL_PAD_V    := UITheme.PAD_XL * 2
const PANEL_CORNER_R := 16
const PANEL_MIN_W    := 520.0
const COL_GAP        := UITheme.PAD_L
const STAT_GAP       := UITheme.PAD_S
const STAT_ROW_W     := 420.0
const BTN_W          := 320.0
const BTN_H          := 64.0

const HOVER_SCALE     := 1.03
const HOVER_DUR       := 0.10
const PRESS_FLASH_DUR := 0.08

# Mirrors PauseMenu — same labels and sizes so settings on either screen feel
# like the same dialog.
const RESOLUTION_OPTIONS := [
	{"label": "Fullscreen",     "size": Vector2i(0, 0),       "fullscreen": true},
	{"label": "1280 × 720",     "size": Vector2i(1280, 720),  "fullscreen": false},
	{"label": "1600 × 900",     "size": Vector2i(1600, 900),  "fullscreen": false},
	{"label": "1920 × 1080",    "size": Vector2i(1920, 1080), "fullscreen": false},
	{"label": "2560 × 1440",    "size": Vector2i(2560, 1440), "fullscreen": false},
]

# Two-step confirm window for RESET PROGRESS. After the first click the button
# flips to the warn label for this many seconds; a second click within the
# window commits, otherwise it reverts.
const RESET_CONFIRM_WINDOW := 3.0

var _reset_btn:        Button = null
var _back_btn:         Button = null
var _reset_armed:      bool   = false
var _reset_armed_until: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:
	# Backdrop dims the StartScreen behind us so the panel reads cleanly.
	var backdrop := ColorRect.new()
	var bd := UITheme.COLOR_DEEP
	bd.a = 0.78
	backdrop.color = bd
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_MIN_W, 0.0)
	var sb := UITheme.panel_stylebox(UITheme.COLOR_BORDER_HAIR)
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

	var title := Label.new()
	title.text = "SETTINGS"
	UITheme.style_heading(title, UITheme.FONT_HEADING_L, UITheme.COLOR_ACCENT_LIME)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", STAT_GAP)
	col.add_child(rows)

	rows.add_child(_make_resolution_row())
	rows.add_child(_make_volume_row("MUSIC", SaveData.music_volume,
		func(v: float) -> void: SaveData.set_music_volume(v)))
	rows.add_child(_make_volume_row("SFX", SaveData.sfx_volume,
		func(v: float) -> void: SaveData.set_sfx_volume(v)))

	col.add_child(_divider())

	_reset_btn = _make_warn_button("RESET PROGRESS")
	_reset_btn.pressed.connect(_on_reset_pressed)
	col.add_child(_reset_btn)

	col.add_child(_divider())

	_back_btn = _make_primary_button("BACK")
	_back_btn.pressed.connect(_on_back_pressed)
	col.add_child(_back_btn)
	# Re-grab focus every time the overlay opens — gamepad/keyboard users land
	# on BACK by default. Settings rows take over via ui_down navigation.
	visibility_changed.connect(_on_visibility_changed)

# ── Rows ─────────────────────────────────────────────────────────────────────

func _make_resolution_row() -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(STAT_ROW_W, 0.0)
	hbox.add_theme_constant_override("separation", UITheme.PAD_M)

	var lbl := Label.new()
	lbl.text = "RESOLUTION"
	UITheme.style_label_caps(lbl, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_TEXT_SECONDARY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)

	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", UITheme.FONT_LABEL_CAPS)
	opt.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_LIME)
	opt.add_theme_constant_override("outline_size", 0)
	var current_idx := 0
	for i in RESOLUTION_OPTIONS.size():
		var entry: Dictionary = RESOLUTION_OPTIONS[i]
		opt.add_item(entry["label"], i)
		if SaveData.fullscreen and bool(entry["fullscreen"]):
			current_idx = i
		elif (not SaveData.fullscreen) and (not bool(entry["fullscreen"])) \
				and Vector2i(entry["size"]) == SaveData.window_size:
			current_idx = i
	opt.select(current_idx)
	opt.item_selected.connect(_on_resolution_selected)
	hbox.add_child(opt)
	return hbox

func _on_resolution_selected(idx: int) -> void:
	AudioManager.play("ui_click")
	if idx < 0 or idx >= RESOLUTION_OPTIONS.size():
		return
	var entry: Dictionary = RESOLUTION_OPTIONS[idx]
	SaveData.set_resolution(Vector2i(entry["size"]), bool(entry["fullscreen"]))

func _make_volume_row(label_text: String, initial: float, on_change: Callable) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(STAT_ROW_W, 0.0)
	hbox.add_theme_constant_override("separation", UITheme.PAD_M)

	var lbl := Label.new()
	lbl.text = label_text
	UITheme.style_label_caps(lbl, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_TEXT_SECONDARY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(160.0, 0.0)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step      = 0.05
	slider.value     = initial
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var pct := Label.new()
	pct.text = "%d%%" % roundi(initial * 100.0)
	UITheme.style_label_caps(pct, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_ACCENT_LIME)
	pct.custom_minimum_size = Vector2(64.0, 0.0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	slider.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % roundi(v * 100.0)
		on_change.call(v)
	)

	hbox.add_child(slider)
	hbox.add_child(pct)
	return hbox

func _divider() -> Control:
	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_top",    UITheme.PAD_S)
	wrapper.add_theme_constant_override("margin_bottom", UITheme.PAD_S)
	var bar := ColorRect.new()
	bar.color                 = UITheme.COLOR_BORDER_HAIR
	bar.custom_minimum_size   = Vector2(0.0, UITheme.HAIR_DIVIDER_H)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(bar)
	return wrapper

# ── Reset confirm flow ───────────────────────────────────────────────────────

func _on_reset_pressed() -> void:
	AudioManager.play("ui_click")
	if _reset_armed and Time.get_ticks_msec() / 1000.0 <= _reset_armed_until:
		_commit_reset()
		return
	_arm_reset()

func _arm_reset() -> void:
	_reset_armed = true
	_reset_armed_until = Time.get_ticks_msec() / 1000.0 + RESET_CONFIRM_WINDOW
	if _reset_btn != null and is_instance_valid(_reset_btn):
		_reset_btn.text = "TAP AGAIN TO CONFIRM"

func _disarm_reset() -> void:
	_reset_armed = false
	_reset_armed_until = 0.0
	if _reset_btn != null and is_instance_valid(_reset_btn):
		_reset_btn.text = "RESET PROGRESS"

func _commit_reset() -> void:
	SaveData.reset_progress()
	if _reset_btn != null and is_instance_valid(_reset_btn):
		_reset_btn.text = "PROGRESS RESET"
	_reset_armed = false
	_reset_armed_until = 0.0

func _process(_delta: float) -> void:
	if _reset_armed and Time.get_ticks_msec() / 1000.0 > _reset_armed_until:
		_disarm_reset()

# ── Close ────────────────────────────────────────────────────────────────────

func _on_back_pressed() -> void:
	AudioManager.play("ui_click")
	closed.emit()

func _on_visibility_changed() -> void:
	if visible and _back_btn != null:
		_back_btn.call_deferred("grab_focus")

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		return
	closed.emit()
	get_viewport().set_input_as_handled()

# ── Buttons ──────────────────────────────────────────────────────────────────

func _make_primary_button(text: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(BTN_W, BTN_H)
	btn.pivot_offset = Vector2(BTN_W * 0.5, BTN_H * 0.5)
	UITheme.apply_primary_button(btn, text, PANEL_CORNER_R)
	_wire_button_motion(btn)
	return btn

# Warn-tinted secondary button used for destructive actions (reset progress).
# Same shape as the lime secondary, just orange-red border + label.
func _make_warn_button(text: String) -> Button:
	var btn := _make_button_base(text, UITheme.COLOR_ACCENT_WARN)
	var normal := StyleBoxFlat.new()
	normal.bg_color     = UITheme.COLOR_PANEL
	normal.border_color = UITheme.COLOR_ACCENT_WARN
	normal.set_border_width_all(int(UITheme.PANEL_BORDER_W))
	normal.set_corner_radius_all(PANEL_CORNER_R)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	var warn_wash := UITheme.COLOR_ACCENT_WARN
	warn_wash.a = 0.14
	hover.bg_color = warn_wash
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color     = UITheme.COLOR_ACCENT_WARN
	pressed.border_color = UITheme.COLOR_ACCENT_WARN
	btn.add_theme_stylebox_override("pressed", pressed)
	_wire_button_motion(btn)
	return btn

func _make_button_base(text: String, font_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text.to_upper()
	btn.custom_minimum_size = Vector2(BTN_W, BTN_H)
	btn.add_theme_font_size_override("font_size", UITheme.FONT_LABEL_CAPS)
	btn.add_theme_color_override("font_color",      font_color)
	btn.add_theme_constant_override("outline_size", 0)
	btn.add_theme_stylebox_override("focus", UITheme.focus_outline_box(PANEL_CORNER_R))
	btn.pivot_offset = Vector2(BTN_W * 0.5, BTN_H * 0.5)
	return btn

func _wire_button_motion(btn: Button) -> void:
	# focus_entered / focus_exited mirror the mouse hover so gamepad and
	# keyboard navigation get the same audio + scale-up affordance.
	var hover_in := func() -> void:
		if not is_instance_valid(btn):
			return
		AudioManager.play("ui_hover")
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_DUR)
	var hover_out := func() -> void:
		if not is_instance_valid(btn):
			return
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2.ONE, HOVER_DUR)
	btn.mouse_entered.connect(hover_in)
	btn.focus_entered.connect(hover_in)
	btn.mouse_exited.connect(hover_out)
	btn.focus_exited.connect(hover_out)
	btn.button_down.connect(func() -> void:
		if not is_instance_valid(btn):
			return
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(0.96, 0.96), PRESS_FLASH_DUR)
	)
	btn.button_up.connect(func() -> void:
		if not is_instance_valid(btn):
			return
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), PRESS_FLASH_DUR)
	)
