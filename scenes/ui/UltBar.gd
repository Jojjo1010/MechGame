extends CanvasLayer

const SLOT_W        := 240.0
const SLOT_H        := 86.0
const SLOT_GAP      := 12.0
const MARGIN_BOT    := 24.0
const COLOR_STRIP_W := 6.0
const PAD_LEFT      := 14.0
const BAR_H         := 22.0   # tall enough for READY! text
const NAME_FONT     := 28
const KEY_FONT      := 20

var _charge_fills:  Array[ColorRect] = []
var _bar_bgs:       Array[ColorRect] = []
var _ready_labels:  Array[Label]     = []
var _flash_tweens:  Array            = [null, null, null]

func _ready() -> void:
	layer = 6

func setup(weapons: Array, mech_colors: Array) -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var total_w := SLOT_W * weapons.size() + SLOT_GAP * (weapons.size() - 1)

	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect()
	root.position = Vector2((vp.size.x - total_w) * 0.5, vp.size.y - SLOT_H - MARGIN_BOT)

	for i in weapons.size():
		var weapon   = weapons[i]
		var color: Color = mech_colors[i]
		var x := (SLOT_W + SLOT_GAP) * i
		var bar_y := SLOT_H - BAR_H - 6.0

		# ── Slot background ───────────────────────────────────
		var bg := ColorRect.new()
		bg.color        = Color(0.06, 0.05, 0.10, 0.84)
		bg.size         = Vector2(SLOT_W, SLOT_H)
		bg.position     = Vector2(x, 0.0)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)

		# ── Mech colour strip (left edge) ─────────────────────
		var strip := ColorRect.new()
		strip.color        = color
		strip.size         = Vector2(COLOR_STRIP_W, SLOT_H)
		strip.position     = Vector2(x, 0.0)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(strip)

		# ── Weapon name ───────────────────────────────────────
		var name_lbl := Label.new()
		name_lbl.text = weapon.weapon_name
		name_lbl.add_theme_font_size_override("font_size", NAME_FONT)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
		name_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
		name_lbl.add_theme_constant_override("shadow_offset_x", 1)
		name_lbl.add_theme_constant_override("shadow_offset_y", 1)
		name_lbl.position     = Vector2(x + COLOR_STRIP_W + PAD_LEFT, 10.0)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(name_lbl)

		# ── [E] key hint ──────────────────────────────────────
		var key_lbl := Label.new()
		key_lbl.text = "[E]"
		key_lbl.add_theme_font_size_override("font_size", KEY_FONT)
		key_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.45, 0.90))
		key_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
		key_lbl.add_theme_constant_override("shadow_offset_x", 1)
		key_lbl.add_theme_constant_override("shadow_offset_y", 1)
		key_lbl.position     = Vector2(x + SLOT_W - 46.0, 12.0)
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(key_lbl)

		# ── Charge bar background ─────────────────────────────
		var bar_bg := ColorRect.new()
		bar_bg.color        = Color(0.14, 0.11, 0.20, 1.0)
		bar_bg.size         = Vector2(SLOT_W - COLOR_STRIP_W - 2.0, BAR_H)
		bar_bg.position     = Vector2(x + COLOR_STRIP_W + 2.0, bar_y)
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar_bg)
		_bar_bgs.append(bar_bg)

		# ── Charge fill ───────────────────────────────────────
		var fill := ColorRect.new()
		fill.color        = Color(0.3, 0.7, 1.0, 0.9)
		fill.size         = Vector2(0.0, BAR_H)
		fill.position     = Vector2(x + COLOR_STRIP_W + 2.0, bar_y)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(fill)
		_charge_fills.append(fill)

		# ── READY! label — replaces bar when ult is charged ───
		var ready_lbl := Label.new()
		ready_lbl.text = "READY!"
		ready_lbl.add_theme_font_size_override("font_size", 18)
		ready_lbl.add_theme_color_override("font_color",        Color(0.35, 1.0, 0.45, 1.0))
		ready_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.4, 0.0, 0.9))
		ready_lbl.add_theme_constant_override("shadow_offset_x", 1)
		ready_lbl.add_theme_constant_override("shadow_offset_y", 1)
		ready_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ready_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		ready_lbl.size         = Vector2(SLOT_W - COLOR_STRIP_W - 2.0, BAR_H)
		ready_lbl.position     = Vector2(x + COLOR_STRIP_W + 2.0, bar_y)
		ready_lbl.visible      = false
		ready_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(ready_lbl)
		_ready_labels.append(ready_lbl)

		# ── Connect charge signal ─────────────────────────────
		var idx := i
		weapon.charge_changed.connect(func(v: float) -> void: _on_charge(idx, v))

func _on_charge(idx: int, value: float) -> void:
	if idx >= _charge_fills.size():
		return

	var fill      := _charge_fills[idx]
	var bar_bg    := _bar_bgs[idx]
	var ready_lbl := _ready_labels[idx]
	var bar_w     := SLOT_W - COLOR_STRIP_W - 2.0

	if value >= 1.0:
		# Hide bar, show READY!
		fill.visible    = false
		bar_bg.visible  = false
		ready_lbl.visible = true
		_start_flash(idx)
	else:
		# Show bar, hide READY!
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
