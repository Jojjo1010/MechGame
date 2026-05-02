extends RefCounted

# Level-up upgrade catalog. An upgrade is a Dictionary:
#   { id, title, description, rarity, target, unique? }
# `target` is a weapon_name ("GUN", "GARLIC", "BEAM", "ROCKET").
# `unique` (default false): once taken, removed from the pool for the rest of the run.
# Filtering at draw-time excludes cards whose target weapon isn't in the run, and
# unique cards already taken.

const RARITY_COMMON   := 0
const RARITY_UNCOMMON := 1
const RARITY_RARE     := 2

# Relative pick weights per rarity. Common ~70%, uncommon ~25%, rare ~5%.
const RARITY_WEIGHTS  := [70.0, 25.0, 5.0]

const ALL := [
	# Each weapon has the same shape: 3 stat commons + 1 unique uncommon mechanic.
	# Descriptions don't repeat the weapon name — the card already shows it via
	# the title and archetype tint.
	# ── Gun ───────────────────────────────────────────────────────────────────
	{id="gun_firerate",   title="Rapid Gun",      description="+25% fire rate",
	 rarity=0, target="GUN"},
	{id="gun_headshot",   title="Headshot",       description="Every Nth shot crits 6× — N drops 4→3→2→1",
	 rarity=0, target="GUN"},
	{id="gun_projectile", title="Twin Shot",      description="+1 bullet per shot",
	 rarity=0, target="GUN"},
	{id="gun_splash",     title="Explosive Rounds", description="Bullets do AOE on impact",
	 rarity=1, target="GUN", unique=true},
	{id="gun_pierce",     title="Hollow Rounds",  description="Bullets pierce 2 extra enemies",
	 rarity=2, target="GUN", unique=true},
	# ── Garlic ────────────────────────────────────────────────────────────────
	{id="garlic_wither",   title="Withering",     description="Pulses on the same enemy stack damage (max 3 wither stacks)",
	 rarity=0, target="GARLIC"},
	{id="garlic_bulwark",  title="Bulwark",       description="Mechs inside the aura take less damage",
	 rarity=0, target="GARLIC"},
	{id="garlic_range",    title="Wide Aura",     description="+20% radius",
	 rarity=0, target="GARLIC"},
	{id="garlic_slow",     title="Crippling Spores", description="Aura slows enemies 70% for 2.5s",
	 rarity=1, target="GARLIC", unique=true},
	{id="garlic_sanctuary", title="Sanctuary",     description="Mechs inside the aura regen 2 HP/s",
	 rarity=2, target="GARLIC", unique=true},
	# ── Beam ──────────────────────────────────────────────────────────────────
	{id="beam_firerate",   title="Rapid Beam",    description="+25% fire rate",
	 rarity=0, target="BEAM"},
	{id="beam_damage",     title="Hot Beam",      description="+20% damage",
	 rarity=0, target="BEAM"},
	{id="beam_bounces",    title="Long Chain",    description="+1 bounce",
	 rarity=0, target="BEAM"},
	{id="beam_splash",     title="Static Discharge", description="Bounces splash damage to nearby enemies",
	 rarity=1, target="BEAM", unique=true},
	{id="beam_overcharge", title="Overcharge",     description="+50% damage, +2 bounces, +30% range",
	 rarity=2, target="BEAM", unique=true},
	# ── Rocket ────────────────────────────────────────────────────────────────
	{id="rocket_firerate", title="Quick Reload",   description="+25% fire rate",
	 rarity=0, target="ROCKET"},
	{id="rocket_radius",   title="Bigger Boom",    description="+30% splash radius",
	 rarity=0, target="ROCKET"},
	{id="rocket_damage",   title="Heavy Warhead",  description="+25% damage",
	 rarity=0, target="ROCKET"},
	{id="rocket_cluster",  title="Cluster Munition", description="Each impact spawns 3 micro-detonations around it",
	 rarity=1, target="ROCKET", unique=true},
	{id="rocket_napalm",   title="Napalm Payload", description="Impacts leave a burn zone for 4s",
	 rarity=2, target="ROCKET", unique=true},
]

# Hades-style weighted pick: draw `count` distinct upgrades from `pool`, with
# probability per item proportional to its rarity weight. Common is more likely
# than uncommon than rare.
static func pick_weighted(pool: Array, count: int) -> Array:
	var working: Array = pool.duplicate()
	var picked: Array  = []
	for i in count:
		if working.is_empty():
			break
		var total: float = 0.0
		for d in working:
			total += RARITY_WEIGHTS[int(d.rarity)]
		var roll := randf() * total
		var acc: float = 0.0
		var idx := working.size() - 1
		for j in working.size():
			acc += RARITY_WEIGHTS[int(working[j].rarity)]
			if roll <= acc:
				idx = j
				break
		picked.append(working[idx])
		working.remove_at(idx)
	return picked

