extends CanvasLayer

# Hades-style level-up picker.
#
# Each level-up:
#   1. The system rolls a single random target (one mech, or LINE) from those
#      that still have available upgrades — "the god that showed up".
#   2. It rolls N_OFFERS boons from that target's pool, weighted by rarity.
#   3. The player picks one. No skip, no rerolls.
#
# Visuals match the in-game dark UI (MechOptionsPanel / ControlsLegend palette):
# dark navy panels, cream chips, light text. The rolled target's portrait is
# highlighted gold; others dim. Equipped slots are shown above the boons.

const Upgrades     := preload("res://src/Upgrades.gd")
const ICON_DIAMOND := preload("res://scenes/ui/IconDiamond.gd")

# ── Sizing ────────────────────────────────────────────────────────────────────
const PORTRAIT_SIZE := 84.0
const PORTRAIT_GAP  := 14.0
const CARD_W        := 320.0
const CARD_H        := 420.0
const CARD_GAP      := 28.0
const ICON_W        := 130.0
const ICON_H        := 110.0
const SLOT_HEX_W    := 116.0
const SLOT_HEX_H    := 100.0
const MAIN_PANEL_W  := 1080.0
const MAIN_PANEL_PAD := 28

const N_OFFERS := 3   # how many boons offered per level-up

# ── Palette aliases (single source of truth: UITheme) ────────────────────────
const BACKDROP      := Color(0.0, 0.0, 0.0, 0.78)
const PANEL_BG      := UITheme.COLOR_PANEL_ALPHA
const PANEL_BG_2    := UITheme.COLOR_PANEL
const TEXT_LIGHT    := UITheme.COLOR_TEXT_PRIMARY
const TEXT_DIM      := UITheme.COLOR_TEXT_SECONDARY
const BORDER_DIM    := UITheme.COLOR_BORDER_HAIR
const BORDER_DARK   := UITheme.COLOR_OUTLINE
# "Rolled target" call-out — hot pink keeps the new selected/committed language
# consistent with the rest of the UI.
const SELECTED_GOLD := UITheme.COLOR_ACCENT_HOT

# ── Rarity styling — lime stays "live", hot pink reserved for rare ───────────
const RARITY_DATA := [
	{name = "COMMON",   fill = UITheme.COLOR_BORDER_HAIR},
	{name = "UNCOMMON", fill = UITheme.COLOR_ACCENT_LIME},
	{name = "RARE",     fill = UITheme.COLOR_ACCENT_HOT},
]
const RARITY_TEXT := [
	UITheme.COLOR_TEXT_MUTED,
	UITheme.COLOR_BORDER_BRIGHT,
	UITheme.COLOR_ACCENT_HOT,
]

# ── Icon code map (shared with UltBar) ────────────────────────────────────────
const UPGRADE_ICONS := {
	"gun_firerate":     "FR",
	"gun_headshot":     "HS",
	"gun_projectile":   "+1",
	"gun_splash":       "EX",
	"gun_pierce":       "PI",
	"garlic_wither":    "WT",
	"garlic_bulwark":   "BW",
	"garlic_range":     "RN",
	"garlic_slow":      "SL",
	"garlic_sanctuary": "SA",
	"beam_firerate":    "FR",
	"beam_damage":      "DM",
	"beam_bounces":     "+1",
	"beam_splash":      "ZP",
	"beam_overcharge":  "OV",
}

# ── Runtime state ─────────────────────────────────────────────────────────────
var _weapons: Array = []
var _targets: Array = []
var _target_colors: Array = []
var _rolled_target_idx: int = -1
var _offered: Array = []
var _pending: int = 0

# UI nodes
var _root: Control
var _backdrop: ColorRect
var _portraits_hbox: HBoxContainer
var _portrait_buttons: Array[Button] = []
var _portrait_styles:  Array[StyleBoxFlat] = []
var _portrait_full_labels: Array[Label] = []
var _subtitle_label:  Label = null
var _equipped_label:  Label = null
var _equipped_row:    HBoxContainer = null
var _cards_row:       HBoxContainer = null

