extends Control
class_name ActionIcon

# Bare procedural action glyph — no hex frame so it doesn't compete with the
# key chips next to it. Tints with `accent`. Set `action_id` to one of the
# IDs handled by ActionGlyphs.draw ("move", "dash", "ult", "repair", "camera",
# "zoom").

@export var action_id: String = ""
@export var accent:    Color  = UITheme.COLOR_ACCENT_LIME

func _ready() -> void:
	queue_redraw()

func set_action(id: String) -> void:
	if action_id == id:
		return
	action_id = id
	queue_redraw()

func set_accent(color: Color) -> void:
	if accent == color:
		return
	accent = color
	queue_redraw()

func _draw() -> void:
	if action_id == "" or size.x <= 0.0 or size.y <= 0.0:
		return
	ActionGlyphs.draw(self, Rect2(Vector2.ZERO, size), action_id, accent)
