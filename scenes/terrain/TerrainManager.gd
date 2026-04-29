extends Node3D

const CHUNK_SIZE  := 24.0
const VIEW_RADIUS := 3

var _chunks: Dictionary = {}  # Vector2i -> Node3D

func _process(_delta: float) -> void:
	var center := _mech_center()
	var cx := int(floor(center.x / CHUNK_SIZE))
	var cz := int(floor(center.z / CHUNK_SIZE))
	_load_around(cx, cz)
	_cull_distant(cx, cz)

func _mech_center() -> Vector3:
	var mechs := get_tree().get_nodes_in_group("mechs")
	if mechs.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for m in mechs:
		c += m.global_position
	return c / mechs.size()

func _load_around(cx: int, cz: int) -> void:
	for dx in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
		for dz in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if _chunks.has(key):
				continue
			var chunk_script := load("res://scenes/terrain/TerrainChunk.gd")
			var chunk: Node3D = Node3D.new()
			chunk.set_script(chunk_script)
			add_child(chunk)
			chunk.build(key.x, key.y)
			_chunks[key] = chunk

func _cull_distant(cx: int, cz: int) -> void:
	var to_remove: Array[Vector2i] = []
	for key: Vector2i in _chunks:
		if abs(key.x - cx) > VIEW_RADIUS + 1 or abs(key.y - cz) > VIEW_RADIUS + 1:
			to_remove.append(key)
	for key in to_remove:
		_chunks[key].queue_free()
		_chunks.erase(key)
