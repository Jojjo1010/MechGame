extends CanvasLayer

# Tutorial director launched from the HOW TO PLAY button. The Game scene is
# stripped to essentials (no waves, no XP / ult / upgrade UI), so the player
# only sees what each prompt is teaching at the time. A 3D marker hovers over
# whichever mech the player should approach next so the ult and repair prompts
# always tie to a concrete target. Each prompt completes with a lime flash +
# audible cue so the player feels the input register before the next step.
#
# Visual style mirrors ControlsLegend: chip (real key cap or WASD cluster) +
# ActionIcon glyph + uppercase action label.

const APPROACH_RADIUS    := 5.0
const FADE_DUR           := 0.30
const PRACTICE_DUR       := 5.0    # seconds of free play after each prompt
# How long the per-mech archetype intro lingers before swapping to the ult
# prompt. Long enough to read the name + tagline, short enough not to drag.
const INTRO_DUR          := 2.5
# Post-fire wait so projectiles/splash can finish landing before we judge
# success. After this elapses, ULT_FADING checks the dummy count: all dead →
# celebrate + advance, any alive → repeat the same mech's lesson.
const ULT_RESOLVE_DELAY  := 1.5
# Input lockout after a prompt enters — covers FADE_DUR plus a moment to read.
# Without this, a player who's already pressing W when WASD_SHOWING enters
# satisfies the trigger on the same frame and skips past the prompt entirely.
const MIN_PROMPT_TIME    := 0.45

# Tutorial practice dummies — instantiated on demand, low HP so each ult
# one-shots the formation. Reuse the standard Enemy scene with `is_dummy=true`
# so the lesson uses the same silhouette the player will see in real combat.
const ENEMY_SCENE         := preload("res://scenes/enemies/Enemy.tscn")
const TUTORIAL_DUMMY_HP   := 30.0
# Distance ahead of the marked mech (along -Z, the marching forward axis) at
# which weapon-specific formations spawn.
const DUMMY_FORWARD_DIST  := 9.0

# Completion feedback — a brief lime tint on the modal panel + a positive
# audio ping. Tuned short so the next prompt comes promptly, not lingering.
const COMPLETE_FLASH_DUR := 0.08
const COMPLETE_TINT      := Color(1.5, 1.9, 0.7, 1.0)
const COMPLETE_SOUND     := "repair_correct_3"

# How much HP to subtract from the chosen repair target before showing the
# REPAIR prompt. Picked to drop below BURN_THRESHOLD (0.45 in Mech.gd) so
# `needs_repair()` returns true and the F key actually opens the minigame.
const REPAIR_DAMAGE_FRACTION := 0.70

# 3D marker (downward cone) that floats above whichever mech the tutorial is
# pointing at. Sized for the orthographic camera; bobs and pulses in place so
# it reads as a UI cue rather than world geometry.
const MARKER_HEIGHT       := 7.5
const MARKER_BOB_AMP      := 0.4
const MARKER_BOB_FREQ     := 4.0
const MARKER_PULSE_AMP    := 0.12
const MARKER_CONE_RADIUS  := 0.7
const MARKER_CONE_HEIGHT  := 1.6

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

# Combined ult flow: ULT_SHOWING_E waits for the player to approach the
# marked mech and press E. If the mech's ult uses aim mode (GUN/BEAM/ROCKET),
# we slide into ULT_SHOWING_LMB by swapping the chip inline — no fade — so
# it reads as the second half of one continuous "fire ult" beat instead of a
# fresh prompt. ULT_FADING is the post-completion practice window.
enum State {
	WASD_SHOWING,    WASD_FADING,
	SHIFT_SHOWING,   SHIFT_FADING,
	ULT_INTRO,       # archetype name + tagline, auto-advances after INTRO_DUR
	ULT_SHOWING_E,   ULT_SHOWING_LMB,   ULT_FADING,
	REPAIR_SHOWING,
	DONE,
}

var _state: State           = State.WASD_SHOWING
var _state_timer: float     = 0.0
var _drone:        Node3D   = null
var _mechs:        Array    = []
var _modal_root:   PanelContainer = null
var _row:          HBoxContainer = null
var _chip_holder:  CenterContainer = null   # swapped each prompt — holds the key chip
var _action_icon:  ActionIcon = null
var _action_label: Label    = null
# Big lime check that pops in over the modal on every step completion. Lives
# outside the modal panel so its scale punch isn't constrained by the panel
# layout.
var _check_overlay: ActionIcon = null

