extends CanvasLayer

# End-of-run victory modal. Sibling of DeathScreen — same panel skeleton, same
# stat block, same button hierarchy — but tonally celebratory: subtitle in lime
# (not muted), positive stinger, copy that frames the run as a delivery
# completed rather than a loss survived.
#
# `show_results` is called from Game.gd after RunManager.run_won fires.
# `_on_play_again_pressed` / `_on_garage_pressed` are referenced by the button
# signal connections. Do not rename.

const GAME_SCENE_PATH  := "res://scenes/game/Game.tscn"
const START_SCENE_PATH := "res://scenes/ui/StartScreen.tscn"

# ── Layout tokens (8 px grid) — match DeathScreen so the two screens read as
# siblings ──────────────────────────────────────────────────────────────────
const PANEL_PAD_H     := UITheme.PAD_XL * 2
const PANEL_PAD_V     := UITheme.PAD_XL * 2
const PANEL_CORNER_R  := 16
const PANEL_MIN_W     := 560.0
const STAT_ROW_W      := 432.0
const COL_GAP         := UITheme.PAD_L
const STAT_GAP        := UITheme.PAD_M
const TITLE_GAP       := UITheme.PAD_S
const BTN_GAP         := UITheme.PAD_L
const BTN_W           := 224.0
const BTN_H           := 64.0
const DIVIDER_PAD_V   := UITheme.PAD_S

const FADE_TITLE_DUR  := 0.35
const FADE_STAT_DUR   := 0.20
const FADE_STAT_STEP  := 0.08
const FADE_BTN_DUR    := 0.30
const HOVER_SCALE     := 1.03
const HOVER_DUR       := 0.10
const PRESS_FLASH_DUR := 0.08

func show_results(waves: int, gold: int, earned_scrap: int, total_scrap: int) -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build(waves, gold, earned_scrap, total_scrap)
	# Win stinger — reuse the existing positive level-up cue rather than
	# adding a new asset.
	AudioManager.play("level_up", Vector3.INF, -2.0, 0.85)
	get_tree().paused = true

func _build(waves: int, gold: int, earned: int, total: int) -> void:
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

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_MIN_W, 0.0)
	# Use the bright border instead of the dim hairline to mark this as the
	# success variant — one small cue, doesn't break visual parity with Death.
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

	# ── Title block ──────────────────────────────────────────────────────────
	var title_block := VBoxContainer.new()
	title_block.add_theme_constant_override("separation", TITLE_GAP)
	title_block.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(title_block)

	var title := Label.new()
	title.text = "MISSION COMPLETE"
	UITheme.style_heading(title, UITheme.FONT_HEADING_XL, UITheme.COLOR_TEXT_PRIMARY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_block.add_child(title)

	# Subtitle in lime — the tonal flip from DeathScreen, where it's muted.
	# Keeps the lore framing ("drop-off") consistent with the start crawl.
	var subtitle := Label.new()
	subtitle.text = "DROP-OFF REACHED"
	UITheme.style_label_caps(subtitle, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_ACCENT_LIME)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_block.add_child(subtitle)

	col.add_child(_make_divider_block())

	# ── Stat block ───────────────────────────────────────────────────────────
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", STAT_GAP)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(stats)

	var stat_rows: Array[Control] = []
	stat_rows.append(_make_stat_row("WAVES SURVIVED", "%d" % waves))
	stat_rows.append(_make_stat_row("GOLD COLLECTED", "%d" % gold))
	stat_rows.append(_make_stat_row("SCRAP EARNED",   "+%d" % earned))
	stat_rows.append(_make_stat_row("TOTAL SCRAP",    "%d" % total))
	for row in stat_rows:
		stats.add_child(row)

	# ── Button row ───────────────────────────────────────────────────────────
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", BTN_GAP)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_row)

	var play_again_btn := _make_primary_button("PLAY AGAIN")
	var quit_btn       := _make_secondary_button("QUIT")
	play_again_btn.pressed.connect(_on_play_again_pressed)
	quit_btn.pressed.connect(_on_garage_pressed)
	btn_row.add_child(play_again_btn)
	btn_row.add_child(quit_btn)

	_animate_entrance(title_block, stat_rows, btn_row)

func _make_divider_block() -> Control:
	var wrapper := MarginContainer.new()
	wrapper.add_theme_constant_override("margin_top",    DIVIDER_PAD_V)
	wrapper.add_theme_constant_override("margin_bottom", DIVIDER_PAD_V)
	var bar := ColorRect.new()
	bar.color                 = UITheme.COLOR_BORDER_HAIR
	bar.custom_minimum_size   = Vector2(0.0, UITheme.HAIR_DIVIDER_H)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(bar)
	return wrapper

func _make_stat_row(label_text: String, value_text: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(STAT_ROW_W, 0.0)
	hbox.add_theme_constant_override("separation", UITheme.PAD_M)

	var lbl := Label.new()
	lbl.text = label_text
	UITheme.style_label_caps(lbl, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_TEXT_SECONDARY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	UITheme.style_label_caps(val, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_ACCENT_LIME)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(val)
	return hbox

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
	# Mouse signals can fire while the scene is tearing down (button click →
	# change_scene → btn queued for free); guard each tween creation so the
	# captured `btn` isn't dereferenced after free.
	btn.mouse_entered.connect(func() -> void:
		if not is_instance_valid(btn):
			return
		AudioManager.play("ui_hover")
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_DUR)
	)
	btn.mouse_exited.connect(func() -> void:
		if not is_instance_valid(btn):
			return
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2.ONE, HOVER_DUR)
	)
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

func _animate_entrance(title_block: Control, stat_rows: Array[Control], btn_row: Control) -> void:
	title_block.modulate.a = 0.0
	for row in stat_rows:
		row.modulate.a = 0.0
	btn_row.modulate.a = 0.0

	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(title_block, "modulate:a", 1.0, FADE_TITLE_DUR)
	for i in stat_rows.size():
		var row: Control = stat_rows[i]
		t.parallel().tween_property(row, "modulate:a", 1.0, FADE_STAT_DUR) \
			.set_delay(FADE_TITLE_DUR + float(i) * FADE_STAT_STEP)
	var btn_delay: float = FADE_TITLE_DUR + float(stat_rows.size()) * FADE_STAT_STEP
	t.parallel().tween_property(btn_row, "modulate:a", 1.0, FADE_BTN_DUR) \
		.set_delay(btn_delay)

func _on_play_again_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func _on_garage_pressed() -> void:
	# Handler name kept verbatim for parity with DeathScreen. QUIT routes back
	# to the Start screen until the meta-progression flow lands.
	AudioManager.play("ui_click")
	get_tree().paused = false
	get_tree().change_scene_to_file(START_SCENE_PATH)