# ── Public ────────────────────────────────────────────────────────────────────
func setup(weapons: Array, mech_colors: Array) -> void:
	_weapons = weapons
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS

	_targets       = []
	_target_colors = []
	for i in weapons.size():
		_targets.append(weapons[i].weapon_name)
		_target_colors.append(mech_colors[i] if i < mech_colors.size() else Color.WHITE)

	_build()
	_root.visible = false
	RunManager.level_up.connect(_on_level_up)

# ── Build (once) ──────────────────────────────────────────────────────────────
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.color = BACKDROP
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	# Headline
	var title := Label.new()
	title.text = "LEVEL UP"
	title.add_theme_font_size_override("font_size", 88)
	title.add_theme_color_override("font_color",         Color(0.98, 0.92, 0.65, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	title.add_theme_constant_override("outline_size",    6)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override("font_size", 38)
	_subtitle_label.add_theme_color_override("font_color",         TEXT_DIM)
	_subtitle_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_subtitle_label.add_theme_constant_override("outline_size",    2)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_subtitle_label)

	# Main dark panel
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(MAIN_PANEL_W, 0.0)
	var ps := StyleBoxFlat.new()
	ps.bg_color = PANEL_BG
	ps.set_corner_radius_all(10)
	ps.set_border_width_all(2)
	ps.border_color = BORDER_DIM
	ps.content_margin_left   = MAIN_PANEL_PAD
	ps.content_margin_right  = MAIN_PANEL_PAD
	ps.content_margin_top    = MAIN_PANEL_PAD
	ps.content_margin_bottom = MAIN_PANEL_PAD
	panel.add_theme_stylebox_override("panel", ps)
	col.add_child(panel)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 18)
	panel.add_child(pv)

	# Portraits row
	_portraits_hbox = HBoxContainer.new()
	_portraits_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_portraits_hbox.add_theme_constant_override("separation", int(PORTRAIT_GAP))
	pv.add_child(_portraits_hbox)
	for i in _targets.size():
		_portraits_hbox.add_child(_build_portrait(i))

	# Equipped section label
	_equipped_label = Label.new()
	_equipped_label.add_theme_font_size_override("font_size", 26)
	_equipped_label.add_theme_color_override("font_color", TEXT_DIM)
	_equipped_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(_equipped_label)

	# Equipped slots row
	_equipped_row = HBoxContainer.new()
	_equipped_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_equipped_row.add_theme_constant_override("separation", 18)
	pv.add_child(_equipped_row)

	# Separator
	var sep := ColorRect.new()
	sep.color = Color(BORDER_DIM.r, BORDER_DIM.g, BORDER_DIM.b, 0.40)
	sep.custom_minimum_size = Vector2(0.0, 1.0)
	pv.add_child(sep)

	# Cards row
	_cards_row = HBoxContainer.new()
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.add_theme_constant_override("separation", int(CARD_GAP))
	pv.add_child(_cards_row)

# ── Portrait construction ─────────────────────────────────────────────────────
func _build_portrait(idx: int) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	btn.text = ""
	# Hades: portraits are display-only (the system picks the target).
	btn.disabled = true
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var color: Color = _target_colors[idx]
	var target_str: String = _targets[idx]

	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.set_corner_radius_all(8)
	st.set_border_width_all(2)
	st.border_color = BORDER_DIM
	btn.add_theme_stylebox_override("normal",   st)
	btn.add_theme_stylebox_override("disabled", st)
	_portrait_styles.append(st)

	# Inner content rendered on top of the button
	var inner := Control.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)
	_draw_face_icon(inner, PORTRAIT_SIZE)

	v.add_child(btn)
	_portrait_buttons.append(btn)

	var lbl := Label.new()
	lbl.text = target_str
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", TEXT_LIGHT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(lbl)

	var full := Label.new()
	full.text = "FULL"
	full.add_theme_font_size_override("font_size", 16)
	full.add_theme_color_override("font_color", Color(0.85, 0.40, 0.30, 1.0))
	full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	full.visible = false
	v.add_child(full)
	_portrait_full_labels.append(full)
	return v

