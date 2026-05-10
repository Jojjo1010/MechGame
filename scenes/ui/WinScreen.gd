extends CanvasLayer

# End-of-run victory modal. Same panel skeleton + stat block + button
# hierarchy as DeathScreen so the data layer reads as familiar, but layered
# with celebration cues: a falling-confetti backdrop in the archetype palette,
# a scale-punch + hot-pink flash on the title, and a stacked audio stinger
# (level-up + ult-ready). Together they push the screen past "death screen
# but green" into something that actually feels like a finish.
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
	# Layered stinger: level-up melody first, ult-ready confirmation chimes a
	# beat later. Together they read as "victory + confirmed delivery", which
	# the single level-up sound on its own didn't sell.
	AudioManager.play("level_up", Vector3.INF, -2.0, 0.85)
	var late := get_tree().create_timer(0.18, true, false, true)
	late.timeout.connect(func() -> void:
		AudioManager.play("ult_ready", Vector3.INF, -3.0, 1.10)
	)
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

	# Falling confetti behind the panel — procedural rectangles in archetype +
	# accent colors. Spawns once, drifts down through the viewport over a few
	# seconds, then frees itself.
	var confetti := _ConfettiLayer.new()
	confetti.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confetti.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(confetti)
	confetti.spawn(get_viewport().get_visible_rect().size)

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
	play_again_btn.call_deferred("grab_focus")
	quit_btn.pressed.connect(_on_garage_pressed)
	btn_row.add_child(play_again_btn)
	btn_row.add_child(quit_btn)

	_animate_entrance(title, subtitle, stat_rows, btn_row)

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
	btn.add_theme_stylebox_override("focus", UITheme.focus_outline_box(PANEL_CORNER_R))
	btn.pivot_offset = Vector2(BTN_W * 0.5, BTN_H * 0.5)
	return btn

func _wire_button_motion(btn: Button) -> void:
	# Mouse signals can fire while the scene is tearing down (button click →
	# change_scene → btn queued for free); guard each tween creation so the
	# captured `btn` isn't dereferenced after free.
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

func _animate_entrance(title: Label, subtitle: Label, stat_rows: Array[Control], btn_row: Control) -> void:
	# Title pops in with an overshoot scale + hot-pink → white flash; the rest
	# of the panel still fades in (same staggered cadence as DeathScreen) so
	# the punch reads as the celebratory beat against a familiar settle.
	title.modulate = UITheme.COLOR_ACCENT_HOT
	title.scale = Vector2(1.4, 1.4)
	subtitle.modulate.a = 0.0
	for row in stat_rows:
		row.modulate.a = 0.0
	btn_row.modulate.a = 0.0

	# Pivot has to read the post-layout title size or the punch scales from
	# the top-left and slides off-center.
	await get_tree().process_frame
	if not is_instance_valid(title):
		return
	title.pivot_offset = title.size * 0.5

	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.parallel().tween_property(title, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Color settle lags the bounce slightly so the hot-pink flash is still
	# resolving when the title hits its final size.
	t.parallel().tween_property(title, "modulate", Color.WHITE, 0.55)
	t.parallel().tween_property(subtitle, "modulate:a", 1.0, FADE_TITLE_DUR) \
		.set_delay(0.22)
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

# ── Confetti ─────────────────────────────────────────────────────────────────
# Procedural falling-rectangle layer. Spawns a fixed pool of pieces above the
# viewport and lets gravity + a sin-wave horizontal wobble carry them down
# through the screen behind the panel. No assets — just draw_rect + transform.
class _ConfettiLayer extends Control:
	const PIECE_COUNT     := 80
	const FALL_SPEED_MIN  := 180.0
	const FALL_SPEED_MAX  := 320.0
	const DRIFT_X_RANGE   := 60.0
	const ROT_SPEED_RANGE := 4.5
	const WOBBLE_FREQ     := 2.4
	const WOBBLE_AMP_PX   := 55.0
	const GRAVITY         := 35.0
	const PIECE_W_RANGE   := Vector2(8.0, 16.0)
	const PIECE_H_RANGE   := Vector2(4.0, 10.0)
	const LIFETIME_S      := 7.0

	# Hot pink + bright lime for the brand accents, plus the four archetype
	# tints so the confetti reads as "all four mechs cheering".
	const PALETTE := [
		Color("#ff2d6e"),  # COLOR_ACCENT_HOT
		Color("#c8ff58"),  # COLOR_BORDER_BRIGHT
		Color("#e07338"),  # GUN  / VOLLEY
		Color("#3acb74"),  # GARLIC / AEGIS
		Color("#3aa6e6"),  # BEAM   / ARC
		Color("#e6a93a"),  # ROCKET / SALVO
	]

	var _pieces: Array = []
	var _elapsed: float = 0.0

	func spawn(viewport_size: Vector2) -> void:
		_pieces.clear()
		# Spread initial Y across a tall band above the viewport so pieces
		# feed in over a few seconds rather than hitting the screen all at
		# once — gives the burst a sustained "rain" feel.
		for i in PIECE_COUNT:
			_pieces.append({
				"pos":     Vector2(randf_range(0.0, viewport_size.x), randf_range(-viewport_size.y * 1.2, -20.0)),
				"vel":     Vector2(randf_range(-DRIFT_X_RANGE, DRIFT_X_RANGE), randf_range(FALL_SPEED_MIN, FALL_SPEED_MAX)),
				"rot":     randf_range(0.0, TAU),
				"rot_vel": randf_range(-ROT_SPEED_RANGE, ROT_SPEED_RANGE),
				"size":    Vector2(randf_range(PIECE_W_RANGE.x, PIECE_W_RANGE.y), randf_range(PIECE_H_RANGE.x, PIECE_H_RANGE.y)),
				"color":   PALETTE[randi() % PALETTE.size()],
				"phase":   randf() * TAU,
			})
		set_process(true)

	func _process(delta: float) -> void:
		_elapsed += delta
		if _elapsed >= LIFETIME_S:
			queue_free()
			return
		for piece in _pieces:
			piece.vel.y += GRAVITY * delta
			piece.pos += piece.vel * delta
			piece.pos.x += sin(piece.phase + _elapsed * WOBBLE_FREQ) * WOBBLE_AMP_PX * delta
			piece.rot += piece.rot_vel * delta
		queue_redraw()

	func _draw() -> void:
		for piece in _pieces:
			var s: Vector2 = piece.size
			draw_set_transform(piece.pos, piece.rot, Vector2.ONE)
			draw_rect(Rect2(-s * 0.5, s), piece.color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
