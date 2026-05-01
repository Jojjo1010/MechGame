extends Node

var wave:          int = 0
var gold:          int = 0
var xp:            int = 0
var level:         int = 1
var xp_to_next:    int = 10   # XP needed for next level (scales up each level)

# Run-wide multipliers applied by upgrades
var line_speed_mult: float = 1.0

# Conga-combo: kills give the whole line a stacking damage buff for a short window
var combo_enabled:  bool        = false
const COMBO_MAX_STACKS  := 3
const COMBO_DURATION    := 2.0
const COMBO_PER_STACK   := 0.30
var _combo_stacks:  Array[float] = []   # remaining time per active stack

# Tracks which one-shot (unique) upgrades have been taken so they drop from the pool.
var taken_unique_upgrades: Array[String] = []

# Full record of upgrades taken this run (in pick order). The UltBar listens
# to upgrade_taken to render its inventory grid.
var taken_upgrades: Array[Dictionary] = []
signal upgrade_taken(upgrade: Dictionary)

# Per-target upgrade-slot tracking. Shape: { target_str → { upgrade_id → stack_count } }
# Drives the type-cap and stack-cap rules used by the upgrade picker.
var owned_upgrades: Dictionary = {}

# Caps — tune freely.
const MAX_TYPES_PER_TARGET := 2   # how many DISTINCT upgrade types each mech (or LINE) can carry
const MAX_STACKS_COMMON    := 3   # how many times a single common can stack within its slot

signal wave_started(number: int)
signal gold_changed(total: int)
signal xp_changed(current: int, needed: int)
signal level_up(new_level: int)
signal combo_changed(stacks: int)

func _process(delta: float) -> void:
	if _combo_stacks.is_empty():
		return
	var changed := false
	for i in range(_combo_stacks.size() - 1, -1, -1):
		_combo_stacks[i] -= delta
		if _combo_stacks[i] <= 0.0:
			_combo_stacks.remove_at(i)
			changed = true
	if changed:
		combo_changed.emit(_combo_stacks.size())

func start_wave(number: int) -> void:
	wave = number
	wave_started.emit(wave)

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

func add_xp(amount: int) -> void:
	xp += amount
	while xp >= xp_to_next:
		xp        -= xp_to_next
		level     += 1
		# Multiplicative curve: 10, 15, 21, 30, 44, 64, 92, 134 …
		xp_to_next = roundi(10.0 * pow(1.45, level - 1))
		level_up.emit(level)
		AudioManager.play("level_up")
	xp_changed.emit(xp, xp_to_next)

func record_upgrade(upgrade: Dictionary) -> void:
	taken_upgrades.append(upgrade)
	var target: String = String(upgrade.get("target", ""))
	var id: String     = String(upgrade.get("id", ""))
	if target != "" and id != "":
		if not owned_upgrades.has(target):
			owned_upgrades[target] = {}
		var bucket: Dictionary = owned_upgrades[target]
		bucket[id] = int(bucket.get(id, 0)) + 1
	upgrade_taken.emit(upgrade)

# How many stacks of `id` does `target` currently own? 0 if none.
func upgrade_stack_count(target: String, id: String) -> int:
	if not owned_upgrades.has(target):
		return 0
	return int((owned_upgrades[target] as Dictionary).get(id, 0))

# How many distinct upgrade types does `target` currently own?
func target_owned_type_count(target: String) -> int:
	if not owned_upgrades.has(target):
		return 0
	return (owned_upgrades[target] as Dictionary).size()

# Has `target` reached the type-cap?
func is_target_at_type_cap(target: String) -> bool:
	return target_owned_type_count(target) >= MAX_TYPES_PER_TARGET

func notify_kill() -> void:
	if not combo_enabled:
		return
	_combo_stacks.append(COMBO_DURATION)
	if _combo_stacks.size() > COMBO_MAX_STACKS:
		_combo_stacks.pop_front()
	# Chime escalates with stack count so the player hears the buildup
	var pitch := 1.0 + 0.18 * float(_combo_stacks.size())
	AudioManager.play("xp_collect", Vector3.INF, -8.0, pitch)
	combo_changed.emit(_combo_stacks.size())

func combo_mult() -> float:
	return 1.0 + COMBO_PER_STACK * float(_combo_stacks.size())

func reset_run() -> void:
	wave       = 0
	gold       = 0
	xp         = 0
	level      = 1
	xp_to_next = 10
	line_speed_mult = 1.0
	combo_enabled = true
	_combo_stacks.clear()
	taken_unique_upgrades.clear()
	taken_upgrades.clear()
	owned_upgrades.clear()
	gold_changed.emit(gold)
	xp_changed.emit(xp, xp_to_next)
	combo_changed.emit(0)
