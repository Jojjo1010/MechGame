extends Control

# Between-runs upgrade shop. Shows the meta gold balance, lets the player buy
# drone upgrades (multi-level), offer mech-slot unlocks for later mechs, and
# start a new run. Replaces the old Garage screen.

const GAME_SCENE_PATH  := "res://scenes/game/Game.tscn"
const START_SCENE_PATH := "res://scenes/ui/StartScreen.tscn"

const StartScreenDroneScript := preload("res://scenes/ui/StartScreenDrone.gd")

# Overwatch-HUD palette. Bright cyan accent matches Drone.BODY_COLOR so the
# drone and its upgrade UI read as one piece. Filled segments glow; empty ones
# show only a cyan hairline border. Numerals/level text sit beside the bar,
# not inside it — matches the reference HUD style.
const COLOR_BG          := Color(0.04, 0.05, 0.10, 1.0)
const COLOR_CYAN        := Color(0.20, 0.85, 1.00, 1.0)
const COLOR_CYAN_DIM    := Color(0.20, 0.85, 1.00, 0.55)
const COLOR_CYAN_FAINT  := Color(0.10, 0.45, 0.65, 0.85)
const COLOR_TEXT_PRIM   := Color(0.92, 0.97, 1.00, 1.0)
const COLOR_TEXT_MUTED  := Color(0.62, 0.78, 0.86, 1.0)
const COLOR_GOLD        := Color(1.00, 0.82, 0.20, 1.0)

# Segmented level bar — three Overwatch-style chips per upgrade. Filled segments
# = owned level, hairline cyan = next purchasable rung, dim = locked further out.
const SEG_W   := 34.0
const SEG_H   := 14.0
const SEG_GAP := 4.0

# Per-row column widths in the drone upgrade section.
const ROW_LABEL_W   := 240.0
const ROW_LEVEL_W   := 64.0   # space for the "Lv X / Y" caption next to the bar
const ROW_COST_W    := 60.0
const ROW_BTN_W     := 100.0

var _gold_lbl:        Label   = null
var _drone_rows:      Array[Control] = []   # one row per drone upgrade id
var _slot_rows:       Array[Control] = []   # one row per non-starting mech slot

func _ready() -> void:
	_build()
	SaveData.gold_changed.connect(_on_gold_changed)
	SaveData.unlocks_changed.connect(_refresh_slot_rows)
	SaveData.drone_upgrades_changed.connect(_refresh_drone_rows)

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	var title := Label.new()
	title.text = "UPGRADES"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color",      COLOR_CYAN)
	title.add_theme_constant_override("outline_size", 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_gold_lbl = Label.new()
	_gold_lbl.text = "Gold: %d" % SaveData.total_gold
	_gold_lbl.add_theme_font_size_override("font_size", 26)
	_gold_lbl.add_theme_color_override("font_color", COLOR_GOLD)
	_gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_gold_lbl)

	col.add_child(_make_separator())

	# ── Drone upgrades ───────────────────────────────────────────────────────
	var drone_section := Label.new()
	drone_section.text = "DRONE"
	drone_section.add_theme_font_size_override("font_size", 20)
	drone_section.add_theme_color_override("font_color", COLOR_CYAN_DIM)
	col.add_child(drone_section)

	# Side-by-side layout: 3D drone viewport (wrapped in a cyan arc ring) on
	# the left, upgrade rows on the right. Reusing StartScreenDrone gives the
	# cursor-tracking + drift "alive" read without inventing a second drone
	# renderer.
	var drone_hbox := HBoxContainer.new()
	drone_hbox.add_theme_constant_override("separation", 24)
	drone_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(drone_hbox)

	var drone_stack := _DroneRing.new()
	drone_stack.custom_minimum_size = Vector2(300.0, 260.0)
	drone_stack.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	drone_hbox.add_child(drone_stack)

	var drone_visual := StartScreenDroneScript.new()
	# Center the 280×220 viewport inside the 300×260 ring frame (10/20 px pad).
	drone_visual.anchor_left   = 0.5
	drone_visual.anchor_top    = 0.5
	drone_visual.anchor_right  = 0.5
	drone_visual.anchor_bottom = 0.5
	drone_visual.offset_left   = -140.0
	drone_visual.offset_top    = -110.0
	drone_visual.offset_right  = 140.0
	drone_visual.offset_bottom = 110.0
	drone_stack.add_child(drone_visual)

	var rows_col := VBoxContainer.new()
	rows_col.add_theme_constant_override("separation", 10)
	drone_hbox.add_child(rows_col)

	for entry in SaveData.DRONE_UPGRADES:
		var row := _make_drone_row(entry)
		_drone_rows.append(row)
		rows_col.add_child(row)

	col.add_child(_make_separator())

	# ── Mech-slot unlocks ────────────────────────────────────────────────────
	var slot_section := Label.new()
	slot_section.text = "MECH SLOTS"
	slot_section.add_theme_font_size_override("font_size", 20)
	slot_section.add_theme_color_override("font_color", COLOR_CYAN_DIM)
	col.add_child(slot_section)

	for slot_index in range(SaveData.STARTING_MECH_SLOTS, SaveData.MAX_MECH_SLOTS):
		var row := _make_slot_row(slot_index)
		_slot_rows.append(row)
		col.add_child(row)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 16.0)
	col.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_row)

	var back_btn := _make_button("BACK", Color(0.75, 0.85, 1.0))
	back_btn.custom_minimum_size = Vector2(180.0, 60.0)
	back_btn.pressed.connect(_on_back_pressed)
	btn_row.add_child(back_btn)

	var start_btn := _make_button("START NEW RUN", Color(0.55, 1.0, 0.55))
	start_btn.custom_minimum_size = Vector2(280.0, 60.0)
	start_btn.pressed.connect(_on_start_run_pressed)
	btn_row.add_child(start_btn)