# Mech currently flagged. _target_mech wears the marker during the ult-
# teaching steps; _repair_mech takes over once we damage it for REPAIR.
var _target_mech:    Node3D = null
var _repair_mech:    Node3D = null
var _marker:         Node3D = null
var _marker_t:       float  = 0.0
# Index into _mechs of the mech we're currently teaching the ult for. Cycles
# through every mech in line so each archetype gets named and demoed.
var _ult_mech_idx:   int    = -1
# Practice dummies for the current phase. Cleared between phases so each
# weapon's lesson starts on a clean stage.
var _dummies:        Array[Node3D] = []
# Set of WASD keys the player has pressed at least once during the WASD
# prompt. Advance only when all four are present — pressing W alone shouldn't
# end the lesson when the prompt is teaching the whole cluster.
var _wasd_seen:      Dictionary = {}
# Latches true while _resolve_ult_success is mid-celebration so its scheduled
# advance can't be re-triggered by per-frame checks.
var _ult_resolving:  bool       = false

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
	# Don't intercept clicks — let LMB during ULT_SHOWING_LMB reach the polling.
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top-anchored hbox: full width, height auto-sizes to the panel content.
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
	# Pivot in the middle so flash-scale (if added later) feels centered.
	_modal_root.pivot_offset        = Vector2(PROMPT_PANEL_W * 0.5, 0.0)
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

	# CenterContainer keeps the chip vertically aligned with the action icon
	# and label regardless of chip height (single 40 px cap vs 84 px WASD
	# cluster vs 84 px LMB silhouette).
	_chip_holder = CenterContainer.new()
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

	# Check overlay — sibling to top_row so it can grow past the modal's edges
	# when its scale punches above 1.0. Anchored to the panel area.
	const CHECK_SIZE := 120.0
	_check_overlay = ActionIcon.new()
	_check_overlay.action_id            = "check"
	_check_overlay.accent               = UITheme.COLOR_ACCENT_LIME
	_check_overlay.custom_minimum_size  = Vector2(CHECK_SIZE, CHECK_SIZE)
	_check_overlay.size                 = Vector2(CHECK_SIZE, CHECK_SIZE)
	_check_overlay.pivot_offset         = Vector2(CHECK_SIZE * 0.5, CHECK_SIZE * 0.5)
	_check_overlay.modulate             = Color(1.0, 1.0, 1.0, 0.0)
	_check_overlay.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_check_overlay.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_check_overlay.offset_left          = -CHECK_SIZE * 0.5
	_check_overlay.offset_right         =  CHECK_SIZE * 0.5
	_check_overlay.offset_top           = PROMPT_TOP_OFFSET + 20.0
	_check_overlay.offset_bottom        = PROMPT_TOP_OFFSET + 20.0 + CHECK_SIZE
	root.add_child(_check_overlay)

# ── State machine ────────────────────────────────────────────────────────────

