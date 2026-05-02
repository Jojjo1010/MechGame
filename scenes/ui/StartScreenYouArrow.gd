extends Control

# Hand-drawn-feel "YOU" annotation that points at the start-screen drone
# mascot. Curve runs from under the label down-left to the arrowhead. Tip
# coordinates are in this Control's local space — parent positions the
# Control such that the tip lands on the drone.

const ARROW_COLOR := Color(1.00, 0.88, 0.30)   # warm yellow, comic-marker feel
const ARROW_THICK := 4.5
const HEAD_LEN    := 18.0
const HEAD_WID    := 16.0
const LABEL_TEXT  := "YOU"
const LABEL_FONT_SIZE := 36

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var tip := Vector2(20.0, size.y * 0.62)
	var shaft_start := Vector2(size.x * 0.78, size.y * 0.38)
	var ctrl1 := Vector2(size.x * 0.55, size.y * 0.78)
	var ctrl2 := Vector2(size.x * 0.32, size.y * 0.74)

	const N := 32
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(N + 1):
		var t: float = float(i) / N
		pts.append(_bezier(t, shaft_start, ctrl1, ctrl2, tip))
	draw_polyline(pts, ARROW_COLOR, ARROW_THICK, true)

	var prev := _bezier(0.96, shaft_start, ctrl1, ctrl2, tip)
	var dir := (tip - prev).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var p1 := tip
	var p2 := tip - dir * HEAD_LEN + perp * HEAD_WID * 0.5
	var p3 := tip - dir * HEAD_LEN - perp * HEAD_WID * 0.5
	draw_colored_polygon(PackedVector2Array([p1, p2, p3]), ARROW_COLOR)

	var font := ThemeDB.fallback_font
	var label_size := font.get_string_size(LABEL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	var ascent := font.get_ascent(LABEL_FONT_SIZE)
	var lp := Vector2(shaft_start.x - label_size.x * 0.5, shaft_start.y - 16.0 - (label_size.y - ascent))
	draw_string(font, lp, LABEL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, ARROW_COLOR)

static func _bezier(t: float, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> Vector2:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)
