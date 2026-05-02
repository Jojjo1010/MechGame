extends CanvasLayer

# First-run on-boarding director. Pauses the game and forces the player to
# perform each core action before continuing — they can't skip past WASD,
# SHIFT, or LEFT-CLICK without doing them. The repair beat is non-blocking
# (movement is required to satisfy it) and triggers when a mech first drops
# below the HP threshold during regular gameplay.
#
# State machine — each *_SHOWING state pauses the tree and waits for the
# corresponding input; each *_FADING state unpauses for a brief practice
# window so the player feels their action register before the next prompt
# overlays. After LMB, control returns to the normal wave loop. REPAIR_WATCH
# polls mechs without modal until first damage; REPAIR_SHOWING displays a
# non-pausing prompt until the drone gets within range. DONE persists the
# SaveData flag and frees the overlay.

const APPROACH_RADIUS    := 5.0
const REPAIR_HP_TRIGGER  := 0.60
const FADE_DUR           := 0.30
const PRACTICE_DUR       := 1.0    # seconds of free play after each prompt
const REPAIR_WATCH_TIMEOUT := 90.0 # auto-complete tutorial if mechs never get hurt

const PROMPT_PANEL_W     := 600.0
const PROMPT_PANEL_PAD   := UITheme.PAD_XL
const PROMPT_CORNER_R    := 16
# How far down from the top of the screen the modal sits — clears the 64 px
# XP bar with a comfortable margin so the gameplay below stays visible.
const PROMPT_TOP_OFFSET  := 140.0

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
var _was_paused:   bool     = false
var _modal_root:   PanelContainer = null
var _chip_label:   Label    = null
var _action_label: Label    = null

func setup(p_drone: Node3D, p_mechs: Array) -> void:
	_drone = p_drone
	_mechs = p_mechs

func _ready() -> void:
	# Above HUD (10–12) and the upgrade picker (50), below DeathScreen / WinScreen (60).
	layer = 55
	# Tutorial drives the pause itself, so it must keep ticking while paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
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

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UITheme.PAD_M)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_root.add_child(col)

	_chip_label = Label.new()
	UITheme.style_label_caps(_chip_label, UITheme.FONT_HEADING_L, UITheme.COLOR_ACCENT_LIME)
	_chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chip_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	col.add_child(_chip_label)

	_action_label = Label.new()
	UITheme.style_label_caps(_action_label, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_TEXT_PRIMARY)
	_action_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_label.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	col.add_child(_action_label)

# ── State machine ────────────────────────────────────────────────────────────

func _enter_state(new_state: State) -> void:
	_state       = new_state
	_state_timer = 0.0
	match new_state:
		State.WASD_SHOWING:   _show_modal("WASD",        "MOVE THE DRONE", true)
		State.SHIFT_SHOWING:  _show_modal("SHIFT",       "DASH",           true)
		State.LMB_SHOWING:    _show_modal("LEFT-CLICK",  "FIRE ULT",       true)
		State.REPAIR_SHOWING: _show_modal("APPROACH",    "REPAIR DAMAGED MECH", false)
		State.WASD_FADING, State.SHIFT_FADING, State.LMB_FADING:
			_hide_modal()
			_set_paused(false)
		State.REPAIR_WATCH:
			_hide_modal()
			_set_paused(false)
		State.DONE:
			_hide_modal()
			_set_paused(false)
			SaveData.mark_tutorial_seen()
			# Wait for the fade to finish before freeing.
			var t := create_tween()
			t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			t.tween_interval(FADE_DUR + 0.1)
			t.tween_callback(queue_free)

func _show_modal(chip_text: String, action_text: String, pause_tree: bool) -> void:
	_chip_label.text   = chip_text.to_upper()
	_action_label.text = action_text.to_upper()
	_set_paused(pause_tree)
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(_modal_root, "modulate:a", 1.0, FADE_DUR)

func _hide_modal() -> void:
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(_modal_root, "modulate:a", 0.0, FADE_DUR)

# Pauses or unpauses the tree, but only flips state if it would change. Avoids
# fighting an upstream pause from another system (e.g. PauseMenu).
func _set_paused(should_pause: bool) -> void:
	get_tree().paused = should_pause

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
