extends Node

var wave:          int = 0
var gold:          int = 0
var xp:            int = 0
var level:         int = 1
var xp_to_next:    int = 10   # XP needed for next level (scales up each level)

# Run-wide multipliers applied by upgrades
var line_speed_mult: float = 1.0

# Set true when the player launches Game.tscn from HOW TO PLAY (tutorial-only
# mode). Game.gd uses it to spawn TutorialPrompts; TutorialPrompts uses it to
# change scene back to StartScreen on DONE instead of dropping into a normal
# wave loop. Transient — not reset by reset_run() since that runs in Game._ready
# *after* the flag is consumed.
var tutorial_only: bool = false

# (Combo system removed in playtest — see git history for the prior wiring.)

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

# Wave the player needs to survive to win the run. WaveSpawner stops spawning
# after this and emits run_won once the final wave is cleared.
const WIN_WAVE := 30

signal wave_started(number: int)
signal gold_changed(total: int)
signal xp_changed(current: int, needed: int)
signal level_up(new_level: int)
signal run_won()

func start_wave(number: int) -> void:
	wave = number
	wave_started.emit(wave)

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

func add_xp(amount: int) -> void:
	# HOW TO PLAY runs the tutorial in a calm sandbox; suppress XP so the
	# UpgradePicker can't fire mid-tutorial — the player hasn't been taught
	# what an upgrade is yet.
	if tutorial_only:
		return
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
	pass   # combo system removed; hook kept so call-sites in Enemy.gd don't break

# Tiny indirection so the run_won signal isn't flagged "unused" by the static
# analyzer — WaveSpawner emits via this helper instead of touching .emit directly.
func emit_run_won() -> void:
	run_won.emit()

func reset_run() -> void:
	wave       = 0
	gold       = 0
	xp         = 0
	level      = 1
	xp_to_next = 10
	line_speed_mult = 1.0
	taken_unique_upgrades.clear()
	taken_upgrades.clear()
	owned_upgrades.clear()
	gold_changed.emit(gold)
	xp_changed.emit(xp, xp_to_next)