func _enter_state(new_state: State) -> void:
	_state       = new_state
	_state_timer = 0.0
	_apply_tutorial_mute(new_state)
	# Surface ContextUI (MechOptionsPanel + ControlsLegend + UltBar) once we're
	# actually teaching ult/repair. Hiding it during WASD/CAMERA/SHIFT keeps the
	# screen focused on the prompt being taught; revealing it on ULT_INTRO gives
	# the player the supporting reference UI right when the ult tour begins.
	var late_ui_visible := _state_uses_mech_panel(new_state) or new_state == State.ULT_INTRO
	_set_mech_options_enabled(late_ui_visible)
	_set_late_ui_visible(late_ui_visible)
	match new_state:
		State.WASD_SHOWING:
			_wasd_seen.clear()
			_show_prompt(KeyChip.make_movement_cluster(KEY_FONT), "move", "MOVE THE DRONE")
		State.SHIFT_SHOWING:
			_spawn_shift_dummies()
			_show_prompt(KeyChip.make_key_cap("SHIFT", KeyChip.SHIFT_W, KeyChip.SHIFT_H, SHIFT_FONT), "dash", "DASH THROUGH ENEMIES")
		State.ULT_INTRO:
			# _target_mech / _ult_mech_idx are set by _advance_to_next_ult()
			# before this state is entered.
			_spawn_dummies_for(_target_mech)
			_force_target_ult_ready()
			_show_intro_for(_target_mech)
		State.ULT_SHOWING_E:
			_show_prompt(KeyChip.make_key_cap("E", KeyChip.KEY_SIZE, KeyChip.KEY_SIZE, KEY_FONT), "ult", "FIRE " + _archetype_name_for(_target_mech) + " ULT")
		State.ULT_SHOWING_LMB:
			# Inline swap — modal stays visible. Reads as the second beat of
			# one ult-firing action instead of a fresh prompt that surprises
			# the player after they "already fired".
			_swap_prompt(_make_lmb_chip(), "ult", "AIM & FIRE")
		State.REPAIR_SHOWING:
			_repair_mech = _force_damage_for_repair()
			_attach_marker_to(_repair_mech)
			_show_prompt(KeyChip.make_key_cap("F", KeyChip.KEY_SIZE, KeyChip.KEY_SIZE, KEY_FONT), "repair", "REPAIR MARKED MECH")
		State.WASD_FADING, State.SHIFT_FADING:
			_complete_and_fade()
		State.ULT_FADING:
			# No celebration on entry — we don't know yet if the ult killed all
			# dummies. The resolve-delay branch in _process decides:
			#   all dead → _resolve_ult_success (celebrate + advance)
			#   any alive → _restart_current_mech (repeat instructions)
			pass
		State.DONE:
			_free_marker()
			_clear_dummies()
			# Player chooses when to leave — show a completion panel with a
			# button instead of auto-routing back to the menu, so they can
			# linger and play with the controls they just learned.
			_show_done_panel()

# Fresh prompt with fade-in. Used when the modal isn't already showing the
# step's content (start of a step).
func _show_prompt(chip: Control, icon_id: String, action_text: String) -> void:
	for child in _chip_holder.get_children():
		child.queue_free()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_holder.add_child(chip)
	_chip_holder.custom_minimum_size.x = chip.custom_minimum_size.x
	_action_icon.set_action(icon_id)
	_action_label.text = action_text
	var t := create_tween()
	t.tween_property(_modal_root, "modulate", Color(1.0, 1.0, 1.0, 1.0), FADE_DUR)

# Inline content swap on the already-visible modal — no fade. Used for the
# ULT_SHOWING_E → ULT_SHOWING_LMB transition.
func _swap_prompt(chip: Control, icon_id: String, action_text: String) -> void:
	for child in _chip_holder.get_children():
		child.queue_free()
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_holder.add_child(chip)
	_chip_holder.custom_minimum_size.x = chip.custom_minimum_size.x
	_action_icon.set_action(icon_id)
	_action_label.text = action_text

# Lime flash on the panel + positive ping + a check-mark pop, then fade out.
# Used at every step completion so the player feels the input register before
# the next prompt.
func _complete_and_fade() -> void:
	AudioManager.play(COMPLETE_SOUND, Vector3.INF, -2.0, 1.0)
	_play_check_animation()
	var t := create_tween()
	t.tween_property(_modal_root, "modulate", COMPLETE_TINT, COMPLETE_FLASH_DUR)
	t.tween_property(_modal_root, "modulate", Color(1.0, 1.0, 1.0, 0.0), FADE_DUR)

# Big lime check, scale-punches in then fades. The pop reads as a clear
# "you did it" beat even when the panel itself fades out behind it.
func _play_check_animation() -> void:
	if _check_overlay == null:
		return
	_check_overlay.scale    = Vector2(0.4, 0.4)
	_check_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_check_overlay.set_action("check")
	var t := create_tween()
	# Pop in: bigger overshoot than before so the celebration reads.
	t.set_parallel(true)
	t.tween_property(_check_overlay, "scale", Vector2(1.35, 1.35), 0.20) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_check_overlay, "modulate:a", 1.0, 0.12)
	t.set_parallel(false)
	# Settle to 1.0 and hold longer so the player sees their accomplishment
	# while continuing to practice — pairs with the modal staying visible too.
	t.tween_property(_check_overlay, "scale", Vector2(1.0, 1.0), 0.14)
	t.tween_interval(1.10)
	# Slow shrink + fade out — drawn out so the moment lingers.
	t.set_parallel(true)
	t.tween_property(_check_overlay, "scale", Vector2(0.85, 0.85), 0.45)
	t.tween_property(_check_overlay, "modulate:a", 0.0, 0.45)