func _draw_face_icon(inner: Control, size: float) -> void:
	var dark := BORDER_DARK
	var s := size - 6.0
	var eye_w := s * 0.18
	var eye_h := s * 0.13
	var eye_y := s * 0.32
	_add_rect(inner, Vector2(s * 0.20, eye_y), Vector2(eye_w, eye_h), dark)
	_add_rect(inner, Vector2(s * 0.62, eye_y), Vector2(eye_w, eye_h), dark)
	var mouth_w := s * 0.55
	var mouth_h := s * 0.10
	_add_rect(inner, Vector2((s - mouth_w) * 0.5, s * 0.62), Vector2(mouth_w, mouth_h), dark)

func _add_rect(parent: Control, pos: Vector2, sz: Vector2, color: Color) -> void:
	var r := ColorRect.new()
	r.color = color
	r.size = sz
	r.position = pos
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)

# ── Show / hide ───────────────────────────────────────────────────────────────
func _on_level_up(_new_level: int) -> void:
	if _root.visible:
		_pending += 1
		return
	_show_picker()

func _show_picker() -> void:
	# Build list of targets that still have available upgrades, mark capped ones FULL
	var available_targets: Array = []
	for i in _targets.size():
		var avail := Upgrades.available_for_target(_weapons, _targets[i])
		var full := avail.is_empty()
		_portrait_full_labels[i].visible = full
		if not full:
			available_targets.append({idx = i, pool = avail})

	# All targets capped — silently consume the level-up
	if available_targets.is_empty():
		if _pending > 0:
			_pending -= 1
		return

	# Roll a random target uniformly across those with offers
	var rolled: Dictionary = available_targets[randi() % available_targets.size()]
	_rolled_target_idx = int(rolled.idx)
	# Roll N_OFFERS rarity-weighted boons from that target's pool
	_offered = Upgrades.pick_weighted(rolled.pool, N_OFFERS)

	# Hide everything that depends on the rolled target until the roll lands
	_subtitle_label.text = "Rolling…"
	_subtitle_label.add_theme_color_override("font_color", TEXT_DIM)
	_equipped_row.visible    = false
	_equipped_label.visible  = false
	_cards_row.visible       = false

	_root.visible = true
	get_tree().paused = true

	# Slot-machine-style cycle through portraits, slowing into the final pick
	await _animate_roll(_rolled_target_idx)

	# Reveal the rolled target's info and boons
	_refresh_subtitle()
	_refresh_equipped_slots()
	_refresh_cards()
	_equipped_label.visible = true
	_equipped_row.visible   = true
	_cards_row.visible      = true

# Cycle the gold border through portraits with progressively longer delays,
# landing on `final_idx` with a tick + ding fanfare.
func _animate_roll(final_idx: int) -> void:
	const TICK_COUNT  := 18
	const TICK_FAST   := 0.06
	const TICK_SLOW   := 0.22
	var n := _portrait_buttons.size()
	if n == 0:
		return
	# Build the sequence: cycle freely for most ticks, then walk the last few
	# steps deterministically into final_idx so the cadence still slows on the
	# correct portrait.
	var seq: Array = []
	# Start from a random portrait so successive level-ups don't always begin the
	# cycle on slot 0 (which would feel scripted).
	var cur := randi() % n
	var path_len: int = mini(4, TICK_COUNT)
	for i in (TICK_COUNT - path_len):
		cur = (cur + 1) % n
		seq.append(cur)
	# Walk into final_idx: each step moves +1 mod n until landing
	for _i in path_len:
		cur = (cur + 1) % n
		seq.append(cur)
	# Force the last to be exactly final_idx (replaces whatever the walk produced)
	seq[seq.size() - 1] = final_idx

	for i in seq.size():
		_highlight_only(seq[i], i == seq.size() - 1)
		var t := float(i) / float(maxi(seq.size() - 1, 1))
		# Quadratic ease-out — fast start, slow finish
		var delay := lerpf(TICK_FAST, TICK_SLOW, t * t)
		if i == seq.size() - 1:
			AudioManager.play("repair_correct_3", Vector3.INF, -2.0, 1.0)
		else:
			AudioManager.play("ui_hover", Vector3.INF, -18.0, randf_range(0.95, 1.10))
		await get_tree().create_timer(delay).timeout