func _make_separator() -> Control:
	var sep := ColorRect.new()
	sep.color = COLOR_CYAN_FAINT
	sep.custom_minimum_size = Vector2(680.0, 1.0)
	return sep

# ── Drone upgrade row ─────────────────────────────────────────────────────────

func _make_drone_row(entry: Dictionary) -> Control:
	var id := String(entry.get("id", ""))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.set_meta("upgrade_id", id)

	# ── Label + description column ──────────────────────────────────────────
	var text_col := VBoxContainer.new()
	text_col.custom_minimum_size = Vector2(ROW_LABEL_W, 0.0)
	text_col.add_theme_constant_override("separation", 2)
	text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var label := Label.new()
	label.text = String(entry.get("label", ""))
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COLOR_TEXT_PRIM)
	text_col.add_child(label)

	var desc := Label.new()
	desc.text = String(entry.get("desc", ""))
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(ROW_LABEL_W, 0.0)
	text_col.add_child(desc)
	hbox.add_child(text_col)

	# ── Segmented level bar (Overwatch-HUD style) ───────────────────────────
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", int(SEG_GAP))
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.set_meta("role", "pips")
	hbox.add_child(pips)

	# ── "Lv X / Y" caption next to the bar ──────────────────────────────────
	var level_lbl := Label.new()
	level_lbl.add_theme_font_size_override("font_size", 14)
	level_lbl.add_theme_color_override("font_color", COLOR_CYAN)
	level_lbl.custom_minimum_size = Vector2(ROW_LEVEL_W, 0.0)
	level_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	level_lbl.set_meta("role", "level")
	hbox.add_child(level_lbl)

	# ── Cost ────────────────────────────────────────────────────────────────
	var cost_lbl := Label.new()
	cost_lbl.add_theme_font_size_override("font_size", 18)
	cost_lbl.add_theme_color_override("font_color", COLOR_GOLD)
	cost_lbl.custom_minimum_size = Vector2(ROW_COST_W, 0.0)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cost_lbl.set_meta("role", "cost")
	hbox.add_child(cost_lbl)

	# ── BUY / MAX ───────────────────────────────────────────────────────────
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(ROW_BTN_W, 44.0)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.set_meta("role", "btn")
	btn.pressed.connect(_on_buy_drone_upgrade.bind(id))
	hbox.add_child(btn)

	_apply_drone_row_state(hbox)
	return hbox