# Final "you're done" panel — replaces the prompt content with a heading and a
# button. Stays up until the player clicks; the tutorial does NOT auto-route
# back to the start screen so the player can keep practicing afterward.
func _show_done_panel() -> void:
	AudioManager.play(COMPLETE_SOUND, Vector3.INF, -2.0, 1.0)
	_play_check_animation()
	for child in _row.get_children():
		child.queue_free()
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment             = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UITheme.PAD_L)
	v.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_row.add_child(v)

	var heading := Label.new()
	heading.text = "TUTORIAL COMPLETE"
	UITheme.style_heading(heading, UITheme.FONT_HEADING_M, UITheme.COLOR_ACCENT_LIME)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(heading)

	var btn := Button.new()
	UITheme.apply_primary_button(btn, "BACK TO MENU", PROMPT_CORNER_R)
	btn.custom_minimum_size = Vector2(280.0, 56.0)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(_on_done_button_pressed)
	v.add_child(btn)

	# Flash to lime, then settle to white at full opacity (modal already visible).
	var t := create_tween()
	t.tween_property(_modal_root, "modulate", COMPLETE_TINT, COMPLETE_FLASH_DUR)
	t.tween_property(_modal_root, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.20)

func _on_done_button_pressed() -> void:
	AudioManager.play("ui_click")
	# Clear the flag first so re-entering Game.tscn from PLAY doesn't re-spawn
	# the tutorial.
	RunManager.tutorial_only = false
	var t := create_tween()
	t.tween_property(_modal_root, "modulate:a", 0.0, FADE_DUR)
	t.tween_callback(func() -> void:
		get_tree().change_scene_to_file("res://scenes/ui/StartScreen.tscn"))

# Mouse silhouette with the left button highlighted in lime — sized to match
# the WASD cluster height so the prompt row stays visually balanced.
func _make_lmb_chip() -> Control:
	var m := MouseIcon.new()
	m.highlight           = MouseIcon.Highlight.LEFT
	m.body_color          = UITheme.COLOR_TEXT_PRIMARY
	m.accent              = UITheme.COLOR_ACCENT_LIME
	m.custom_minimum_size = Vector2(56.0, KeyChip.KEY_SIZE * 2.0 + KeyChip.KEY_GAP)
	return m


# ── Per-frame ────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_state_timer += delta
	_animate_marker(delta)
	# Pause the conga line while the target weapon is aiming. The aim point is
	# in world space but practice dummies are parented to the marching mech —
	# without pausing, the row drifts out from under the player's crosshair
	# between the first click (place) and the second (fire). Tutorial-only;
	# the main game keeps moving during aim mode by design.
	RunManager.line_speed_mult = 0.0 if _target_mech_in_aim_mode() else 1.0
	# Cross-state kill-check for the showing states only — if the panel fires
	# the ult on its own range check (looser than APPROACH_RADIUS) and the
	# kills happen before our state polling catches the fire, jump straight
	# to the success path. ULT_FADING is judged on its own resolve timer
	# below so the success/fail branch is deterministic.
	if not _ult_resolving and (_state == State.ULT_SHOWING_E or _state == State.ULT_SHOWING_LMB):
		# Require the target mech's ult to actually be on cooldown before
		# accepting an empty-dummy state as success — otherwise stray fire
		# from non-target mechs can trip the shortcut without the player
		# pressing E.
		if not _dummies.is_empty() and _alive_dummy_count() == 0 and _target_mech_ult_on_cooldown():
			_resolve_ult_success()
			return
	# Poll the target mech's weapon directly — the tutorial's own E listener
	# requires drone-near-target, but the panel's E binding fires on whichever
	# mech is closest. If the player presses E while standing closer to a
	# non-target mech, the panel triggers the *wrong* mech's ult and our
	# state gate never trips. Watching the target weapon's aim/cooldown state
	# advances the tutorial whenever the target mech actually fires, no matter
	# which keystroke caused it.
	if _state == State.ULT_SHOWING_E:
		if _target_uses_aim_mode():
			if _target_mech_in_aim_mode():
				_enter_state(State.ULT_SHOWING_LMB)
				return
		elif _target_mech_ult_on_cooldown():
			_enter_state(State.ULT_FADING)
			return
	elif _state == State.ULT_SHOWING_LMB:
		# Aim-mode weapons leave is_aim_mode() once they fire (cooldown set on
		# the same call). Right-click cancels also clear is_aim_mode() but
		# don't start the cooldown — checking both fields distinguishes a
		# real fire from a bail.
		if _target_mech_ult_on_cooldown() and not _target_mech_in_aim_mode():
			_enter_state(State.ULT_FADING)
			return
	match _state:
		State.WASD_SHOWING:
			# MIN_PROMPT_TIME gate: a player who's already pressing W when this
			# state enters would otherwise satisfy the trigger on the same
			# frame and skip the prompt entirely. Player must press all four
			# directions at least once before advancing — pressing only forward
			# shouldn't end the lesson on the whole cluster. Either WASD or
			# arrow keys count for each logical direction.
			_track_wasd_seen()
			if _state_timer >= MIN_PROMPT_TIME and _wasd_all_seen():
				_enter_state(State.WASD_FADING)
		State.WASD_FADING:
			if _state_timer >= PRACTICE_DUR:
				_enter_state(State.SHIFT_SHOWING)
		State.SHIFT_SHOWING:
			if _state_timer >= MIN_PROMPT_TIME and Input.is_key_pressed(KEY_SHIFT):
				_enter_state(State.SHIFT_FADING)
		State.SHIFT_FADING:
			if _state_timer >= PRACTICE_DUR:
				_advance_to_next_ult()
		State.ULT_INTRO:
			if _state_timer >= INTRO_DUR:
				_enter_state(State.ULT_SHOWING_E)
		State.ULT_FADING:
			# Wait ULT_RESOLVE_DELAY for projectiles/splash to land, then
			# branch on success vs miss.
			if not _ult_resolving and _state_timer >= ULT_RESOLVE_DELAY:
				if _alive_dummy_count() == 0:
					_resolve_ult_success()
				else:
					_restart_current_mech()
		State.REPAIR_SHOWING:
			# Wait for the actual repair to land, not just proximity. The
			# minigame calls Mech.repair() on success, which flips _is_burning
			# off → needs_repair() returns false. The grace timer locks HP so
			# the mech can't die while the player works through the minigame.
			if _repair_mech != null and is_instance_valid(_repair_mech) \
					and _repair_mech.has_method("needs_repair") \
					and not _repair_mech.needs_repair():
				_enter_state(State.DONE)
		State.DONE:
			pass

