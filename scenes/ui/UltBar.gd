extends CanvasLayer

# Bottom HUD strip — one slot per mech in the conga line. Each slot has:
#   • Mech portrait on the left (color + stylized face), Bad North style
#   • Weapon name + [E] key chip + charge bar in the middle
#   • Inventory grid of upgrade badges on the right (Ball x Pit style: stacks
#     show as one slot with a count number in the corner)

const SLOT_W              := 380.0
const SLOT_H              := 144.0
const SLOT_GAP            := 16.0
const MARGIN_BOT          := 24.0
const MARGIN_LEFT         := 24.0
const PORTRAIT_SIZE       := 96.0
const PORTRAIT_BORDER     := 4.0
# Inventory has one slot per possible unique upgrade type per weapon. The
# run-side cap is RunManager.MAX_TYPES_PER_TARGET (= 2) — each mech can carry
# at most two distinct upgrade types, with stacks reflected via the count pill.
const MAX_UPGRADE_SLOTS   := 2
const UPGRADE_SLOT_SIZE   := 48.0
const UPGRADE_SLOT_GAP    := 8.0
const NAME_FONT           := 26
const KEY_CHIP_SIZE       := 36.0
const BAR_H               := 14.0

const UpgradeBadgeIconCS := preload("res://scenes/ui/UpgradeBadgeIcon.gd")
const MechPortraitCS     := preload("res://scenes/ui/MechPortrait.gd")

# Rarity → border color. Common = dim lime (frame), uncommon = bright lime
# (live), rare = hot pink (call-out). Lime stays the live signal across the UI.
const RARITY_BORDERS := [
	UITheme.COLOR_BORDER_HAIR,
	UITheme.COLOR_BORDER_BRIGHT,
	UITheme.COLOR_ACCENT_HOT,
]

# Per-slot runtime state
var _root:          Control = null
var _charge_fills:  Array[ColorRect] = []
var _bar_bgs:       Array[ColorRect] = []
var _weapon_names:  Array[String]    = []
var _slot_colors:   Array[Color]     = []   # archetype tint per slot, used by charge fill
var _upgrade_grids: Array[HBoxContainer] = []
var _upgrade_states: Array[Dictionary]   = []   # per slot: { id → { count, slot_idx, count_lbl, count_pill } }
var _upgrade_slot_panels: Array[Array]    = []   # per mech: array of empty/filled placeholder PanelContainers

# Rocket-strike state. ROCKET fires from anywhere via the global R key, so its
# slot uses an "R" chip that pulses to hot pink during aim mode and brightens
# to lime when ready. _rocket_weapon is the weapon ref we poll each frame.
var _rocket_weapon:     Node3D       = null
var _rocket_chip_style: StyleBoxFlat = null
var _rocket_chip_label: Label        = null

func _ready() -> void:
	layer = 6

func setup(weapons: Array, mech_colors: Array) -> void:
	# Re-runnable: called once at boot, then again whenever a mech dies so
	# the bottom strip's slot count tracks the surviving conga line.
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_charge_fills.clear()
	_bar_bgs.clear()
	_weapon_names.clear()
	_slot_colors.clear()
	_upgrade_grids.clear()
	_upgrade_states.clear()
	_upgrade_slot_panels.clear()

	var slot_count := weapons.size()
	if slot_count == 0:
		_root = null
		return

	var total_w := SLOT_W * slot_count + SLOT_GAP * maxi(slot_count - 1, 0)

	# Pin bottom-left via anchors so the bar always sits there even if the
	# viewport hasn't fully laid out by the time setup() runs.
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.anchor_left   = 0.0
	_root.anchor_right  = 0.0
	_root.anchor_top    = 1.0
	_root.anchor_bottom = 1.0
	_root.offset_left   = MARGIN_LEFT
	_root.offset_right  = MARGIN_LEFT + total_w
	_root.offset_top    = -SLOT_H - MARGIN_BOT
	_root.offset_bottom = -MARGIN_BOT
	add_child(_root)

	for i in slot_count:
		_build_slot(_root, i, weapons[i], mech_colors[i])

	# Connect upgrade pickup → grid badge (guard against double-connect on rebuild)
	if not RunManager.upgrade_taken.is_connected(_on_upgrade_taken):
		RunManager.upgrade_taken.connect(_on_upgrade_taken)
	# Replay any upgrades already taken so surviving slots show the inventory
	# they had before the rebuild.
	for u in RunManager.taken_upgrades:
		_apply_upgrade_to_grid(u)

