extends CanvasLayer

# Title screen. Black backdrop, oversized game title, lime tagline, and a
# vertical column of buttons. PLAY routes through the lore crawl into the
# game; HOW TO PLAY opens a modal panel; GARAGE is a placeholder pinned to
# "COMING SOON" until the meta-progression flow is wired into the main loop;
# QUIT exits the application. Visual language matches DeathScreen / WinScreen
# so the three modal-style screens read as siblings.

const LORE_SCENE_PATH := "res://scenes/ui/LoreCrawl.tscn"
const GAME_SCENE_PATH := "res://scenes/game/Game.tscn"
const HOW_TO_PLAY_SCRIPT := preload("res://scenes/ui/HowToPlayPanel.gd")

# Layout tokens — same 8 px grid the rest of the UI uses.
const PANEL_CORNER_R := 16
const TITLE_GAP      := UITheme.PAD_S
const SECTION_GAP    := UITheme.PAD_XL * 2   # 64 between title block / buttons
const BTN_GAP        := UITheme.PAD_M
const BTN_W          := 320.0
const BTN_H          := 64.0
const HOVER_SCALE    := 1.03
const HOVER_DUR      := 0.10
const PRESS_DUR      := 0.08
const FADE_DUR       := 0.45
const FADE_STAGGER   := 0.08

func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	# StartScreen is reached via change_scene, which leaves the tree paused if
	# the previous scene paused it (DeathScreen / WinScreen do). Unpause so
	# tweens, button motion, and audio actually run on this screen.
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.color = UITheme.COLOR_DEEP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", SECTION_GAP)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	# ── Title block ──────────────────────────────────────────────────────────
	var title_block := VBoxContainer.new()
	title_block.add_theme_constant_override("separation", TITLE_GAP)
	title_block.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(title_block)

	var title := Label.new()
	title.text = "CONGA MECHS"
	UITheme.style_heading(title, UITheme.FONT_HEADING_XL, UITheme.COLOR_TEXT_PRIMARY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_block.add_child(title)

	var tagline := Label.new()
	tagline.text = "KEEP THEM WALKING"
	UITheme.style_label_caps(tagline, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_ACCENT_LIME)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_block.add_child(tagline)

	# ── Button column ────────────────────────────────────────────────────────
	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", BTN_GAP)
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_col)

	var play_btn := _make_primary_button("PLAY")
	var how_btn  := _make_secondary_button("HOW TO PLAY")
	var grg_btn  := _make_disabled_button("GARAGE — COMING SOON")
	var quit_btn := _make_secondary_button("QUIT")

	play_btn.pressed.connect(_on_play_pressed)
	how_btn.pressed.connect(_on_how_to_play_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	btn_col.add_child(play_btn)
	btn_col.add_child(how_btn)
	btn_col.add_child(grg_btn)
	btn_col.add_child(quit_btn)

	_animate_entrance(title_block, [play_btn, how_btn, grg_btn, quit_btn])

# ── Buttons ──────────────────────────────────────────────────────────────────

func _make_primary_button(text: String) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(BTN_W, BTN_H)
	btn.pivot_offset = Vector2(BTN_W * 0.5, BTN_H * 0.5)
	UITheme.apply_primary_button(btn, text, PANEL_CORNER_R)
	_wire_button_motion(btn)
	return btn

func _make_secondary_button(text: String) -> Button:
	var btn := _make_button_base(text, UITheme.COLOR_ACCENT_LIME)

	var normal := StyleBoxFlat.new()
	normal.bg_color     = UITheme.COLOR_PANEL
	normal.border_color = UITheme.COLOR_ACCENT_LIME
	normal.set_border_width_all(int(UITheme.PANEL_BORDER_W))
	normal.set_corner_radius_all(PANEL_CORNER_R)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	var lime_wash := UITheme.COLOR_ACCENT_LIME
	lime_wash.a = 0.10
	hover.bg_color     = lime_wash
	hover.border_color = UITheme.COLOR_BORDER_BRIGHT
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color     = UITheme.COLOR_ACCENT_HOT
	pressed.border_color = UITheme.COLOR_ACCENT_HOT
	btn.add_theme_stylebox_override("pressed", pressed)

	_wire_button_motion(btn)
	return btn

# Inert "coming soon" button — visible to tease the feature, but no hover, no
# click audio, no motion. Disabled state takes Godot off the focus chain.
func _make_disabled_button(text: String) -> Button:
	var btn := _make_button_base(text, UITheme.COLOR_TEXT_MUTED)
	btn.disabled = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN

	var muted := StyleBoxFlat.new()
	muted.bg_color     = UITheme.COLOR_PANEL
	muted.border_color = UITheme.COLOR_BORDER_HAIR
	muted.set_border_width_all(int(UITheme.PANEL_BORDER_W))
	muted.set_corner_radius_all(PANEL_CORNER_R)
	btn.add_theme_stylebox_override("normal",   muted)
	btn.add_theme_stylebox_override("disabled", muted)
	btn.add_theme_stylebox_override("hover",    muted)
	btn.add_theme_color_override("font_disabled_color", UITheme.COLOR_TEXT_MUTED)
	return btn

func _make_button_base(text: String, font_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text.to_upper()
	btn.custom_minimum_size = Vector2(BTN_W, BTN_H)
	btn.add_theme_font_size_override("font_size", UITheme.FONT_LABEL_CAPS)
	btn.add_theme_color_override("font_color",      font_color)
	btn.add_theme_constant_override("outline_size", 0)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pivot_offset = Vector2(BTN_W * 0.5, BTN_H * 0.5)
	return btn

func _wire_button_motion(btn: Button) -> void:
	btn.mouse_entered.connect(func() -> void:
		AudioManager.play("ui_hover")
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_DUR)
	)
	btn.mouse_exited.connect(func() -> void:
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2.ONE, HOVER_DUR)
	)
	btn.button_down.connect(func() -> void:
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(0.96, 0.96), PRESS_DUR)
	)
	btn.button_up.connect(func() -> void:
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), PRESS_DUR)
	)

# Title fades in first, then each button staggers in below.
func _animate_entrance(title_block: Control, btns: Array) -> void:
	title_block.modulate.a = 0.0
	for b in btns:
		(b as Control).modulate.a = 0.0

	var t := create_tween()
	t.tween_property(title_block, "modulate:a", 1.0, FADE_DUR)
	for i in btns.size():
		var c: Control = btns[i]
		t.parallel().tween_property(c, "modulate:a", 1.0, FADE_DUR) \
			.set_delay(FADE_DUR + float(i) * FADE_STAGGER)

# ── Handlers ─────────────────────────────────────────────────────────────────

func _on_play_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file(LORE_SCENE_PATH)

func _on_how_to_play_pressed() -> void:
	AudioManager.play("ui_click")
	var panel := CanvasLayer.new()
	panel.set_script(HOW_TO_PLAY_SCRIPT)
	add_child(panel)

func _on_quit_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().quit()