func _highlight_only(idx: int, final: bool = false) -> void:
	for i in _portrait_buttons.size():
		var st := _portrait_styles[i]
		var btn := _portrait_buttons[i]
		if i == idx:
			st.border_color = SELECTED_GOLD
			st.set_border_width_all(6 if final else 4)
			btn.modulate = Color.WHITE
		else:
			st.border_color = BORDER_DIM
			st.set_border_width_all(2)
			btn.modulate = Color(1.0, 1.0, 1.0, 0.40)

func _refresh_portrait_styles() -> void:
	for i in _portrait_buttons.size():
		var st := _portrait_styles[i]
		var btn := _portrait_buttons[i]
		if i == _rolled_target_idx:
			st.border_color = SELECTED_GOLD
			st.set_border_width_all(5)
			btn.modulate = Color.WHITE
		else:
			st.border_color = BORDER_DIM
			st.set_border_width_all(2)
			btn.modulate = Color(1.0, 1.0, 1.0, 0.40)

func _refresh_subtitle() -> void:
	var target_str: String = _targets[_rolled_target_idx]
	var color: Color = MechArchetypes.color_for(target_str)
	_subtitle_label.text = "Upgrade %s" % target_str
	_subtitle_label.add_theme_color_override("font_color", color)

func _refresh_equipped_slots() -> void:
	for child in _equipped_row.get_children():
		child.queue_free()

	var target: String = _targets[_rolled_target_idx]
	var used := RunManager.target_owned_type_count(target)
	_equipped_label.text = "Equipped on %s — %d / %d slots used" % [
		target, used, RunManager.MAX_TYPES_PER_TARGET
	]

	var owned: Dictionary = {}
	if RunManager.owned_upgrades.has(target):
		owned = RunManager.owned_upgrades[target]
	var owned_ids := owned.keys()

	for slot_i in RunManager.MAX_TYPES_PER_TARGET:
		_equipped_row.add_child(_make_slot_column(owned, owned_ids, slot_i))

func _make_slot_column(owned: Dictionary, owned_ids: Array, slot_i: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var hex := Control.new()
	hex.set_script(ICON_DIAMOND)
	hex.custom_minimum_size = Vector2(SLOT_HEX_W, SLOT_HEX_H)
	hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hex)

	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_lbl)

	if slot_i < owned_ids.size():
		var id := String(owned_ids[slot_i])
		var stacks := int(owned[id])
		var upgrade := _find_upgrade_by_id(id)
		var rarity_idx: int = clampi(int(upgrade.get("rarity", 0)), 0, RARITY_DATA.size() - 1)
		var code: String = UPGRADE_ICONS.get(id, _fallback_code(String(upgrade.get("title", ""))))
		hex.set_icon(code, RARITY_DATA[rarity_idx].fill as Color, 36)
		hex.border_color = BORDER_DARK
		hex.queue_redraw()
		var stack_text: String = ""
		if not bool(upgrade.get("unique", false)):
			stack_text = " ×%d" % stacks
		name_lbl.text = String(upgrade.get("title", "")) + stack_text
		name_lbl.add_theme_color_override("font_color", TEXT_LIGHT)
	else:
		# Empty slot: outline-only hex, no icon
		hex.set_icon("", Color(0, 0, 0, 0), 22)
		hex.border_color = Color(BORDER_DIM.r, BORDER_DIM.g, BORDER_DIM.b, 0.45)
		hex.queue_redraw()
		name_lbl.text = "empty"
		name_lbl.add_theme_color_override("font_color", TEXT_DIM)
	return col

func _find_upgrade_by_id(id: String) -> Dictionary:
	for d in Upgrades.ALL:
		if String(d.id) == id:
			return d
	return {}

# ── Boon cards ────────────────────────────────────────────────────────────────
func _refresh_cards() -> void:
	for child in _cards_row.get_children():
		child.queue_free()
	for upgrade in _offered:
		_cards_row.add_child(_make_card(upgrade))

