extends Node3D

const LIFETIME      := 0.65
const LIFETIME_CRIT := 1.10
const RISE_SPEED    := 4.5

# Hard cap on simultaneous floating numbers across the whole scene. Once we'd
# exceed this, the oldest number is freed early so the new one can spawn —
# Diablo 3-style. Without the cap, dense late-game frames pile dozens of
# numbers in the same screen patch and they blur into illegible static.
const MAX_ACTIVE := 12
static var _active: Array = []   # Array[DamageNumber] — newest at end

static func spawn(amount: float, world_pos: Vector3, parent: Node,
		color: Color = Color(1.0, 0.92, 0.15), is_crit: bool = false) -> void:
	# Filter dead refs (scene reloads, race with queue_free) so the cap doesn't
	# count phantoms.
	var alive: Array = []
	for n in _active:
		if is_instance_valid(n):
			alive.append(n)
	_active = alive
	# Evict oldest if we're at the cap. The newest hit always wins because the
	# player just fired it — old numbers fading out are less interesting.
	while _active.size() >= MAX_ACTIVE:
		var oldest = _active.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var inst := Node3D.new()
	inst.set_script(load("res://scenes/ui/DamageNumber.gd"))
	parent.add_child(inst)
	inst.global_position = world_pos + Vector3(randf_range(-0.35, 0.35), 0.0, 0.0)
	inst._start(amount, color, is_crit)
	_active.append(inst)

var _label: Label3D
var _age:   float = 0.0
var _drift: Vector3
var _lifetime: float = LIFETIME

func _start(amount: float, color: Color, is_crit: bool = false) -> void:
	_lifetime = LIFETIME_CRIT if is_crit else LIFETIME
	_label = Label3D.new()
	# Crit numbers shout: prepend a !, hike font size, fatter outline.
	_label.text       = ("%d!" % int(amount)) if is_crit else str(int(amount))
	_label.font_size  = 140 if is_crit else 80
	_label.modulate   = color
	_label.outline_size     = 18 if is_crit else 12
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	_label.billboard       = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test   = true
	_label.render_priority = 10
	add_child(_label)

	# Pop: crits punch in bigger and hold longer.
	var spawn_scale: float = 3.6 if is_crit else 2.4
	_label.scale = Vector3.ONE * spawn_scale
	var tw := create_tween()
	tw.tween_property(_label, "scale", Vector3.ONE * (1.4 if is_crit else 1.1), 0.09 if is_crit else 0.07) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(_label, "scale", Vector3.ONE * (1.15 if is_crit else 1.0), 0.06) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

	# Arc drift: upward with random sideways kick. Crits rise slower so they hang.
	_drift = Vector3(randf_range(-1.0, 1.0), RISE_SPEED * (0.7 if is_crit else 1.0), 0.0)

func _process(delta: float) -> void:
	_age     += delta
	position += _drift * delta
	# Slow the rise, dampen sideways
	_drift.y  = maxf(_drift.y - 4.0 * delta, 0.0)
	_drift.x *= 0.88

	if is_instance_valid(_label):
		# Stays fully opaque for first 25%, then fades quickly
		var fade := clampf((_age / _lifetime - 0.25) / 0.75, 0.0, 1.0)
		_label.modulate.a = 1.0 - fade

	if _age >= _lifetime:
		_active.erase(self)
		queue_free()