func _build_slot(root: Control, idx: int, weapon: Node3D, color: Color) -> void:
	var x := (SLOT_W + SLOT_GAP) * idx

	# ── Slot background panel ─────────────────────────────────────────────────
	var bg_panel := PanelContainer.new()
	bg_panel.position = Vector2(x, 0.0)
	bg_panel.size     = Vector2(SLOT_W, SLOT_H)
	bg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = UITheme.COLOR_PANEL_ALPHA
	bg_style.set_corner_radius_all(16)
	bg_style.set_border_width_all(int(UITheme.PANEL_BORDER_W))
	# Border picks up the archetype tint at 0.55 alpha — the slot's mech-identity cue.
	bg_style.border_color = Color(color.r, color.g, color.b, 0.55)
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	root.add_child(bg_panel)

	# ── Portrait (Bad North-ish) ──────────────────────────────────────────────
	var portrait := _build_portrait(String(weapon.weapon_name))
	portrait.position = Vector2(x + 14.0, (SLOT_H - PORTRAIT_SIZE) * 0.5)
	root.add_child(portrait)

	# ── Header row: weapon name + [E] chip + charge bar ───────────────────────
	var header_x := x + 14.0 + PORTRAIT_SIZE + 14.0

	var name_lbl := Label.new()
	# Archetype name (VOLLEY / AEGIS / ARC) — display label tinted with the
	# mech color. Matching against upgrades still uses weapon_name (data).
	name_lbl.text = MechArchetypes.name_for(String(weapon.weapon_name))
	name_lbl.add_theme_font_size_override("font_size", NAME_FONT)
	name_lbl.add_theme_color_override("font_color",      color)
	name_lbl.add_theme_constant_override("outline_size", 0)
	name_lbl.position     = Vector2(header_x, 14.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_lbl)
	_weapon_names.append(weapon.weapon_name)
	_slot_colors.append(color)

	# Charge bar — under the name with a comfortable gap. Computed first so the
	# ult chip can be vertically centered with it.
	var bar_y := 14.0 + NAME_FONT + 14.0
	var bar_w := SLOT_W - (PORTRAIT_SIZE + 14.0 + 14.0) - KEY_CHIP_SIZE - 14.0 - 14.0

	# Each slot advertises its actual control: ROCKET fires globally on R, the
	# rest fire on E from the proximity panel. The R chip recolours per-frame
	# based on ready / aim state; the E chip is static.
	var chip: PanelContainer
	if String(weapon.weapon_name) == "ROCKET":
		chip = _make_rocket_strike_chip(color)
		_rocket_weapon = weapon
	else:
		chip = _make_key_chip("E")
	chip.position = Vector2(x + SLOT_W - KEY_CHIP_SIZE - 14.0, bar_y + (BAR_H - KEY_CHIP_SIZE) * 0.5)
	root.add_child(chip)

	var bar_bg := ColorRect.new()
	bar_bg.color    = UITheme.COLOR_DEEP
	bar_bg.size     = Vector2(bar_w, BAR_H)
	bar_bg.position = Vector2(header_x, bar_y)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_bg)
	_bar_bgs.append(bar_bg)

	var fill := ColorRect.new()
	fill.color    = color   # archetype-tinted; lerps to bright lime as it fills
	fill.size     = Vector2(0.0, BAR_H)
	fill.position = Vector2(header_x, bar_y)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	_charge_fills.append(fill)

	# ── Upgrade inventory grid (Ball x Pit-style row of small slots) ──────────
	# Slots are pre-created empty so the row stays a constant strip of squares
	# regardless of how many upgrades have been picked. _fill_slot swaps an
	# empty placeholder into a populated badge in-place — same dimensions either
	# state, so the layout never shifts when a level-up lands.
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", int(UPGRADE_SLOT_GAP))
	grid.position = Vector2(header_x, bar_y + BAR_H + 8.0)
	grid.size     = Vector2(bar_w, UPGRADE_SLOT_SIZE)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grid)
	_upgrade_grids.append(grid)
	_upgrade_states.append({})

	var slot_panels: Array = []
	for j in MAX_UPGRADE_SLOTS:
		var slot_panel := _make_empty_slot()
		grid.add_child(slot_panel)
		slot_panels.append(slot_panel)
	_upgrade_slot_panels.append(slot_panels)

	# ── Connect charge signal ─────────────────────────────────────────────────
	var slot_idx := idx
	weapon.charge_changed.connect(func(v: float) -> void: _on_charge(slot_idx, v))
	# weapon.setup() already emitted charge_changed before this connect ran, so
	# pull the current charge once to seed the bar — otherwise it sits empty on
	# wave 1 even though the ult is fully charged.
	_on_charge(slot_idx, weapon.get_charge())

