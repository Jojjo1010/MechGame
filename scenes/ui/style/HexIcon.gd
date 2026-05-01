extends Control
class_name HexIcon

# OW-style hex container. Pointy-top hexagon, hairline accent border, optional
# inner glow and centered text/glyph.
#
# Usage:
#   var hex := HexIcon.new()
#   hex.custom_minimum_size = Vector2(56, 56)
#   hex.set_label("E")
#   hex.set_accent(team_color)   # optional per-mech tint; default cyan

@export var label_text:    String = ""
@export var label_size:    int    = 28
@export var label_color:   Color  = UITheme.COLOR_TEXT_PRIMARY
@export var accent_color:  Color  = UITheme.COLOR_ACCENT_LIME
@export var fill_color:    Color  = UITheme.COLOR_PANEL_ALPHA
@export var border_width:  float  = UITheme.HEX_BORDER_W
@export var enable_glow:   bool   = true
@export var glyph_id:      String = ""   # if set, draws a UpgradeGlyphs glyph instead of label_text

var _label: Label = null
var _glow_amount: float = 1.0   # 0..1 — multiplier on the outer glow alpha

func _ready() -> void:
	_ensure_label()
	queue_redraw()

func _ensure_label() -> void:
	if _label == null or not is_instance_valid(_label):
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		add_child(_label)
	# Glyph mode hides the label so we can draw the glyph in _draw()
	_label.visible = (glyph_id == "")
	_label.text    = label_text
	UITheme.style_label_caps(_label, label_size, label_color)

func set_label(text: String, font_size: int = label_size,
		color: Color = UITheme.COLOR_TEXT_PRIMARY) -> void:
	label_text  = text
	label_size  = font_size
	label_color = color
	_ensure_label()

func set_accent(color: Color) -> void:
	if accent_color == color:
		return
	accent_color = color
	queue_redraw()

func set_glyph(glyph: String) -> void:
	if glyph_id == glyph:
		return
	glyph_id = glyph
	_ensure_label()
	queue_redraw()

func set_glow(amount: float) -> void:
	var clamped: float = clampf(amount, 0.0, 1.0)
	if _glow_amount == clamped:
		return
	_glow_amount = clamped
	queue_redraw()

func _hex_points(rect_size: Vector2, factor: float = 1.0) -> PackedVector2Array:
	# Pointy-top hexagon: top/bottom verts on the y-axis, sides at ±0.5 width.
	var c := rect_size * 0.5
	var w := rect_size.x * 0.5 * factor
	var h := rect_size.y * 0.5 * factor
	return PackedVector2Array([
		Vector2(c.x,         c.y - h),         # top
		Vector2(c.x + w,     c.y - h * 0.5),
		Vector2(c.x + w,     c.y + h * 0.5),
		Vector2(c.x,         c.y + h),
		Vector2(c.x - w,     c.y + h * 0.5),
		Vector2(c.x - w,     c.y - h * 0.5),
	])

func _draw() -> void:
	# Outer glow — three semi-transparent hex outlines at progressively larger
	# scales, blended in by enable_glow. Cheap, no shaders.
	if enable_glow and _glow_amount > 0.0:
		for i in 3:
			var s: float = 1.06 + 0.04 * float(i)
			var alpha: float = (0.18 - 0.05 * float(i)) * _glow_amount
			var glow_color := Color(accent_color.r, accent_color.g, accent_color.b, alpha)
			_stroke_hex(_hex_points(size, s), glow_color, border_width)
	# Body fill + hairline accent border share the same 0.96-scale polygon.
	var body_pts := _hex_points(size, 0.96)
	if fill_color.a > 0.0:
		draw_colored_polygon(body_pts, fill_color)
	_stroke_hex(body_pts, accent_color, border_width)
	# Glyph mode: delegate to UpgradeGlyphs (class_name'd, no load needed)
	if glyph_id != "":
		var inset := minf(size.x, size.y) * 0.18
		var grect := Rect2(inset, inset, size.x - inset * 2.0, size.y - inset * 2.0)
		UpgradeGlyphs.draw(self, grect, glyph_id, label_color)

func _stroke_hex(pts: PackedVector2Array, color: Color, w: float) -> void:
	var loop := PackedVector2Array(pts)
	loop.append(pts[0])
	draw_polyline(loop, color, w, true)
