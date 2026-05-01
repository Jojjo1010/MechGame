class_name UpgradeBadgeIcon
extends Control

# Small procedural-glyph icon used inside upgrade badges (UltBar inventory grid,
# UpgradePicker chip, etc). Delegates drawing to UpgradeGlyphs.

var upgrade_id: String = ""
var glyph_color: Color = Color.WHITE

func setup(id: String, color: Color) -> void:
	upgrade_id  = id
	glyph_color = color
	queue_redraw()

func _draw() -> void:
	UpgradeGlyphs.draw(self, Rect2(Vector2.ZERO, size), upgrade_id, glyph_color)
