# Sound Library — Required Files

All sounds must come from royalty-free / CC0 / Creative Commons libraries.
**Never synthesize or hand-craft audio for this project.**

Drop files into the matching subfolders below, using the exact filenames listed.
The AudioManager auto-loads variants — name them `*_01.wav`, `*_02.wav`, etc. and
it will pick a random one each play.

Preferred format: **OGG Vorbis** (smaller, no licensing snags). WAV also works.

---

## mech/
- `mech_step_01.ogg` ... `mech_step_04.ogg` — conga / tom drum hit (THE signature sound)
- `mech_hit_01.ogg` ... `mech_hit_03.ogg` — metal clank when mech takes damage
- `mech_burn_ignite.ogg` — fire whoosh on ignite
- `mech_burn_loop.ogg` — looping fire crackle (set Loop in import)
- `mech_death.ogg` — heavy mechanical death thud
- `mech_repair_complete.ogg` — bright success jingle
- `ult_ready.ogg` — rising chime when ult charges
- `ult_fired.ogg` — power-up whoosh on ult cast

## weapons/
- `gun_fire_01.ogg` ... `gun_fire_03.ogg` — short pop / energy shot
- `gun_ult.ogg` — bigger multi-shot blast
- `beam_fire.ogg` — electric zap launch
- `beam_bounce_01.ogg` ... `beam_bounce_03.ogg` — short crackle on bounce
- `garlic_pulse.ogg` — soft hum tick
- `garlic_ult.ogg` — low boom + whoosh shockwave
- `bullet_impact_01.ogg` ... `bullet_impact_03.ogg` — small impact

## enemies/
- `enemy_death_01.ogg` ... `enemy_death_04.ogg` — crunch / pop variants
- `enemy_hit_01.ogg` ... `enemy_hit_03.ogg` — soft thud (optional, on damage)

## drone/
- `drone_hum_loop.ogg` — low electric whir (looping)
- `drone_daze.ogg` — electronic stutter
- `drone_repair_spark_01.ogg` ... `drone_repair_spark_03.ogg` — short welder zap

## pickups/
- `xp_collect.ogg` — crystal blip
- `gold_collect.ogg` — coin ding
- `level_up.ogg` — triumphant fanfare

## ui/
- `repair_correct_1.ogg` ... `repair_correct_4.ogg` — rising 4-note ladder (one note per step)
- `repair_wrong.ogg` — error buzz
- `ui_hover.ogg` — subtle tick
- `ui_click.ogg` — minimal click
- `wave_start.ogg` — low ominous drum

## ambient/
- `wind_loop.ogg` — quiet outdoor bed (looping)

## music/
- `bgm_main.ogg` — percussion-driven upbeat loop (looping)

---

## Where to source these (recommended)

| Need | Best source |
|---|---|
| Mech step (conga) | Freesound — search "conga hit" or "tom drum" filtered to CC0 |
| Metal clanks, UI, sci-fi | Kenney audio packs (kenney.nl) — all CC0 |
| Magic / level up / pickup | Leohpaz "RPG Essentials SFX - Free" (itch.io) |
| Explosions, fire, big hits | Sonniss GDC Bundle (sonniss.com/gameaudiogdc) |
| Music | YannZ free packs (Godot Forum) or itch.io tagged "Royalty Free" |
| Specific one-offs | Freesound.org with CC0 license filter |

## Import settings (Godot)

For looping sounds (`*_loop.ogg`, `bgm_main.ogg`, `wind_loop.ogg`):
- Select the file in FileSystem dock
- Import tab → check **Loop** → Reimport

Everything else: leave at default.
