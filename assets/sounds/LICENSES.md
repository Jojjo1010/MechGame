# Sound Asset Licenses

All sounds currently in this project come from **Kenney Game Assets**
(https://kenney.nl/), released under the **Creative Commons Zero (CC0 1.0
Universal)** license — public domain, no attribution required, free for
commercial use.

Kenney attribution is appreciated but not required:
> Sounds by Kenney (kenney.nl)

## Source packs

| Pack | URL |
|---|---|
| Impact Sounds | https://kenney.nl/assets/impact-sounds |
| Sci-Fi Sounds | https://kenney.nl/assets/sci-fi-sounds |
| Interface Sounds | https://kenney.nl/assets/interface-sounds |
| RPG Audio | https://kenney.nl/assets/rpg-audio |
| Digital Audio | https://kenney.nl/assets/digital-audio |
| UI Audio | https://kenney.nl/assets/ui-audio |

## File mapping (project id → source file)

### mech/
- `mech_step_01..04` ← `kenney_impact-sounds/Audio/impactWood_heavy_000..003.ogg`
- `mech_hit_01..03` ← `kenney_impact-sounds/Audio/impactMetal_medium_000..002.ogg`
- `mech_burn_ignite` ← `kenney_sci-fi-sounds/Audio/thrusterFire_000.ogg`
- `mech_burn_loop` ← `kenney_sci-fi-sounds/Audio/forceField_000.ogg` *(needs Loop import)*
- `mech_death` ← `kenney_sci-fi-sounds/Audio/lowFrequency_explosion_000.ogg`
- `mech_repair_complete` ← `kenney_digital-audio/Audio/zapThreeToneUp.ogg`
- `ult_ready` ← `kenney_digital-audio/Audio/highUp.ogg`
- `ult_fired` ← `kenney_digital-audio/Audio/phaserUp1.ogg`

### weapons/
- `gun_fire_01..03` ← `kenney_sci-fi-sounds/Audio/laserSmall_000..002.ogg`
- `gun_ult` ← `kenney_sci-fi-sounds/Audio/laserLarge_000.ogg`
- `beam_fire` ← `kenney_digital-audio/Audio/zap1.ogg`
- `beam_bounce_01..03` ← digital `zap2`, `zapTwoTone`, `zapTwoTone2`
- `garlic_pulse` ← `kenney_sci-fi-sounds/Audio/forceField_001.ogg`
- `garlic_ult` ← `kenney_sci-fi-sounds/Audio/lowFrequency_explosion_001.ogg`
- `bullet_impact_01..03` ← `kenney_impact-sounds/Audio/impactGeneric_light_000..002.ogg`

### enemies/
- `enemy_death_01..04` ← `kenney_sci-fi-sounds/Audio/explosionCrunch_000..003.ogg`
- `enemy_hit_01..03` ← `kenney_impact-sounds/Audio/impactSoft_medium_000..002.ogg`

### drone/
- `drone_hum_loop` ← `kenney_sci-fi-sounds/Audio/spaceEngineLow_000.ogg` *(needs Loop import)*
- `drone_daze` ← `kenney_interface-sounds/Audio/glitch_001.ogg`
- `drone_repair_spark_01..03` ← `kenney_digital-audio/Audio/spaceTrash1..3.ogg`

### pickups/
- `xp_collect` ← `kenney_digital-audio/Audio/pepSound1.ogg`
- `gold_collect` ← `kenney_rpg-audio/Audio/handleCoins.ogg`
- `level_up` ← `kenney_digital-audio/Audio/phaseJump3.ogg`

### ui/
- `repair_correct_1..4` ← `kenney_digital-audio/Audio/pepSound1..4.ogg`
- `repair_wrong` ← `kenney_interface-sounds/Audio/error_001.ogg`
- `ui_hover` ← `kenney_ui-audio/Audio/rollover1.ogg`
- `ui_click` ← `kenney_ui-audio/Audio/click1.ogg`
- `wave_start` ← `kenney_digital-audio/Audio/lowThreeTone.ogg`

## Music

| File | Source | License | Author |
|---|---|---|---|
| `music/bgm_main.mp3` | Pixabay (game-mode-on, ID 356552) | Pixabay Content License (royalty-free, commercial OK) | kissan4 |

## Still missing (intentional gaps)

- `ambient/wind_loop.ogg` — not in Kenney's library; grab from Freesound CC0 if wanted

## Substitutions worth upgrading later

- **mech_step**: hollow wood thunks are a placeholder. A real conga / tom hit from Freesound (search "conga hit", filter CC0) would sell the conga theme much better.
- **mech_burn_loop**: forceField is a hum, not a fire crackle. Search "fire crackle loop" on Freesound CC0.
- **drone_hum_loop**: spaceEngineLow is the right vibe but on the loud side; reduce volume_db in code or trim/loop a quieter section.