func _make_card(upgrade: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.clip_contents = true
	btn.text = ""
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	var rarity_idx: int = clampi(int(upgrade.get("rarity", 0)), 0, RARITY_DATA.size() - 1)
	var rarity: Dictionary = RARITY_DATA[rarity_idx]
	var target_str: String = String(upgrade.target)
	var target_color: Color = MechArchetypes.color_for(target_str)

	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL_BG_2
	bg.set_corner_radius_all(10)
	bg.set_border_width_all(3)
	bg.border_color = Color(target_color.r, target_color.g, target_color.b, 0.55)
	btn.add_theme_stylebox_override("normal", bg)

	var hover := bg.duplicate()
	hover.bg_color = PANEL_BG_2.lightened(0.06)
	hover.border_color = target_color
	hover.set_border_width_all(4)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := bg.duplicate()
	pressed.bg_color = PANEL_BG_2.darkened(0.10)
	btn.add_theme_stylebox_override("pressed", pressed)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   24)
	margin.add_theme_constant_override("margin_right",  24)
	margin.add_theme_constant_override("margin_top",    24)
	margin.add_theme_constant_override("margin_bottom", 24)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)

	# Rarity tag
	var rarity_lbl := Label.new()
	rarity_lbl.text = String(rarity.name)
	rarity_lbl.add_theme_font_size_override("font_size", 22)
	rarity_lbl.add_theme_color_override("font_color", RARITY_TEXT[rarity_idx])
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rarity_lbl)

	# Hex icon
	var icon_row := CenterContainer.new()
	icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(icon_row)

	var icon := Control.new()
	icon.set_script(ICON_DIAMOND)
	icon.custom_minimum_size = Vector2(ICON_W, ICON_H)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_row.add_child(icon)
	var id := String(upgrade.id)
	var code: String = UPGRADE_ICONS.get(id, _fallback_code(String(upgrade.title)))
	icon.set_icon(code, rarity.fill as Color, 42)
	icon.border_color = BORDER_DARK
	icon.queue_redraw()

	# Title
	var title_lbl := Label.new()
	title_lbl.text = String(upgrade.title)
	title_lbl.add_theme_font_size_override("font_size", 36)
	title_lbl.add_theme_color_override("font_color", TEXT_LIGHT)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title_lbl)

	# Decorative thin separator in the target color
	var sep := ColorRect.new()
	sep.color = Color(target_color.r, target_color.g, target_color.b, 0.40)
	sep.custom_minimum_size = Vector2(80.0, 1.0)
	sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sep)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = String(upgrade.description)
	desc_lbl.add_theme_font_size_override("font_size", 22)
	desc_lbl.add_theme_color_override("font_color", TEXT_DIM)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(desc_lbl)

	# Level indicator at the bottom — "NEW" for fresh picks, "Level X → Level X+1"
	# for stacking commons. Caps the post-pick number at MAX_STACKS_COMMON.
	var stacks_lbl := Label.new()
	var current_stacks := RunManager.upgrade_stack_count(target_str, id)
	if bool(upgrade.get("unique", false)):
		stacks_lbl.text = "unique slot"
	elif current_stacks <= 0:
		stacks_lbl.text = "NEW"
	else:
		var next_level: int = mini(current_stacks + 1, RunManager.MAX_STACKS_COMMON)
		stacks_lbl.text = "Level %d  →  Level %d" % [current_stacks, next_level]
	stacks_lbl.add_theme_font_size_override("font_size", 18)
	stacks_lbl.add_theme_color_override("font_color", TEXT_DIM)
	stacks_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stacks_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stacks_lbl)

	btn.pressed.connect(_on_card_pressed.bind(upgrade))
	btn.mouse_entered.connect(func() -> void: AudioManager.play("ui_hover"))
	return btn

func _fallback_code(title: String) -> String:
	var t := title.strip_edges()
	if t.is_empty():
		return "?"
	return t.substr(0, 2).to_upper()

# ── Selection / close ─────────────────────────────────────────────────────────
func _on_card_pressed(upgrade: Dictionary) -> void:
	AudioManager.play("ui_click")
	Upgrades.apply(upgrade, _weapons)
	RunManager.record_upgrade(upgrade)
	_close()

func _close() -> void:
	_root.visible = false
	if _pending > 0:
		_pending -= 1
		await get_tree().process_frame
		_show_picker()
	else:
		get_tree().paused = false
