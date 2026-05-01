extends CanvasLayer

# Transient occlusion hint — appears when the drone is hidden behind a mech so
# the player remembers it's still under their control. Static informational
# chip: dark panel with a hairline lime border, a small drone glyph, and a
# caps label. Center-top so it sits in the player's peripheral vision without
# covering action. Fade-in/out is data-driven (driven by Game.gd's occlusion
# check via set_hint_visible), not an interaction state.

const TOP_OFFSET   := 96.0                          # 12×8 — sits below the XP strip
const PANEL_PAD_H  := UITheme.PAD_M                 # 16
const PANEL_PAD_V  := UITheme.PAD_S                 # 8
const ROW_SEP      := UITheme.PAD_S + 4             # 12 — icon ↔ label
const ICON_SIZE    := 28.0                          # supporting iconography
const LABEL_FONT   := UITheme.FONT_LABEL_CAPS       # 24
const FADE_TIME    := 0.18

var _root:       Control
var _panel:      PanelContainer
var _fade_tween: Tween

func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top    = TOP_OFFSET
	center.offset_bottom = TOP_OFFSET
	center.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.panel_stylebox()
	sb.set_corner_radius_all(16)
	sb.content_margin_left   = PANEL_PAD_H
	sb.content_margin_right  = PANEL_PAD_H
	sb.content_margin_top    = PANEL_PAD_V
	sb.content_margin_bottom = PANEL_PAD_V
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(row)

	# Drone glyph — lime so it stands out as the subject of the hint, even
	# though the rest of the chip stays quiet.
	var icon := ActionIcon.new()
	icon.action_id           = "drone"
	icon.accent              = UITheme.COLOR_ACCENT_LIME
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text = "Drone hidden"
	UITheme.style_label_caps(lbl, LABEL_FONT, UITheme.COLOR_TEXT_SECONDARY)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	_root.modulate.a = 0.0
	_root.visible    = false

func set_hint_visible(on: bool) -> void:
	if _root == null:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	if on:
		_root.visible = true
		_fade_tween.tween_property(_root, "modulate:a", 1.0, FADE_TIME)
	else:
		_fade_tween.tween_property(_root, "modulate:a", 0.0, FADE_TIME)
		_fade_tween.tween_callback(func() -> void:
			if is_instance_valid(_root):
				_root.visible = false)