# Tap-style inputs (E, LMB) go through events rather than per-frame polling.
# Polling can drop a quick press if it lands between frames; events fire on the
# pressed edge regardless of frame timing. The MIN_PROMPT_TIME gate still
# applies so the prompt has time to render before the input counts.
func _input(event: InputEvent) -> void:
	if _state_timer < MIN_PROMPT_TIME:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match _state:
			State.ULT_SHOWING_E:
				if event.keycode == KEY_E and _drone_near_target_mech():
					if _target_uses_aim_mode():
						_enter_state(State.ULT_SHOWING_LMB)
					else:
						_enter_state(State.ULT_FADING)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and _state == State.ULT_SHOWING_LMB:
			_enter_state(State.ULT_FADING)

# ── Target / marker ──────────────────────────────────────────────────────────

# Step the ult tour to the next valid mech. Skips dead / freed entries, and
# falls through to REPAIR once we've cycled through the whole line. Sets
# _target_mech and re-attaches the marker so the prompt has a live subject.
# Always clears the previous phase's dummies first so each lesson starts on a
# clean stage (covers SHIFT → ULT and ULT[i] → ULT[i+1] / REPAIR transitions).
# Success branch out of ULT_FADING. Plays the celebration on the still-visible
# modal, waits for it to fade out, then steps to the next mech (or REPAIR).
# _ult_resolving latches so the per-frame checks don't re-fire while the tween
# is in flight.
func _resolve_ult_success() -> void:
	_ult_resolving = true
	_complete_and_fade()
	var t := create_tween()
	t.tween_interval(COMPLETE_FLASH_DUR + FADE_DUR + 0.4)
	t.tween_callback(func() -> void:
		_ult_resolving = false
		_advance_to_next_ult())

# Miss branch out of ULT_FADING. The player fired but didn't clear the
# formation — wipe survivors, re-attach the marker, and re-enter ULT_INTRO so
# the same archetype's intro + ult prompt play again. _ult_mech_idx stays put.
func _restart_current_mech() -> void:
	_clear_dummies()
	if _target_mech == null or not is_instance_valid(_target_mech):
		_advance_to_next_ult()
		return
	_attach_marker_to(_target_mech)
	# Brief fade-out so the re-intro reads as a fresh attempt rather than an
	# abrupt content swap on the still-visible panel.
	var t := create_tween()
	t.tween_property(_modal_root, "modulate:a", 0.0, 0.20)
	t.tween_callback(func() -> void: _enter_state(State.ULT_INTRO))

