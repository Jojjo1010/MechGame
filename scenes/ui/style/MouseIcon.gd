extends Control
class_name MouseIcon

# Mouse silhouette with one region tinted in accent. `highlight` selects which
# region: SCROLL fills a wheel pill at top-center (used by ControlsLegend for
# scroll-zoom); LEFT / RIGHT fill the corresponding top-button quadrant (used
# by TutorialPrompts to point at LMB / RMB).

enum Highlight { SCROLL, LEFT, RIGHT }

@export var body_color: Color = UITheme.COLOR_TEXT_SECONDARY
@export var accent:     Color = UITheme.COLOR_ACCENT_LIME
@export var line_w:     float = 2.0
@export var highlight:  Highlight = Highlight.SCROLL

func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var pad := line_w * 0.5
	var inner := Rect2(pad, pad, s.x - pad * 2.0, s.y - pad * 2.0)
	var radius := minf(inner.size.x, inner.size.y) * 0.32
	var div_y := inner.position.y + inner.size.y * 0.42
	# Fill the highlighted button first so the body outline draws on top of it.
	if highlight == Highlight.LEFT or highlight == Highlight.RIGHT:
		_draw_button_quadrant(inner, radius, div_y, highlight == Highlight.LEFT)
	# Body outline — rounded rectangle, neutral
	var pts := _rounded_rect(inner, radius, 6)
	pts.append(pts[0])
	draw_polyline(pts, body_color, line_w, true)
	# Top-of-buttons divider — neutral, part of the silhouette
	draw_line(
		Vector2(inner.position.x + radius * 0.5,                div_y),
		Vector2(inner.position.x + inner.size.x - radius * 0.5, div_y),
		body_color, line_w
	)
	# Scroll wheel — filled vertical pill at top-center, highlighted in accent
	if highlight == Highlight.SCROLL:
		var ww := inner.size.x * 0.22
		var wh := inner.size.y * 0.20
		var wx := inner.position.x + (inner.size.x - ww) * 0.5
		var wy := inner.position.y + inner.size.y * 0.13
		draw_rect(Rect2(wx, wy, ww, wh), accent, true)

# Fills one of the two top button quadrants with the accent color. The outer
# corner (top-left or top-right) traces the same rounded radius as the body so
# the highlight tucks into the silhouette instead of squaring off.
func _draw_button_quadrant(inner: Rect2, radius: float, div_y: float, is_left: bool) -> void:
	var mid_x := inner.position.x + inner.size.x * 0.5
	var segs := 6
	var pts := PackedVector2Array()
	if is_left:
		pts.append(Vector2(mid_x, inner.position.y))
		pts.append(Vector2(inner.position.x + radius, inner.position.y))
		var center_l := Vector2(inner.position.x + radius, inner.position.y + radius)
		for i in segs + 1:
			var a: float = -PI * 0.5 - (PI * 0.5) * (float(i) / float(segs))
			pts.append(center_l + Vector2(cos(a), sin(a)) * radius)
		pts.append(Vector2(inner.position.x, div_y))
		pts.append(Vector2(mid_x, div_y))
	else:
		pts.append(Vector2(mid_x, inner.position.y))
		pts.append(Vector2(inner.position.x + inner.size.x - radius, inner.position.y))
		var center_r := Vector2(inner.position.x + inner.size.x - radius, inner.position.y + radius)
		for i in segs + 1:
			var a: float = -PI * 0.5 + (PI * 0.5) * (float(i) / float(segs))
			pts.append(center_r + Vector2(cos(a), sin(a)) * radius)
		pts.append(Vector2(inner.position.x + inner.size.x, div_y))
		pts.append(Vector2(mid_x, div_y))
	draw_polygon(pts, [accent])

# Approximates a rounded rectangle as a polyline. Each corner is a quarter-arc
# of `segs` segments; the straight edges fall out of the corner sequence.
func _rounded_rect(rect: Rect2, radius: float, segs: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var centers: Array[Vector2] = [
		Vector2(rect.position.x + radius,                  rect.position.y + radius),
		Vector2(rect.position.x + rect.size.x - radius,    rect.position.y + radius),
		Vector2(rect.position.x + rect.size.x - radius,    rect.position.y + rect.size.y - radius),
		Vector2(rect.position.x + radius,                  rect.position.y + rect.size.y - radius),
	]
	var starts: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
	for k in 4:
		var center: Vector2 = centers[k]
		var start: float = starts[k]
		for i in segs + 1:
			var t: float = start + (PI * 0.5) * (float(i) / float(segs))
			pts.append(center + Vector2(cos(t), sin(t)) * radius)
	return pts
