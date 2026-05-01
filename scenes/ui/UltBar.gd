extends CanvasLayer

# Bottom HUD strip — one slot per mech in the conga line. Each slot has:
#   • Mech portrait on the left (color + stylized face), Bad North style
#   • Weapon name + [E] key chip + charge bar in the middle
#   • Inventory grid of upgrade badges on the right (Ball x Pit style: stacks
#     show as one slot with a count number in the corner)

const SLOT_W              := 380.0
const SLOT_H              := 130.0
const SLOT_GAP            := 16.0
const MARGIN_BOT          := 24.0
const MARGIN_LEFT         := 24.0
const PORTRAIT_SIZE       := 96.0
const PORTRAIT_BORDER     := 4.0
const UPGRADE_SLOT_SIZE   := 36.0
const UPGRADE_SLOT_GAP    := 6.0
const UPGRADE_GRID_COLS   := 6
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
var _ready_labels:  Array[Label]     = []
var _flash_tweens:  Array            = []
var _weapon_names:  Array[String]    = []
var _slot_colors:   Array[Color]     = []   # archetype tint per slot, used by charge fill
var _upgrade_grids: Array[HBoxContainer] = []
var _upgrade_states: Array[Dictionary]   = []   # per slot: { id → { count, badge, count_lbl } }

func _ready() -> void:
	layer = 6

func setup(weapons: Array, mech_colors: Array) -> void:
	# Re-runnable: called once at boot, then again whenever a mech dies so
	# the bottom strip's slot count tracks the surviving conga line.
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_charge_fills.clear()
	_bar_bgs.clear()
	_ready_labels.clear()
	_flash_tweens.clear()
	_weapon_names.clear()
	_slot_colors.clear()
	_upgrade_grids.clear()
	_upgrade_states.clear()

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
	var portrait := _build_portrait(color)
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

	var chip := _make_ult_chip()
	chip.position = Vector2(x + SLOT_W - KEY_CHIP_SIZE - 14.0, 14.0)
	root.add_child(chip)

	# Charge bar — under the name with a comfortable gap
	var bar_y := 14.0 + NAME_FONT + 14.0
	var bar_w := SLOT_W - (PORTRAIT_SIZE + 14.0 + 14.0) - KEY_CHIP_SIZE - 14.0 - 14.0

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

	var ready_lbl := Label.new()
	ready_lbl.text = "READY"
	ready_lbl.add_theme_font_size_override("font_size", 14)
	ready_lbl.add_theme_color_override("font_color",      UITheme.COLOR_ACCENT_HOT)
	ready_lbl.add_theme_constant_override("outline_size", 0)
	ready_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	ready_lbl.size      = Vector2(bar_w, BAR_H)
	ready_lbl.position  = Vector2(header_x, bar_y)
	ready_lbl.visible   = false
	ready_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ready_lbl)
	_ready_labels.append(ready_lbl)
	_flash_tweens.append(null)

	# ── Upgrade inventory grid (Ball x Pit-style row of small slots) ──────────
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", int(UPGRADE_SLOT_GAP))
	grid.position = Vector2(header_x, bar_y + BAR_H + 8.0)
	grid.size     = Vector2(bar_w, UPGRADE_SLOT_SIZE)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grid)
	_upgrade_grids.append(grid)
	_upgrade_states.append({})

	# ── Connect charge signal ─────────────────────────────────────────────────
	var slot_idx := idx
	weapon.charge_changed.connect(func(v: float) -> void: _on_charge(slot_idx, v))

# ── Portrait construction ─────────────────────────────────────────────────────
func _build_portrait(color: Color) -> Control:
	var p: Control = MechPortraitCS.new()
	p.call("setup", color, PORTRAIT_SIZE, PORTRAIT_BORDER)
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

# Same chip frame as _make_key_chip but the content is the ult starburst glyph
# (ActionGlyphs.ult) instead of a key letter — communicates "this charges your
# ult" at a glance.
func _make_ult_chip() -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size = Vector2(KEY_CHIP_SIZE, KEY_CHIP_SIZE)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

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

	var icon := ActionIcon.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.action_id = "ult"
	icon.accent    = UITheme.COLOR_ACCENT_LIME
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(icon)
	return chip

