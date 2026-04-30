extends Node

# Central audio manager. Looks up sounds by string id, plays them positionally
# in 3D when given a position, or as 2D UI sound when not. Supports random
# variants — drop *_01.ogg, *_02.ogg etc. into the same folder and the
# matching id will pick one at random per play.
#
# Sounds NEVER come from code. All audio must live in assets/sounds/ as
# files sourced from royalty-free libraries (see assets/sounds/README.md).

const SOUNDS_DIR := "res://assets/sounds"

# id → category subfolder. Keep in sync with README.md.
const SOUND_MAP := {
	# mech
	"mech_step":           "mech",
	"mech_hit":            "mech",
	"mech_burn_ignite":    "mech",
	"mech_burn_loop":      "mech",
	"mech_death":          "mech",
	"mech_repair_complete":"mech",
	"ult_ready":           "mech",
	"ult_fired":           "mech",
	# weapons
	"gun_fire":            "weapons",
	"gun_ult":             "weapons",
	"beam_fire":           "weapons",
	"beam_bounce":         "weapons",
	"garlic_pulse":        "weapons",
	"garlic_ult":          "weapons",
	"bullet_impact":       "weapons",
	# enemies
	"enemy_death":         "enemies",
	"enemy_hit":           "enemies",
	# drone
	"drone_hum_loop":      "drone",
	"drone_daze":          "drone",
	"drone_repair_spark":  "drone",
	# pickups
	"xp_collect":          "pickups",
	"gold_collect":        "pickups",
	"level_up":            "pickups",
	# ui
	"repair_correct_1":    "ui",
	"repair_correct_2":    "ui",
	"repair_correct_3":    "ui",
	"repair_correct_4":    "ui",
	"repair_wrong":        "ui",
	"ui_hover":            "ui",
	"ui_click":            "ui",
	"wave_start":          "ui",
	# ambient
	"wind_loop":           "ambient",
	# music
	"bgm_main":            "music",
}

const POOL_SIZE_3D := 24
const POOL_SIZE_2D := 8

var _variants_cache: Dictionary = {}   # id → Array[AudioStream]
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _pool_2d: Array[AudioStreamPlayer]   = []
var _pool_idx_3d: int = 0
var _pool_idx_2d: int = 0
var _music_player: AudioStreamPlayer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_SIZE_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 14.0
		p.max_distance = 60.0
		add_child(p)
		_pool_3d.append(p)
	for i in POOL_SIZE_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool_2d.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Master"
	add_child(_music_player)

# ── Public API ────────────────────────────────────────────────────────────

func play(id: String, position: Vector3 = Vector3.INF, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream := _pick_variant(id)
	if stream == null:
		return
	if position == Vector3.INF:
		_play_2d(stream, volume_db, pitch)
	else:
		_play_3d(stream, position, volume_db, pitch)

# Background music: 2D, non-positional, plays once and lets the stream loop
# itself if the import is set to Loop. Calling this with a different id swaps
# tracks with a quick fade.
func play_music(id: String, volume_db: float = -10.0) -> void:
	var stream := _pick_variant(id)
	if stream == null:
		return
	if _music_player.stream == stream and _music_player.playing:
		return
	_music_player.stream    = stream
	_music_player.volume_db = volume_db
	_music_player.play()

func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()

# Loop a stream on a dedicated player parented to a node. Returns the player so
# the caller can stop/free it (e.g. when the burn ends or drone despawns).
func play_loop_on(id: String, parent: Node3D, volume_db: float = -6.0) -> AudioStreamPlayer3D:
	var stream := _pick_variant(id)
	if stream == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream      = stream
	p.unit_size   = 14.0
	p.max_distance = 60.0
	p.volume_db   = volume_db
	p.autoplay    = true
	parent.add_child(p)
	return p

# ── Internals ─────────────────────────────────────────────────────────────

func _pick_variant(id: String) -> AudioStream:
	if not SOUND_MAP.has(id):
		push_warning("AudioManager: unknown sound id '%s'" % id)
		return null
	var variants: Array = _variants_cache.get(id, [])
	if variants.is_empty():
		variants = _load_variants(id)
		_variants_cache[id] = variants
	if variants.is_empty():
		return null
	return variants[randi() % variants.size()]

# Looks for {id}.ogg / .wav, then {id}_01.. {id}_99.
func _load_variants(id: String) -> Array:
	var folder: String = SOUND_MAP[id]
	var dir_path := "%s/%s" % [SOUNDS_DIR, folder]
	var found: Array = []

	for ext in ["ogg", "wav", "mp3"]:
		var single := "%s/%s.%s" % [dir_path, id, ext]
		if ResourceLoader.exists(single):
			var s := load(single) as AudioStream
			if s != null:
				found.append(s)

	# Numbered variants
	for i in range(1, 100):
		var hit := false
		for ext in ["ogg", "wav", "mp3"]:
			var path := "%s/%s_%02d.%s" % [dir_path, id, i, ext]
			if ResourceLoader.exists(path):
				var s := load(path) as AudioStream
				if s != null:
					found.append(s)
					hit = true
		if not hit and i > 1:
			break   # stop after first gap past _01

	if found.is_empty():
		push_warning("AudioManager: no audio file found for id '%s' in %s/" % [id, dir_path])
	return found

func _play_3d(stream: AudioStream, pos: Vector3, volume_db: float, pitch: float) -> void:
	var p := _pool_3d[_pool_idx_3d]
	_pool_idx_3d = (_pool_idx_3d + 1) % POOL_SIZE_3D
	p.stream         = stream
	p.global_position = pos
	p.volume_db      = volume_db
	p.pitch_scale    = pitch
	p.play()

func _play_2d(stream: AudioStream, volume_db: float, pitch: float) -> void:
	var p := _pool_2d[_pool_idx_2d]
	_pool_idx_2d = (_pool_idx_2d + 1) % POOL_SIZE_2D
	p.stream      = stream
	p.volume_db   = volume_db
	p.pitch_scale = pitch
	p.play()
