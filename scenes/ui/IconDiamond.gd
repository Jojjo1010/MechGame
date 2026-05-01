extends Control

# Bad-North-style geometric icon: a flat-topped hexagon (diamond-ish) with
# a thick border and a centered text label. Used in UpgradePicker cards.

var fill_color:   Color  = Color(0.65, 0.45, 0.55, 1.0)   # dusty pink default
var border_color: Color  = Color(0.18, 0.12, 0.08, 1.0)
var border_width: float  = 4.0
var icon_text:    String = ""
var icon_color:   Color  = Color(1.0, 1.0, 1.0, 1.0)
var icon_size:    int    = 36

# When set, _draw() renders the procedural UpgradeGlyphs glyph for this id and
# hides the text label. Lets the same diamond render either text codes or
# real glyphs depending on the caller.
var upgrade_id:   String = ""
var glyph_color:  Color  = UITheme.COLOR_DEEP

func _ready() -> void:
	_ensure_label()
	queue_redraw()

func _ensure_label() -> void:
	if get_node_or_null("Label") != null:
		return
	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = icon_text
	lbl.add_theme_font_size_override("font_size", icon_size)
	lbl.add_theme_color_override("font_color",      icon_color)
	lbl.add_theme_constant_override("outline_size", 0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)

func set_icon(text: String, fill: Color, font_size: int = 36) -> void:
	icon_text   = text
	fill_color  = fill
	icon_size   = font_size
	upgrade_id  = ""
	_ensure_label()
	var lbl := get_node_or_null("Label") as Label
	if lbl != null:
		lbl.visible = true
		lbl.text = icon_text
		lbl.add_theme_font_size_override("font_size", icon_size)
	queue_redraw()

# Render the procedural UpgradeGlyphs glyph for `id` instead of a text code.
# The text label is hidden while a glyph is set.
func set_glyph(id: String, fill: Color, glyph_col: Color = UITheme.COLOR_DEEP) -> void:
	upgrade_id  = id
	fill_color  = fill
	glyph_color = glyph_col
	var lbl := get_node_or_null("Label") as Label
	if lbl != null:
		lbl.visible = false
	queue_redraw()

func _draw() -> void:
	var s := size
	# Flat-topped hexagon vertices
	var pts := PackedVector2Array([
		Vector2(s.x * 0.25, 0.0),
		Vector2(s.x * 0.75, 0.0),
		Vector2(s.x,        s.y * 0.5),
		Vector2(s.x * 0.75, s.y),
		Vector2(s.x * 0.25, s.y),
		Vector2(0.0,        s.y * 0.5),
	])
	# Skip fill if alpha==0 — caller can use this to render an "empty slot" outline.
	if fill_color.a > 0.0:
		draw_colored_polygon(pts, fill_color)
	var loop := PackedVector2Array(pts)
	loop.append(pts[0])
	draw_polyline(loop, border_color, border_width, true)

	if not upgrade_id.is_empty():
		# Inset the glyph rect so it doesn't run into the hex border.
		var pad := minf(s.x, s.y) * 0.20
		var inner := Rect2(Vector2(pad, pad), Vector2(s.x - pad * 2.0, s.y - pad * 2.0))
		UpgradeGlyphs.draw(self, inner, upgrade_id, glyph_color)
