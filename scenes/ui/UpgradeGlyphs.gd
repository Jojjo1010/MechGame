class_name UpgradeGlyphs
extends RefCounted

# Procedural glyph renderer for each upgrade id. Drawn into a Rect2 inside a
# HexIcon. Glyphs are intentionally simple silhouettes (a few primitives each)
# so they read at small sizes and through the heavy hex border.
#
# To swap to a real icon library later, replace the per-id branches with
# texture draws — the call site (HexIcon._draw) doesn't change.

# Public: draw the glyph for `upgrade_id` centered in `rect`, in `color`.
# Returns true if a custom glyph was drawn; false means the caller should
# fall back to its default (e.g. a 2-letter text code).
static func draw(canvas: CanvasItem, rect: Rect2, upgrade_id: String, color: Color) -> bool:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.42
	match upgrade_id:
		"gun_firerate":     _rapid_fire(canvas, c, r, color)
		"gun_headshot":     _crosshair(canvas, c, r, color)
		"gun_projectile":   _double_shot(canvas, c, r, color)
		"gun_splash":       _explosion(canvas, c, r, color)
		"garlic_wither":    _decay(canvas, c, r, color)
		"garlic_bulwark":   _shield(canvas, c, r, color)
		"garlic_range":     _concentric(canvas, c, r, color)
		"garlic_slow":      _snowflake(canvas, c, r, color)
		"beam_firerate":    _lightning_bolt(canvas, c, r, color)
		"beam_damage":      _laser(canvas, c, r, color)
		"beam_bounces":     _zigzag_chain(canvas, c, r, color)
		"beam_splash":      _star_burst(canvas, c, r, color)
		"gun_pierce":       _pierce(canvas, c, r, color)
		"garlic_sanctuary": _sanctuary(canvas, c, r, color)
		"beam_overcharge":  _overcharge(canvas, c, r, color)
		_:                  return false
	return true

# ── Archetype standees ───────────────────────────────────────────────────────
# Big procedural silhouettes for the upgrade picker's mech-centerpiece zone.
# Each standee fills the given rect with a single-color, dramatic emblem of the
# archetype's identity: VOLLEY = riot-shield + rifle, AEGIS = aura'd guardian,
# ARC = lightning rod. Drawn in the archetype tint.
static func draw_standee(canvas: CanvasItem, rect: Rect2, weapon_name: String, color: Color) -> bool:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.42
	match weapon_name:
		"GUN":    _standee_volley(canvas, c, r, color)
		"GARLIC": _standee_aegis(canvas, c, r, color)
		"BEAM":   _standee_arc(canvas, c, r, color)
		_:        return false
	return true


# ─────────────────────────────────────────────────────────────────────────────
# Glyphs — each is a small composition of primitives. Color is the foreground;
# everything strokes/fills in that color so the hex's fill provides contrast.

