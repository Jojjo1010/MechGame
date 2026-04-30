# Sound Asset Licenses

All sounds in this project are CC0 (public domain) — no attribution required,
free for commercial use. Two source organizations:

- **Kenney Game Assets** (https://kenney.nl/) — CC0
- **OpenGameArt.org** — CC0 contributors (per-file attribution below, even
  though CC0 doesn't require it, because credit is nice)

Optional credit line:
> Sounds by Kenney (kenney.nl), kurt, rubberduck, AntumDeluge (opengameart.org)

## Source packs / files

### Kenney
| Pack | URL |
|---|---|
| Impact Sounds | https://kenney.nl/assets/impact-sounds |
| Sci-Fi Sounds | https://kenney.nl/assets/sci-fi-sounds |
| Interface Sounds | https://kenney.nl/assets/interface-sounds |
| RPG Audio | https://kenney.nl/assets/rpg-audio |
| UI Audio | https://kenney.nl/assets/ui-audio |
| Digital Audio *(reduced — was bleepy)* | https://kenney.nl/assets/digital-audio |

### OpenGameArt (CC0)
| Source | Author | URL |
|---|---|---|
| Gunshots (.22 Pistol, .22 Magnum, Black Powder) | kurt | https://opengameart.org/content/gunshots |
| 100 CC0 SFX (explosion, metal hits) | rubberduck | https://opengameart.org/content/100-cc0-sfx |
| Fire Crackling | AntumDeluge | https://opengameart.org/content/fire-crackling |

## File mapping (project id → source file)

### mech/
- `mech_step_01..04` ← Kenney impact `impactWood_heavy_000..003.ogg`
- `mech_hit_01..03` ← Kenney impact `impactMetal_medium_000..002.ogg`
- `mech_burn_ignite` ← Kenney sci-fi `thrusterFire_000.ogg`
- `mech_burn_loop` ← **OGA AntumDeluge `fire-1_0.ogg`** *(real fire crackle, needs Loop import)*
- `mech_death` ← **OGA rubberduck `100-CC0-SFX/explosion.ogg`**
- `mech_repair_complete` ← Kenney interface `confirmation_002.ogg`
- `ult_ready` ← Kenney interface `confirmation_001.ogg`
- `ult_fired` ← Kenney sci-fi `thrusterFire_001.ogg`

### weapons/
- `gun_fire_01..03` ← **OGA kurt `22 Pistol.wav`, `22 Magnum.wav`, `22 Pistol.wav`** *(real gunshots)*
- `gun_ult` ← **OGA kurt `Black Powder.wav`** *(big real gunshot)*
- `beam_fire` ← Kenney sci-fi `forceField_002.ogg`
- `beam_bounce_01..03` ← Kenney sci-fi `impactMetal_000..002.ogg`
- `garlic_pulse` ← Kenney sci-fi `forceField_001.ogg`
- `garlic_ult` ← **OGA rubberduck `100-CC0-SFX/explosion.ogg`**
- `bullet_impact_01..03` ← **OGA rubberduck `100-CC0-SFX/metal_01..03.ogg`**

### enemies/
- `enemy_death_01..04` ← Kenney sci-fi `explosionCrunch_000..003.ogg`
- `enemy_hit_01..03` ← Kenney impact `impactSoft_medium_000..002.ogg`

### drone/
- `drone_hum_loop` ← Kenney sci-fi `spaceEngineLow_000.ogg` *(needs Loop import)*
- `drone_daze` ← Kenney interface `glitch_001.ogg`
- `drone_repair_spark_01..03` ← Kenney digital `spaceTrash1..3.ogg`

### pickups/
- `xp_collect` ← Kenney interface `pluck_001.ogg`
- `gold_collect` ← Kenney RPG `handleCoins.ogg`
- `level_up` ← Kenney interface `confirmation_003.ogg`

### ui/
- `repair_correct_1..4` ← Kenney interface `pluck_001.ogg`, `pluck_002.ogg`, `confirmation_001.ogg`, `confirmation_002.ogg` *(ascending)*
- `repair_wrong` ← Kenney interface `error_001.ogg`
- `ui_hover` ← Kenney UI `rollover1.ogg`
- `ui_click` ← Kenney UI `click1.ogg`
- `wave_start` ← Kenney sci-fi `lowFrequency_explosion_000.ogg`

## Music

| File | Source | License | Author |
|---|---|---|---|
| `music/bgm_main.mp3` | Pixabay (game-mode-on, ID 356552) | Pixabay Content License (royalty-free, commercial OK) | kissan4 |

## Still missing (intentional gaps)

- `ambient/wind_loop.ogg` — not added; grab from Freesound CC0 if wanted

## Substitutions worth upgrading later

- **mech_step**: hollow wood thunks are a placeholder. A real conga / tom hit from Freesound (search "conga hit", filter CC0) would sell the conga theme much better.
- **drone_hum_loop**: still on the loud side; reduce volume_db in code or trim/loop a quieter section.
