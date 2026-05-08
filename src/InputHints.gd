extends Node

# Tracks the player's most-recently-used input device so UI can swap key caps
# for gamepad face buttons.

signal device_changed(new_device: int)

const DEVICE_KBM     := 0
const DEVICE_GAMEPAD := 1

# Filter resting-stick noise so a slightly-off-center pad at boot doesn't
# register as gamepad input.
const STICK_DEFLECTION_MIN := 0.5

var device: int = DEVICE_KBM

# Mouse-active gate for aim-mode fallbacks. Aim ults (Gun, Beam) project the
# cursor onto the ground; a player without a mouse needs a substitute (we use
# the drone's position). Counts the mouse as "active" while it's been moved
# within MOUSE_ACTIVE_WINDOW seconds.
const MOUSE_ACTIVE_WINDOW := 2.0
var _last_mouse_motion_t: float = -INF

const KBM_GLYPHS := {
	"dash":          "SHIFT",
	"ult":           "E",
	"repair":        "F",
	"rocket_strike": "R",
	"aim_confirm":   "LMB",
	"aim_cancel":    "RMB",
	"pause":         "ESC",
	"zoom_in":       "WHEEL",
	"zoom_out":      "WHEEL",
}

const GAMEPAD_GLYPHS := {
	"dash":          "A",
	"ult":           "X",
	"repair":        "Y",
	"rocket_strike": "RB",
	"aim_confirm":   "A",
	"aim_cancel":    "B",
	"pause":         "START",
	"zoom_in":       "RT",
	"zoom_out":      "LT",
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_last_mouse_motion_t = _now()
		return
	var new_device := device
	if event is InputEventKey or event is InputEventMouseButton:
		new_device = DEVICE_KBM
	elif event is InputEventJoypadButton:
		var b := event as InputEventJoypadButton
		if b.pressed:
			print("[InputHints] joypad button ", b.button_index, " device ", b.device)
		new_device = DEVICE_GAMEPAD
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) < STICK_DEFLECTION_MIN:
			return
		print("[InputHints] joypad axis ", motion.axis, " value ", motion.axis_value, " device ", motion.device)
		new_device = DEVICE_GAMEPAD
	if new_device != device:
		device = new_device
		device_changed.emit(device)

func glyph_for(action: String) -> String:
	var table: Dictionary = GAMEPAD_GLYPHS if device == DEVICE_GAMEPAD else KBM_GLYPHS
	return table.get(action, action.to_upper())

# True if the player is steering with a mouse right now (mouse moved within
# MOUSE_ACTIVE_WINDOW seconds). Aim weapons fall back to drone-tracked aim
# when this returns false, so keyboard-only and gamepad players still get a
# meaningful aim direction.
func mouse_active() -> bool:
	return _now() - _last_mouse_motion_t < MOUSE_ACTIVE_WINDOW

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