static func _rapid_fire(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Three horizontal "muzzle bursts" stacked vertically — implies rate of fire
	var bw := r * 1.6
	var bh := r * 0.16
	var gap := r * 0.32
	for i in 3:
		var y := p.y + (float(i) - 1.0) * gap
		c.draw_rect(Rect2(p.x - bw * 0.5, y - bh * 0.5, bw, bh), col, true)
		# tiny arrow tip on right
		var tip := PackedVector2Array([
			Vector2(p.x + bw * 0.5,            y - bh * 1.2),
			Vector2(p.x + bw * 0.5 + r * 0.30, y),
			Vector2(p.x + bw * 0.5,            y + bh * 1.2),
		])
		c.draw_colored_polygon(tip, col)

static func _crosshair(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Outer ring
	c.draw_arc(p, r, 0.0, TAU, 32, col, r * 0.16, true)
	# Four arms — outer tip toward each cardinal, leaving a gap at the center
	var dirs: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	for dir: Vector2 in dirs:
		c.draw_line(p + dir * r * 0.45, p + dir * r * 1.15, col, r * 0.16)
	# Center dot — the kill-shot point
	c.draw_circle(p, r * 0.18, col)

static func _double_shot(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Two bullets side by side, leading to the right
	var sides: Array[float] = [-1.0, 1.0]
	for s: float in sides:
		var off := Vector2(0.0, s * r * 0.45)
		var body := Rect2(p.x - r * 0.7 + off.x, p.y - r * 0.18 + off.y, r * 1.0, r * 0.36)
		c.draw_rect(body, col, true)
		var tip := PackedVector2Array([
			Vector2(body.position.x + body.size.x,         body.position.y),
			Vector2(body.position.x + body.size.x + r * 0.45, body.position.y + body.size.y * 0.5),
			Vector2(body.position.x + body.size.x,         body.position.y + body.size.y),
		])
		c.draw_colored_polygon(tip, col)

static func _explosion(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# 8-point starburst with a hot center
	var spikes := 8
	var pts := PackedVector2Array()
	for i in spikes * 2:
		var t := float(i) / float(spikes * 2) * TAU
		var rr: float = (r * 1.15) if (i % 2 == 0) else (r * 0.5)
		pts.append(p + Vector2(cos(t), sin(t)) * rr)
	c.draw_colored_polygon(pts, col)
	c.draw_circle(p, r * 0.28, col.lightened(0.4))

static func _decay(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Three downward-dripping teardrops — withering / decay
	var sides: Array[float] = [-1.0, 0.0, 1.0]
	for s: float in sides:
		var ox := s * r * 0.55
		var top := p + Vector2(ox, -r * 0.7)
		var bot := p + Vector2(ox,  r * 0.6)
		c.draw_circle(bot, r * 0.32, col)
		var drip := PackedVector2Array([
			Vector2(top.x - r * 0.10, top.y),
			Vector2(top.x + r * 0.10, top.y),
			Vector2(bot.x + r * 0.30, bot.y),
			Vector2(bot.x - r * 0.30, bot.y),
		])
		c.draw_colored_polygon(drip, col)

static func _shield(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Heater-shield silhouette
	var pts := PackedVector2Array([
		Vector2(p.x - r * 0.95, p.y - r * 0.95),
		Vector2(p.x + r * 0.95, p.y - r * 0.95),
		Vector2(p.x + r * 0.95, p.y + r * 0.20),
		Vector2(p.x,            p.y + r * 1.15),
		Vector2(p.x - r * 0.95, p.y + r * 0.20),
	])
	c.draw_colored_polygon(pts, col)
	# Inner cross (lighter) so the shape reads as a shield, not a pentagon
	var inner: Color = col.darkened(0.45)
	c.draw_rect(Rect2(p.x - r * 0.16, p.y - r * 0.55, r * 0.32, r * 1.30), inner, true)
	c.draw_rect(Rect2(p.x - r * 0.55, p.y - r * 0.16, r * 1.10, r * 0.32), inner, true)

static func _concentric(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Three concentric rings — aura growing
	for i in 3:
		var rr: float = r * (0.45 + 0.30 * float(i))
		c.draw_arc(p, rr, 0.0, TAU, 36, col, r * 0.14, true)
	c.draw_circle(p, r * 0.18, col)

static func _snowflake(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Six-armed snowflake — slow / freeze
	var arm_len := r * 1.10
	var thick := r * 0.12
	for i in 6:
		var a := float(i) / 6.0 * TAU
		var dir := Vector2(cos(a), sin(a))
		c.draw_line(p, p + dir * arm_len, col, thick)
		# tiny side prongs at 70% of each arm
		var mid := p + dir * arm_len * 0.65
		var perp := Vector2(-dir.y, dir.x) * arm_len * 0.22
		c.draw_line(mid - perp, mid + perp, col, thick * 0.7)
	c.draw_circle(p, r * 0.18, col)

static func _lightning_bolt(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Classic zigzag bolt
	var pts := PackedVector2Array([
		Vector2(p.x + r * 0.20, p.y - r * 1.10),
		Vector2(p.x - r * 0.50, p.y + r * 0.05),
		Vector2(p.x - r * 0.05, p.y + r * 0.05),
		Vector2(p.x - r * 0.30, p.y + r * 1.10),
		Vector2(p.x + r * 0.55, p.y - r * 0.20),
		Vector2(p.x + r * 0.10, p.y - r * 0.20),
	])
	c.draw_colored_polygon(pts, col)

static func _laser(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Wide-tapered laser ray firing rightward, with a glowing tip
	var pts := PackedVector2Array([
		Vector2(p.x - r * 1.10, p.y - r * 0.30),
		Vector2(p.x + r * 0.85, p.y - r * 0.10),
		Vector2(p.x + r * 1.15, p.y),
		Vector2(p.x + r * 0.85, p.y + r * 0.10),
		Vector2(p.x - r * 1.10, p.y + r * 0.30),
	])
	c.draw_colored_polygon(pts, col)
	c.draw_circle(Vector2(p.x + r * 1.05, p.y), r * 0.22, col.lightened(0.4))

static func _zigzag_chain(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Multi-bounce chain: a wider zigzag with three peaks
	var w := r * 1.30
	var th := r * 0.22
	var pts := PackedVector2Array([
		Vector2(p.x - w,       p.y - r * 0.55),
		Vector2(p.x - w * 0.5, p.y + r * 0.55),
		Vector2(p.x,           p.y - r * 0.55),
		Vector2(p.x + w * 0.5, p.y + r * 0.55),
		Vector2(p.x + w,       p.y - r * 0.55),
	])
	for i in pts.size() - 1:
		c.draw_line(pts[i], pts[i + 1], col, th)
	# Dots at each peak so the chain reads as discrete bounces
	for v in pts:
		c.draw_circle(v, r * 0.18, col)

static func _star_burst(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Central dot + radial spokes — discharge / spark
	c.draw_circle(p, r * 0.32, col)
	var spokes := 8
	for i in spokes:
		var a := float(i) / float(spokes) * TAU
		var dir := Vector2(cos(a), sin(a))
		c.draw_line(p + dir * r * 0.45, p + dir * r * 1.15, col, r * 0.14)

# ── Rare-tier glyphs (added with rarity=2 catalog entries) ────────────────────

static func _pierce(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Long arrow piercing through three stacked targets — pierce/hollow rounds.
	var dot_x: Array[float] = [-r * 0.55, 0.0, r * 0.55]
	for x: float in dot_x:
		c.draw_arc(Vector2(p.x + x, p.y), r * 0.28, 0.0, TAU, 24, col, r * 0.10, true)
	# Shaft
	c.draw_rect(Rect2(p.x - r * 1.10, p.y - r * 0.08, r * 2.20, r * 0.16), col, true)
	# Arrow tip
	var tip := PackedVector2Array([
		Vector2(p.x + r * 1.10, p.y - r * 0.32),
		Vector2(p.x + r * 1.45, p.y),
		Vector2(p.x + r * 1.10, p.y + r * 0.32),
	])
	c.draw_colored_polygon(tip, col)

static func _sanctuary(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Cross-on-shield / heart pulse — sanctuary / regen
	var pts := PackedVector2Array([
		Vector2(p.x - r * 0.95, p.y - r * 0.95),
		Vector2(p.x + r * 0.95, p.y - r * 0.95),
		Vector2(p.x + r * 0.95, p.y + r * 0.20),
		Vector2(p.x,            p.y + r * 1.15),
		Vector2(p.x - r * 0.95, p.y + r * 0.20),
	])
	c.draw_colored_polygon(pts, col)
	var inner: Color = col.darkened(0.55)
	# Plus sign — medical / healing
	c.draw_rect(Rect2(p.x - r * 0.14, p.y - r * 0.55, r * 0.28, r * 1.10), inner, true)
	c.draw_rect(Rect2(p.x - r * 0.55, p.y - r * 0.14, r * 1.10, r * 0.28), inner, true)

static func _overcharge(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Twin lightning bolts crossing — supercharged beam
	var bolt_a := PackedVector2Array([
		Vector2(p.x - r * 0.20, p.y - r * 1.15),
		Vector2(p.x - r * 0.75, p.y + r * 0.05),
		Vector2(p.x - r * 0.30, p.y + r * 0.05),
		Vector2(p.x - r * 0.55, p.y + r * 1.15),
		Vector2(p.x + r * 0.30, p.y - r * 0.10),
		Vector2(p.x - r * 0.10, p.y - r * 0.10),
	])
	c.draw_colored_polygon(bolt_a, col)
	var bolt_b := PackedVector2Array([
		Vector2(p.x + r * 0.65, p.y - r * 1.15),
		Vector2(p.x + r * 0.10, p.y + r * 0.05),
		Vector2(p.x + r * 0.55, p.y + r * 0.05),
		Vector2(p.x + r * 0.30, p.y + r * 1.15),
		Vector2(p.x + r * 1.15, p.y - r * 0.10),
		Vector2(p.x + r * 0.75, p.y - r * 0.10),
	])
	c.draw_colored_polygon(bolt_b, col.lightened(0.25))

# ── Archetype standees (large mech silhouettes) ───────────────────────────────
# Hand-tuned for the UpgradePicker card's hero zone. Each is a single-color,
# slightly-stylized "loadout standee" — read at a glance from across the room.

static func _standee_volley(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Riot-shield silhouette + rifle barrel poking out the side. Heavy, planted.
	var shield_w := r * 1.30
	var shield_h := r * 1.80
	# Shield body (rounded-top tower shield)
	var shield := PackedVector2Array([
		Vector2(p.x - shield_w, p.y - shield_h * 0.55),
		Vector2(p.x + shield_w, p.y - shield_h * 0.55),
		Vector2(p.x + shield_w, p.y + shield_h * 0.30),
		Vector2(p.x,            p.y + shield_h * 0.60),
		Vector2(p.x - shield_w, p.y + shield_h * 0.30),
	])
	c.draw_colored_polygon(shield, col)
	# Vertical seam (darker) — shield split
	var seam: Color = col.darkened(0.45)
	c.draw_rect(Rect2(p.x - r * 0.06, p.y - shield_h * 0.55, r * 0.12, shield_h * 0.95), seam, true)
	# Horizontal cross-band
	c.draw_rect(Rect2(p.x - shield_w * 0.85, p.y - r * 0.10, shield_w * 1.70, r * 0.20), seam, true)
	# Rifle barrel — poking out the right edge, suggests sustained fire
	var barrel: Color = col.darkened(0.20)
	c.draw_rect(Rect2(p.x + shield_w * 0.50, p.y - r * 0.22, shield_w * 1.10, r * 0.18), barrel, true)
	# Muzzle
	c.draw_rect(Rect2(p.x + shield_w * 1.55, p.y - r * 0.32, r * 0.30, r * 0.38), barrel, true)
	# "Helmet" dome over the top so it reads as a mech, not just a shield
	c.draw_circle(Vector2(p.x, p.y - shield_h * 0.65), r * 0.55, col)
	# Visor slit
	c.draw_rect(Rect2(p.x - r * 0.40, p.y - shield_h * 0.65 - r * 0.05, r * 0.80, r * 0.14), seam, true)

static func _standee_aegis(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Guardian: round helmet + wide chest plate + concentric aura rings emanating
	# outward. Communicates "support / shield".
	# Aura rings (drawn first so the body sits on top)
	for i in 3:
		var rr: float = r * (0.95 + 0.45 * float(i))
		var ring_alpha: float = 0.55 - 0.15 * float(i)
		var ring: Color = Color(col.r, col.g, col.b, ring_alpha)
		c.draw_arc(p, rr, 0.0, TAU, 48, ring, r * 0.10, true)
	# Body — wide trapezoidal chest
	var body := PackedVector2Array([
		Vector2(p.x - r * 0.95, p.y - r * 0.20),
		Vector2(p.x + r * 0.95, p.y - r * 0.20),
		Vector2(p.x + r * 1.20, p.y + r * 0.95),
		Vector2(p.x - r * 1.20, p.y + r * 0.95),
	])
	c.draw_colored_polygon(body, col)
	# Helmet — round dome
	c.draw_circle(Vector2(p.x, p.y - r * 0.55), r * 0.55, col)
	# Visor stripe
	var seam: Color = col.darkened(0.45)
	c.draw_rect(Rect2(p.x - r * 0.42, p.y - r * 0.60, r * 0.84, r * 0.14), seam, true)
	# Chest emblem — simple inset cross
	c.draw_rect(Rect2(p.x - r * 0.10, p.y + r * 0.10, r * 0.20, r * 0.65), seam, true)
	c.draw_rect(Rect2(p.x - r * 0.40, p.y + r * 0.32, r * 0.80, r * 0.20), seam, true)

static func _standee_arc(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	# Tall, antenna-tipped lightning rod silhouette with a bolt arcing across.
	# Communicates "chained beam / energy".
	# Body — narrow tower
	var body := PackedVector2Array([
		Vector2(p.x - r * 0.65, p.y - r * 0.30),
		Vector2(p.x + r * 0.65, p.y - r * 0.30),
		Vector2(p.x + r * 0.85, p.y + r * 1.00),
		Vector2(p.x - r * 0.85, p.y + r * 1.00),
	])
	c.draw_colored_polygon(body, col)
	# Helmet — sharp angular head
	var head := PackedVector2Array([
		Vector2(p.x - r * 0.55, p.y - r * 0.40),
		Vector2(p.x,            p.y - r * 1.00),
		Vector2(p.x + r * 0.55, p.y - r * 0.40),
	])
	c.draw_colored_polygon(head, col)
	# Antenna prong above
	c.draw_rect(Rect2(p.x - r * 0.05, p.y - r * 1.45, r * 0.10, r * 0.50), col, true)
	c.draw_circle(Vector2(p.x, p.y - r * 1.50), r * 0.13, col.lightened(0.25))
	# Arcing lightning bolt across the chest — the archetype's identity beat
	var bolt: Color = col.lightened(0.30)
	var bolt_pts := PackedVector2Array([
		Vector2(p.x - r * 0.55, p.y + r * 0.10),
		Vector2(p.x - r * 0.10, p.y + r * 0.30),
		Vector2(p.x + r * 0.05, p.y + r * 0.20),
		Vector2(p.x + r * 0.55, p.y + r * 0.85),
		Vector2(p.x + r * 0.20, p.y + r * 0.55),
		Vector2(p.x + r * 0.05, p.y + r * 0.65),
	])
	c.draw_colored_polygon(bolt_pts, bolt)
	# Visor stripe
	var seam: Color = col.darkened(0.50)
	c.draw_rect(Rect2(p.x - r * 0.32, p.y - r * 0.55, r * 0.64, r * 0.12), seam, true)