func _advance_to_next_ult() -> void:
	_clear_dummies()
	while _ult_mech_idx + 1 < _mechs.size():
		_ult_mech_idx += 1
		var mech: Node3D = _mechs[_ult_mech_idx]
		if not is_instance_valid(mech):
			continue
		_target_mech = mech
		_attach_marker_to(mech)
		_enter_state(State.ULT_INTRO)
		return
	# All mechs taught — move on to repair.
	_enter_state(State.REPAIR_SHOWING)

func _target_uses_aim_mode() -> bool:
	var w := _weapon_for(_target_mech)
	return w != null and w.uses_aim_mode_ult

func _weapon_name_for(mech: Node3D) -> String:
	if mech == null or not is_instance_valid(mech):
		return ""
	var w := mech.get("weapon") as Node3D
	if w == null:
		return ""
	return String(w.weapon_name)

func _weapon_for(mech: Node3D) -> Node3D:
	if mech == null or not is_instance_valid(mech):
		return null
	return mech.get("weapon") as Node3D

func _target_mech_in_aim_mode() -> bool:
	var w := _weapon_for(_target_mech)
	return w != null and w.has_method("is_aim_mode") and w.is_aim_mode()

func _target_mech_ult_on_cooldown() -> bool:
	var w := _weapon_for(_target_mech)
	return w != null and w.has_method("is_ready") and not w.is_ready()

func _force_target_ult_ready() -> void:
	var w := _weapon_for(_target_mech)
	if w != null and w.has_method("force_ult_ready"):
		w.force_ult_ready()

func _archetype_name_for(mech: Node3D) -> String:
	return MechArchetypes.name_for(_weapon_name_for(mech))

# Two-line "this is the X mech" panel — archetype name on top, tagline below.
# Auto-advances to the ult prompt; no chip, since the player isn't pressing
# anything yet.
func _show_intro_for(mech: Node3D) -> void:
	for child in _chip_holder.get_children():
		child.queue_free()
	_chip_holder.custom_minimum_size.x = 0.0
	var weapon_name := _weapon_name_for(mech)
	var arch_name   := MechArchetypes.name_for(weapon_name)
	var tagline     := MechArchetypes.tagline_for(weapon_name).to_upper()
	_action_icon.set_action("ult")
	_action_label.text = arch_name + "\n" + tagline
	var t := create_tween()
	t.tween_property(_modal_root, "modulate", Color(1.0, 1.0, 1.0, 1.0), FADE_DUR)

func _attach_marker_to(mech: Node3D) -> void:
	_free_marker()
	if mech == null or not is_instance_valid(mech):
		return
	var marker := Node3D.new()
	var mesh := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius    = 0.0
	cone.bottom_radius = MARKER_CONE_RADIUS
	cone.height        = MARKER_CONE_HEIGHT
	mesh.mesh = cone
	var mat := StandardMaterial3D.new()
	# Unshaded so the marker holds full lime regardless of sun angle. Emission
	# is irrelevant in unshaded mode; the bright albedo carries it.
	mat.albedo_color = UITheme.COLOR_ACCENT_LIME
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.set_surface_override_material(0, mat)
	# Flip so the tapered tip points down toward the mech.
	mesh.rotation_degrees = Vector3(180.0, 0.0, 0.0)
	marker.add_child(mesh)
	marker.position = Vector3(0.0, MARKER_HEIGHT, 0.0)
	mech.add_child(marker)
	_marker = marker
	_marker_t = 0.0

func _free_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null

func _animate_marker(delta: float) -> void:
	if _marker == null or not is_instance_valid(_marker):
		return
	_marker_t += delta
	var bob := sin(_marker_t * MARKER_BOB_FREQ)
	_marker.position.y = MARKER_HEIGHT + bob * MARKER_BOB_AMP
	var s := 1.0 + bob * MARKER_PULSE_AMP
	_marker.scale = Vector3(s, s, s)

# ── Practice dummies ─────────────────────────────────────────────────────────

