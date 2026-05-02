extends CanvasLayer

# Tutorial director launched from the HOW TO PLAY button. The game keeps
# running underneath the prompt — the player sees the world alive (mechs
# walking, drone steerable) while learning each control. Each *_SHOWING state
# waits for its input non-blockingly; each *_FADING state gives a long
# practice window so the player can mess with the control they just learned.
# REPAIR_WATCH polls mechs without modal until first damage; REPAIR_SHOWING
# displays a prompt until the drone gets within range. DONE returns to the
# start screen.
#
# Visual style mirrors ControlsLegend: chip (real key cap or WASD cluster) +
# ActionIcon glyph + uppercase action label.

const APPROACH_RADIUS    := 5.0
const REPAIR_HP_TRIGGER  := 0.60
const FADE_DUR           := 0.30
const PRACTICE_DUR       := 5.0    # seconds of free play after each prompt
const REPAIR_WATCH_TIMEOUT := 90.0 # auto-complete tutorial if mechs never get hurt

const PROMPT_PANEL_W     := 640.0
const PROMPT_PANEL_PAD   := UITheme.PAD_XL
const PROMPT_CORNER_R    := 16
# How far down from the top of the screen the modal sits — clears the 64 px
# XP bar with a comfortable margin so the gameplay below stays visible.
const PROMPT_TOP_OFFSET  := 140.0

# Chip sizing is shared with ControlsLegend via KeyChip — referenced from
# there, not duplicated, so the tutorial prompt and the persistent legend on
# the left side of the HUD never visually drift apart.
const KEY_FONT   := UITheme.FONT_LABEL_CAPS  # 24 — single-letter caps in WASD
const SHIFT_FONT := UITheme.FONT_BODY        # 16 — multi-letter wide caps
const ICON_SIZE  := 40.0

enum State {
	WASD_SHOWING,  WASD_FADING,
	SHIFT_SHOWING, SHIFT_FADING,
	LMB_SHOWING,   LMB_FADING,
	REPAIR_WATCH,  REPAIR_SHOWING,
	DONE,
}

var _state: State           = State.WASD_SHOWING
var _state_timer: float     = 0.0
var _drone:        Node3D   = null
var _mechs:        Array    = []
var _modal_root:   PanelContainer = null
var _row:          HBoxContainer = null
var _chip_holder:  Control  = null   # swapped each prompt — holds the key chip
var _action_icon:  ActionIcon = null
var _action_label: Label    = null

func setup(p_drone: Node3D, p_mechs: Array) -> void:
	_drone = p_drone
	_mechs = p_mechs

func _ready() -> void:
	# Above HUD (10–12) and the upgrade picker (50), below DeathScreen / WinScreen (60).
	layer = 55
	_build()
	_enter_state(State.WASD_SHOWING)

# ── Layout ───────────────────────────────────────────────────────────────────

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Don't intercept clicks — let LMB during LMB_SHOWING reach the polling.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top-anchored hbox: full width, height auto-sizes to the panel content.
	# Pushing offset_top down past the XP bar leaves the gameplay area below
	# fully visible — the original CenterContainer placed the prompt over the
	# mech line and made the action unreadable.
	var top_row := HBoxContainer.new()
	top_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_row.offset_top    = PROMPT_TOP_OFFSET
	top_row.offset_bottom = PROMPT_TOP_OFFSET
	top_row.alignment     = BoxContainer.ALIGNMENT_CENTER
	top_row.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_row)

	_modal_root = PanelContainer.new()
	_modal_root.custom_minimum_size = Vector2(PROMPT_PANEL_W, 0.0)
	_modal_root.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.panel_stylebox(UITheme.COLOR_BORDER_BRIGHT)
	sb.bg_color              = UITheme.COLOR_PANEL
	sb.set_corner_radius_all(PROMPT_CORNER_R)
	sb.content_margin_left   = PROMPT_PANEL_PAD
	sb.content_margin_right  = PROMPT_PANEL_PAD
	sb.content_margin_top    = PROMPT_PANEL_PAD
	sb.content_margin_bottom = PROMPT_PANEL_PAD
	_modal_root.add_theme_stylebox_override("panel", sb)
	_modal_root.modulate.a = 0.0
	top_row.add_child(_modal_root)

	# Layout mirrors ControlsLegend rows: chip on the left, action glyph in
	# the middle, uppercase label on the right.
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", UITheme.PAD_L)
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_root.add_child(_row)

	_chip_holder = Control.new()
	_chip_holder.custom_minimum_size = Vector2(0.0, KeyChip.KEY_SIZE * 2.0 + KeyChip.KEY_GAP)
	_chip_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_chip_holder)

	_action_icon = ActionIcon.new()
	_action_icon.accent              = UITheme.COLOR_ACCENT_LIME
	_action_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_action_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_action_icon.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_action_icon)

	_action_label = Label.new()
	UITheme.style_label_caps(_action_label, UITheme.FONT_HEADING_M, UITheme.COLOR_TEXT_PRIMARY)
	_action_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_action_label.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_action_label)

