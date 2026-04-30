extends Node

var wave:          int = 0
var gold:          int = 0
var xp:            int = 0
var level:         int = 1
var xp_to_next:    int = 10   # XP needed for next level (scales up each level)

signal wave_started(number: int)
signal gold_changed(total: int)
signal xp_changed(current: int, needed: int)
signal level_up(new_level: int)

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
		xp_to_next = 10 + (level - 1) * 5   # 10, 15, 20, 25 …
		level_up.emit(level)
		AudioManager.play("level_up")
	xp_changed.emit(xp, xp_to_next)

func reset_run() -> void:
	wave       = 0
	xp         = 0
	level      = 1
	xp_to_next = 10
