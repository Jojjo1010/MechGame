extends CanvasLayer

# Pause menu — opens on ESC. Two views:
#   MAIN  — RESUME (primary), DEBUG (secondary), QUIT (secondary)
#   DEBUG — live run stats + action buttons (level-up, gold, heal, kill enemies)
# ESC closes from MAIN, goes back to MAIN from DEBUG.
#
# Spawned from Game.gd as a CanvasLayer at layer 55 (above gameplay UI but
# below DeathScreen at 60). Pauses the tree on open; resumes on close. The
# entire layer runs PROCESS_MODE_ALWAYS so it keeps ticking while paused.

const START_SCENE_PATH := "res://scenes/ui/StartScreen.tscn"
const Upgrades         := preload("res://src/Upgrades.gd")
const MechArchetypesCS := preload("res://scenes/mechs/MechArchetypes.gd")

const PANEL_PAD_H    := UITheme.PAD_XL * 2
const PANEL_PAD_V    := UITheme.PAD_XL * 2
const PANEL_CORNER_R := 16
const PANEL_MIN_W    := 480.0
const COL_GAP        := UITheme.PAD_L
const TITLE_GAP      := UITheme.PAD_S
const BTN_W          := 320.0
const BTN_H          := 64.0
const BTN_GAP        := UITheme.PAD_M

const STAT_GAP       := UITheme.PAD_S
const STAT_ROW_W     := 384.0

const HOVER_SCALE     := 1.03
const HOVER_DUR       := 0.10
const PRESS_FLASH_DUR := 0.08

var _root:           Control = null
var _main_view:      Control = null
var _debug_view:     Control = null
var _settings_view:  Control = null
var _stat_labels:    Dictionary = {}   # label_key -> Label
var _level_target:   SpinBox = null
var _wave_target:    SpinBox = null
var _upgrade_choice: OptionButton = null
var _selected_target_idx: int = 0      # index into the surviving-weapons array
var _target_buttons: Array[Button] = []
var _equipped_label: Label = null

# Resolution presets shown in the settings dropdown. (0,0) is the
# "Fullscreen" entry — handled specially.
const RESOLUTION_OPTIONS := [
	{"label": "Fullscreen",     "size": Vector2i(0, 0),       "fullscreen": true},
	{"label": "1280 × 720",     "size": Vector2i(1280, 720),  "fullscreen": false},
	{"label": "1600 × 900",     "size": Vector2i(1600, 900),  "fullscreen": false},
	{"label": "1920 × 1080",    "size": Vector2i(1920, 1080), "fullscreen": false},
	{"label": "2560 × 1440",    "size": Vector2i(2560, 1440), "fullscreen": false},
]

func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	get_tree().paused = true

func _exit_tree() -> void:
	# Defensive — if we're freed without going through _resume, restore the tree.
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Backdrop — see-through enough that the player still sees the frozen
	# battlefield, dark enough that the menu reads cleanly.
	var backdrop := ColorRect.new()
	var bd_color := UITheme.COLOR_DEEP
	bd_color.a = 0.78
	backdrop.color = bd_color
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(backdrop)

	_main_view     = _build_main_view()
	_debug_view    = _build_debug_view()
	_settings_view = _build_settings_view()
	_root.add_child(_main_view)
	_root.add_child(_debug_view)
	_root.add_child(_settings_view)
	_debug_view.visible    = false
	_settings_view.visible = false

