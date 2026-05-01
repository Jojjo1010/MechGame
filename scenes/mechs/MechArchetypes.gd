class_name MechArchetypes
extends RefCounted

# Static lookup: weapon_name → mech archetype identity.
# A "mech" has no per-instance identity beyond its weapon — the weapon defines
# the archetype, the archetype defines the name + tint + role.
# UI surfaces (UpgradePicker, MechOptionsPanel, DeathScreen) pull from here so
# the visual identity stays consistent across the game.

const _DATA := {
	"GUN": {
		name    = "VOLLEY",
		tagline = "Sustained precision fire",
		color   = Color("#b35a2c"),   # rust-orange
	},
	"GARLIC": {
		name    = "AEGIS",
		tagline = "Aura support, damage shield",
		color   = Color("#2ea25d"),   # emerald
	},
	"BEAM": {
		name    = "ARC",
		tagline = "Chained beam strikes",
		color   = Color("#2e85b8"),   # azure
	},
	"ROCKET": {
		name    = "SALVO",
		tagline = "Heavy splash ordnance",
		color   = Color("#b8872e"),   # bronze-saffron
	},
}

# Returns the archetype dictionary for `weapon_name`, or an empty fallback if
# the weapon is unknown. Callers should treat the returned dict as read-only.
static func get_archetype(weapon_name: String) -> Dictionary:
	if _DATA.has(weapon_name):
		return _DATA[weapon_name]
	return {name = weapon_name, tagline = "", color = Color.WHITE}

static func name_for(weapon_name: String) -> String:
	return get_archetype(weapon_name).get("name", weapon_name)

static func color_for(weapon_name: String) -> Color:
	return get_archetype(weapon_name).get("color", Color.WHITE)

static func tagline_for(weapon_name: String) -> String:
	return get_archetype(weapon_name).get("tagline", "")
