extends CanvasLayer

# Lore intro that plays before each run. Stages of text typewriter in over a
# black backdrop; each stage waits for the player to press → / SPACE / ENTER /
# click before advancing — never auto-advances. ← / BACKSPACE returns to the
# previous stage (rendered already filled). The last stage routes into
# Game.tscn.

const GAME_SCENE_PATH := "res://scenes/game/Game.tscn"

# Stages of the crawl. `text` is the body. `header` (optional) renders larger,
# uppercase, lime — used for the first "CARGO RUN ECHO-7" beat.
const STAGES := [
	{header = true,  text = "CARGO RUN ECHO-7"},
	{header = false, text = "A century ago, the line lost lateral movement.\nFirmware locked. Servos welded. Forward only."},
	{header = false, text = "The last directive from Logistics:\n\n\"Deliver the cargo. Confirm at drop-off.\nAwait further instructions.\""},
	{header = false, text = "Logistics never spoke again."},
	{header = false, text = "The mechs marched anyway. They march still —\nto the drop-off, back for the next contract,\nforward again. Forever forward."},
	{header = false, text = "You are the drone.\nKeep them walking."},
]

# Reveal speed in characters per second. Slow enough to read along with, fast
# enough that an impatient player can skip a stage with one keypress.
const CHARS_PER_SEC := 38.0
const FADE_DUR      := 0.45

enum State { TYPING, READING, DONE }

var _stage_idx: int   = 0
var _state: State     = State.TYPING
var _visible_chars:    float = 0.0
var _label:        Label = null
var _nav_hint:     Label = null

func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_load_stage(0)

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.color = UITheme.COLOR_DEEP
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode        = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size  = Vector2(960.0, 0.0)
	_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	center.add_child(_label)

	# Nav hint pinned to the bottom — small, muted; updates per-stage so the
	# first stage hides the BACK arrow.
	var hint_anchor := Control.new()
	hint_anchor.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_anchor.offset_top = -64.0
	hint_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint_anchor)

	_nav_hint = Label.new()
	UITheme.style_label_caps(_nav_hint, UITheme.FONT_MICRO_CAPS, UITheme.COLOR_TEXT_MUTED)
	_nav_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nav_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_nav_hint.offset_top    = -32.0
	_nav_hint.offset_bottom = 0.0
	_nav_hint.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	hint_anchor.add_child(_nav_hint)

func _load_stage(idx: int, fully_visible: bool = false) -> void:
	_stage_idx = idx
	var stage: Dictionary = STAGES[idx]
	if bool(stage.header):
		UITheme.style_label_caps(_label, UITheme.FONT_HEADING_L, UITheme.COLOR_ACCENT_LIME)
	else:
		UITheme.style_body(_label, UITheme.COLOR_TEXT_PRIMARY)
		_label.add_theme_font_size_override("font_size", UITheme.FONT_HEADING_M)
	_label.text = String(stage.text)
	if fully_visible:
		# Coming from BACK navigation — show the stage filled, ready for next input.
		_visible_chars              = float(_label.text.length())
		_label.visible_characters   = -1
		_state                      = State.READING
	else:
		_visible_chars              = 0.0
		_label.visible_characters   = 0
		_state                      = State.TYPING

	_refresh_nav_hint()

	# Quick fade-in per stage so the swap doesn't feel hard-cut.
	_label.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_label, "modulate:a", 1.0, FADE_DUR)

# Updates the bottom hint to reflect what the player can do right now.
# Stage 0 hides the BACK arrow (nothing to go back to).
func _refresh_nav_hint() -> void:
	if _nav_hint == null:
		return
	if _stage_idx <= 0:
		_nav_hint.text = "→ NEXT"
	else:
		_nav_hint.text = "← BACK     → NEXT"

func _process(delta: float) -> void:
	if _state == State.TYPING:
		_visible_chars += CHARS_PER_SEC * delta
		_label.visible_characters = int(_visible_chars)
		if _label.visible_characters >= _label.text.length():
			_state = State.READING

func _input(event: InputEvent) -> void:
	if _state == State.DONE:
		return
	var dir := _input_direction(event)
	if dir == 0:
		return
	get_viewport().set_input_as_handled()
	if dir > 0:
		_go_forward()
	else:
		_go_back()

# Returns +1 for "next", -1 for "back", 0 if the event isn't navigation.
func _input_direction(event: InputEvent) -> int:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			return 1
		return 0
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return 0
		match k.keycode:
			KEY_RIGHT, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				return 1
			KEY_LEFT, KEY_BACKSPACE:
				return -1
	return 0

func _go_forward() -> void:
	if _state == State.TYPING:
		# First forward press during typing: snap the current stage to fully
		# visible. The player then needs another press to advance — this gives
		# them the "fill / read / advance" rhythm even on a fast typer.
		_visible_chars = float(_label.text.length())
		_label.visible_characters = -1
		_state = State.READING
		return
	if _stage_idx + 1 >= STAGES.size():
		_state = State.DONE
		_change_to_game()
		return
	_load_stage(_stage_idx + 1)

func _go_back() -> void:
	# BACK during typing snaps the current stage filled (cheap "wait, let me
	# read it" affordance) before any further BACK steps to a prior stage.
	if _state == State.TYPING:
		_visible_chars = float(_label.text.length())
		_label.visible_characters = -1
		_state = State.READING
		return
	if _stage_idx <= 0:
		return
	_load_stage(_stage_idx - 1, true)

func _change_to_game() -> void:
	# Short fade-out before scene change so the cut to the game world is soft.
	var t := create_tween()
	t.tween_property(_label,    "modulate:a", 0.0, FADE_DUR)
	t.parallel().tween_property(_nav_hint, "modulate:a", 0.0, FADE_DUR)
	t.tween_callback(func() -> void:
		get_tree().change_scene_to_file(GAME_SCENE_PATH))
