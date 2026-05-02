class_name MechArchetypes
extends RefCounted

# Static lookup: weapon_name → mech archetype identity.
# A "mech" has no per-instance identity beyond its weapon — the weapon defines
# the archetype, the archetype defines the name + tint + role + visual model.
# UI surfaces (UpgradePicker, MechOptionsPanel, DeathScreen, MechPortrait,
# MechCarousel) and Game.gd's mech-line spawn all pull from here so the
# visual identity stays consistent across the game. Change a model in one
# place — the field unit, the start-screen parade, the upgrade carousel,
# every UI portrait, and the equipped-slot art all follow.

# Per-archetype mech model. All four archetypes now have their own model.
const MODEL_GUN    := preload("res://assets/CongaGoober.fbx")
const MODEL_GARLIC := preload("res://assets/CongaGoober_Round.fbx")
const MODEL_BEAM   := preload("res://assets/CongaGoober_Triangle.fbx")
const MODEL_ROCKET := preload("res://assets/CongaGoober_Rocket.fbx")

const _DATA := {
	"GUN": {
		name    = "VOLLEY",
		tagline = "Sustained precision fire",
		color   = Color("#e07338"),   # orange-red
		model   = MODEL_GUN,
	},
	"GARLIC": {
		name    = "AEGIS",
		tagline = "Aura support, damage shield",
		color   = Color("#3acb74"),   # teal-green
		model   = MODEL_GARLIC,
	},
	"BEAM": {
		name    = "ARC",
		tagline = "Chained beam strikes",
		color   = Color("#3aa6e6"),   # electric blue
		model   = MODEL_BEAM,
	},
	"ROCKET": {
		name    = "SALVO",
		tagline = "Heavy splash ordnance",
		color   = Color("#e6a93a"),   # saffron
		model   = MODEL_ROCKET,
	},
}

# Returns the archetype dictionary for `weapon_name`, or an empty fallback if
# the weapon is unknown. Callers should treat the returned dict as read-only.
static func get_archetype(weapon_name: String) -> Dictionary:
	if _DATA.has(weapon_name):
		return _DATA[weapon_name]
	return {name = weapon_name, tagline = "", color = Color.WHITE, model = MODEL_GUN}

static func name_for(weapon_name: String) -> String:
	return get_archetype(weapon_name).get("name", weapon_name)

static func color_for(weapon_name: String) -> Color:
	return get_archetype(weapon_name).get("color", Color.WHITE)

static func tagline_for(weapon_name: String) -> String:
	return get_archetype(weapon_name).get("tagline", "")

static func model_for(weapon_name: String) -> PackedScene:
	return get_archetype(weapon_name).get("model", MODEL_GUN)
