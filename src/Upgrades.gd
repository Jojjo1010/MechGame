extends RefCounted

# Level-up upgrade catalog. An upgrade is a Dictionary:
#   { id, title, description, rarity, target, unique? }
# `target` is a weapon_name ("GUN", "GARLIC", "BEAM").
# `unique` (default false): once taken, removed from the pool for the rest of the run.
# Filtering at draw-time excludes cards whose target weapon isn't in the run, and
# unique cards already taken.

const RARITY_COMMON   := 0
const RARITY_UNCOMMON := 1
const RARITY_RARE     := 2

# Relative pick weights per rarity. Common ~70%, uncommon ~25%, rare ~5%.
const RARITY_WEIGHTS  := [70.0, 25.0, 5.0]

const ALL := [
	# ── Gun (commons) ─────────────────────────────────────────────────────────
	{id="gun_firerate",   title="Rapid Gun",      description="Gun: +25% fire rate",
	 rarity=0, target="GUN"},
	{id="gun_damage",     title="Heavy Slugs",    description="Gun: +20% damage",
	 rarity=0, target="GUN"},
	{id="gun_projectile", title="Twin Shot",      description="Gun: +1 bullet per shot",
	 rarity=0, target="GUN"},
	{id="gun_dot",        title="Incendiary",     description="Gun: bullets burn for 6 dps over 3s",
	 rarity=0, target="GUN"},
	# ── Gun (uncommons) ───────────────────────────────────────────────────────
	{id="gun_knockback",  title="Punchy Rounds",  description="Gun: bullets knock enemies back",
	 rarity=1, target="GUN", unique=true},
	{id="gun_spread",     title="Cone Burst",     description="Gun: passive fire becomes a wide 3-bullet cone",
	 rarity=1, target="GUN", unique=true},
	{id="gun_splash",     title="Explosive Rounds", description="Gun: bullets do AOE on impact",
	 rarity=1, target="GUN", unique=true},
	# ── Garlic (commons) ──────────────────────────────────────────────────────
	{id="garlic_firerate", title="Quick Pulse",   description="Garlic: +25% pulse rate",
	 rarity=0, target="GARLIC"},
	{id="garlic_damage",   title="Toxic Aura",    description="Garlic: +20% damage",
	 rarity=0, target="GARLIC"},
	{id="garlic_range",    title="Wide Aura",     description="Garlic: +20% radius",
	 rarity=0, target="GARLIC"},
	{id="garlic_dot",      title="Spore Cloud",   description="Garlic: pulses poison for 5 dps over 3s",
	 rarity=0, target="GARLIC"},
	# ── Garlic (uncommons) ────────────────────────────────────────────────────
	{id="garlic_slow",     title="Crippling Spores", description="Garlic: aura slows enemies 50% for 1.5s",
	 rarity=1, target="GARLIC", unique=true},
	# ── Beam (commons) ────────────────────────────────────────────────────────
	{id="beam_firerate",   title="Rapid Beam",    description="Beam: +25% fire rate",
	 rarity=0, target="BEAM"},
	{id="beam_damage",     title="Hot Beam",      description="Beam: +20% damage",
	 rarity=0, target="BEAM"},
	{id="beam_bounces",    title="Long Chain",    description="Beam: +1 bounce",
	 rarity=0, target="BEAM"},
	{id="beam_range",      title="Far Reach",     description="Beam: +25% bounce range",
	 rarity=0, target="BEAM"},
	# ── Beam (uncommons) ──────────────────────────────────────────────────────
	{id="beam_splash",     title="Static Discharge", description="Beam: bounces splash damage to nearby enemies",
	 rarity=1, target="BEAM", unique=true},
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
		"gun_damage":       _scale(weapons, "GUN",    "damage_mult",    1.20)
		"gun_projectile":   _add  (weapons, "GUN",    "projectile_count_bonus", 1)
		"gun_dot":          _add  (weapons, "GUN",    "dot_dps", 6.0)
		"gun_knockback":    _set_prop(weapons, "GUN",    "knockback_force", 14.0)
		"gun_spread":       _gun_cone_burst(weapons)
		"gun_splash":       _set_prop(weapons, "GUN",    "splash_radius", 2.5)
		"garlic_firerate":  _scale(weapons, "GARLIC", "fire_rate_mult", 1.25)
		"garlic_damage":    _scale(weapons, "GARLIC", "damage_mult",    1.20)
		"garlic_range":     _scale(weapons, "GARLIC", "range_mult",     1.20)
		"garlic_dot":       _add  (weapons, "GARLIC", "dot_dps", 5.0)
		"garlic_slow":      _garlic_slow(weapons)
		"beam_firerate":    _scale(weapons, "BEAM",   "fire_rate_mult", 1.25)
		"beam_damage":      _scale(weapons, "BEAM",   "damage_mult",    1.20)
		"beam_bounces":     _add  (weapons, "BEAM",   "projectile_count_bonus", 1)
		"beam_range":       _scale(weapons, "BEAM",   "range_mult",     1.25)
		"beam_splash":      _set_prop(weapons, "BEAM",   "splash_radius", 2.0)
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

static func _gun_cone_burst(weapons: Array) -> void:
	for w in weapons:
		if w != null and w.weapon_name == "GUN":
			w.passive_spread_per_bullet = 14.0
			w.projectile_count_bonus += 2

static func _garlic_slow(weapons: Array) -> void:
	for w in weapons:
		if w != null and w.weapon_name == "GARLIC":
			w.slow_mult     = 0.5
			w.slow_duration = 1.5
