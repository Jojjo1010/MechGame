extends CanvasLayer

# Lore intro that plays before each run. Stages of text typewriter in over a
# black backdrop; each stage holds briefly, then auto-advances. Any click or
# keypress accelerates: during typing it fills the current stage instantly,
# during the hold it advances to the next stage. The last stage routes into
# Game.tscn.

const GAME_SCENE_PATH := "res://scenes/game/Game.tscn"

# Stages of the crawl. `text` is the body. `header` (optional) renders smaller,
# uppercase, lime — used for the first "CARGO RUN ECHO-7" beat. `hold` is the
# auto-advance delay after the typewriter finishes.
const STAGES := [
	{header = true,  text = "CARGO RUN ECHO-7",                                                  hold = 1.6},
	{header = false, text = "A century ago, the line lost lateral movement.\nFirmware locked. Servos welded. Forward only.", hold = 2.4},
	{header = false, text = "The last directive from Logistics:\n\n\"Deliver the cargo. Confirm at drop-off.\nAwait further instructions.\"", hold = 3.0},
	{header = false, text = "Logistics never spoke again.",                                       hold = 2.4},
	{header = false, text = "The mechs marched anyway. They march still —\nto the drop-off, back for the next contract,\nforward again. Forever forward.", hold = 2.6},
	{header = false, text = "You are the drone.\nKeep them walking.",                             hold = 2.0},
]

# Reveal speed in characters per second. Slow enough to read along with, fast
# enough that an impatient player can skip in two clicks per stage.
const CHARS_PER_SEC := 38.0
const FADE_DUR      := 0.45

enum State { TYPING, READING, DONE }

var _stage_idx: int   = 0
var _state: State     = State.TYPING
var _visible_chars:    float = 0.0
var _read_timer:       float = 0.0
var _label:        Label = null
var _skip_hint:    Label = null

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

	# "click to skip" hint pinned to the bottom — small, muted; always visible.
	var hint_anchor := Control.new()
	hint_anchor.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_anchor.offset_top = -64.0
	hint_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint_anchor)

	_skip_hint = Label.new()
	_skip_hint.text = "CLICK OR PRESS ANY KEY"
	UITheme.style_label_caps(_skip_hint, UITheme.FONT_MICRO_CAPS, UITheme.COLOR_TEXT_MUTED)
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_skip_hint.offset_top    = -32.0
	_skip_hint.offset_bottom = 0.0
	_skip_hint.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	hint_anchor.add_child(_skip_hint)

func _load_stage(idx: int) -> void:
	_stage_idx = idx
	var stage: Dictionary = STAGES[idx]
	if bool(stage.header):
		UITheme.style_label_caps(_label, UITheme.FONT_HEADING_L, UITheme.COLOR_ACCENT_LIME)
	else:
		UITheme.style_body(_label, UITheme.COLOR_TEXT_PRIMARY)
		_label.add_theme_font_size_override("font_size", UITheme.FONT_HEADING_M)
	_label.text             = String(stage.text)
	_label.visible_characters = 0
	_visible_chars          = 0.0
	_state                  = State.TYPING

	# Quick fade-in per stage so the swap doesn't feel hard-cut.
	_label.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(_label, "modulate:a", 1.0, FADE_DUR)

func _process(delta: float) -> void:
	match _state:
		State.TYPING:
			_visible_chars += CHARS_PER_SEC * delta
			_label.visible_characters = int(_visible_chars)
			if _label.visible_characters >= _label.text.length():
				_state = State.READING
				_read_timer = float(STAGES[_stage_idx].hold)
		State.READING:
			_read_timer -= delta
			if _read_timer <= 0.0:
				_advance()
		State.DONE:
			pass

func _input(event: InputEvent) -> void:
	if _state == State.DONE:
		return
	var pressed_now := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		pressed_now = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventKey:
		var k := event as InputEventKey
		pressed_now = k.pressed and not k.echo
	if not pressed_now:
		return
	get_viewport().set_input_as_handled()
	if _state == State.TYPING:
		# First click during typing: snap to the end of this stage so the
		# player can read it for as long as they want before the next click.
		_visible_chars = float(_label.text.length())
		_label.visible_characters = -1
		_state      = State.READING
		_read_timer = float(STAGES[_stage_idx].hold) * 0.5
	elif _state == State.READING:
		_advance()

func _advance() -> void:
	if _stage_idx + 1 >= STAGES.size():
		_state = State.DONE
		_change_to_game()
		return
	_load_stage(_stage_idx + 1)

func _change_to_game() -> void:
	# Short fade-out before scene change so the cut to the game world is soft.
	var t := create_tween()
	t.tween_property(_label,     "modulate:a", 0.0, FADE_DUR)
	t.parallel().tween_property(_skip_hint, "modulate:a", 0.0, FADE_DUR)
	t.tween_callback(func() -> void:
		get_tree().change_scene_to_file(GAME_SCENE_PATH))
