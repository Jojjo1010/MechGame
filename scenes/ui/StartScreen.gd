extends CanvasLayer

# Title screen. Black backdrop, oversized game title, lime tagline, lore
# paragraph, and a vertical column of buttons. PLAY routes straight into the
# game; HOW TO PLAY opens a modal panel; UPGRADES opens the between-runs
# meta shop; QUIT exits the application. Visual language matches DeathScreen /
# WinScreen so the three modal-style screens read as siblings.

const GAME_SCENE_PATH     := "res://scenes/game/Game.tscn"
const UPGRADES_SCENE_PATH := "res://scenes/upgrades/Upgrades.tscn"
const MechPortraitScript := preload("res://scenes/ui/MechPortrait.gd")
const StartScreenDroneScript := preload("res://scenes/ui/StartScreenDrone.gd")
const StartScreenYouArrowScript := preload("res://scenes/ui/StartScreenYouArrow.gd")
const StartScreenSettingsScript := preload("res://scenes/ui/StartScreenSettings.gd")

# World/run flavor that used to live on its own crawl page. Reads above the
# button column so the player gets the setup before they hit PLAY.
const LORE_TEXT := \
	"The mechs haul cargo.\n" + \
	"Turning was a paid upgrade. Nobody bought it.\n" + \
	"The delivery was supposed to take a week —\n" + \
	"it has been a hundred years.\n\n" + \
	"You're the drone. Patch the dents,\n" + \
	"set off the ults, keep them walking."

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

# Marching mech parade along the bottom of the screen. Cosmetic only — mouse
# filter is IGNORE so clicks pass through to the buttons. Reuses MechPortrait,
# which caches the baked texture per (size, color), so all GUN portraits share
# one texture, all GARLIC share one, etc., regardless of how many march.
const PARADE_MECH_SIZE     := 96.0
const PARADE_MARGIN_BOTTOM := 32.0
const PARADE_SPACING       := 240.0
const PARADE_SPEED         := 90.0   # px/sec, left → right
const PARADE_BOB_AMP       := 4.0    # px
const PARADE_BOB_FREQ      := 2.0    # cycles/sec
const PARADE_WEAPONS       := ["GUN", "GARLIC", "BEAM"]

var _parade_mechs:  Array = []  # Array[Control] — MechPortrait instances
var _parade_phases: Array = []  # Array[float]   — bob phase offset per mech
var _parade_loop_w: float = 0.0 # width of the formation loop for wraparound

# Wrapping all non-backdrop StartScreen visuals lets us hide them in one toggle
# when the settings overlay is open.
var _main_content:    Control = null
var _settings_overlay: Control = null
var _play_btn:        Button  = null