# All upgrades currently available for `target`, respecting type and stack caps.
#   • requires a weapon with matching weapon_name in the run
#   • unique upgrades: hidden once taken
#   • commons: hidden when stack-count >= MAX_STACKS_COMMON
#   • new type: hidden when target is at MAX_TYPES_PER_TARGET (only existing
#     stackable types remain available)
static func available_for_target(weapons: Array, target: String) -> Array:
	var found := false
	for w in weapons:
		if w != null and w.weapon_name == target:
			found = true
			break
	if not found:
		return []

	var pool: Array = []
	var at_cap := RunManager.is_target_at_type_cap(target)
	for d in ALL:
		if String(d.target) != target:
			continue
		var id := String(d.id)
		var is_unique: bool = bool(d.get("unique", false))
		var stacks := RunManager.upgrade_stack_count(target, id)
		if is_unique and stacks > 0:
			continue   # unique already taken
		if not is_unique and stacks >= RunManager.MAX_STACKS_COMMON:
			continue   # common at max stacks
		if at_cap and stacks == 0:
			continue   # type-cap blocks new types
		pool.append(d)
	return pool

# Applies an upgrade by id and records unique flag.
static func apply(upgrade: Dictionary, weapons: Array) -> void:
	if upgrade.get("unique", false):
		RunManager.taken_unique_upgrades.append(upgrade.id)
	match upgrade.id:
		"gun_firerate":     _scale(weapons, "GUN",    "fire_rate_mult", 1.25)
		"gun_headshot":     _add  (weapons, "GUN",    "headshot_count", 1)
		"gun_projectile":   _add  (weapons, "GUN",    "projectile_count_bonus", 1)
		"gun_splash":       _set_prop(weapons, "GUN",    "splash_radius", 2.5)
		"garlic_wither":    _add  (weapons, "GARLIC", "withering_per_stack", 0.25)
		"garlic_bulwark":   _add  (weapons, "GARLIC", "bulwark_dmg_reduction", 0.25)
		"garlic_range":     _scale(weapons, "GARLIC", "range_mult",     1.20)
		"garlic_slow":      _garlic_slow(weapons)
		"beam_firerate":    _scale(weapons, "BEAM",   "fire_rate_mult", 1.25)
		"beam_damage":      _scale(weapons, "BEAM",   "damage_mult",    1.20)
		"beam_bounces":     _add  (weapons, "BEAM",   "projectile_count_bonus", 1)
		"beam_splash":      _set_prop(weapons, "BEAM",   "splash_radius", 2.0)
		"gun_pierce":       _set_prop(weapons, "GUN",    "pierce_count", 2)
		"garlic_sanctuary": _set_prop(weapons, "GARLIC", "aura_regen_per_sec", 2.0)
		"beam_overcharge":  _beam_overcharge(weapons)
		"rocket_firerate":  _scale(weapons, "ROCKET", "fire_rate_mult", 1.25)
		"rocket_radius":    _scale(weapons, "ROCKET", "splash_radius",  1.30)
		"rocket_damage":    _scale(weapons, "ROCKET", "damage_mult",    1.25)
		"rocket_cluster":   _set_prop(weapons, "ROCKET", "cluster_count", 3)
		"rocket_napalm":    _rocket_napalm(weapons)
		_:                  push_warning("Unknown upgrade id: %s" % upgrade.id)

static func _scale(weapons: Array, target: String, prop: String, factor: float) -> void:
	for w in weapons:
		if w != null and w.weapon_name == target:
			w.set(prop, w.get(prop) * factor)

static func _add(weapons: Array, target: String, prop: String, amount: Variant) -> void:
	for w in weapons:
		if w != null and w.weapon_name == target:
			w.set(prop, w.get(prop) + amount)

static func _set_prop(weapons: Array, target: String, prop: String, value: Variant) -> void:
	for w in weapons:
		if w != null and w.weapon_name == target:
			w.set(prop, value)

static func _beam_overcharge(weapons: Array) -> void:
	for w in weapons:
		if w != null and w.weapon_name == "BEAM":
			w.damage_mult *= 1.5
			w.projectile_count_bonus += 2
			w.range_mult *= 1.3

static func _garlic_slow(weapons: Array) -> void:
	for w in weapons:
		if w != null and w.weapon_name == "GARLIC":
			w.slow_mult     = 0.3
			w.slow_duration = 2.5

static func _rocket_napalm(weapons: Array) -> void:
	for w in weapons:
		if w != null and w.weapon_name == "ROCKET":
			w.napalm_burn_dps = 8.0
			w.napalm_radius   = 4.0
			w.napalm_duration = 4.0
