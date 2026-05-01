extends Control

# Rectangular icon tile: rounded-rect frame with a thick border and a centered
# text label or procedural UpgradeGlyphs glyph. Used in UpgradePicker cards
# and equipped slots.

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
	# Rounded-rect tile. Skip fill if alpha==0 so the caller can render an
	# "empty slot" outline.
	var radius: float = minf(s.x, s.y) * 0.18
	var rect := Rect2(Vector2.ZERO, s)
	if fill_color.a > 0.0:
		_draw_rounded_rect(rect, radius, fill_color)
	_draw_rounded_rect_outline(rect, radius, border_color, border_width)

	if not upgrade_id.is_empty():
		# Inset the glyph rect so it doesn't run into the border.
		var pad := minf(s.x, s.y) * 0.18
		var inner := Rect2(Vector2(pad, pad), Vector2(s.x - pad * 2.0, s.y - pad * 2.0))
		UpgradeGlyphs.draw(self, inner, upgrade_id, glyph_color)

func _draw_rounded_rect(rect: Rect2, radius: float, color: Color) -> void:
	# Approximate a rounded rectangle by drawing the central + edge rects and
	# four quarter-circle corners. Cheap; works for any radius.
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var p := rect.position
	var sz := rect.size
	# Center body + side strips
	draw_rect(Rect2(p.x + r,    p.y,        sz.x - r * 2.0, sz.y),       color, true)
	draw_rect(Rect2(p.x,        p.y + r,    r,              sz.y - r * 2.0), color, true)
	draw_rect(Rect2(p.x + sz.x - r, p.y + r, r,             sz.y - r * 2.0), color, true)
	# Corner caps
	draw_circle(Vector2(p.x + r,        p.y + r),        r, color)
	draw_circle(Vector2(p.x + sz.x - r, p.y + r),        r, color)
	draw_circle(Vector2(p.x + r,        p.y + sz.y - r), r, color)
	draw_circle(Vector2(p.x + sz.x - r, p.y + sz.y - r), r, color)

func _draw_rounded_rect_outline(rect: Rect2, radius: float, color: Color, w: float) -> void:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var p := rect.position
	var sz := rect.size
	# Straight edges
	draw_line(Vector2(p.x + r,        p.y),        Vector2(p.x + sz.x - r, p.y),        color, w)
	draw_line(Vector2(p.x + r,        p.y + sz.y), Vector2(p.x + sz.x - r, p.y + sz.y), color, w)
	draw_line(Vector2(p.x,            p.y + r),    Vector2(p.x,            p.y + sz.y - r), color, w)
	draw_line(Vector2(p.x + sz.x,     p.y + r),    Vector2(p.x + sz.x,     p.y + sz.y - r), color, w)
	# Corner arcs
	draw_arc(Vector2(p.x + r,            p.y + r),            r, deg_to_rad(180.0), deg_to_rad(270.0), 8, color, w, true)
	draw_arc(Vector2(p.x + sz.x - r,     p.y + r),            r, deg_to_rad(270.0), deg_to_rad(360.0), 8, color, w, true)
	draw_arc(Vector2(p.x + sz.x - r,     p.y + sz.y - r),     r, deg_to_rad(0.0),   deg_to_rad(90.0),  8, color, w, true)
	draw_arc(Vector2(p.x + r,            p.y + sz.y - r),     r, deg_to_rad(90.0),  deg_to_rad(180.0), 8, color, w, true)
