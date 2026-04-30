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
const PORTRAIT_SIZE       := 96.0
const PORTRAIT_BORDER     := 4.0
const UPGRADE_SLOT_SIZE   := 36.0
const UPGRADE_SLOT_GAP    := 6.0
const UPGRADE_GRID_COLS   := 6
const NAME_FONT           := 26
const KEY_CHIP_SIZE       := 36.0
const BAR_H               := 14.0

# Per-upgrade-id 2-letter inventory icon. Falls back to first 2 chars of title.
const UPGRADE_ICONS := {
	"gun_firerate":    "FR",
	"gun_damage":      "DM",
	"gun_projectile":  "+1",
	"gun_dot":         "BN",
	"gun_knockback":   "KB",
	"gun_spread":      "SP",
	"gun_splash":      "EX",
	"garlic_firerate": "FR",
	"garlic_damage":   "DM",
	"garlic_range":    "RN",
	"garlic_dot":      "PO",
	"garlic_slow":     "SL",
	"beam_firerate":   "FR",
	"beam_damage":     "DM",
	"beam_bounces":    "+1",
	"beam_range":      "RN",
	"beam_splash":     "ZP",
}

# Rarity → border color (matches UpgradePicker)
const RARITY_BORDERS := [
	Color(0.78, 0.78, 0.85),
	Color(0.45, 0.75, 1.00),
	Color(1.00, 0.80, 0.20),
]

# Per-slot runtime state
var _charge_fills:  Array[ColorRect] = []
var _bar_bgs:       Array[ColorRect] = []
var _ready_labels:  Array[Label]     = []
var _flash_tweens:  Array            = []
var _weapon_names:  Array[String]    = []
var _upgrade_grids: Array[HBoxContainer] = []
var _upgrade_states: Array[Dictionary]   = []   # per slot: { id → { count, badge, count_lbl } }

func _ready() -> void:
	layer = 6

