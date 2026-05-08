extends Node

# Per-user custom input bindings on top of project.godot defaults. Each
# rebindable action gets one optional "user binding" appended to its InputMap
# events — defaults stay intact, so a custom binding adds an alternate without
# breaking standard controllers.
#
# Persistence: user://controls.cfg via ConfigFile.

const SAVE_PATH := "user://controls.cfg"

const REBINDABLE := [
	"ult", "repair", "dash", "rocket_strike",
	"aim_confirm", "aim_cancel", "pause",
]

const ACTION_LABELS := {
	"ult":           "ULT",
	"repair":        "REPAIR",
	"dash":          "DASH",
	"rocket_strike": "ROCKET STRIKE",
	"aim_confirm":   "AIM CONFIRM",
	"aim_cancel":    "AIM CANCEL",
	"pause":         "PAUSE",
}

signal bindings_changed

var _user_event: Dictionary = {}  # action -> InputEvent (or absent)

func _ready() -> void:
	_load()
	_apply_all()

func _apply_all() -> void:
	for action: String in REBINDABLE:
		var event: InputEvent = _user_event.get(action)
		if event != null and not _action_has_event(action, event):
			InputMap.action_add_event(action, event)

func set_user_binding(action: String, event: InputEvent) -> void:
	if not action in REBINDABLE:
		return
	clear_user_binding(action)
	if event == null:
		return
	_user_event[action] = event
	if not _action_has_event(action, event):
		InputMap.action_add_event(action, event)
	_save()
	bindings_changed.emit()

func clear_user_binding(action: String) -> void:
	if not _user_event.has(action):
		return
	var prev: InputEvent = _user_event[action]
	for existing in InputMap.action_get_events(action):
		if _events_match(existing, prev):
			InputMap.action_erase_event(action, existing)
			break
	_user_event.erase(action)
	_save()
	bindings_changed.emit()

func reset_all() -> void:
	for action: String in REBINDABLE:
		clear_user_binding(action)

func user_binding(action: String) -> InputEvent:
	return _user_event.get(action)

func _action_has_event(action: String, event: InputEvent) -> bool:
	for existing in InputMap.action_get_events(action):
		if _events_match(existing, event):
			return true
	return false

static func _events_match(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		var a_code := ka.keycode if ka.keycode != 0 else ka.physical_keycode
		var b_code := kb.keycode if kb.keycode != 0 else kb.physical_keycode
		return a_code == b_code
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false

# Stored as "key:<keycode>:<physical>" / "joybtn:<idx>" / "mousebtn:<idx>".
static func _serialize(event: InputEvent) -> String:
	if event is InputEventKey:
		var k := event as InputEventKey
		return "key:%d:%d" % [k.keycode, k.physical_keycode]
	if event is InputEventJoypadButton:
		return "joybtn:%d" % (event as InputEventJoypadButton).button_index
	if event is InputEventMouseButton:
		return "mousebtn:%d" % (event as InputEventMouseButton).button_index
	return ""

static func _deserialize(s: String) -> InputEvent:
	var parts := s.split(":")
	if parts.size() < 2:
		return null
	match parts[0]:
		"key":
			if parts.size() < 3:
				return null
			var k := InputEventKey.new()
			k.keycode = int(parts[1]) as Key
			k.physical_keycode = int(parts[2]) as Key
			return k
		"joybtn":
			var b := InputEventJoypadButton.new()
			b.button_index = int(parts[1]) as JoyButton
			b.pressure = 1.0
			return b
		"mousebtn":
			var m := InputEventMouseButton.new()
			m.button_index = int(parts[1]) as MouseButton
			return m
	return null

func _save() -> void:
	var cfg := ConfigFile.new()
	for action: String in _user_event.keys():
		var s := _serialize(_user_event[action])
		if s != "":
			cfg.set_value("bindings", action, s)
	cfg.save(SAVE_PATH)

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if not cfg.has_section("bindings"):
		return
	for action in cfg.get_section_keys("bindings"):
		var s: String = cfg.get_value("bindings", action, "")
		var event := _deserialize(s)
		if event != null:
			_user_event[action] = event

# Human-readable label for a binding chip.
func event_label(event: InputEvent) -> String:
	if event == null:
		return "—"
	if event is InputEventKey:
		var k := event as InputEventKey
		var kc := k.keycode if k.keycode != 0 else k.physical_keycode
		if kc == 0:
			return "?"
		return OS.get_keycode_string(kc).to_upper()
	if event is InputEventJoypadButton:
		var idx := (event as InputEventJoypadButton).button_index
		return _GAMEPAD_NAMES.get(idx, "BTN %d" % idx)
	if event is InputEventMouseButton:
		var mi := (event as InputEventMouseButton).button_index
		return _MOUSE_NAMES.get(mi, "MB %d" % mi)
	return "?"

const _GAMEPAD_NAMES := {
	0: "A", 1: "B", 2: "X", 3: "Y",
	4: "BACK", 5: "GUIDE", 6: "START",
	7: "LS", 8: "RS",
	9: "LB", 10: "RB",
	11: "D-UP", 12: "D-DOWN", 13: "D-LEFT", 14: "D-RIGHT",
}

const _MOUSE_NAMES := {
	1: "LMB", 2: "RMB", 3: "MMB",
	4: "WHEEL UP", 5: "WHEEL DOWN",
}