func _build_main_view() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	title.text = "PAUSED"
	UITheme.style_heading(title, UITheme.FONT_HEADING_XL, UITheme.COLOR_TEXT_PRIMARY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", BTN_GAP)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btns)

	var resume   := _make_primary_button("RESUME")
	var settings := _make_secondary_button("SETTINGS")
	var debug    := _make_secondary_button("DEBUG")
	var quit     := _make_secondary_button("QUIT TO MENU")
	resume.pressed.connect(_resume)
	settings.pressed.connect(_show_settings)
	debug.pressed.connect(_show_debug)
	quit.pressed.connect(_quit_to_menu)
	btns.add_child(resume)
	btns.add_child(settings)
	btns.add_child(debug)
	btns.add_child(quit)

	resume.call_deferred("grab_focus")
	return center

func _build_debug_view() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

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
	title.text = "DEBUG"
	UITheme.style_heading(title, UITheme.FONT_HEADING_L, UITheme.COLOR_ACCENT_LIME)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	# ── Live stats block ────────────────────────────────────────────────────
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", STAT_GAP)
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(stats)
	for spec in [
		["WAVE",  "wave"],
		["LEVEL", "level"],
		["XP",    "xp"],
		["GOLD",  "gold"],
		["SCRAP", "scrap"],
		["FPS",   "fps"],
	]:
		stats.add_child(_make_stat_row(spec[0], spec[1]))

	col.add_child(_divider())

	# ── Action buttons ──────────────────────────────────────────────────────
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", BTN_GAP)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(actions)

	actions.add_child(_make_wave_jump_row())
	actions.add_child(_make_level_jump_row())
	actions.add_child(_make_add_upgrade_section())
	var gold_btn   := _make_secondary_button("+500 GOLD")
	var heal_btn   := _make_secondary_button("HEAL ALL MECHS")
	var kill_btn   := _make_secondary_button("KILL ALL ENEMIES")
	var picker_btn := _make_secondary_button("TRIGGER UPGRADE PICKER")
	gold_btn.pressed.connect(_dbg_gold)
	heal_btn.pressed.connect(_dbg_heal)
	kill_btn.pressed.connect(_dbg_kill_enemies)
	picker_btn.pressed.connect(_dbg_trigger_picker)
	actions.add_child(gold_btn)
	actions.add_child(heal_btn)
	actions.add_child(kill_btn)
	actions.add_child(picker_btn)

	col.add_child(_divider())
	actions.add_child(_make_pattern_force_label())
	actions.add_child(_make_pattern_force_grid())

	col.add_child(_divider())

	var back := _make_primary_button("BACK")
	back.pressed.connect(_show_main)
	col.add_child(back)

	return center

func _build_settings_view() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

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

	var back := _make_primary_button("BACK")
	back.pressed.connect(_show_main)
	col.add_child(back)

	return center

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

# ── ESC handling ─────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if UITheme.ui_accept_focused(event, get_viewport()):
		return
	if not (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		return
	if _debug_view.visible or _settings_view.visible:
		_show_main()
	else:
		_resume()
	get_viewport().set_input_as_handled()

# ── View transitions ─────────────────────────────────────────────────────────

func _show_main() -> void:
	AudioManager.play("ui_click")
	_main_view.visible     = true
	_debug_view.visible    = false
	_settings_view.visible = false
	_focus_first_button(_main_view)

func _show_debug() -> void:
	AudioManager.play("ui_click")
	_main_view.visible     = false
	_settings_view.visible = false
	_debug_view.visible    = true
	_refresh_stats()
	_focus_first_button(_debug_view)

func _show_settings() -> void:
	AudioManager.play("ui_click")
	_main_view.visible     = false
	_debug_view.visible    = false
	_settings_view.visible = true
	_focus_first_button(_settings_view)

# Deferred so the view is visible by the time the focus call runs.
func _focus_first_button(view: Control) -> void:
	var target := _find_focusable(view)
	if target != null:
		target.call_deferred("grab_focus")

func _find_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control:
			var ctrl := child as Control
			if ctrl.focus_mode == Control.FOCUS_ALL and not ctrl.is_set_as_top_level():
				return ctrl
		var nested := _find_focusable(child)
		if nested != null:
			return nested
	return null

func _resume() -> void:
	AudioManager.play("ui_click")
	get_tree().paused = false
	queue_free()

func _quit_to_menu() -> void:
	AudioManager.play("ui_click")
	get_tree().paused = false
	get_tree().change_scene_to_file(START_SCENE_PATH)

# ── Debug actions ────────────────────────────────────────────────────────────

func _make_wave_jump_row() -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(BTN_W, 0.0)
	hbox.add_theme_constant_override("separation", UITheme.PAD_S)

	_wave_target = SpinBox.new()
	_wave_target.min_value = 1
	_wave_target.max_value = float(RunManager.WIN_WAVE)
	_wave_target.step      = 1
	_wave_target.value     = float(mini(RunManager.wave + 1, RunManager.WIN_WAVE))
	_wave_target.custom_minimum_size = Vector2(96.0, BTN_H)
	_wave_target.add_theme_font_size_override("font_size", UITheme.FONT_LABEL_CAPS)
	_wave_target.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_wave_target)

	var btn := _make_secondary_button("JUMP TO WAVE")
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0.0, BTN_H)
	btn.pressed.connect(_dbg_jump_to_wave)
	hbox.add_child(btn)
	return hbox

func _dbg_jump_to_wave() -> void:
	AudioManager.play("ui_click")
	var target: int = int(_wave_target.value)
	# WaveSpawner is parked at the Game scene root. Find it via group lookup so
	# we don't hard-couple to the scene path — Game.gd holds the only @onready
	# reference and we can't reach it from the pause menu cleanly otherwise.
	var scene := get_tree().current_scene
	if scene == null:
		return
	var spawner := scene.get_node_or_null("WaveSpawner")
	if spawner == null or not spawner.has_method("set_wave"):
		return
	spawner.set_wave(target)
	queue_free()

