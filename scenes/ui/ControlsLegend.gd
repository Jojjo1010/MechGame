extends CanvasLayer

const ENTRIES: Array[String] = [
	"[W A S D]  Move drone",
	"[Q]           Camera angle",
	"[Scroll]     Zoom",
	"[E]           Mech ultimate",
]

const BG_COLOR    := Color(0.0,  0.0,  0.0,  0.50)
const TEXT_COLOR  := Color(1.0,  1.0,  1.0,  0.90)
const KEY_COLOR   := Color(0.85, 0.92, 1.0,  1.0)
const PADDING     := 22
const ROW_GAP     := 10
const TITLE_SIZE  := 28
const ROW_SIZE    := 24

func _ready() -> void:
	layer = 10

	# Full-height transparent anchor on the left edge for vertical centering
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	# Panel sits inside the anchor; we'll center it vertically after sizing
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(root)

	# Background
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Title
	var title := Label.new()
	title.text = "CONTROLS"
	title.add_theme_color_override("font_color", KEY_COLOR)
	title.add_theme_font_size_override("font_size", TITLE_SIZE)
	title.position = Vector2(PADDING, PADDING)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	# Rows
	var y := PADDING + title.get_minimum_size().y + ROW_GAP + 4
	for entry in ENTRIES:
		var row := Label.new()
		row.text = entry
		row.add_theme_color_override("font_color", TEXT_COLOR)
		row.add_theme_font_size_override("font_size", ROW_SIZE)
		row.position = Vector2(PADDING, y)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(row)
		y += row.get_minimum_size().y + ROW_GAP

	# Size bg then vertically center the panel in the anchor
	await get_tree().process_frame
	var max_w := 0.0
	for child in root.get_children():
		if child is Label:
			var lbl := child as Label
			max_w = maxf(max_w, lbl.position.x + lbl.get_minimum_size().x)
	var panel_size := Vector2(max_w + PADDING, y + PADDING - ROW_GAP)
	bg.size = panel_size
	root.size = panel_size
	root.position = Vector2(20, (anchor.size.y - panel_size.y) * 0.5)