# Three dummies in a forward column for the SHIFT/dash step so the player
# punches through all of them with one dash. They're cosmetic now — dash no
# longer damages — so they stay standing once the player passes through.
# SHIFT_FADING clears them before the ult phase begins.
func _spawn_shift_dummies() -> void:
	if _mechs.is_empty():
		return
	var lead: Node3D = _mechs[0]
	if not is_instance_valid(lead):
		return
	var offsets := [
		Vector3(0.0, 0.0, -5.0),
		Vector3(0.0, 0.0, -7.5),
		Vector3(0.0, 0.0, -10.0),
	]
	for off in offsets:
		_spawn_dummy(lead, off)

# Per-mech formations sized to showcase each weapon's ult shape — fan for
# GUN, aura cluster for GARLIC, line for the chained beam, tight cluster for
# rocket splash. Offsets are world-space relative to the mech; parenting the
# dummy to the mech makes them carry along as the conga line marches.
func _spawn_dummies_for(mech: Node3D) -> void:
	if mech == null or not is_instance_valid(mech):
		return
	var offsets: Array[Vector3] = []
	match _weapon_name_for(mech):
		"GUN":
			offsets = [
				Vector3(-3.0, 0.0, -DUMMY_FORWARD_DIST),
				Vector3( 0.0, 0.0, -DUMMY_FORWARD_DIST),
				Vector3( 3.0, 0.0, -DUMMY_FORWARD_DIST),
			]
		"GARLIC":
			# Close in around the mech so the aura tags them; ult bursts.
			offsets = [
				Vector3(-3.0, 0.0, -3.0),
				Vector3( 3.0, 0.0, -3.0),
				Vector3( 0.0, 0.0,  3.0),
			]
		"BEAM":
			# Row off to the +X side, matching the rocket layout — aiming
			# laterally is much easier than threading enemies forward through
			# the line of mechs. Three dummies along the same Z, spaced inside
			# the 12-unit beam length so a click near the mech + a click toward
			# the row threads all three.
			offsets = [
				Vector3( 5.0, 0.0, -3.0),
				Vector3( 8.0, 0.0, -3.0),
				Vector3(11.0, 0.0, -3.0),
			]
		"ROCKET":
			# Cluster off to the +X side so the player has to clearly aim
			# laterally — earlier forward placement made the rocket appear
			# to launch from the front of the conga line and crossed the
			# other mechs on its way out.
			offsets = [
				Vector3(7.5, 0.0, -2.0),
				Vector3(7.5, 0.0,  0.0),
				Vector3(7.5, 0.0,  2.0),
				Vector3(9.0, 0.0,  0.0),
			]
		_:
			# Unknown weapon — fall back to a small single-line group so the
			# step still has something to fire at.
			offsets = [
				Vector3(-2.0, 0.0, -DUMMY_FORWARD_DIST),
				Vector3( 0.0, 0.0, -DUMMY_FORWARD_DIST),
				Vector3( 2.0, 0.0, -DUMMY_FORWARD_DIST),
			]
	for off in offsets:
		_spawn_dummy(mech, off)

# Parent the dummy to `anchor` and place it at `anchor.global_position +
# world_offset`. Godot computes the local position once, so as the anchor
# marches forward each frame the dummy travels with it and the world-space
# offset stays constant — formation reads as fixed relative to the mech.
func _spawn_dummy(anchor: Node3D, world_offset: Vector3) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	var d: Node3D = ENEMY_SCENE.instantiate()
	d.set("is_dummy", true)
	d.set("max_health", TUTORIAL_DUMMY_HP)
	anchor.add_child(d)
	d.global_position = anchor.global_position + world_offset
	_dummies.append(d)

func _clear_dummies() -> void:
	for d in _dummies:
		if is_instance_valid(d):
			d.queue_free()
	_dummies.clear()

func _alive_dummy_count() -> int:
	var n := 0
	for d in _dummies:
		if is_instance_valid(d):
			n += 1
	return n