func setup(weapons: Array, mech_colors: Array) -> void:
	var slot_count := weapons.size()
	var total_w := SLOT_W * slot_count + SLOT_GAP * maxi(slot_count - 1, 0)

	# Pin bottom-center via anchors so the bar always sits there even if the
	# viewport hasn't fully laid out by the time setup() runs.
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_left   = 0.5
	root.anchor_right  = 0.5
	root.anchor_top    = 1.0
	root.anchor_bottom = 1.0
	root.offset_left   = -total_w * 0.5
	root.offset_right  = total_w * 0.5
	root.offset_top    = -SLOT_H - MARGIN_BOT
	root.offset_bottom = -MARGIN_BOT
	add_child(root)

	for i in slot_count:
		_build_slot(root, i, weapons[i], mech_colors[i])

	# Connect upgrade pickup → grid badge
	RunManager.upgrade_taken.connect(_on_upgrade_taken)
	# Replay any upgrades already taken (handles scene reload edge cases)
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
	bg_style.bg_color = Color(0.06, 0.05, 0.10, 0.90)
	bg_style.set_corner_radius_all(10)
	bg_style.set_border_width_all(2)
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
	name_lbl.text = weapon.weapon_name
	name_lbl.add_theme_font_size_override("font_size", NAME_FONT)
	name_lbl.add_theme_color_override("font_color",         Color(1.0, 1.0, 1.0, 0.95))
	name_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	name_lbl.add_theme_constant_override("outline_size",    2)
	name_lbl.position     = Vector2(header_x, 14.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(name_lbl)
	_weapon_names.append(weapon.weapon_name)

	var chip := _make_key_chip("E")
	chip.position = Vector2(x + SLOT_W - KEY_CHIP_SIZE - 14.0, 14.0)
	root.add_child(chip)

	# Charge bar — directly below the name, spanning to before the chip
	var bar_y := 14.0 + NAME_FONT + 4.0
	var bar_w := SLOT_W - (PORTRAIT_SIZE + 14.0 + 14.0) - KEY_CHIP_SIZE - 14.0 - 14.0

	var bar_bg := ColorRect.new()
	bar_bg.color    = Color(0.14, 0.11, 0.20, 1.0)
	bar_bg.size     = Vector2(bar_w, BAR_H)
	bar_bg.position = Vector2(header_x, bar_y)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_bg)
	_bar_bgs.append(bar_bg)

	var fill := ColorRect.new()
	fill.color    = Color(0.3, 0.7, 1.0, 0.9)
	fill.size     = Vector2(0.0, BAR_H)
	fill.position = Vector2(header_x, bar_y)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	_charge_fills.append(fill)

	var ready_lbl := Label.new()
	ready_lbl.text = "READY!"
	ready_lbl.add_theme_font_size_override("font_size", 14)
	ready_lbl.add_theme_color_override("font_color",        Color(0.35, 1.0, 0.45, 1.0))
	ready_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.4, 0.0, 0.9))
	ready_lbl.add_theme_constant_override("shadow_offset_x", 1)
	ready_lbl.add_theme_constant_override("shadow_offset_y", 1)
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
	var panel := PanelContainer.new()
	panel.size         = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	style.set_border_width_all(int(PORTRAIT_BORDER))
	style.border_color = Color(0.05, 0.04, 0.08, 1.0)
	panel.add_theme_stylebox_override("panel", style)

	# Stylized "robot face" via positioned ColorRects, drawn in the panel's
	# child layer so they don't get clipped by the StyleBox.
	var inner := Control.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(inner)

	var dark := Color(0.05, 0.04, 0.08, 1.0)
	var s := PORTRAIT_SIZE - PORTRAIT_BORDER * 2.0

	# Eyes
	var eye_w := s * 0.18
	var eye_h := s * 0.13
	var eye_y := s * 0.32
	var eye_l := ColorRect.new()
	eye_l.color    = dark
	eye_l.size     = Vector2(eye_w, eye_h)
	eye_l.position = Vector2(s * 0.20, eye_y)
	eye_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(eye_l)
	var eye_r := ColorRect.new()
	eye_r.color    = dark
	eye_r.size     = Vector2(eye_w, eye_h)
	eye_r.position = Vector2(s * 0.62, eye_y)
	eye_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(eye_r)

	# Mouth/visor
	var mouth_w := s * 0.55
	var mouth_h := s * 0.10
	var mouth := ColorRect.new()
	mouth.color    = dark
	mouth.size     = Vector2(mouth_w, mouth_h)
	mouth.position = Vector2((s - mouth_w) * 0.5, s * 0.62)
	mouth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(mouth)

	return panel

# ── Key chip matching MechOptionsPanel style ──────────────────────────────────
func _make_key_chip(text: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size = Vector2(KEY_CHIP_SIZE, KEY_CHIP_SIZE)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.90, 0.88, 0.80, 1.0)
	style.set_corner_radius_all(5)
	style.content_margin_left   = 0.0
	style.content_margin_right  = 0.0
	style.content_margin_top    = 0.0
	style.content_margin_bottom = 0.0
	chip.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
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
		fill.color        = Color(0.3, 0.7, 1.0, 0.9).lerp(Color(1.0, 0.88, 0.1, 0.9), value)
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
	style.bg_color = Color(0.13, 0.10, 0.20, 1.0)
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = border
	panel.add_theme_stylebox_override("panel", style)

	# Tooltip = full upgrade name (built-in mouse tooltip; works on PanelContainer)
	panel.tooltip_text = "%s — %s" % [upgrade.get("title", ""), upgrade.get("description", "")]

	# Center icon (2-letter code)
	var icon := Label.new()
	var id := String(upgrade.id)
	var code: String = UPGRADE_ICONS[id] if UPGRADE_ICONS.has(id) else _fallback_code(String(upgrade.title))
	icon.text = code
	icon.add_theme_font_size_override("font_size", 14)
	icon.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	icon.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	icon.add_theme_constant_override("outline_size", 2)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)

	# Count badge in top-right (hidden until count > 1)
	var count_lbl := Label.new()
	count_lbl.text = "1"
	count_lbl.add_theme_font_size_override("font_size", 12)
	count_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4, 1.0))
	count_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	count_lbl.add_theme_constant_override("outline_size", 2)
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

func _fallback_code(title: String) -> String:
	var trimmed := title.strip_edges()
	if trimmed.is_empty():
		return "?"
	return trimmed.substr(0, 2).to_upper()