func _apply_drone_row_state(row: Control) -> void:
	var id: String = String(row.get_meta("upgrade_id"))
	var pips: HBoxContainer = null
	var level_lbl: Label = null
	var cost_lbl: Label = null
	var btn: Button = null
	for child in row.get_children():
		if child.has_meta("role"):
			match child.get_meta("role"):
				"pips":  pips      = child as HBoxContainer
				"level": level_lbl = child as Label
				"cost":  cost_lbl  = child as Label
				"btn":   btn       = child as Button
	if pips == null or level_lbl == null or cost_lbl == null or btn == null:
		return

	_rebuild_pips(pips, id)

	var lvl  := SaveData.drone_upgrade_level(id)
	var maxl := SaveData.drone_upgrade_max_level(id)
	level_lbl.text = "LV %d/%d" % [lvl, maxl]

	if SaveData.drone_upgrade_at_max(id):
		cost_lbl.text = "MAX"
		cost_lbl.add_theme_color_override("font_color", COLOR_CYAN)
		btn.text = "MAX"
		btn.disabled = true
		_style_button(btn, COLOR_CYAN, true)
		return

	var cost := SaveData.drone_upgrade_next_cost(id)
	cost_lbl.text = "%d" % cost
	cost_lbl.add_theme_color_override("font_color", COLOR_GOLD)
	btn.text = "BUY"
	var affordable := SaveData.can_afford(cost)
	btn.disabled = not affordable
	_style_button(btn, COLOR_CYAN if affordable else Color(0.40, 0.55, 0.65), not affordable)

# Wipe + repopulate the segmented bar for `id`. Cheaper to recreate the small
# PanelContainers than juggle per-segment stylebox swaps when the level changes.
func _rebuild_pips(container: HBoxContainer, id: String) -> void:
	for c in container.get_children():
		c.queue_free()
	var lvl  := SaveData.drone_upgrade_level(id)
	var maxl := SaveData.drone_upgrade_max_level(id)
	for i in maxl:
		container.add_child(_make_pip(i < lvl, i == lvl))

# Each pip is one segment of the Overwatch-style bar. Three states:
#   filled  — owned. Solid cyan glow.
#   is_next — the next purchasable rung. Empty fill, bright cyan hairline.
#   default — locked further out. Empty fill, dim cyan hairline.
func _make_pip(filled: bool, is_next: bool) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(SEG_W, SEG_H)

	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(2)
	if filled:
		sb.bg_color     = COLOR_CYAN
		sb.border_color = Color(0.55, 0.95, 1.00, 1.00)
		sb.set_border_width_all(1)
	elif is_next:
		sb.bg_color     = Color(0.05, 0.20, 0.30, 0.45)
		sb.border_color = COLOR_CYAN
		sb.set_border_width_all(2)
	else:
		sb.bg_color     = Color(0.04, 0.10, 0.18, 0.35)
		sb.border_color = COLOR_CYAN_FAINT
		sb.set_border_width_all(1)
	box.add_theme_stylebox_override("panel", sb)
	return box

# Cyan arc ring drawn behind the drone viewport. Faint full circle with a
# brighter active arc at the top — evokes the HUD ring around the reference
# character without the cost of a full 3D shader pipeline.
class _DroneRing extends Control:
	const RING_CYAN := Color(0.20, 0.85, 1.00, 0.85)
	const RING_DIM  := Color(0.20, 0.85, 1.00, 0.22)
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var center := size * 0.5
		var radius: float = minf(size.x, size.y) * 0.48
		# Faint full circle underneath.
		draw_arc(center, radius, 0.0, TAU, 96, RING_DIM, 2.0, true)
		# Bright active arc at the top (~140° span, slightly tilted).
		draw_arc(center, radius, deg_to_rad(-140.0), deg_to_rad(-40.0), 48, RING_CYAN, 4.0, true)
		# Two small tick caps at the arc endpoints.
		var a1 := deg_to_rad(-140.0)
		var a2 := deg_to_rad(-40.0)
		var p1 := center + Vector2(cos(a1), sin(a1)) * radius
		var p2 := center + Vector2(cos(a2), sin(a2)) * radius
		draw_circle(p1, 4.0, RING_CYAN)
		draw_circle(p2, 4.0, RING_CYAN)

func _on_buy_drone_upgrade(id: String) -> void:
	if SaveData.purchase_drone_upgrade(id):
		AudioManager.play("level_up")
	else:
		AudioManager.play("repair_wrong")

func _refresh_drone_rows() -> void:
	for row in _drone_rows:
		_apply_drone_row_state(row)

# ── Mech-slot row (kept from old Garage) ──────────────────────────────────────

