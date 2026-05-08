extends Node

# Tracks which input device the player most recently used so UI can swap
# prompts (key caps vs gamepad face buttons). Emits `device_changed` whenever
# a different device kind is detected; reads via `device` and `glyph_for(action)`.
#
# Watching _input rather than polling: the autoload sits at the top of the
# scene tree at PROCESS_MODE_ALWAYS so events route through it before any
# game/UI input handler runs. Joystick noise is filtered with a 0.5 deflection
# threshold so a slightly-off-center stick at boot doesn't register.

signal device_changed(new_device: int)

const DEVICE_KBM     := 0
const DEVICE_GAMEPAD := 1

const STICK_DEFLECTION_MIN := 0.5

var device: int = DEVICE_KBM

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
	var new_device := device
	if event is InputEventKey or event is InputEventMouseButton:
		new_device = DEVICE_KBM
	elif event is InputEventJoypadButton:
		new_device = DEVICE_GAMEPAD
	elif event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) < STICK_DEFLECTION_MIN:
			return
		new_device = DEVICE_GAMEPAD
	if new_device != device:
		device = new_device
		device_changed.emit(device)

# Short caps label for an action's primary binding on the current device.
# Falls back to the action name in caps if the action isn't registered.
func glyph_for(action: String) -> String:
	var table: Dictionary = GAMEPAD_GLYPHS if device == DEVICE_GAMEPAD else KBM_GLYPHS
	return table.get(action, action.to_upper())
