extends Control
class_name MouseIcon

# Mouse silhouette with a highlighted scroll wheel. Drawn procedurally so it
# tints with the design-system accent and scales with custom_minimum_size.

@export var body_color: Color = UITheme.COLOR_TEXT_SECONDARY  # mouse silhouette — neutral
@export var accent:     Color = UITheme.COLOR_ACCENT_LIME      # scroll wheel — highlighted
@export var line_w:     float = 2.0

func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	var pad := line_w * 0.5
	var inner := Rect2(pad, pad, s.x - pad * 2.0, s.y - pad * 2.0)
	var radius := minf(inner.size.x, inner.size.y) * 0.32
	# Body outline — rounded rectangle, neutral
	var pts := _rounded_rect(inner, radius, 6)
	pts.append(pts[0])
	draw_polyline(pts, body_color, line_w, true)
	# Top-of-buttons divider — also neutral, part of the silhouette
	var div_y := inner.position.y + inner.size.y * 0.42
	draw_line(
		Vector2(inner.position.x + radius * 0.5,                  div_y),
		Vector2(inner.position.x + inner.size.x - radius * 0.5,   div_y),
		body_color, line_w
	)
	# Scroll wheel — filled vertical pill at top-center, highlighted in accent
	var ww := inner.size.x * 0.22
	var wh := inner.size.y * 0.20
	var wx := inner.position.x + (inner.size.x - ww) * 0.5
	var wy := inner.position.y + inner.size.y * 0.13
	draw_rect(Rect2(wx, wy, ww, wh), accent, true)

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