# ── Portrait construction ─────────────────────────────────────────────────────
# pop_out=false keeps the mech model contained inside its 96px box so the head
# and shoulders don't bleed sideways into the archetype name label.
func _build_portrait(weapon_name: String) -> Control:
	var p: Control = MechPortraitCS.new()
	p.call("setup", weapon_name, PORTRAIT_SIZE, PORTRAIT_BORDER, false)
	return p

# ── Key chip matching MechOptionsPanel style ──────────────────────────────────
func _make_key_chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size = Vector2(KEY_CHIP_SIZE, KEY_CHIP_SIZE)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Lime-bordered key cap matching ControlsLegend's _make_key_cap — dark fill,
	# hairline lime border with a thicker bottom edge for the beveled-key feel.
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_PANEL_ALPHA
	style.border_color = UITheme.COLOR_ACCENT_LIME
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 4
	style.set_corner_radius_all(4)
	style.content_margin_left   = 0.0
	style.content_margin_right  = 0.0
	style.content_margin_top    = 0.0
	style.content_margin_bottom = 0.0
	chip.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_LIME)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	return chip

# Saffron-tinted "R" key chip for the ROCKET slot. The style + label refs are
# stashed on UltBar fields so _process can repaint the border based on the
# weapon's ready / aim state without rebuilding the chip.
func _make_rocket_strike_chip(accent: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size = Vector2(KEY_CHIP_SIZE, KEY_CHIP_SIZE)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_PANEL_ALPHA
	style.border_color = accent
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 4
	style.set_corner_radius_all(4)
	chip.add_theme_stylebox_override("panel", style)
	_rocket_chip_style = style

	var lbl := Label.new()
	lbl.text = "R"
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", accent)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	_rocket_chip_label = lbl
	return chip

# ── Per-frame ROCKET strike state ────────────────────────────────────────────
# Polls the rocket weapon and recolours its R chip to advertise current state:
#   AIMING  → hot pink (committed, click to fire)
#   READY   → bright lime (press R to start aim)
#   COOLING → archetype saffron (charging — bar shows %)
func _process(_delta: float) -> void:
	if _rocket_weapon == null or not is_instance_valid(_rocket_weapon):
		return
	if _rocket_chip_style == null or _rocket_chip_label == null:
		return
	var aiming: bool   = bool(_rocket_weapon.call("is_aim_mode"))
	var ready_now: bool = bool(_rocket_weapon.call("is_ready"))
	var border: Color
	var label_col: Color
	if aiming:
		border    = UITheme.COLOR_ACCENT_HOT
		label_col = UITheme.COLOR_ACCENT_HOT
	elif ready_now:
		border    = UITheme.COLOR_BORDER_BRIGHT
		label_col = UITheme.COLOR_BORDER_BRIGHT
	else:
		# Saffron base = ROCKET archetype tint at slot color.
		var slot_idx := _weapon_names.find("ROCKET")
		var base: Color = _slot_colors[slot_idx] if slot_idx >= 0 and slot_idx < _slot_colors.size() else UITheme.COLOR_ACCENT_LIME
		border    = base
		label_col = base
	_rocket_chip_style.border_color = border
	_rocket_chip_label.add_theme_color_override("font_color", label_col)

# ── Charge fill ───────────────────────────────────────────────────────────────
func _on_charge(idx: int, value: float) -> void:
	if idx >= _charge_fills.size():
		return

	var fill   := _charge_fills[idx]
	var bar_bg := _bar_bgs[idx]
	var bar_w  := bar_bg.size.x

	# Charge fill lerps from archetype tint → bright lime as the ult tops off.
	# At full charge the bar simply stays full and bright — no blink, no label.
	var v := clampf(value, 0.0, 1.0)
	fill.size.x = bar_w * v
	var slot_color: Color = _slot_colors[idx] if idx < _slot_colors.size() else UITheme.COLOR_ACCENT_LIME
	fill.color = slot_color.lerp(UITheme.COLOR_BORDER_BRIGHT, v)

# ── Upgrade grid ──────────────────────────────────────────────────────────────
func _on_upgrade_taken(upgrade: Dictionary) -> void:
	_apply_upgrade_to_grid(upgrade)

func _apply_upgrade_to_grid(upgrade: Dictionary) -> void:
	var target: String = String(upgrade.get("target", ""))
	if target == "" or target == "LINE":
		return   # LINE upgrades aren't tied to a specific mech
	for mech_idx in _weapon_names.size():
		if _weapon_names[mech_idx] != target:
			continue
		var state: Dictionary = _upgrade_states[mech_idx]
		var id: String = String(upgrade.id)
		if state.has(id):
			# Stack count — flip the level pill on and update it to "xN".
			var entry: Dictionary = state[id]
			entry.count = int(entry.count) + 1
			var count_lbl: Label = entry.count_lbl
			count_lbl.text = "x%d" % int(entry.count)
			var count_pill: Control = entry.count_pill
			if count_pill != null:
				count_pill.visible = true
		else:
			var slots: Array = _upgrade_slot_panels[mech_idx]
			var slot_idx: int = state.size()
			if slot_idx >= slots.size():
				return   # safety: more unique upgrades than slots — shouldn't happen
			var panel: PanelContainer = slots[slot_idx]
			_fill_slot(panel, upgrade)
			state[id] = {
				"count":      1,
				"slot_idx":   slot_idx,
				"count_lbl":  panel.get_meta("count_lbl"),
				"count_pill": panel.get_meta("count_pill"),
			}

# Empty placeholder slot — same outer dimensions as a filled badge so the row
# never shifts when an upgrade lands. Dim hairline border, no icon.
func _make_empty_slot() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(UPGRADE_SLOT_SIZE, UPGRADE_SLOT_SIZE)
	panel.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
	panel.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	panel.clip_contents = true

	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_PANEL_ALPHA
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = Color(UITheme.COLOR_BORDER_HAIR.r, UITheme.COLOR_BORDER_HAIR.g, UITheme.COLOR_BORDER_HAIR.b, 0.35)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_meta("style", style)
	return panel

# Populate an empty placeholder with an upgrade's icon, rarity border, tooltip,
# and a hidden stack-count pill. Reuses the panel's existing dimensions so the
# slot stays the same square size in either state.
func _fill_slot(panel: PanelContainer, upgrade: Dictionary) -> void:
	var rarity_idx: int = clampi(int(upgrade.get("rarity", 0)), 0, RARITY_BORDERS.size() - 1)
	var border: Color = RARITY_BORDERS[rarity_idx]

	var style: StyleBoxFlat = panel.get_meta("style")
	style.set_border_width_all(2)
	style.border_color = border

	panel.tooltip_text = "%s — %s" % [upgrade.get("title", ""), upgrade.get("description", "")]

	# PanelContainer fits each direct child to the content rect, which would
	# blow up the corner pill. Wrap the icon + pill in a plain Control so
	# anchors work normally inside it.
	var contents := Control.new()
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(contents)

	# Inset the glyph by a few px on each side so it can't visually crowd or
	# overrun the badge border. clip_contents on the panel still belt-and-braces
	# clips anything UpgradeGlyphs draws past its rect.
	var icon: Control = UpgradeBadgeIconCS.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	const ICON_INSET := 4.0
	icon.offset_left   = ICON_INSET
	icon.offset_top    = ICON_INSET
	icon.offset_right  = -ICON_INSET
	icon.offset_bottom = -ICON_INSET
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_child(icon)
	icon.call("setup", String(upgrade.id), UITheme.COLOR_TEXT_PRIMARY)

	# Level pill in bottom-right (hidden until count > 1). Sized for the 48px
	# slot — dark fill + small font keep the "xN" legible against the icon.
	var count_pill := PanelContainer.new()
	count_pill.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count_pill.offset_left   = -36.0
	count_pill.offset_top    = -24.0
	count_pill.offset_right  = -2.0
	count_pill.offset_bottom = -2.0
	count_pill.visible = false
	count_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = UITheme.COLOR_DEEP
	pill_style.set_corner_radius_all(4)
	pill_style.set_border_width_all(0)
	pill_style.content_margin_left   = 2.0
	pill_style.content_margin_right  = 2.0
	pill_style.content_margin_top    = 0.0
	pill_style.content_margin_bottom = 0.0
	count_pill.add_theme_stylebox_override("panel", pill_style)

	var count_lbl := Label.new()
	count_lbl.text = "x1"
	count_lbl.add_theme_font_size_override("font_size", 18)
	count_lbl.add_theme_color_override("font_color", UITheme.COLOR_TEXT_PRIMARY)
	count_lbl.add_theme_constant_override("outline_size", 0)
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_pill.add_child(count_lbl)

	contents.add_child(count_pill)
	panel.set_meta("count_lbl",  count_lbl)
	panel.set_meta("count_pill", count_pill)
