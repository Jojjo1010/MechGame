extends Control
class_name SlantCard

# OW-style slanted parallelogram card. Used for boon offers, hero-select cards,
# anywhere a "menu option" needs to feel angular instead of rectangular.
#
# State machine: idle → hover (cyan glow strengthens) → selected (yellow tail
# below + scale punch). Children render normally on top of the slanted backdrop.

@export var accent_color:    Color = UITheme.COLOR_ACCENT_CYAN
@export var fill_color:      Color = UITheme.COLOR_PANEL_ALPHA
@export var slant_deg:       float = UITheme.CARD_SLANT_DEG
@export var border_width:    float = UITheme.PANEL_BORDER_W
@export var selected_color:  Color = UITheme.COLOR_ACCENT_YELLOW

var _hover:    bool = false
var _selected: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_hover_in)
	mouse_exited.connect(_on_hover_out)

func _on_hover_in() -> void:
	_hover = true
	queue_redraw()

func _on_hover_out() -> void:
	_hover = false
	queue_redraw()

func set_selected(on: bool) -> void:
	_selected = on
	queue_redraw()

func set_accent(color: Color) -> void:
	accent_color = color
	queue_redraw()

# Returns the four corner points of the parallelogram (clockwise from top-left)
func _slant_points(rect_size: Vector2) -> PackedVector2Array:
	# Top edge slants right; bottom edge slants right by the same amount, so
	# the LEFT and RIGHT edges are the diagonals.
	var off: float = tan(deg_to_rad(slant_deg)) * rect_size.y * 0.5
	return PackedVector2Array([
		Vector2(off,                 0.0),                  # top-left
		Vector2(rect_size.x + off,   0.0),                  # top-right
		Vector2(rect_size.x - off,   rect_size.y),          # bottom-right
		Vector2(-off,                rect_size.y),          # bottom-left
	])

func _draw() -> void:
	var pts := _slant_points(size)
	# Hover/selected glow — extra semi-transparent stroke layers
	var glow_color: Color = selected_color if _selected else accent_color
	if _hover or _selected:
		for i in 3:
			var alpha: float = 0.20 - 0.05 * float(i)
			var w: float = border_width + 2.0 + 2.0 * float(i)
			var c := Color(glow_color.r, glow_color.g, glow_color.b, alpha)
			var loop := PackedVector2Array(pts)
			loop.append(pts[0])
			draw_polyline(loop, c, w, true)
	# Body fill
	if fill_color.a > 0.0:
		draw_colored_polygon(pts, fill_color)
	# Hairline border
	var border_loop := PackedVector2Array(pts)
	border_loop.append(pts[0])
	draw_polyline(border_loop, accent_color, border_width, true)
	# Selected tail — small yellow rectangle dropping from the bottom edge
	if _selected:
		var tail_h := 6.0
		var tail_pts := PackedVector2Array([
			pts[3] + Vector2(8.0, 0.0),
			pts[2] + Vector2(-8.0, 0.0),
			pts[2] + Vector2(-8.0, tail_h),
			pts[3] + Vector2(8.0, tail_h),
		])
		draw_colored_polygon(tail_pts, selected_color)