# ── Charge fill ───────────────────────────────────────────────────────────────
func _on_charge(idx: int, value: float) -> void:
	if idx >= _charge_fills.size():
		return

	var fill      := _charge_fills[idx]
	var bar_bg    := _bar_bgs[idx]
	var ready_lbl := _ready_labels[idx]
	var bar_w     := bar_bg.size.x

	if value >= 1.0:
		fill.visible    = false
		bar_bg.visible  = false
		ready_lbl.visible = true
		_start_flash(idx)
	else:
		fill.visible      = true
		bar_bg.visible    = true
		ready_lbl.visible = false
		fill.size.x       = bar_w * value
		# Charge fill lerps from archetype tint → bright lime as the ult tops off.
		var slot_color: Color = _slot_colors[idx] if idx < _slot_colors.size() else UITheme.COLOR_ACCENT_LIME
		fill.color = slot_color.lerp(UITheme.COLOR_BORDER_BRIGHT, value)
		if _flash_tweens[idx] != null:
			_flash_tweens[idx].kill()
			_flash_tweens[idx] = null
		ready_lbl.modulate.a = 1.0

func _start_flash(idx: int) -> void:
	var lbl := _ready_labels[idx]
	if _flash_tweens[idx] != null:
		_flash_tweens[idx].kill()
	var tw := lbl.create_tween().set_loops()
	tw.tween_property(lbl, "modulate:a", 0.2, 0.45)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.45)
	_flash_tweens[idx] = tw

# ── Upgrade grid ──────────────────────────────────────────────────────────────
func _on_upgrade_taken(upgrade: Dictionary) -> void:
	_apply_upgrade_to_grid(upgrade)

func _apply_upgrade_to_grid(upgrade: Dictionary) -> void:
	var target: String = String(upgrade.get("target", ""))
	if target == "" or target == "LINE":
		return   # LINE upgrades aren't tied to a specific mech
	for slot_idx in _weapon_names.size():
		if _weapon_names[slot_idx] != target:
			continue
		var state: Dictionary = _upgrade_states[slot_idx]
		var id: String = String(upgrade.id)
		if state.has(id):
			# Stack count
			var entry: Dictionary = state[id]
			entry.count = int(entry.count) + 1
			var count_lbl: Label = entry.count_lbl
			count_lbl.text = str(entry.count)
			count_lbl.visible = true
		else:
			var badge := _make_upgrade_badge(upgrade)
			_upgrade_grids[slot_idx].add_child(badge)
			state[id] = {
				"count":     1,
				"badge":     badge,
				"count_lbl": badge.get_meta("count_lbl"),
			}

func _make_upgrade_badge(upgrade: Dictionary) -> Control:
	var rarity_idx: int = clampi(int(upgrade.get("rarity", 0)), 0, RARITY_BORDERS.size() - 1)
	var border: Color = RARITY_BORDERS[rarity_idx]

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(UPGRADE_SLOT_SIZE, UPGRADE_SLOT_SIZE)

	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_PANEL_ALPHA
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = border
	panel.add_theme_stylebox_override("panel", style)

	# Tooltip = full upgrade name (built-in mouse tooltip; works on PanelContainer)
	panel.tooltip_text = "%s — %s" % [upgrade.get("title", ""), upgrade.get("description", "")]

	# Center procedural glyph — same renderer used in UpgradePicker.
	var icon: Control = UpgradeBadgeIconCS.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	icon.call("setup", String(upgrade.id), UITheme.COLOR_TEXT_PRIMARY)

	# Count badge in top-right (hidden until count > 1)
	var count_lbl := Label.new()
	count_lbl.text = "1"
	count_lbl.add_theme_font_size_override("font_size", 12)
	count_lbl.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_LIME)
	count_lbl.add_theme_constant_override("outline_size", 0)
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	count_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	count_lbl.offset_left   = -16.0
	count_lbl.offset_top    = -1.0
	count_lbl.offset_right  = -2.0
	count_lbl.offset_bottom = 14.0
	count_lbl.visible = false   # only shown when stack > 1
	count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(count_lbl)
	panel.set_meta("count_lbl", count_lbl)

	return panel
