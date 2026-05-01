extends CanvasLayer

# Top-of-screen XP/level readout. Static informational UI — no interaction
# states. Dark strip with a full-height lime fill that grows L→R with XP.
# Level label sits centered with a strong outline so it remains legible across
# both filled (lime) and unfilled (dark) portions of the bar. A level-up
# triggers a brief brighten on the fill + label flash; that's data-driven
# animation, not an interaction state.

const TOTAL_H    := 64.0                    # 8 × 8 — strip height
const PAD_SIDE   := UITheme.PAD_S           # 8 — small inset so the fill almost spans the screen
const LABEL_FONT := UITheme.FONT_HEADING_M  # 32

var _bar_bg:      ColorRect
var _fill_live:   ColorRect    # full-height lime fill — grows L→R with XP
var _lv_label:    Label
var _flash_tween: Tween

func _ready() -> void:
	layer = 5
	_build()
	RunManager.xp_changed.connect(_on_xp_changed)
	RunManager.level_up.connect(_on_level_up)
	_refresh(RunManager.xp, RunManager.xp_to_next)

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Dark panel — sits behind the fill so unfilled XP still reads as a strip.
	_bar_bg = ColorRect.new()
	_bar_bg.color = UITheme.COLOR_PANEL_ALPHA
	_bar_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_bg.offset_top    = 0.0
	_bar_bg.offset_bottom = TOTAL_H
	_bar_bg.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bar_bg)

	# Full-height lime fill — width tracks XP fraction. Sits inside the side
	# padding so a sliver of dark frames the meter at either end.
	_fill_live = ColorRect.new()
	_fill_live.color    = UITheme.COLOR_ACCENT_LIME
	_fill_live.position = Vector2(PAD_SIDE, 0.0)
	_fill_live.size     = Vector2(0.0, TOTAL_H)
	_fill_live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fill_live)

	# Level label — white with strong outline so it stays legible whether the
	# fill is behind it or not.
	_lv_label = Label.new()
	_lv_label.text = "LV 1"
	UITheme.style_label_caps(_lv_label, LABEL_FONT, UITheme.COLOR_TEXT_PRIMARY)
	_lv_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_lv_label.offset_top           = 0.0
	_lv_label.offset_bottom        = TOTAL_H
	_lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lv_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_lv_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	root.add_child(_lv_label)

func _refresh(current: int, needed: int) -> void:
	await get_tree().process_frame
	var full_w: float = _bar_bg.size.x - PAD_SIDE * 2.0
	var t: float = clampf(float(current) / float(needed), 0.0, 1.0)
	_fill_live.size.x = full_w * t

func _on_xp_changed(current: int, needed: int) -> void:
	_refresh(current, needed)

func _on_level_up(new_level: int) -> void:
	_lv_label.text = "LV %d" % new_level
	_refresh(0, RunManager.xp_to_next)
	# Data-driven flash: fill briefly jumps to bright lime, label tints lime,
	# both ease back. Not an interaction state — fires on the level_up signal.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_fill_live, "color", UITheme.COLOR_BORDER_BRIGHT, 0.08)
	_flash_tween.parallel().tween_property(_lv_label, "theme_override_colors/font_color", UITheme.COLOR_ACCENT_LIME, 0.08)
	_flash_tween.tween_property(_fill_live, "color", UITheme.COLOR_ACCENT_LIME, 0.30)
	_flash_tween.parallel().tween_property(_lv_label, "theme_override_colors/font_color", UITheme.COLOR_TEXT_PRIMARY, 0.30)