func _make_level_jump_row() -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(BTN_W, 0.0)
	hbox.add_theme_constant_override("separation", UITheme.PAD_S)

	_level_target = SpinBox.new()
	_level_target.min_value = 2
	_level_target.max_value = 99
	_level_target.step      = 1
	_level_target.value     = float(RunManager.level + 1)
	_level_target.custom_minimum_size = Vector2(96.0, BTN_H)
	_level_target.add_theme_font_size_override("font_size", UITheme.FONT_LABEL_CAPS)
	_level_target.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_level_target)

	var btn := _make_secondary_button("JUMP TO LEVEL")
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0.0, BTN_H)
	btn.pressed.connect(_dbg_jump_to_level)
	hbox.add_child(btn)
	return hbox

func _dbg_jump_to_level() -> void:
	AudioManager.play("ui_click")
	var target: int = int(_level_target.value)
	if target <= RunManager.level:
		return
	# Silent jump — RunManager.set_level skips the level_up signal so we don't
	# queue a stack of upgrade pickers (one per level skipped). Use the new
	# ADD UPGRADE row to grant specific upgrades after jumping.
	RunManager.set_level(target)
	queue_free()

# ── ADD UPGRADE section ──────────────────────────────────────────────────────
# Three-row layout so a tester can see at a glance which mech they're touching
# and what's already on it:
#   1) tinted target buttons — one per surviving mech, archetype-coloured, the
#      currently-selected one is highlighted
#   2) equipped summary — text line listing what the selected mech already has
#      with stack counts ("Rapid Gun ×2 · Bulwark · Twin Shot")
#   3) available-upgrade dropdown + ADD — dropdown items are annotated so you
#      can read at a glance what's already maxed or already taken
# Replaces the old 3-control row that just said "GUN | Rapid Gun | ADD" with no
# context for either side of the assignment.
func _make_add_upgrade_section() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(BTN_W, 0.0)
	col.add_theme_constant_override("separation", UITheme.PAD_S)

	col.add_child(_make_target_buttons_row())
	_equipped_label = _make_equipped_summary_label()
	col.add_child(_equipped_label)
	col.add_child(_make_upgrade_picker_row())

	_refresh_equipped_summary()
	_populate_upgrade_choices()
	return col

func _make_target_buttons_row() -> Control:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", UITheme.PAD_S)
	_target_buttons.clear()
	var weapons := _get_run_weapons()
	for i in weapons.size():
		var w: Variant = weapons[i]
		if w == null:
			continue
		var weapon_name := String(w.weapon_name)
		var btn := Button.new()
		btn.text = MechArchetypesCS.name_for(weapon_name)
		btn.custom_minimum_size = Vector2(0.0, BTN_H * 0.75)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", UITheme.FONT_LABEL_CAPS)
		btn.add_theme_color_override("font_color", MechArchetypesCS.color_for(weapon_name))
		btn.pressed.connect(_dbg_select_upgrade_target.bind(i))
		_target_buttons.append(btn)
		hbox.add_child(btn)
	_apply_target_button_styles()
	return hbox

func _make_equipped_summary_label() -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(BTN_W, 0.0)
	UITheme.style_body(l)
	return l

func _make_upgrade_picker_row() -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UITheme.PAD_S)

	_upgrade_choice = OptionButton.new()
	_upgrade_choice.add_theme_font_size_override("font_size", UITheme.FONT_LABEL_CAPS)
	_upgrade_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_choice.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_upgrade_choice)

	var btn := _make_secondary_button("ADD")
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.custom_minimum_size = Vector2(96.0, BTN_H)
	btn.pressed.connect(_dbg_apply_upgrade)
	hbox.add_child(btn)
	return hbox

func _dbg_select_upgrade_target(idx: int) -> void:
	AudioManager.play("ui_click")
	_selected_target_idx = idx
	_apply_target_button_styles()
	_refresh_equipped_summary()
	_populate_upgrade_choices()

# Bright the selected button, dim the others. Keeps the "which mech are we
# touching" answer visible without making the user re-read the row.
func _apply_target_button_styles() -> void:
	for i in _target_buttons.size():
		var b := _target_buttons[i]
		if not is_instance_valid(b):
			continue
		var weapons := _get_run_weapons()
		if i >= weapons.size() or weapons[i] == null:
			continue
		var tint: Color = MechArchetypesCS.color_for(String(weapons[i].weapon_name))
		var is_selected := (i == _selected_target_idx)
		var c := tint if is_selected else Color(tint.r, tint.g, tint.b, 0.55)
		b.add_theme_color_override("font_color", c)
		# Brighter font + stronger weight cue for the active mech.
		var font_size := UITheme.FONT_LABEL_CAPS + (4 if is_selected else 0)
		b.add_theme_font_size_override("font_size", font_size)

