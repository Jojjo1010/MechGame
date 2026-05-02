class_name ActionGlyphs
extends RefCounted

# Procedural glyph renderer for control actions in ControlsLegend. Same shape
# API as UpgradeGlyphs.draw: returns true if drawn, false to let the caller
# fall back. Glyphs are minimalist silhouettes designed to read at ~28 px.

static func draw(canvas: CanvasItem, rect: Rect2, action_id: String, color: Color) -> bool:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.42
	match action_id:
		"move":   _move(canvas, c, r, color)
		"dash":   _dash(canvas, c, r, color)
		"ult":    _ult(canvas, c, r, color)
		"repair": _repair(canvas, c, r, color)
		"camera": _camera(canvas, c, r, color)
		"zoom":   _zoom(canvas, c, r, color)
		"gold":   _gold(canvas, c, r, color)
		"drone":  _drone(canvas, c, r, color)
		"check":  _check(canvas, c, r, color)
		_:        return false
	return true

# ─────────────────────────────────────────────────────────────────────────────

# 4-arrow rosette pointing to the cardinal directions — reads as "move".
static func _move(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var dirs: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	for dir: Vector2 in dirs:
		var perp := Vector2(-dir.y, dir.x)
		var base := p + dir * r * 0.30
		var shaft_end := p + dir * r * 0.78
		var shaft := PackedVector2Array([
			base + perp * r * 0.10,
			shaft_end + perp * r * 0.10,
			shaft_end - perp * r * 0.10,
			base - perp * r * 0.10,
		])
		c.draw_colored_polygon(shaft, col)
		var tip := p + dir * r * 1.10
		var head := PackedVector2Array([
			tip,
			shaft_end + perp * r * 0.32,
			shaft_end - perp * r * 0.32,
		])
		c.draw_colored_polygon(head, col)
	c.draw_circle(p, r * 0.15, col)

# Three forward chevrons — fast-forward / dash motion.
static func _dash(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var th := r * 0.22
	var span := r * 0.55
	for i in 3:
		var ox: float = (float(i) - 1.0) * r * 0.42
		var pts := PackedVector2Array([
			Vector2(p.x + ox - span * 0.5, p.y - r * 0.70),
			Vector2(p.x + ox + span * 0.5, p.y),
			Vector2(p.x + ox - span * 0.5, p.y + r * 0.70),
		])
		c.draw_polyline(pts, col, th, true)

# Starburst — implies the screen-clearing energy of an ultimate.
static func _ult(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	c.draw_circle(p, r * 0.32, col)
	var spokes := 8
	for i in spokes:
		var a := float(i) / float(spokes) * TAU
		var dir := Vector2(cos(a), sin(a))
		c.draw_line(p + dir * r * 0.45, p + dir * r * 1.15, col, r * 0.16)

# Open-end wrench — diagonal handle, jaw at the upper-right with a 90° gap.
static func _repair(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var dir := Vector2(0.707, -0.707)            # bottom-left → upper-right
	var perp := Vector2(-dir.y, dir.x)
	var th := r * 0.24
	var tail := p - dir * r * 1.00
	var head_center := p + dir * r * 0.40
	# Handle
	var shaft := PackedVector2Array([
		tail + perp * th * 0.5,
		head_center + perp * th * 0.5,
		head_center - perp * th * 0.5,
		tail - perp * th * 0.5,
	])
	c.draw_colored_polygon(shaft, col)
	c.draw_circle(tail, th * 0.55, col)
	# Open-end jaw: 270° arc with the gap pointing along `dir`
	var jaw_r := r * 0.44
	var open_a := dir.angle()
	var span := deg_to_rad(270.0)
	var arc_start := open_a + (TAU - span) * 0.5
	var arc_end := arc_start + span
	c.draw_arc(head_center, jaw_r, arc_start, arc_end, 24, col, r * 0.18, true)

# Curved arrow making a 250° loop with an arrow tip — orbit / camera angle.
static func _camera(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var arc_r := r * 0.85
	var start := deg_to_rad(-30.0)
	var end_a := deg_to_rad(220.0)
	c.draw_arc(p, arc_r, start, end_a, 36, col, r * 0.18, true)
	# Arrow tip at the end, pointing tangent to the arc (CCW)
	var end_p := p + Vector2(cos(end_a), sin(end_a)) * arc_r
	var tangent := Vector2(-sin(end_a), cos(end_a))
	var perp := Vector2(-tangent.y, tangent.x)
	var head := PackedVector2Array([
		end_p + tangent * r * 0.34,
		end_p + perp * r * 0.30,
		end_p - perp * r * 0.30,
	])
	c.draw_colored_polygon(head, col)
	c.draw_circle(p, r * 0.18, col)

# Magnifying glass with a "+" inside — zoom.
static func _zoom(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var lens_c := p + Vector2(-r * 0.18, -r * 0.18)
	var lens_r := r * 0.62
	c.draw_arc(lens_c, lens_r, 0.0, TAU, 36, col, r * 0.16, true)
	var plus_th := r * 0.14
	c.draw_line(lens_c + Vector2(-lens_r * 0.55, 0.0),
				lens_c + Vector2( lens_r * 0.55, 0.0), col, plus_th)
	c.draw_line(lens_c + Vector2(0.0, -lens_r * 0.55),
				lens_c + Vector2(0.0,  lens_r * 0.55), col, plus_th)
	var handle_a := lens_c + Vector2(lens_r * 0.58, lens_r * 0.58)
	var handle_b := lens_c + Vector2(r * 1.05, r * 1.05)
	c.draw_line(handle_a, handle_b, col, r * 0.22)

# Coin face — outlined circle with a centered "$" stroke. Reads as currency
# without leaning on a typeface.
static func _gold(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var coin_r := r * 0.92
	c.draw_arc(p, coin_r, 0.0, TAU, 36, col, r * 0.16, true)
	# Center vertical stroke of the "$"
	var stem_h := r * 0.78
	var stem_th := r * 0.14
	c.draw_line(p + Vector2(0.0, -stem_h * 0.5),
				p + Vector2(0.0,  stem_h * 0.5), col, stem_th)
	# Two stacked half-arcs forming the S curve. Top opens left, bottom opens right.
	var s_r := r * 0.30
	var top_c := p + Vector2(0.0, -s_r * 0.65)
	var bot_c := p + Vector2(0.0,  s_r * 0.65)
	c.draw_arc(top_c, s_r, deg_to_rad(-30.0), deg_to_rad(210.0), 18, col, r * 0.14, true)
	c.draw_arc(bot_c, s_r, deg_to_rad(150.0), deg_to_rad(390.0), 18, col, r * 0.14, true)

# Quadcopter silhouette — small body with four rotor arms. Simple, recognizable
# at ~28 px without competing with the mech-related iconography.
static func _drone(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Four diagonal arms — X frame
	var arm := r * 0.95
	var th := r * 0.14
	for d: Vector2 in [Vector2(0.707, 0.707), Vector2(-0.707, 0.707)]:
		c.draw_line(p - d * arm, p + d * arm, col, th)
	# Rotor discs at the four arm tips
	var rotor_r := r * 0.26
	for d: Vector2 in [Vector2(0.707, 0.707), Vector2(-0.707, 0.707),
			Vector2(0.707, -0.707), Vector2(-0.707, -0.707)]:
		c.draw_arc(p + d * arm, rotor_r, 0.0, TAU, 18, col, r * 0.10, true)
	# Central body — small filled square, rotated 45° to match the X frame
	var body := r * 0.30
	var body_pts := PackedVector2Array([
		p + Vector2(0.0, -body),
		p + Vector2(body, 0.0),
		p + Vector2(0.0,  body),
		p + Vector2(-body, 0.0),
	])
	c.draw_colored_polygon(body_pts, col)

# Bold checkmark — three-vertex polyline (down stroke + up stroke). Used by
# TutorialPrompts as the "step completed" overlay.
static func _check(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	var th := r * 0.32
	var pts := PackedVector2Array([
		p + Vector2(-r * 0.85,  r * 0.0),
		p + Vector2(-r * 0.18,  r * 0.55),
		p + Vector2( r * 0.85, -r * 0.55),
	])
	c.draw_polyline(pts, col, th, true)