func _make_slot_row(slot_index: int) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(560.0, 0.0)
	hbox.add_theme_constant_override("separation", 12)
	hbox.set_meta("slot_index", slot_index)

	var label := Label.new()
	var label_text := "Slot %d (%s mech)" % [slot_index + 1, _ordinal(slot_index + 1)]
	label.text = label_text
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95, 1.0))
	label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	hbox.add_child(label)

	var cost_lbl := Label.new()
	cost_lbl.add_theme_font_size_override("font_size", 18)
	cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	cost_lbl.custom_minimum_size = Vector2(96.0, 0.0)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_lbl.set_meta("role", "cost")
	hbox.add_child(cost_lbl)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(120.0, 44.0)
	btn.add_theme_font_size_override("font_size", 18)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.set_meta("role", "btn")
	btn.pressed.connect(_on_buy_slot_pressed.bind(slot_index))
	hbox.add_child(btn)

	_apply_slot_state(hbox, slot_index)
	return hbox

func _apply_slot_state(row: Control, slot_index: int) -> void:
	var cost_lbl: Label = null
	var btn: Button = null
	for child in row.get_children():
		if child.has_meta("role"):
			match child.get_meta("role"):
				"cost": cost_lbl = child as Label
				"btn":  btn = child as Button
	if cost_lbl == null or btn == null:
		return

	var cost := SaveData.mech_slot_cost(slot_index)
	var owned := slot_index < SaveData.unlocked_mech_slots
	var prereq_met := slot_index == SaveData.unlocked_mech_slots   # next slot to buy
	var affordable := SaveData.can_afford(cost)

	if owned:
		cost_lbl.text = ""
		btn.text = "OWNED"
		btn.disabled = true
		_style_button(btn, Color(0.55, 1.0, 0.55), true)
	elif not prereq_met:
		cost_lbl.text = "%d" % cost
		btn.text = "LOCKED"
		btn.disabled = true
		_style_button(btn, Color(0.5, 0.5, 0.55), true)
	elif not affordable:
		cost_lbl.text = "%d" % cost
		btn.text = "BUY"
		btn.disabled = true
		_style_button(btn, Color(0.55, 0.55, 0.65), true)
	else:
		cost_lbl.text = "%d" % cost
		btn.text = "BUY"
		btn.disabled = false
		_style_button(btn, Color(0.55, 1.0, 0.55), false)

func _on_buy_slot_pressed(slot_index: int) -> void:
	if slot_index != SaveData.unlocked_mech_slots:
		return   # not the next slot
	if SaveData.unlock_next_mech_slot():
		AudioManager.play("level_up")
	else:
		AudioManager.play("repair_wrong")

func _refresh_slot_rows() -> void:
	for row in _slot_rows:
		var idx: int = int(row.get_meta("slot_index"))
		_apply_slot_state(row, idx)

# ── Shared styling ────────────────────────────────────────────────────────────

func _style_button(btn: Button, accent: Color, disabled: bool) -> void:
	var alpha := 0.45 if disabled else 0.55
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.05, 0.10, 0.95)
	normal.set_corner_radius_all(6)
	normal.set_border_width_all(2)
	normal.border_color = Color(accent.r, accent.g, accent.b, alpha)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("disabled", normal)

	var hover := normal.duplicate()
	hover.bg_color = Color(0.12, 0.10, 0.20, 0.98)
	hover.border_color = accent
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.18, 0.14, 0.28, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed)

	var color := Color(0.55, 0.55, 0.60) if disabled else Color.WHITE
	btn.add_theme_color_override("font_color", color)
	btn.add_theme_color_override("font_disabled_color", color)

func _make_button(text: String, accent: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_constant_override("outline_size", 0)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.05, 0.10, 0.95)
	normal.set_corner_radius_all(8)
	normal.set_border_width_all(2)
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = Color(0.12, 0.10, 0.20, 0.98)
	hover.border_color = accent
	hover.set_border_width_all(3)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.18, 0.14, 0.28, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.mouse_entered.connect(func() -> void: AudioManager.play("ui_hover"))
	return btn

func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
		_: return "%dth" % n

func _on_gold_changed(_total: int) -> void:
	if _gold_lbl != null:
		_gold_lbl.text = "Gold: %d" % SaveData.total_gold
	_refresh_drone_rows()
	_refresh_slot_rows()

func _on_start_run_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE_PATH)

func _on_back_pressed() -> void:
	AudioManager.play("ui_click")
	get_tree().change_scene_to_file(START_SCENE_PATH)
