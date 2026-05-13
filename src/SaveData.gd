extends Node

# Persistent meta-progression data. Loaded once on launch; saved on every
# gold-affecting change. Single profile, JSON file in user://.
#
# Currency: gold, banked from runs (RunManager.gold) at run-end. Legacy saves
# stored this under "total_scrap" — load_from_disk migrates that key forward
# transparently on first load.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2

const STARTING_MECH_SLOTS := 4   # one mech per weapon archetype (GUN / GARLIC / BEAM / ROCKET)
const MAX_MECH_SLOTS       := 5

var total_gold:          int = 0
var unlocked_mech_slots: int = STARTING_MECH_SLOTS

# Drone upgrades — id (String) → current level (int). Absent ids count as 0.
var drone_upgrade_levels: Dictionary = {}

# Settings — persisted across runs.
var music_volume:   float = 1.0   # 0..1 linear
var sfx_volume:     float = 1.0   # 0..1 linear
var window_size:    Vector2i = Vector2i(0, 0)   # (0,0) means "leave as configured"
var fullscreen:     bool = true

signal gold_changed(total: int)
signal unlocks_changed()
signal drone_upgrades_changed()
signal settings_changed()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()
	_apply_settings()

# ── Settings ──────────────────────────────────────────────────────────────────

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	AudioManager.set_music_volume(music_volume)
	save_to_disk()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	AudioManager.set_sfx_volume(sfx_volume)
	save_to_disk()

func set_resolution(size: Vector2i, want_fullscreen: bool) -> void:
	window_size = size
	fullscreen  = want_fullscreen
	_apply_window_settings()
	save_to_disk()
	settings_changed.emit()

func _apply_settings() -> void:
	AudioManager.set_music_volume(music_volume)
	AudioManager.set_sfx_volume(sfx_volume)
	_apply_window_settings()

func _apply_window_settings() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if window_size.x > 0 and window_size.y > 0:
			DisplayServer.window_set_size(window_size)
			# Re-center after resize so the window doesn't end up off-screen.
			# Integer division is intentional — window_set_position takes a Vector2i.
			var screen := DisplayServer.screen_get_size()
			@warning_ignore("integer_division")
			var pos := (screen - window_size) / 2
			DisplayServer.window_set_position(pos)

# ── Persistence ───────────────────────────────────────────────────────────────