func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	# StartScreen is reached via change_scene, which leaves the tree paused if
	# the previous scene paused it (DeathScreen / WinScreen do). Unpause so
	# tweens, button motion, and audio actually run on this screen.
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	# Wait two frames so CenterContainer has finished laying out the buttons —
	# grab_focus before layout completes can silently no-op.
	await get_tree().process_frame
	await get_tree().process_frame
	if _play_btn != null and is_instance_valid(_play_btn):
		_play_btn.grab_focus()

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

	# Holder for everything except the backdrop. Hidden as one unit when the
	# settings overlay opens so the title/lore/parade don't bleed through.
	_main_content = Control.new()
	_main_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_main_content)

	# ── Title block (anchored above the centered buttons) ────────────────────
	# Anchored relative to screen center so the title sits just above the
	# button area, not pinned to the very top of the screen.
	var title_block := VBoxContainer.new()
	title_block.add_theme_constant_override("separation", TITLE_GAP)
	title_block.alignment = BoxContainer.ALIGNMENT_BEGIN
	title_block.anchor_left   = 0.0
	title_block.anchor_right  = 1.0
	title_block.anchor_top    = 0.5
	title_block.anchor_bottom = 0.5
	title_block.offset_top    = -350.0
	title_block.offset_bottom = -220.0
	title_block.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_main_content.add_child(title_block)

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

	# ── Button column (true screen center) ───────────────────────────────────
	# SIZE_SHRINK_CENTER pins the column to its BTN_W minimum so the buttons
	# don't stretch to the wider container; combined with CenterContainer this
	# puts the buttons at exactly screen_center ± BTN_W/2.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_content.add_child(center)

	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", BTN_GAP)
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(btn_col)

	# ── Lore paragraph (floats just right of the centered button column) ─────
	# Top edge aligns with the top of the button column; left edge sits
	# LORE_GAP px right of the BTN_W-wide buttons.
	const LORE_W := 600.0
	const LORE_GAP := 48.0
	const BTN_COL_HALF_H := (BTN_H * 5.0 + BTN_GAP * 4.0) * 0.5
	var lore := Label.new()
	lore.text = LORE_TEXT
	UITheme.style_body(lore, UITheme.COLOR_TEXT_SECONDARY)
	lore.add_theme_font_size_override("font_size", 24)
	lore.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lore.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	lore.autowrap_mode        = TextServer.AUTOWRAP_OFF
	lore.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	lore.anchor_left   = 0.5
	lore.anchor_right  = 0.5
	lore.anchor_top    = 0.5
	lore.anchor_bottom = 0.5
	lore.offset_left   = BTN_W * 0.5 + LORE_GAP
	lore.offset_right  = lore.offset_left + LORE_W
	lore.offset_top    = -BTN_COL_HALF_H
	lore.offset_bottom = -BTN_COL_HALF_H + 480.0
	_main_content.add_child(lore)

	# Mascot drone, sitting under the lore — the visual answer to "You're the
	# drone." Centered within the lore column so it reads as part of that block.
	# 3D SubViewport, so the body actually tilts toward the cursor instead of
	# faking depth with 2D drawing.
	const DRONE_W := 280.0
	const DRONE_H := 220.0
	const DRONE_TOP_OFFSET := 250.0   # below the lore text
	var drone := StartScreenDroneScript.new()
	var lore_center_x: float = (lore.offset_left + lore.offset_right) * 0.5
	drone.anchor_left   = 0.5
	drone.anchor_right  = 0.5
	drone.anchor_top    = 0.5
	drone.anchor_bottom = 0.5
	drone.offset_left   = lore_center_x - DRONE_W * 0.5
	drone.offset_right  = lore_center_x + DRONE_W * 0.5
	drone.offset_top    = lore.offset_top + DRONE_TOP_OFFSET
	drone.offset_bottom = drone.offset_top + DRONE_H
	_main_content.add_child(drone)

	# "YOU" arrow annotation pointing at the drone — sits to the right of the
	# drone, overlapping its right edge so the arrowhead lands on the body.
	const ARROW_W := 280.0
	const ARROW_H := 200.0
	var you_arrow := StartScreenYouArrowScript.new()
	you_arrow.anchor_left   = 0.5
	you_arrow.anchor_right  = 0.5
	you_arrow.anchor_top    = 0.5
	you_arrow.anchor_bottom = 0.5
	you_arrow.offset_left   = lore_center_x + DRONE_W * 0.18
	you_arrow.offset_right  = you_arrow.offset_left + ARROW_W
	you_arrow.offset_top    = drone.offset_top - 20.0
	you_arrow.offset_bottom = you_arrow.offset_top + ARROW_H
	_main_content.add_child(you_arrow)

	_play_btn     = _make_primary_button("PLAY")
	var how_btn   := _make_secondary_button("HOW TO PLAY")
	var stg_btn   := _make_secondary_button("SETTINGS")
	var upg_btn   := _make_secondary_button("UPGRADES")
	var quit_btn  := _make_secondary_button("QUIT")

	_play_btn.pressed.connect(_on_play_pressed)
	how_btn.pressed.connect(_on_how_to_play_pressed)
	stg_btn.pressed.connect(_on_settings_pressed)
	upg_btn.pressed.connect(_on_upgrades_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)

	btn_col.add_child(_play_btn)
	btn_col.add_child(how_btn)
	btn_col.add_child(stg_btn)
	btn_col.add_child(upg_btn)
	btn_col.add_child(quit_btn)

	var parade_band := _build_mech_parade(_main_content)

	# Settings overlay sits on the root (above _main_content, including the
	# parade) but starts hidden — _on_settings_pressed brings it up.
	_settings_overlay = StartScreenSettingsScript.new()
	_settings_overlay.visible = false
	_settings_overlay.closed.connect(_on_settings_closed)
	root.add_child(_settings_overlay)

	_animate_entrance(title_block, lore, drone, you_arrow, parade_band, [_play_btn, how_btn, stg_btn, upg_btn, quit_btn])

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
	btn.add_theme_stylebox_override("focus", UITheme.focus_outline_box(PANEL_CORNER_R))
	btn.pivot_offset = Vector2(BTN_W * 0.5, BTN_H * 0.5)
	return btn

func _wire_button_motion(btn: Button) -> void:
	# Mouse signals can fire while the scene is tearing down (PLAY/HOW TO PLAY
	# pressed → change_scene → btn queued for free); guard each tween creation
	# so the captured `btn` isn't dereferenced after free.
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
		t.tween_property(btn, "scale", Vector2(0.96, 0.96), PRESS_DUR)
	)
	btn.button_up.connect(func() -> void:
		if not is_instance_valid(btn):
			return
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), PRESS_DUR)
	)

