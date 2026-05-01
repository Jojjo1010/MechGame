extends Control

# Procedural sci-fi card back used as the face-down placeholder in the level-up
# picker before the player's mech roll lands. Stable per (size, seed) — varies
# slightly across the three placeholder cards so the row doesn't look uniform.

const PRIMARY := UITheme.COLOR_BORDER_HAIR     # dim lime — main strokes
const ACCENT  := UITheme.COLOR_ACCENT_HOT      # hot pink — highlight pops
const FAINT   := UITheme.COLOR_TEXT_MUTED      # very dim — grid + scaffold

var _seed: int = 0

func set_seed(seed_value: int) -> void:
	_seed = seed_value
	queue_redraw()

func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed

	_draw_dot_grid(s)
	_draw_corner_arcs(s, rng)
	_draw_central_glyph(s)
	_draw_diagonal_dots(s, rng)
	_draw_corner_hashes(s)
	_draw_perimeter_ticks(s)

# Faint dot grid filling the card.
func _draw_dot_grid(s: Vector2) -> void:
	var spacing := 18.0
	var col := FAINT
	col.a = 0.18
	var x := spacing
	while x < s.x:
		var y := spacing
		while y < s.y:
			draw_circle(Vector2(x, y), 1.0, col)
			y += spacing
		x += spacing

# Stack of three offset chevron-rectangles in the center, fading down.
func _draw_central_glyph(s: Vector2) -> void:
	var center := s * 0.5
	var slant := 14.0
	var w := 80.0
	var h := 18.0
	for i in 3:
		var off := Vector2(float(i) * 4.0 - 4.0, float(i) * 18.0 - 18.0)
		var pts := PackedVector2Array([
			center + Vector2(-w * 0.5 + slant, -h * 0.5) + off,
			center + Vector2( w * 0.5,         -h * 0.5) + off,
			center + Vector2( w * 0.5 - slant,  h * 0.5) + off,
			center + Vector2(-w * 0.5,          h * 0.5) + off,
		])
		var c := PRIMARY
		c.a = 0.95 - float(i) * 0.30
		draw_colored_polygon(pts, c)
	# Tiny pink dot at the glyph anchor — focal pop.
	draw_circle(center + Vector2(-w * 0.5 - 8.0, 0.0), 3.0, ACCENT)

# Concentric arc cluster in a corner — placement varies by seed.
func _draw_corner_arcs(s: Vector2, rng: RandomNumberGenerator) -> void:
	var corners := [
		Vector2(s.x * 0.18, s.y * 0.78),
		Vector2(s.x * 0.82, s.y * 0.22),
	]
	var arc_center: Vector2 = corners[rng.randi_range(0, corners.size() - 1)]
	var arc_color := ACCENT
	arc_color.a = 0.55
	for r in [18.0, 28.0, 38.0]:
		draw_arc(arc_center, r,
			deg_to_rad(rng.randf_range(0.0, 60.0)),
			deg_to_rad(rng.randf_range(120.0, 200.0)),
			28, arc_color, 1.5, true)

# Diagonal dotted line across one quadrant.
func _draw_diagonal_dots(s: Vector2, rng: RandomNumberGenerator) -> void:
	var start := Vector2(s.x * rng.randf_range(0.55, 0.70), 14.0)
	var end_pt := Vector2(s.x - 14.0, s.y * rng.randf_range(0.30, 0.45))
	var dim := PRIMARY
	dim.a = 0.45
	draw_line(start, end_pt, dim, 1.0)
	for i in 6:
		var t := float(i) / 5.0
		var pt: Vector2 = start.lerp(end_pt, t)
		draw_circle(pt, 2.0, ACCENT)

# Small angled hash marks in the bottom-right corner — like serial-number
# tally marks.
func _draw_corner_hashes(s: Vector2) -> void:
	var c := FAINT
	c.a = 0.55
	for i in 5:
		var hx: float = s.x - 22.0 - float(i) * 5.0
		var hy: float = s.y - 14.0
		draw_line(Vector2(hx, hy), Vector2(hx + 8.0, hy - 8.0), c, 1.5)

# Tiny tick marks along the inside edges of the card — frame the pattern.
func _draw_perimeter_ticks(s: Vector2) -> void:
	var c := PRIMARY
	c.a = 0.40
	var step := 24.0
	# Top + bottom edges
	var x := step
	while x < s.x - step * 0.5:
		draw_line(Vector2(x, 6.0), Vector2(x, 12.0), c, 1.0)
		draw_line(Vector2(x, s.y - 6.0), Vector2(x, s.y - 12.0), c, 1.0)
		x += step
	# Left + right edges
	var y := step
	while y < s.y - step * 0.5:
		draw_line(Vector2(6.0, y), Vector2(12.0, y), c, 1.0)
		draw_line(Vector2(s.x - 6.0, y), Vector2(s.x - 12.0, y), c, 1.0)
		y += step