# ── State machine ────────────────────────────────────────────────────────────

func _enter_state(new_state: State) -> void:
	_state       = new_state
	_state_timer = 0.0
	match new_state:
		State.WASD_SHOWING:   _show_prompt(KeyChip.make_wasd_cluster(KEY_FONT),                                          "move",   "MOVE THE DRONE")
		State.SHIFT_SHOWING:  _show_prompt(KeyChip.make_key_cap("SHIFT", KeyChip.SHIFT_W, KeyChip.SHIFT_H, SHIFT_FONT),  "dash",   "DASH")
		State.LMB_SHOWING:    _show_prompt(KeyChip.make_key_cap("LMB",   KeyChip.SHIFT_W, KeyChip.SHIFT_H, SHIFT_FONT),  "ult",    "FIRE ULT")
		State.REPAIR_SHOWING: _show_prompt(KeyChip.make_key_cap("APPROACH", KeyChip.SHIFT_W * 1.6, KeyChip.SHIFT_H, SHIFT_FONT), "repair", "REPAIR DAMAGED MECH")
		State.WASD_FADING, State.SHIFT_FADING, State.LMB_FADING:
			_hide_modal()
		State.REPAIR_WATCH:
			_hide_modal()
		State.DONE:
			_hide_modal()
			# Tutorial only runs via HOW TO PLAY now, so DONE always returns to
			# the start screen. Clear the flag first so re-entering Game.tscn
			# from PLAY doesn't re-spawn the tutorial.
			RunManager.tutorial_only = false
			var t := create_tween()
			t.tween_interval(FADE_DUR + 0.1)
			t.tween_callback(func() -> void:
				get_tree().change_scene_to_file("res://scenes/ui/StartScreen.tscn"))

func _show_prompt(chip: Control, icon_id: String, action_text: String) -> void:
	# Swap the chip into the holder slot. Frees any previous chip so the row
	# always has exactly one input visualization.
	for child in _chip_holder.get_children():
		child.queue_free()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_holder.add_child(chip)
	_chip_holder.custom_minimum_size.x = chip.custom_minimum_size.x
	_action_icon.set_action(icon_id)
	_action_label.text = action_text
	var t := create_tween()
	t.tween_property(_modal_root, "modulate:a", 1.0, FADE_DUR)

func _hide_modal() -> void:
	var t := create_tween()
	t.tween_property(_modal_root, "modulate:a", 0.0, FADE_DUR)


# ── Per-frame ────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_state_timer += delta
	match _state:
		State.WASD_SHOWING:
			if _wasd_pressed():
				_enter_state(State.WASD_FADING)
		State.WASD_FADING:
			if _state_timer >= PRACTICE_DUR:
				_enter_state(State.SHIFT_SHOWING)
		State.SHIFT_SHOWING:
			if Input.is_key_pressed(KEY_SHIFT):
				_enter_state(State.SHIFT_FADING)
		State.SHIFT_FADING:
			if _state_timer >= PRACTICE_DUR:
				_enter_state(State.LMB_SHOWING)
		State.LMB_SHOWING:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_enter_state(State.LMB_FADING)
		State.LMB_FADING:
			if _state_timer >= PRACTICE_DUR:
				_enter_state(State.REPAIR_WATCH)
		State.REPAIR_WATCH:
			if _state_timer >= REPAIR_WATCH_TIMEOUT:
				# Player is doing fine without help — call the tutorial done.
				_enter_state(State.DONE)
				return
			if _any_mech_damaged():
				_enter_state(State.REPAIR_SHOWING)
		State.REPAIR_SHOWING:
			if _drone_near_damaged_mech():
				_enter_state(State.DONE)
		State.DONE:
			pass

# ── Conditions ───────────────────────────────────────────────────────────────

func _wasd_pressed() -> bool:
	return Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) \
		or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D)

func _any_mech_damaged() -> bool:
	for m in _mechs:
		if _mech_is_damaged(m):
			return true
	return false

func _drone_near_damaged_mech() -> bool:
	if _drone == null or not is_instance_valid(_drone):
		return false
	for m in _mechs:
		if not is_instance_valid(m):
			continue
		if not _mech_is_damaged(m):
			continue
		if _drone.global_position.distance_to(m.global_position) <= APPROACH_RADIUS:
			return true
	return false

func _mech_is_damaged(m: Object) -> bool:
	if not is_instance_valid(m):
		return false
	var hp:     Variant = m.get("health")
	var hp_max: Variant = m.get("max_health")
	if hp == null or hp_max == null or float(hp_max) <= 0.0:
		return false
	return float(hp) / float(hp_max) < REPAIR_HP_TRIGGER
