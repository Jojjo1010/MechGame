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

const Upgrades       := preload("res://src/Upgrades.gd")
const ICON_DIAMOND   := preload("res://scenes/ui/IconDiamond.gd")
const MechPortraitCS := preload("res://scenes/ui/MechPortrait.gd")
const CardBackCS     := preload("res://scenes/ui/CardBack.gd")
const MechCarouselCS := preload("res://scenes/ui/MechCarousel.gd")

# ── Sizing ────────────────────────────────────────────────────────────────────
const CAROUSEL_W    := 420.0   # 3D mech carousel width
const CAROUSEL_H    := 480.0
const CAROUSEL_GAP  := 36.0    # between carousel and cards section
const CARD_W        := 320.0
const CARD_H        := 420.0
const CARD_GAP      := 28.0
const ICON_W        := 130.0
const ICON_H        := 110.0
const SLOT_HEX_W    := 116.0
const SLOT_HEX_H    := 100.0
const MAIN_PANEL_W  := 1532.0
const MAIN_PANEL_PAD := 28

const N_OFFERS := 3   # how many boons offered per level-up

# ── Palette aliases (single source of truth: UITheme) ────────────────────────
# Backdrop near-opaque + panels solid: cards read as a clean fixed surface
# rather than a translucent overlay washed out by the world behind.
const BACKDROP      := Color(0.0, 0.0, 0.0, 0.92)
const PANEL_BG      := UITheme.COLOR_PANEL
const PANEL_BG_2    := UITheme.COLOR_PANEL
const TEXT_LIGHT    := UITheme.COLOR_TEXT_PRIMARY
const TEXT_DIM      := UITheme.COLOR_TEXT_SECONDARY
const BORDER_DIM    := UITheme.COLOR_BORDER_HAIR
const BORDER_DARK   := UITheme.COLOR_OUTLINE

# ── Rarity styling — lime stays "live", hot pink reserved for rare ───────────
# COMMON uses a brighter mid-lime than the dim hairline color so the icon hex
# reads cleanly on the card; uncommon stays full-accent lime, rare stays hot
# pink. Common label still uses muted text to keep the rarity hierarchy
# legible at a glance.
const RARITY_DATA := [
	{name = "COMMON",   fill = Color("#92c12a")},
	{name = "UNCOMMON", fill = UITheme.COLOR_ACCENT_LIME},
	{name = "RARE",     fill = UITheme.COLOR_ACCENT_HOT},
]
const RARITY_TEXT := [
	UITheme.COLOR_TEXT_SECONDARY,
	UITheme.COLOR_BORDER_BRIGHT,
	UITheme.COLOR_ACCENT_HOT,
]

# ── Runtime state ─────────────────────────────────────────────────────────────
var _weapons: Array = []
var _targets: Array = []
var _target_colors: Array = []
var _rolled_target_idx: int = -1
var _offered: Array = []
var _pending: int = 0
var _available_pools: Dictionary = {}   # target_idx → pool of upgrades

# UI nodes
var _root: Control
var _backdrop: ColorRect
var _carousel: Control = null   # MechCarousel instance
var _subtitle_label:  Label = null
var _equipped_label:  Label = null
var _equipped_row:    HBoxContainer = null
var _cards_row:       HBoxContainer = null

