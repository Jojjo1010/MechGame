extends Node

# Persistent meta-progression data. Loaded once on launch; saved on every
# scrap-affecting change. Single profile, JSON file in user://.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

const STARTING_MECH_SLOTS := 3
const MAX_MECH_SLOTS       := 5

var total_scrap:         int = 0
var unlocked_mech_slots: int = STARTING_MECH_SLOTS

signal scrap_changed(total: int)
signal unlocks_changed()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()

# ── Persistence ───────────────────────────────────────────────────────────────

func save_to_disk() -> void:
	var data := {
		"version":             SAVE_VERSION,
		"total_scrap":         total_scrap,
		"unlocked_mech_slots": unlocked_mech_slots,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveData: failed to open %s for writing" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "  "))

func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var raw := file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_warning("SaveData: malformed save file at %s" % SAVE_PATH)
		return
	var data: Dictionary = parsed
	total_scrap         = int(data.get("total_scrap", 0))
	unlocked_mech_slots = clampi(int(data.get("unlocked_mech_slots", STARTING_MECH_SLOTS)),
		STARTING_MECH_SLOTS, MAX_MECH_SLOTS)

# ── Scrap ─────────────────────────────────────────────────────────────────────

func add_scrap(amount: int) -> void:
	if amount <= 0:
		return
	total_scrap += amount
	save_to_disk()
	scrap_changed.emit(total_scrap)

func can_afford(cost: int) -> bool:
	return total_scrap >= cost

func _spend(cost: int) -> bool:
	if total_scrap < cost:
		return false
	total_scrap -= cost
	scrap_changed.emit(total_scrap)
	return true

# ── Unlocks ───────────────────────────────────────────────────────────────────

# Cost table for each mech slot index (0-based slot index → cost).
# Slots 0..(STARTING_MECH_SLOTS-1) are free; only later slots cost scrap.
const MECH_SLOT_COSTS := [0, 0, 0, 50, 120]

func mech_slot_cost(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= MECH_SLOT_COSTS.size():
		return 0
	return MECH_SLOT_COSTS[slot_index]

# Unlock the next mech slot (one past current). Returns true on success.
func unlock_next_mech_slot() -> bool:
	if unlocked_mech_slots >= MAX_MECH_SLOTS:
		return false
	var cost: int = mech_slot_cost(unlocked_mech_slots)
	if not _spend(cost):
		return false
	unlocked_mech_slots += 1
	save_to_disk()
	unlocks_changed.emit()
	return true