# Force enough damage on a mech to push it below BURN_THRESHOLD so
# `needs_repair()` returns true. Without this, REPAIR_SHOWING would point at
# nothing — the calm tutorial sandbox doesn't reliably produce organic damage.
# Skips the ult target and any mech the drone is currently inside APPROACH_RADIUS
# of, so REPAIR_SHOWING can't auto-complete the moment we attach the marker.
func _force_damage_for_repair() -> Node3D:
	var pick: Node3D = null
	for m in _mechs:
		if not is_instance_valid(m):
			continue
		if m == _target_mech:
			continue
		if _drone != null and is_instance_valid(_drone) \
				and _drone.global_position.distance_to(m.global_position) <= APPROACH_RADIUS:
			continue
		pick = m
		break
	if pick == null:
		# All other mechs were filtered — fall back to any non-target mech so
		# at least the prompt has a real subject. The player will still need
		# to walk over since the proximity gate hasn't been satisfied yet.
		for m in _mechs:
			if is_instance_valid(m) and m != _target_mech:
				pick = m
				break
	if pick == null or not pick.has_method("take_damage"):
		return null
	var hp_max: float = float(pick.get("max_health"))
	pick.take_damage(hp_max * REPAIR_DAMAGE_FRACTION)
	# Keep the mech alive for the rest of the tutorial. Burn DPS routes through
	# take_damage which respects the repair-grace timer, so a long grace window
	# acts as full invulnerability — the player can read the prompt and look
	# away without the mech ticking itself dead.
	if pick.has_method("start_repair_grace"):
		pick.start_repair_grace(9999.0)
	return pick

# ── Conditions ───────────────────────────────────────────────────────────────

# Track logical directions (up/left/down/right) so a player can satisfy the
# tutorial with arrow keys, WASD, or any mix. Using string keys so dict size
# directly tracks how many directions have been touched.
func _track_wasd_seen() -> void:
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):    _wasd_seen["up"]    = true
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):  _wasd_seen["left"]  = true
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):  _wasd_seen["down"]  = true
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): _wasd_seen["right"] = true

func _wasd_all_seen() -> bool:
	return _wasd_seen.size() >= 4

# Whether the in-world MechOptionsPanel (E ult / F repair prompts) should be
# allowed to surface during this state. Off during pure-input phases so it
# doesn't compete with the tutorial prompts; on once we're teaching the
# panel-driven actions.
func _state_uses_mech_panel(s: State) -> bool:
	return s == State.ULT_SHOWING_E \
		or s == State.ULT_SHOWING_LMB \
		or s == State.ULT_FADING \
		or s == State.REPAIR_SHOWING \
		or s == State.DONE

func _set_mech_options_enabled(p_enabled: bool) -> void:
	var mo := get_parent().get_node_or_null("MechOptionsPanel")
	if mo != null and mo.has_method("set_enabled"):
		mo.set_enabled(p_enabled)

# Toggle visibility on the supporting UI Game.gd tagged for the tutorial late
# phases (ControlsLegend, UltBar). They're spawned hidden at the start of the
# tutorial and revealed once we reach ULT_INTRO.
func _set_late_ui_visible(p_visible: bool) -> void:
	for n in get_tree().get_nodes_in_group("tutorial_late_ui"):
		(n as CanvasLayer).visible = p_visible

func _drone_near_target_mech() -> bool:
	return _drone_near_mech_xz(_target_mech)

func _drone_near_repair_target() -> bool:
	return _drone_near_mech_xz(_repair_mech)

# Silence non-target mechs during the ult tour so their auto-fire can't kill
# the lesson dummies before the player demonstrates the ult. REPAIR mutes
# everyone (combat is paused; player just needs to press F). DONE unmutes.
func _apply_tutorial_mute(s: State) -> void:
	var mute_target_only: bool = s == State.ULT_INTRO \
		or s == State.ULT_SHOWING_E \
		or s == State.ULT_SHOWING_LMB \
		or s == State.ULT_FADING
	var mute_all: bool = s == State.REPAIR_SHOWING
	for mech in _mechs:
		if mech == null or not is_instance_valid(mech):
			continue
		var w := _weapon_for(mech as Node3D)
		if w == null:
			continue
		if mute_all:
			w.set("tutorial_muted", true)
		elif mute_target_only:
			w.set("tutorial_muted", mech != _target_mech)
		else:
			w.set("tutorial_muted", false)

# Match Game.gd's `_check_drone_proximity` — XZ distance only, no Y. The drone
# hovers ~2.2 units off the floor while mechs sit at y=0; including Y here
# would reject positions where E already fires the ult in-game (panel visible,
# ult fired) and the tutorial would never advance.
func _drone_near_mech_xz(mech: Node3D) -> bool:
	if _drone == null or mech == null:
		return false
	if not is_instance_valid(_drone) or not is_instance_valid(mech):
		return false
	var diff := _drone.global_position - mech.global_position
	diff.y = 0.0
	return diff.length() <= APPROACH_RADIUS