# ── Public ────────────────────────────────────────────────────────────────────
# Re-runnable: called once at boot and again whenever a mech dies, so the
# portrait row + offer pool track only the surviving mechs.
func setup(weapons: Array, mech_colors: Array) -> void:
	_weapons = weapons
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS

	_targets       = []
	_target_colors = []
	for i in weapons.size():
		_targets.append(weapons[i].weapon_name)
		_target_colors.append(mech_colors[i] if i < mech_colors.size() else Color.WHITE)

	if _root != null and is_instance_valid(_root):
		_root.queue_free()

	_build()
	_root.visible = false
	if not RunManager.level_up.is_connected(_on_level_up):
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
	title.add_theme_color_override("font_color",      Color(0.98, 0.92, 0.65, 1.0))
	title.add_theme_constant_override("outline_size", 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

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

	# Subtitle text — sits at the top of the panel, centered. Color flips to
	# the rolled target's archetype tint in _refresh_subtitle().
	_subtitle_label = Label.new()
	_subtitle_label.add_theme_font_size_override("font_size", 28)
	_subtitle_label.add_theme_color_override("font_color",      TEXT_DIM)
	_subtitle_label.add_theme_constant_override("outline_size", 0)
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pv.add_child(_subtitle_label)

	# Top section: 3D carousel on the left, vertical card column on the right.
	var content_hbox := HBoxContainer.new()
	content_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	content_hbox.add_theme_constant_override("separation", int(CAROUSEL_GAP))
	pv.add_child(content_hbox)

	# Left column: 3D carousel on top, equipped-upgrade slots row underneath
	# (so the slots read as "what this mech is already carrying").
	var carousel_col := VBoxContainer.new()
	carousel_col.alignment = BoxContainer.ALIGNMENT_CENTER
	carousel_col.add_theme_constant_override("separation", 14)
	carousel_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content_hbox.add_child(carousel_col)

	_carousel = MechCarouselCS.new()
	# _targets carries the surviving mechs' weapon names; carousel pulls
	# per-slot model + tint from MechArchetypes.
	_carousel.call("setup", _targets, Vector2(CAROUSEL_W, CAROUSEL_H))
	carousel_col.add_child(_carousel)

	_equipped_row = HBoxContainer.new()
	_equipped_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_equipped_row.add_theme_constant_override("separation", 18)
	carousel_col.add_child(_equipped_row)

	# Cards row — kept horizontal at full width on the right.
	_cards_row = HBoxContainer.new()
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.add_theme_constant_override("separation", int(CARD_GAP))
	_cards_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content_hbox.add_child(_cards_row)

	# Equipped label kept hidden but in the tree for backwards compat.
	_equipped_label = Label.new()
	_equipped_label.add_theme_font_size_override("font_size", 26)
	_equipped_label.add_theme_color_override("font_color", TEXT_DIM)
	_equipped_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_equipped_label.visible = false
	pv.add_child(_equipped_label)

# ── Show / hide ───────────────────────────────────────────────────────────────
func _on_level_up(_new_level: int) -> void:
	if _root.visible:
		_pending += 1
		return
	_show_picker()

func _show_picker() -> void:
	# If the level-up triggered while a weapon was in aim mode, Game.gd left
	# Engine.time_scale at the slow-mo value. The picker pauses gameplay
	# anyway, so kick time back to 1.0 — otherwise the carousel spin and card
	# flips inherit the slow-mo cadence. Game._check_drone_proximity rewrites
	# this on the first unpaused tick after the picker closes.
	Engine.time_scale = 1.0

	# Build list of targets that still have available upgrades.
	_available_pools.clear()
	var available_targets: Array = []
	for i in _targets.size():
		var avail := Upgrades.available_for_target(_weapons, _targets[i])
		if not avail.is_empty():
			_available_pools[i] = avail
			available_targets.append(i)

	# All targets capped — silently consume the level-up
	if available_targets.is_empty():
		if _pending > 0:
			_pending -= 1
		return

	# Roll a random target uniformly from those with offers.
	_rolled_target_idx = available_targets[randi() % available_targets.size()]
	_offered = Upgrades.pick_weighted(_available_pools[_rolled_target_idx], N_OFFERS)

	# Single eligible target (last mech standing, or the others have all
	# capped) — the spin reveals nothing. Snap the carousel and skip straight
	# to the cards.
	if available_targets.size() == 1:
		_root.visible = true
		get_tree().paused = true
		if _carousel != null and is_instance_valid(_carousel):
			# duration=0, revs=0 → tween fires the same frame, no perceived spin.
			_carousel.call("spin_to", _rolled_target_idx, 0.0, 0.0)
		_refresh_subtitle()
		_refresh_equipped_slots()
		_equipped_row.visible = true
		_refresh_cards()
		_cards_row.visible = true
		return

	# Roll setup: subtitle says "Rolling…", equipped section hidden, cards
	# row visible with placeholder ??? cards. Cards flip to real after the
	# carousel disk lands on the rolled mech.
	_subtitle_label.text = "Rolling…"
	_subtitle_label.add_theme_color_override("font_color", TEXT_DIM)
	_equipped_row.visible    = false
	_equipped_label.visible  = false
	_refresh_cards_placeholder()
	_cards_row.visible = true

	_root.visible = true
	get_tree().paused = true

	# Spin the 3D disk to the rolled mech, then reveal. Duration is paced
	# slow enough that the player can read each mech as it passes.
	if _carousel != null and is_instance_valid(_carousel):
		_carousel.call("spin_to", _rolled_target_idx, 3.4)
		await _carousel.landed

	_refresh_subtitle()
	_refresh_equipped_slots()
	_equipped_row.visible = true
	_flip_cards_to_real()

func _refresh_subtitle() -> void:
	var target_str: String = _targets[_rolled_target_idx]
	var color: Color = MechArchetypes.color_for(target_str)
	_subtitle_label.text = "Upgrade %s" % target_str
	_subtitle_label.add_theme_color_override("font_color", color)

func _refresh_equipped_slots() -> void:
	for child in _equipped_row.get_children():
		child.queue_free()

	var target: String = _targets[_rolled_target_idx]

	var owned: Dictionary = {}
	if RunManager.owned_upgrades.has(target):
		owned = RunManager.owned_upgrades[target]
	var owned_ids := owned.keys()

	for slot_i in RunManager.MAX_TYPES_PER_TARGET:
		_equipped_row.add_child(_make_slot_column(owned, owned_ids, slot_i))

func _make_slot_column(owned: Dictionary, owned_ids: Array, slot_i: int) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	# Top-align so the hex sits at the same Y across columns regardless of
	# how many lines the label below wraps to. ALIGNMENT_CENTER pushed the
	# 1-line columns lower than the 2-line ones, staggering the row.
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	# Pin column width to the hex so longer upgrade names ("Napalm Payload")
	# don't push their column wider than an "empty" column. Label autowraps
	# inside this fixed width if needed.
	col.custom_minimum_size = Vector2(SLOT_HEX_W, 0.0)

	var hex := Control.new()
	hex.set_script(ICON_DIAMOND)
	hex.custom_minimum_size = Vector2(SLOT_HEX_W, SLOT_HEX_H)
	hex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hex.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(hex)

	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.custom_minimum_size = Vector2(SLOT_HEX_W, 0.0)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_lbl)

	if slot_i < owned_ids.size():
		var id := String(owned_ids[slot_i])
		var stacks := int(owned[id])
		var upgrade := _find_upgrade_by_id(id)
		var rarity_idx: int = clampi(int(upgrade.get("rarity", 0)), 0, RARITY_DATA.size() - 1)
		hex.set_glyph(id, RARITY_DATA[rarity_idx].fill as Color)
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

