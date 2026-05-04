extends CanvasLayer

# Centre-screen "WAVE N" banner that punches in at the start of each wave.
# Named waves (10/20/30) add a subtitle in hot pink — that subtitle is the
# only telegraph the player gets for off-axis spawns, so the banner lands
# *before* enemies appear. Spawn-spread is 4s (WaveSpawner.SPAWN_SPREAD), so
# a ~2s show is comfortably under the first enemy's arrival.

const HOLD_S      := 1.5
const FADE_IN_S   := 0.20
const FADE_OUT_S  := 0.40
const POP_SCALE   := 1.18

var _root: Control = null
var _title_label: Label = null
var _subtitle_label: Label = null
var _active_tween: Tween = null

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a = 0.0
	add_child(_root)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = 96.0
	box.offset_left = 0.0
	box.offset_right = 0.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", UITheme.FONT_HEADING_L)
	_title_label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_LIME)
	_title_label.add_theme_color_override("font_outline_color", UITheme.COLOR_OUTLINE)
	_title_label.add_theme_constant_override("outline_size", UITheme.OUTLINE_HEADING)
	box.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", UITheme.FONT_HEADING_M)
	_subtitle_label.add_theme_color_override("font_color", UITheme.COLOR_ACCENT_HOT)
	_subtitle_label.add_theme_color_override("font_outline_color", UITheme.COLOR_OUTLINE)
	_subtitle_label.add_theme_constant_override("outline_size", UITheme.OUTLINE_HEADING)
	box.add_child(_subtitle_label)

func show_wave(_number: int, _title: String, subtitle: String) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	# "WAVE N" title suppressed — only the milestone subtitle ("FLANK ASSAULT",
	# "PINCER", "LAST STAND") still pops. Regular waves now have no banner.
	if subtitle == "":
		return
	_title_label.visible = false
	_subtitle_label.text = subtitle
	_subtitle_label.visible = true

	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_root.modulate.a = 0.0
	_root.scale = Vector2.ONE * 0.92
	_root.pivot_offset = _root.size * 0.5

	_active_tween = create_tween()
	_active_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN_S) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.parallel().tween_property(_root, "scale", Vector2.ONE * POP_SCALE, FADE_IN_S) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_root, "scale", Vector2.ONE, 0.10).set_ease(Tween.EASE_IN)
	_active_tween.tween_interval(HOLD_S)
	_active_tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT_S).set_ease(Tween.EASE_IN)