func save_to_disk() -> void:
	var data := {
		"version":              SAVE_VERSION,
		"total_gold":           total_gold,
		"unlocked_mech_slots":  unlocked_mech_slots,
		"drone_upgrade_levels": drone_upgrade_levels,
		"music_volume":         music_volume,
		"sfx_volume":           sfx_volume,
		"window_w":             window_size.x,
		"window_h":             window_size.y,
		"fullscreen":           fullscreen,
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
	# Migrate legacy "total_scrap" field forward when the new "total_gold" is absent.
	if data.has("total_gold"):
		total_gold = int(data["total_gold"])
	else:
		total_gold = int(data.get("total_scrap", 0))
	unlocked_mech_slots = clampi(int(data.get("unlocked_mech_slots", STARTING_MECH_SLOTS)),
		STARTING_MECH_SLOTS, MAX_MECH_SLOTS)
	var raw_levels: Variant = data.get("drone_upgrade_levels", {})
	drone_upgrade_levels = {}
	if raw_levels is Dictionary:
		for k in (raw_levels as Dictionary).keys():
			drone_upgrade_levels[String(k)] = int((raw_levels as Dictionary)[k])
	music_volume = clampf(float(data.get("music_volume", 1.0)), 0.0, 1.0)
	sfx_volume   = clampf(float(data.get("sfx_volume",   1.0)), 0.0, 1.0)
	window_size   = Vector2i(int(data.get("window_w", 0)), int(data.get("window_h", 0)))
	fullscreen    = bool(data.get("fullscreen", true))

# ── Gold ──────────────────────────────────────────────────────────────────────

# Deposit run-collected gold (RunManager.gold + run bonuses) into the meta pool.
func bank_gold(amount: int) -> void:
	if amount <= 0:
		return
	total_gold += amount
	save_to_disk()
	gold_changed.emit(total_gold)

# Wipe meta-progression (gold + mech-slot unlocks + drone upgrades). Audio/window
# settings are preferences, not progress, so they survive.
func reset_progress() -> void:
	total_gold          = 0
	unlocked_mech_slots = STARTING_MECH_SLOTS
	drone_upgrade_levels.clear()
	save_to_disk()
	gold_changed.emit(total_gold)
	unlocks_changed.emit()
	drone_upgrades_changed.emit()

func can_afford(cost: int) -> bool:
	return total_gold >= cost

func _spend(cost: int) -> bool:
	if total_gold < cost:
		return false
	total_gold -= cost
	gold_changed.emit(total_gold)
	return true

# ── Mech-slot unlocks ─────────────────────────────────────────────────────────

# Cost table for each mech slot index (0-based slot index → cost).
# Slots 0..(STARTING_MECH_SLOTS-1) are free; only later slots cost gold.
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

# ── Drone upgrades ────────────────────────────────────────────────────────────

# Catalog: each entry is { id, label, desc, costs: [int per level], max_level }.
# Effect values live in the per-upgrade getters below — keep the table here
# focused on identity + price so the UI can drive itself from this list alone.
const DRONE_UPGRADES: Array[Dictionary] = [
	{
		"id":        "drone_speed",
		"label":     "ENGINE TUNING",
		"desc":      "Drone moves faster.",
		"costs":     [30, 70, 140],
		"max_level": 3,
	},
	{
		"id":        "pickup_range",
		"label":     "MAGNET ARRAY",
		"desc":      "Bigger pickup attract radius.",
		"costs":     [30, 70, 140],
		"max_level": 3,
	},
	{
		"id":        "dash_double",
		"label":     "DASH CAPACITORS",
		"desc":      "Extra dash charges; Lv3 also speeds recharge.",
		"costs":     [60, 140, 280],
		"max_level": 3,
	},
	{
		"id":        "dash_slow",
		"label":     "STASIS BURST",
		"desc":      "Dash slows enemies it punches through.",
		"costs":     [40, 90, 180],
		"max_level": 3,
	},
	{
		"id":        "dash_bonus_loot",
		"label":     "SCAVENGER WAKE",
		"desc":      "Dash hits drop extra gold (and XP at Lv3).",
		"costs":     [40, 90, 180],
		"max_level": 3,
	},
]

func _find_drone_upgrade(id: String) -> Dictionary:
	for entry in DRONE_UPGRADES:
		if String(entry.get("id", "")) == id:
			return entry
	return {}

func drone_upgrade_level(id: String) -> int:
	return int(drone_upgrade_levels.get(id, 0))

func drone_upgrade_max_level(id: String) -> int:
	var entry := _find_drone_upgrade(id)
	if entry.is_empty():
		return 0
	return int(entry.get("max_level", 0))

func drone_upgrade_at_max(id: String) -> bool:
	return drone_upgrade_level(id) >= drone_upgrade_max_level(id)

# Cost of the NEXT level for `id`. 0 if already at max or id unknown.
func drone_upgrade_next_cost(id: String) -> int:
	var entry := _find_drone_upgrade(id)
	if entry.is_empty():
		return 0
	var lvl := drone_upgrade_level(id)
	var costs: Array = entry.get("costs", [])
	if lvl >= costs.size():
		return 0
	return int(costs[lvl])

# Returns true if the purchase happened (gold spent, level incremented).
func purchase_drone_upgrade(id: String) -> bool:
	if drone_upgrade_at_max(id):
		return false
	var cost := drone_upgrade_next_cost(id)
	if not _spend(cost):
		return false
	drone_upgrade_levels[id] = drone_upgrade_level(id) + 1
	save_to_disk()
	drone_upgrades_changed.emit()
	return true

# ── Drone upgrade effect getters ──────────────────────────────────────────────
# Read by Drone.gd / Pickup.gd. Keep the level → effect mapping here so the
# tuning curve is in one place and the consumers stay one-line.

# 1.0 / 1.10 / 1.20 / 1.30 — multiplier on Drone.SPEED.
func drone_speed_mult() -> float:
	return 1.0 + 0.10 * float(drone_upgrade_level("drone_speed"))

# 0 / 1.5 / 3.0 / 5.0 — added to Pickup.ATTRACT_RADIUS at spawn.
func attract_radius_bonus() -> float:
	match drone_upgrade_level("pickup_range"):
		1: return 1.5
		2: return 3.0
		3: return 5.0
		_: return 0.0

# 1 / 2 / 3 / 3 — concurrent dash charges available.
func dash_max_charges() -> int:
	match drone_upgrade_level("dash_double"):
		1: return 2
		2: return 3
		3: return 3
		_: return 1

# 1.0 at Lv0-2, 0.75 at Lv3 — multiplier on the charge-refill cooldown.
func dash_cooldown_mult() -> float:
	return 0.75 if drone_upgrade_level("dash_double") >= 3 else 1.0

# {} if Lv0; else { "mult": float (speed multiplier), "duration": float (seconds) }.
# mult < 1.0 = slower enemies. Apply via Enemy.apply_slow(mult, duration).
func dash_slow_data() -> Dictionary:
	match drone_upgrade_level("dash_slow"):
		1: return {"mult": 0.60, "duration": 1.5}
		2: return {"mult": 0.45, "duration": 2.0}
		3: return {"mult": 0.30, "duration": 2.5}
		_: return {}

# 0 / 1 / 2 / 3 — bonus gold spawned at the position of each enemy punched
# through by a dash.
func dash_bonus_gold() -> int:
	return drone_upgrade_level("dash_bonus_loot")

# True at Lv3 of dash_bonus_loot — a small XP gem also drops per dash hit.
func dash_bonus_xp_on_hit() -> bool:
	return drone_upgrade_level("dash_bonus_loot") >= 3