# Face-down placeholder cards shown before the player picks a mech. Same shape
# as a real card; "???" content + dim border so they read as concealed.
func _refresh_cards_placeholder() -> void:
	for child in _cards_row.get_children():
		child.queue_free()
	# Per-card seed offset so the three card backs vary slightly, while staying
	# stable for this run.
	var run_seed := hash(RunManager.level)
	for i in N_OFFERS:
		_cards_row.add_child(_make_placeholder_card(run_seed + i * 31))

# Card "flip": collapse old (placeholder) cards horizontally, swap in real
# cards, expand back. Staggered so the row reads as a sequential reveal.
func _flip_cards_to_real() -> void:
	const FLIP_HALF_DUR := 0.16
	const FLIP_STAGGER  := 0.07
	var old_cards := _cards_row.get_children()
	for i in old_cards.size():
		var card: Control = old_cards[i]
		card.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
		var tw := create_tween()
		tw.tween_interval(i * FLIP_STAGGER)
		tw.tween_property(card, "scale:x", 0.0, FLIP_HALF_DUR) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Once all collapse-half tweens finish, rebuild and expand the real cards.
	var total_collapse := (old_cards.size() - 1) * FLIP_STAGGER + FLIP_HALF_DUR + 0.01
	var swap_tw := create_tween()
	swap_tw.tween_interval(total_collapse)
	swap_tw.tween_callback(_reveal_real_cards.bind(FLIP_HALF_DUR, FLIP_STAGGER))

