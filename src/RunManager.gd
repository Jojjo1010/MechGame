extends Node

var wave: int = 0
var gold: int = 0

signal wave_started(number: int)
signal gold_changed(amount: int)

func start_wave(number: int) -> void:
	wave = number
	wave_started.emit(wave)

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)
