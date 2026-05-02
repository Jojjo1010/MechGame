class_name EnemyGrid
extends RefCounted

# Coarse XZ spatial hash over the enemies group. Built lazily once per frame
# (first call from any enemy triggers the rebuild; subsequent calls in the
# same frame are no-ops). Used by Enemy._get_separation to avoid the O(N²)
# tree-wide scan that pegs the frame budget at ~60+ enemies.

# 2.5 strikes a balance: small radii (bullet 0.8u, separation 1.3u) still hit a
# 3×3 cell window, but Gun's 22u shoot range scans 19×19 = 361 cells instead of
# the 31×31 = 961 the previous 1.5u cell size required. Net ~62% fewer dict
# lookups per long-range query, and per-cell candidate counts stay manageable.
const CELL_SIZE := 2.5

static var _cells:      Dictionary = {}      # Vector2i → Array[Node3D]
static var _last_frame: int = -1

# Refresh the grid if we haven't yet this frame. Cheap when already fresh.
static func ensure_fresh(scene_tree: SceneTree) -> void:
	var f := Engine.get_process_frames()
	if _last_frame == f:
		return
	_last_frame = f
	_cells.clear()
	for e in scene_tree.get_nodes_in_group("enemies"):
		var n := e as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var key := _key(n.global_position)
		if not _cells.has(key):
			_cells[key] = []
		_cells[key].append(n)

# Returns the enemies whose cells overlap a square of side 2*radius around pos.
# Caller still needs to filter by precise distance; this just shrinks the
# candidate set from "every enemy" to "enemies near pos".
static func query(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var span := int(ceilf(radius / CELL_SIZE))
	var cx := int(floor(pos.x / CELL_SIZE))
	var cz := int(floor(pos.z / CELL_SIZE))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if _cells.has(key):
				for e in _cells[key]:
					out.append(e)
	return out

static func _key(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL_SIZE)), int(floor(p.z / CELL_SIZE)))