func _selected_target_name() -> String:
	var weapons := _get_run_weapons()
	if _selected_target_idx < 0 or _selected_target_idx >= weapons.size():
		return ""
	var w: Variant = weapons[_selected_target_idx]
	return String(w.weapon_name) if w != null else ""

func _refresh_equipped_summary() -> void:
	if _equipped_label == null:
		return
	var target_weapon := _selected_target_name()
	if target_weapon == "":
		_equipped_label.text = "(no mech selected)"
		return
	var parts: Array[String] = []
	for d in Upgrades.ALL:
		if String(d.target) != target_weapon:
			continue
		var stacks: int = RunManager.upgrade_stack_count(target_weapon, String(d.id))
		if stacks <= 0:
			continue
		if bool(d.get("unique", false)):
			parts.append(String(d.title))
		else:
			parts.append("%s ×%d" % [String(d.title), stacks])
	var archetype_name := MechArchetypesCS.name_for(target_weapon)
	if parts.is_empty():
		_equipped_label.text = "%s — no upgrades yet" % archetype_name
	else:
		_equipped_label.text = "%s — %s" % [archetype_name, " · ".join(parts)]

# Annotate each upgrade with its current stack state so the tester sees what
# they're about to add: "Rapid Gun (×2/3)" / "Bulwark [MAX]" / "Sanctuary [TAKEN]".
# Debug ADD ignores caps anyway, but the labels make the consequence obvious.
func _populate_upgrade_choices() -> void:
	if _upgrade_choice == null:
		return
	_upgrade_choice.clear()
	var target_weapon := _selected_target_name()
	if target_weapon == "":
		return
	for d in Upgrades.ALL:
		if String(d.target) != target_weapon:
			continue
		var id := String(d.id)
		var title := String(d.title)
		var is_unique: bool = bool(d.get("unique", false))
		var stacks: int = RunManager.upgrade_stack_count(target_weapon, id)
		var label: String = title
		if is_unique:
			var tag: String
			if stacks > 0:
				tag = "TAKEN"
			elif int(d.rarity) == 2:
				tag = "RARE"
			else:
				tag = "UNCOMMON"
			label = "%s [%s]" % [title, tag]
		else:
			if stacks >= RunManager.MAX_STACKS_COMMON:
				label = "%s [MAX]" % title
			else:
				label = "%s (×%d/%d)" % [title, stacks, RunManager.MAX_STACKS_COMMON]
		_upgrade_choice.add_item(label)
		# Stash the upgrade id on the item metadata so _dbg_apply_upgrade doesn't
		# have to reverse-parse the annotated label back into an upgrade.
		_upgrade_choice.set_item_metadata(_upgrade_choice.item_count - 1, id)

func _dbg_apply_upgrade() -> void:
	AudioManager.play("ui_click")
	if _upgrade_choice == null or _upgrade_choice.item_count == 0:
		return
	var id_meta: Variant = _upgrade_choice.get_item_metadata(_upgrade_choice.selected)
	if id_meta == null:
		return
	var id := String(id_meta)
	var upgrade: Dictionary = {}
	for d in Upgrades.ALL:
		if String(d.id) == id:
			upgrade = d
			break
	if upgrade.is_empty():
		return
	var weapons := _get_run_weapons()
	if weapons.is_empty():
		return
	Upgrades.apply(upgrade, weapons)
	RunManager.record_upgrade(upgrade)
	# Refresh both readouts so the tester sees the change without re-opening.
	_refresh_equipped_summary()
	_populate_upgrade_choices()

# Pulls the live weapons array off Game.gd. Game owns the canonical list and
# replays it whenever a mech dies, so this stays in sync without us tracking it.
func _get_run_weapons() -> Array:
	var scene := get_tree().current_scene
	if scene == null:
		return []
	var raw: Variant = scene.get("_weapons")
	if raw is Array:
		return raw
	return []

func _dbg_gold() -> void:
	AudioManager.play("ui_click")
	RunManager.add_gold(500)
	_refresh_stats()

func _dbg_heal() -> void:
	AudioManager.play("ui_click")
	for m in get_tree().get_nodes_in_group("mechs"):
		if not is_instance_valid(m):
			continue
		if not bool(m.get("is_alive")):
			continue
		var max_hp: float = float(m.get("max_health"))
		m.set("health", max_hp)
		if m.has_signal("health_changed"):
			m.emit_signal("health_changed", max_hp, max_hp)