func _reveal_real_cards(half_dur: float, stagger: float) -> void:
	for child in _cards_row.get_children():
		child.queue_free()
	var first_click: Button = null
	for i in _offered.size():
		var card := _make_card(_offered[i])
		card.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
		card.scale.x = 0.0
		_cards_row.add_child(card)
		if i == 0:
			first_click = _find_card_button(card)
		var tw := create_tween()
		tw.tween_interval(i * stagger)
		tw.tween_property(card, "scale:x", 1.0, half_dur) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Grab focus on the leftmost card once all three are present so gamepad /
	# keyboard players can navigate with ui_left/right and confirm with ui_accept.
	if first_click != null:
		first_click.call_deferred("grab_focus")

func _find_card_button(card: Node) -> Button:
	for child in card.get_children():
		if child is Button:
			return child as Button
		var nested := _find_card_button(child)
		if nested != null:
			return nested
	return null

func _make_placeholder_card(seed_value: int = 0) -> Control:
	# Same PanelContainer shape as a real card so the row geometry stays
	# consistent across the flip.
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0.0)
	card.size_flags_vertical = Control.SIZE_FILL
	card.clip_contents = true
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL_BG_2
	bg.set_corner_radius_all(10)
	bg.set_border_width_all(2)
	bg.border_color = BORDER_DIM
	bg.content_margin_left   = 0
	bg.content_margin_right  = 0
	bg.content_margin_top    = 0
	bg.content_margin_bottom = 0
	card.add_theme_stylebox_override("panel", bg)

	var back: Control = CardBackCS.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.call("set_seed", seed_value if seed_value != 0 else randi())
	card.add_child(back)
	return card

