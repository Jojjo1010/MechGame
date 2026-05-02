extends CanvasLayer

# First-run on-boarding overlay. A short stack of hint rows on the right edge
# of the screen — each row fades out the moment its action is satisfied. Once
# all four are dismissed, the player is marked "tutorialized" via SaveData
# and the overlay frees itself; Game.gd no longer spawns it on subsequent runs.
#
# Designed to be unobtrusive: rows are small, sit out of the way of mechs
# and the action, and don't block input. No modal pause, no enforced order —
# whatever the player does first, the matching hint vanishes.

const ROW_W           := 320.0
const ROW_H           := 56.0
const ROW_GAP         := 12
const PANEL_CORNER_R  := 10
const SIDE_MARGIN     := 32.0
const FADE_DUR        := 0.45

# Drone-mech proximity that counts as "approached" — must match Game.gd's
# DRONE_INTERACT_RADIUS so the dismissal lines up with when MechOptionsPanel
# would actually let the player repair.
const APPROACH_RADIUS := 5.0
const REPAIR_HP_TRIGGER := 0.60   # mech HP fraction below which the repair hint surfaces

enum HintId { WASD, SHIFT, LMB, REPAIR }

var _drone:  Node3D = null
var _mechs:  Array  = []
var _rows: Dictionary = {}        # HintId → PanelContainer
var _dismissed: Dictionary = {}   # HintId → bool

# Visibility-gating state.
var _repair_visible: bool = false
var _all_done:       bool = false

func setup(p_drone: Node3D, p_mechs: Array) -> void:
	_drone = p_drone
	_mechs = p_mechs

func _ready() -> void:
	layer = 12   # above the HUD strip, below pause / death / win modals
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build()

func _build() -> void:
	var anchor := Control.new()
	anchor.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", ROW_GAP)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchor: right edge, vertically centered in viewport.
	col.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	col.position = Vector2(-ROW_W - SIDE_MARGIN, -((ROW_H + ROW_GAP) * 2))
	anchor.add_child(col)

	_rows[HintId.WASD]   = _make_row("WASD",        "MOVE")
	_rows[HintId.SHIFT]  = _make_row("SHIFT",       "DASH")
	_rows[HintId.LMB]    = _make_row("LEFT-CLICK",  "FIRE ULT")
	_rows[HintId.REPAIR] = _make_row("APPROACH",    "REPAIR DAMAGED MECH")

	for id in [HintId.WASD, HintId.SHIFT, HintId.LMB, HintId.REPAIR]:
		var row: PanelContainer = _rows[id]
		col.add_child(row)
		# REPAIR starts hidden; surfaces when a mech first drops below the HP
		# threshold so it doesn't compete for attention before it's relevant.
		if id == HintId.REPAIR:
			row.modulate.a = 0.0

func _make_row(chip_text: String, action_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ROW_W, ROW_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color     = UITheme.COLOR_PANEL_ALPHA
	sb.border_color = UITheme.COLOR_BORDER_BRIGHT
	sb.set_border_width_all(int(UITheme.PANEL_BORDER_W))
	sb.set_corner_radius_all(PANEL_CORNER_R)
	sb.content_margin_left   = UITheme.PAD_M
	sb.content_margin_right  = UITheme.PAD_M
	sb.content_margin_top    = UITheme.PAD_S
	sb.content_margin_bottom = UITheme.PAD_S
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UITheme.PAD_M)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var chip := Label.new()
	chip.text = chip_text
	UITheme.style_label_caps(chip, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_ACCENT_LIME)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chip)

	var action := Label.new()
	action.text = action_text
	UITheme.style_label_caps(action, UITheme.FONT_LABEL_CAPS, UITheme.COLOR_TEXT_PRIMARY)
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	action.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	action.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(action)
	return panel

# ── Polling ──────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _all_done:
		return
	_check_wasd()
	_check_shift()
	_check_lmb()
	_check_repair()
	_check_done()

func _check_wasd() -> void:
	if _dismissed.get(HintId.WASD, false):
		return
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) \
			or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D):
		_dismiss(HintId.WASD)

func _check_shift() -> void:
	if _dismissed.get(HintId.SHIFT, false):
		return
	if Input.is_key_pressed(KEY_SHIFT):
		_dismiss(HintId.SHIFT)

# Ults start fully charged on wave 1 (BaseWeapon.setup), so the LMB hint is
# always actionable from frame one — no gating needed.
func _check_lmb() -> void:
	if _dismissed.get(HintId.LMB, false):
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dismiss(HintId.LMB)

func _check_repair() -> void:
	if _dismissed.get(HintId.REPAIR, false):
		return
	if not _repair_visible:
		if _any_mech_damaged():
			_repair_visible = true
			_fade_in(_rows[HintId.REPAIR])
		return
	# Dismiss when the drone closes within interact range of any damaged mech —
	# at that point MechOptionsPanel surfaces the actual REPAIR button and
	# takes over the affordance.
	if _drone == null or not is_instance_valid(_drone):
		return
	for m in _mechs:
		if not is_instance_valid(m):
			continue
		if not _mech_is_damaged(m):
			continue
		var d := _drone.global_position.distance_to(m.global_position)
		if d <= APPROACH_RADIUS:
			_dismiss(HintId.REPAIR)
			return

func _any_mech_damaged() -> bool:
	for m in _mechs:
		if _mech_is_damaged(m):
			return true
	return false

func _mech_is_damaged(m: Object) -> bool:
	if not is_instance_valid(m):
		return false
	var hp:    Variant = m.get("health")
	var hp_max: Variant = m.get("max_health")
	if hp == null or hp_max == null or float(hp_max) <= 0.0:
		return false
	return float(hp) / float(hp_max) < REPAIR_HP_TRIGGER

# ── Dismissal ────────────────────────────────────────────────────────────────

func _dismiss(id: int) -> void:
	if _dismissed.get(id, false):
		return
	_dismissed[id] = true
	var row: Control = _rows[id]
	var t := create_tween()
	t.tween_property(row, "modulate:a", 0.0, FADE_DUR)
	t.tween_callback(row.queue_free)

func _fade_in(row: Control) -> void:
	var t := create_tween()
	t.tween_property(row, "modulate:a", 1.0, FADE_DUR)

func _check_done() -> void:
	# All four prompts have been satisfied — persist the flag and self-destruct.
	for id in [HintId.WASD, HintId.SHIFT, HintId.LMB, HintId.REPAIR]:
		if not _dismissed.get(id, false):
			return
	_all_done = true
	SaveData.mark_tutorial_seen()
	# Small grace so the last fade finishes before the layer is freed.
	var t := create_tween()
	t.tween_interval(FADE_DUR + 0.1)
	t.tween_callback(queue_free)