func _dbg_kill_enemies() -> void:
	AudioManager.play("ui_click")
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.has_method("take_damage"):
			e.take_damage(99999.0, true)

# Fires the level_up signal directly so the UpgradePicker plays its full
# slot-machine + cards flow — useful for debugging the picker UI itself
# without needing to grind XP. The receiver ignores the level number, so
# RunManager.level / xp aren't touched. Use JUMP TO LEVEL for actual progression.
func _dbg_trigger_picker() -> void:
	AudioManager.play("ui_click")
	RunManager.level_up.emit(RunManager.level)
	queue_free()

# ── Spawn pattern force ──────────────────────────────────────────────────────
# Labels + ints map to WaveSpawner.Pattern enum order — keep in sync. Clicking
# any button forces the next wave to that pattern AND fires it immediately
# (closes the pause menu so the wave can play out). Lets a tester sample each
# pattern in isolation without rolling and waiting.
const _PATTERN_BUTTONS: Array = [
	["ENCIRCLE",   0],
	["FRONT",      1],
	["L FLANK",    2],
	["R FLANK",    3],
	["REAR",       4],
	["PINCER",     5],
]

func _make_pattern_force_label() -> Control:
	var l := Label.new()
	l.text = "FORCE PATTERN"
	UITheme.style_label_caps(l)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _make_pattern_force_grid() -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UITheme.PAD_S)
	grid.add_theme_constant_override("v_separation", UITheme.PAD_S)
	for entry in _PATTERN_BUTTONS:
		var btn := _make_secondary_button(String(entry[0]))
		btn.custom_minimum_size = Vector2(160.0, BTN_H)
		btn.pressed.connect(_dbg_force_pattern.bind(int(entry[1])))
		grid.add_child(btn)
	return grid

func _dbg_force_pattern(pattern: int) -> void:
	AudioManager.play("ui_click")
	var scene := get_tree().current_scene
	if scene == null:
		return
	var spawner := scene.get_node_or_null("WaveSpawner")
	if spawner == null or not spawner.has_method("force_next_pattern"):
		return
	spawner.force_next_pattern(pattern)
	queue_free()

# ── Stats ────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _debug_view != null and _debug_view.visible:
		_refresh_stats()

func _refresh_stats() -> void:
	_set_stat("wave",  "%d" % RunManager.wave)
	_set_stat("level", "%d" % RunManager.level)
	_set_stat("xp",    "%d / %d" % [RunManager.xp, RunManager.xp_to_next])
	_set_stat("gold",  "%d" % RunManager.gold)
	_set_stat("scrap", "%d" % SaveData.total_scrap)
	_set_stat("fps",   "%d" % Engine.get_frames_per_second())

func _set_stat(key: String, value: String) -> void:
	var lbl: Label = _stat_labels.get(key)
	if lbl != null:
		lbl.text = value

func _make_stat_row(label_text: String, key: String) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(STAT_ROW_W, 0.0)
	hbox.add_theme_constant_override("separation", UITheme.PAD_M)

	var lbl := Label.new()
	lbl.text = label_text
	UITheme.style_label_caps(lbl, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_TEXT_SECONDARY)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)

	var val := Label.new()
	val.text = "—"
	UITheme.style_label_caps(val, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_ACCENT_LIME)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(val)
	_stat_labels[key] = val
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

# ── Buttons (mirrors DeathScreen styling) ────────────────────────────────────

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
	# Mouse signals can fire while the menu is tearing down (PauseMenu close →
	# btn queued for free); guard each tween creation so the captured `btn`
	# isn't dereferenced after free.
	var hover_in := func() -> void:
		if not is_instance_valid(btn):
			return
		AudioManager.play("ui_hover")
		var t := btn.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_property(btn, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_DUR)
	var hover_out := func() -> void:
		if not is_instance_valid(btn):
			return
		var t := btn.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_property(btn, "scale", Vector2.ONE, HOVER_DUR)
	btn.mouse_entered.connect(hover_in)
	btn.focus_entered.connect(hover_in)
	btn.mouse_exited.connect(hover_out)
	btn.focus_exited.connect(hover_out)
	btn.button_down.connect(func() -> void:
		if not is_instance_valid(btn):
			return
		var t := btn.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_property(btn, "scale", Vector2(0.96, 0.96), PRESS_FLASH_DUR)
	)
	btn.button_up.connect(func() -> void:
		if not is_instance_valid(btn):
			return
		var t := btn.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_property(btn, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), PRESS_FLASH_DUR)
	)