# Quiet NEW pill shown next to the rarity tag for fresh / unique picks.
# Dark fill + hairline border keeps it neutral so it advertises freshness
# without adding a third strong accent color to the card.
func _make_new_badge() -> Control:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_DEEP
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color("#6e716e")
	style.content_margin_left   = 8.0
	style.content_margin_right  = 8.0
	style.content_margin_top    = 2.0
	style.content_margin_bottom = 2.0
	pill.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = "NEW"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color",      Color("#c0c4bf"))
	lbl.add_theme_constant_override("outline_size", 0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(lbl)
	return pill

func _make_card(upgrade: Dictionary) -> Control:
	var rarity_idx: int = clampi(int(upgrade.get("rarity", 0)), 0, RARITY_DATA.size() - 1)
	var rarity: Dictionary = RARITY_DATA[rarity_idx]
	var target_str: String = String(upgrade.target)
	var target_color: Color = MechArchetypes.color_for(target_str)

	# PanelContainer auto-sizes to content + content_margins. SIZE_FILL on
	# vertical makes the card stretch to the row height (= tallest sibling),
	# so all three cards land at identical heights.
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_W, 0.0)
	card.size_flags_vertical = Control.SIZE_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS

	var bg := StyleBoxFlat.new()
	bg.bg_color = PANEL_BG_2
	bg.set_corner_radius_all(10)
	bg.set_border_width_all(2)
	# Neutral mid-grey border — the rarity tag, mech identity in the title,
	# and the icon hex already carry the color story. Stays out of the way of
	# the rarity-tinted UNCOMMON / RARE accent colors.
	bg.border_color = Color("#6e716e")
	bg.content_margin_left   = 24
	bg.content_margin_right  = 24
	bg.content_margin_top    = 16
	bg.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", bg)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	# Top-align so two-line wrapped descriptions (e.g. "+3 micro-blasts/impact")
	# don't push the icon + title down compared to neighbouring cards. Each
	# card still SIZE_FILLs to the tallest sibling's height, so a worst-case
	# wrapping card pins the height for the whole row and shorter cards just
	# leave empty space at the bottom.
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)

	# Hover/click overlay — invisible Button stretching across the card. On
	# hover, brighten the card border + lift the card slightly so the player
	# sees their pointer is committing to a real choice.
	var click := Button.new()
	click.flat = true
	click.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	click.add_theme_stylebox_override("normal",   StyleBoxEmpty.new())
	click.add_theme_stylebox_override("hover",    StyleBoxEmpty.new())
	click.add_theme_stylebox_override("pressed",  StyleBoxEmpty.new())
	click.add_theme_stylebox_override("focus",    StyleBoxEmpty.new())
	click.pressed.connect(_on_card_pressed.bind(upgrade))
	# Hover keeps the archetype hue — a small lighten + the scale lift carry
	# the affordance, so the card doesn't snap to a different color entirely.
	# focus_entered / focus_exited mirror mouse hover so gamepad / keyboard
	# navigation gets the same lift + audio cue.
	var idle_border: Color = bg.border_color
	var hover_border: Color = idle_border.lightened(0.25)
	var hover_in := func() -> void:
		AudioManager.play("ui_hover")
		bg.border_color = hover_border
		card.scale = Vector2(1.03, 1.03)
		card.pivot_offset = card.size * 0.5
	var hover_out := func() -> void:
		bg.border_color = idle_border
		card.scale = Vector2.ONE
	click.mouse_entered.connect(hover_in)
	click.focus_entered.connect(hover_in)
	click.mouse_exited.connect(hover_out)
	click.focus_exited.connect(hover_out)
	card.add_child(click)

	# Top row: rarity tag + (when fresh / unique) a NEW badge in hot pink.
	# CenterContainer keeps the row centered whether the badge is present or
	# not, so cards line up regardless.
	var top_row := HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_theme_constant_override("separation", 12)
	top_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top_row)

	var rarity_lbl := Label.new()
	rarity_lbl.text = String(rarity.name)
	rarity_lbl.add_theme_font_size_override("font_size", 22)
	rarity_lbl.add_theme_color_override("font_color", RARITY_TEXT[rarity_idx])
	rarity_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(rarity_lbl)

	var fresh_pick: bool = bool(upgrade.get("unique", false)) \
		or RunManager.upgrade_stack_count(target_str, String(upgrade.id)) <= 0
	if fresh_pick:
		top_row.add_child(_make_new_badge())

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
	icon.set_glyph(id, rarity.fill as Color)
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

	# Hades-style progression block: concrete before → after for the matching
	# weapon's current state. Replaces the "+25% per stack (×1.25 multiplicative)"
	# description with numbers the player can read directly.
	var current_stacks := RunManager.upgrade_stack_count(target_str, id)
	var prog: Dictionary = Upgrades.progression(upgrade, _weapons)
	if prog.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = String(upgrade.description)
		desc_lbl.add_theme_font_size_override("font_size", 22)
		desc_lbl.add_theme_color_override("font_color", TEXT_DIM)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(desc_lbl)
	else:
		var delta_lbl := Label.new()
		delta_lbl.text = "%s %s" % [String(prog.delta), String(prog.stat)]
		delta_lbl.add_theme_font_size_override("font_size", 26)
		delta_lbl.add_theme_color_override("font_color", TEXT_LIGHT)
		delta_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		delta_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		delta_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(delta_lbl)

		# Level N maps to (stacks + 1) so the base / unowned state reads as
		# Level 1 — picking it for the first time advances to Level 2.
		var prog_lbl := Label.new()
		var before := String(prog.before)
		var after  := String(prog.after)
		var cur_lvl: int = current_stacks + 1
		var nxt_lvl: int = current_stacks + 2
		prog_lbl.text = "Level %d  %s   →   Level %d  %s" % [cur_lvl, before, nxt_lvl, after]
		prog_lbl.add_theme_font_size_override("font_size", 20)
		prog_lbl.add_theme_color_override("font_color", TEXT_LIGHT)
		prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prog_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		prog_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(prog_lbl)

	return card

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