# Title fades in first, lore follows, then each button staggers in below.
func _animate_entrance(title_block: Control, lore: Control, drone: Control, you_arrow: Control, parade: Control, btns: Array) -> void:
	title_block.modulate.a = 0.0
	lore.modulate.a = 0.0
	drone.modulate.a = 0.0
	you_arrow.modulate.a = 0.0
	parade.modulate.a = 0.0
	for b in btns:
		(b as Control).modulate.a = 0.0

	var t := create_tween()
	t.tween_property(title_block, "modulate:a", 1.0, FADE_DUR)
	t.parallel().tween_property(lore, "modulate:a", 1.0, FADE_DUR).set_delay(FADE_DUR * 0.5)
	t.parallel().tween_property(drone, "modulate:a", 1.0, FADE_DUR).set_delay(FADE_DUR * 0.75)
	# Arrow drops in last so the player sees the drone first, *then* the
	# annotation labelling it — reads like a callout being added.
	t.parallel().tween_property(you_arrow, "modulate:a", 1.0, FADE_DUR).set_delay(FADE_DUR * 1.1)
	t.parallel().tween_property(parade, "modulate:a", 1.0, FADE_DUR).set_delay(FADE_DUR * 0.5)
	for i in btns.size():
		var c: Control = btns[i]
		t.parallel().tween_property(c, "modulate:a", 1.0, FADE_DUR) \
			.set_delay(FADE_DUR + float(i) * FADE_STAGGER)

# ── Mech parade ──────────────────────────────────────────────────────────────

# Builds a strip pinned to the bottom of the screen and fills it with mech
# portraits cycling through the three archetype tints. The portraits are
# positioned manually (no container) so we can drive them from _process.
func _build_mech_parade(root: Control) -> Control:
	var band := Control.new()
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top    = -PARADE_MECH_SIZE - PARADE_MARGIN_BOTTOM
	band.offset_bottom = -PARADE_MARGIN_BOTTOM
	band.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	# MechPortrait pop-out renders the mech 1.9× the layout box height, anchored
	# to the bottom — so heads extend above the band into the lore area. That's
	# fine, but the band itself must not clip them.
	band.clip_contents = false
	root.add_child(band)

	var screen_w := float(get_viewport().get_visible_rect().size.x)
	# +1 spare so the leftmost mech can sit just off-screen at all times,
	# keeping the wraparound seam invisible.
	var slots := int(ceil(screen_w / PARADE_SPACING)) + 1
	_parade_loop_w = float(slots) * PARADE_SPACING

	for i in slots:
		var weapon: String = PARADE_WEAPONS[i % PARADE_WEAPONS.size()]
		var portrait: Control = MechPortraitScript.new()
		# facing_deg=180 → front faces +X (screen right), matching the walk
		# direction. Latest FBX exports authored their front toward -X, so the
		# 180° flip puts the noses pointing along the parade march again.
		# weapon_name pulls model + tint from MechArchetypes — the parade reflects
		# whatever per-archetype model is registered there.
		portrait.call("setup", weapon, PARADE_MECH_SIZE, 0.0, true, 180.0)
		# Whole formation starts off-screen to the left, so the title opens
		# empty and the line walks in. i=0 is the front of the conga (closest
		# to the screen edge); higher i sits further off-screen back.
		portrait.position = Vector2(-float(i + 1) * PARADE_SPACING, 0.0)
		band.add_child(portrait)
		_parade_mechs.append(portrait)
		# Stagger bob phase so the mechs don't bob in lockstep — reads as a
		# walking conga line rather than a single bouncing block.
		_parade_phases.append(float(i) * 0.35)

	return band

func _process(delta: float) -> void:
	if _parade_mechs.is_empty() or _parade_loop_w <= 0.0:
		return
	var screen_w := float(get_viewport().get_visible_rect().size.x)
	var t := Time.get_ticks_msec() / 1000.0
	for i in _parade_mechs.size():
		var portrait: Control = _parade_mechs[i]
		if not is_instance_valid(portrait):
			continue
		portrait.position.x += PARADE_SPEED * delta
		if portrait.position.x > screen_w:
			portrait.position.x -= _parade_loop_w
		var phase: float = _parade_phases[i]
		portrait.position.y = sin((t + phase) * PARADE_BOB_FREQ * TAU) * PARADE_BOB_AMP

# ── Handlers ─────────────────────────────────────────────────────────────────

func _on_play_pressed() -> void:
	AudioManager.play("ui_click")
	AudioManager.play_music("bgm_main", -12.0)
	RunManager.tutorial_only = false
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func _on_how_to_play_pressed() -> void:
	AudioManager.play("ui_click")
	AudioManager.play_music("bgm_main", -12.0)
	RunManager.tutorial_only = true
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func _on_settings_pressed() -> void:
	AudioManager.play("ui_click")
	if _settings_overlay == null:
		return
	_main_content.visible = false
	_settings_overlay.visible = true

func _on_settings_closed() -> void:
	if _settings_overlay == null:
		return
	_settings_overlay.visible = false
	_main_content.visible = true
	# Restore focus to PLAY when the overlay closes — settings stole it.
	if _play_btn != null and is_instance_valid(_play_btn):
		_play_btn.call_deferred("grab_focus")

func _on_upgrades_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file(UPGRADES_SCENE_PATH)

func _on_quit_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().quit()
