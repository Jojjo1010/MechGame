extends CanvasLayer

# Lore intro that plays before each run. Single page: header at the top,
# body text typewritered in below, nav hint right under the body. Pressing
# → / SPACE / ENTER / click skips the typewriter (if mid-type) or advances
# to Game.tscn (if already revealed).

const GAME_SCENE_PATH := "res://scenes/game/Game.tscn"

const LORE_HEADER := "CARGO RUN ECHO-7"
const LORE_BODY := \
	"A century ago, the line lost lateral movement.\n" + \
	"Firmware locked. Servos welded. Forward only.\n\n" + \
	"The last directive from Logistics:\n" + \
	"\"Deliver the cargo. Confirm at drop-off.\n" + \
	"Await further instructions.\"\n\n" + \
	"Logistics never spoke again.\n\n" + \
	"The mechs marched anyway. They march still —\n" + \
	"to the drop-off, back for the next contract,\n" + \
	"forward again. Forever forward.\n\n" + \
	"You are the drone. Keep them walking."

const CHARS_PER_SEC := 60.0
const FADE_DUR      := 0.45

enum State { TYPING, READING, DONE }

var _state: State    = State.TYPING
var _visible_chars:  float = 0.0
var _header:    Label = null
var _label:     Label = null
var _nav_hint:  Label = null

func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()

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

	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 28)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(stack)

	_header = Label.new()
	UITheme.style_label_caps(_header, UITheme.FONT_HEADING_L, UITheme.COLOR_ACCENT_LIME)
	_header.text = LORE_HEADER
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.custom_minimum_size  = Vector2(960.0, 0.0)
	_header.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_header)

	_label = Label.new()
	UITheme.style_body(_label, UITheme.COLOR_TEXT_PRIMARY)
	_label.add_theme_font_size_override("font_size", UITheme.FONT_HEADING_M)
	_label.text = LORE_BODY
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode        = TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size  = Vector2(960.0, 0.0)
	_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_label.visible_characters   = 0
	stack.add_child(_label)

	_nav_hint = Label.new()
	UITheme.style_label_caps(_nav_hint, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_TEXT_MUTED)
	_nav_hint.text = "→ NEXT"
	_nav_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nav_hint.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	stack.add_child(_nav_hint)

	# Soft fade-in for the whole stack so the page doesn't pop.
	var c := root
	c.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(c, "modulate:a", 1.0, FADE_DUR)

func _process(delta: float) -> void:
	if _state == State.TYPING:
		_visible_chars += CHARS_PER_SEC * delta
		_label.visible_characters = int(_visible_chars)
		if _label.visible_characters >= _label.text.length():
			_label.visible_characters = -1
			_state = State.READING

func _input(event: InputEvent) -> void:
	if _state == State.DONE:
		return
	if not _is_advance(event):
		return
	get_viewport().set_input_as_handled()
	if _state == State.TYPING:
		# First press: snap the body fully visible. Player needs another press
		# to advance — gives the "fill / read / start" rhythm even on a fast typer.
		_visible_chars = float(_label.text.length())
		_label.visible_characters = -1
		_state = State.READING
		return
	_state = State.DONE
	_change_to_game()

func _is_advance(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return false
		match k.keycode:
			KEY_RIGHT, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				return true
	return false

func _change_to_game() -> void:
	# Short fade-out before the scene change so the cut to the game world is soft.
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, FADE_DUR)
	t.tween_callback(func() -> void:
		get_tree().change_scene_to_file(GAME_SCENE_PATH))
