extends Node3D

const LIFETIME   := 0.65
const RISE_SPEED := 4.5

static func spawn(amount: float, world_pos: Vector3, parent: Node,
		color: Color = Color(1.0, 0.92, 0.15)) -> void:
	var inst := Node3D.new()
	inst.set_script(load("res://scenes/ui/DamageNumber.gd"))
	parent.add_child(inst)
	inst.global_position = world_pos + Vector3(randf_range(-0.35, 0.35), 0.0, 0.0)
	inst._start(amount, color)

var _label: Label3D
var _age:   float = 0.0
var _drift: Vector3

func _start(amount: float, color: Color) -> void:
	_label = Label3D.new()
	_label.text       = str(int(amount))
	_label.font_size  = 80
	_label.modulate   = color
	_label.outline_size     = 12
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_label.billboard       = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test   = true
	_label.render_priority = 10
	add_child(_label)

	# Pop: spawn oversized, snap back fast
	_label.scale = Vector3(2.4, 2.4, 2.4)
	var tw := create_tween()
	tw.tween_property(_label, "scale", Vector3.ONE * 1.1, 0.07) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(_label, "scale", Vector3.ONE, 0.05) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# Arc drift: upward with random sideways kick
	_drift = Vector3(randf_range(-1.0, 1.0), RISE_SPEED, 0.0)

func _process(delta: float) -> void:
	_age     += delta
	position += _drift * delta
	# Slow the rise, dampen sideways
	_drift.y  = maxf(_drift.y - 4.0 * delta, 0.0)
	_drift.x *= 0.88

	if is_instance_valid(_label):
		# Stays fully opaque for first 25%, then fades quickly
		var fade := clampf((_age / LIFETIME - 0.25) / 0.75, 0.0, 1.0)
		_label.modulate.a = 1.0 - fade

	if _age >= LIFETIME:
		queue_free()
