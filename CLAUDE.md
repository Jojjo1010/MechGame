# Conga Mechs — Claude handoff

Read this first. It's the cold-start brief for any Claude session on this repo.

## Project

**Conga Mechs** — Godot 4.6 roguelite. Solo dev. Repo: `Jojjo1010/MechGame`.

You play a drone hovering over a marching line of three mechs. The mechs auto-fire at enemies; the drone supports them by triggering ults (E), repairing damage (F), and dashing (Space). Survive waves; level up; pick upgrades.

Three weapon archetypes — one per mech in the line:

| Weapon | Archetype | Tint | Role |
|---|---|---|---|
| `GUN` | **VOLLEY** | Orange-red `#e07338` | Sustained precision fire |
| `GARLIC` | **AEGIS** | Teal-green `#3acb74` | Aura support, damage shield |
| `BEAM` | **ARC** | Electric blue `#3aa6e6` | Chained beam strikes |

Identity lives in `scenes/mechs/MechArchetypes.gd` — `name_for(weapon_name)`, `color_for(weapon_name)`, `tagline_for(weapon_name)`. Game.gd colors mechs by weapon, not line position.

## Tech

- Godot **4.6.2** (match the version exactly — different minor versions will re-import assets and shift `.uid` files).
- GDScript with strict typing.
- No `.tscn` files in `scenes/ui/` — the entire UI is hand-built in `.gd` files inside `_ready()` / `_build()`. Update the script, not a scene.
- Autoloads (in `project.godot`): `RunManager`, `AudioManager`, `SaveData`.

## Architecture

| Path | Notes |
|---|---|
| `scenes/game/Game.gd` | Top-level orchestrator: spawns mechs, drone, UI; handles waves, repair flow, run-end, camera |
| `scenes/mechs/Mech.gd` | Single mech node. Bob/walk, burn state, bulwark/sanctuary aura scan, take_damage |
| `scenes/mechs/MechArchetypes.gd` | Static lookup `weapon_name → {name, tagline, color}` |
| `scenes/mechs/weapons/BaseWeapon.gd` | All shared weapon state: damage_mult, fire_rate_mult, range_mult, projectile_count_bonus, dot_dps, knockback_force, splash_radius, slow_mult/duration, headshot_count, withering_per_stack, bulwark_dmg_reduction, **pierce_count**, **aura_regen_per_sec** |
| `scenes/mechs/weapons/{GunWeapon,GarlicWeapon,BouncyBeamWeapon}.gd` | One per archetype, extend BaseWeapon |
| `scenes/projectiles/Bullet.gd` | Bullet with pierce mechanic (Hollow Rounds upgrade) |
| `scenes/drones/Drone.gd` | Player-controlled. Dash uses **polled** Space (not event), steerable with held WASD |
| `src/RunManager.gd` | XP/level, gold, upgrade tracking, signals (`xp_changed`, `level_up`, `gold_changed`, `upgrade_taken`) |
| `src/Upgrades.gd` | Upgrade catalog (`ALL` array), weighted picker, `apply()` per-id wiring. 3 commons + 1 uncommon + 1 rare per weapon |
| `src/SaveData.gd` | Meta progression — scrap currency between runs |
| `scenes/ui/style/UITheme.gd` | **Single source of truth** for colors / fonts / spacing tokens |
| `scenes/ui/style/{ActionGlyphs,UpgradeGlyphs}.gd` | Procedural icon rendering, no image assets |
| `docs/gdd.html` | Canonical game design doc (HTML, dark-themed, on master) |

## UI design system

Marathon-inspired. Dark panels with hairline lime borders. Lime is "live/interactive". Hot pink is "selected/committed/ready" — the call-to-action. Per-mech archetype tints overlay lime as the mech-identity cue.

All tokens live in `UITheme.gd`. Reference everything from there — don't introduce magic numbers or one-off colors.

```
COLOR_PANEL_ALPHA   dark see-through panel back
COLOR_ACCENT_LIME   live / interactive
COLOR_ACCENT_HOT    selected / committed / ready (hot pink)
COLOR_ACCENT_WARN   danger / repair urgency (orange-red)
COLOR_BORDER_HAIR   1.5 px hairline borders
COLOR_BORDER_BRIGHT bright lime — active hairline
PAD_S=8 / PAD_M=16 / PAD_L=24 / PAD_XL=32   8px design system
FONT_HEADING_XL=72 / L=48 / M=32 / FONT_LABEL_CAPS=24 / FONT_BODY=16
```

Helpers: `UITheme.panel_stylebox()`, `style_heading()`, `style_label_caps()`, `style_body()`. Use them.

### UI migration status (as of 2026-05-01)

| File | State |
|---|---|
| `XPBar.gd` | Fully restyled — lime fill grows L→R, level-up flash to hot pink |
| `ControlsLegend.gd` | Fully restyled — real key caps, WASD cluster, mouse glyph, action icons |
| `DeathScreen.gd` | Fully restyled — "MECHS FALLEN" with warn-color outline, RESTART hot pink |
| `DroneHiddenHint.gd` | Fully restyled — drone glyph + "DRONE HIDDEN" caps |
| `UltBar.gd` | **Minimal token swap only** — kept the original UX (bottom strip, one slot per mech with portrait + ult charge + upgrade grid). Just colors → UITheme + archetype names |
| `UpgradePicker.gd` | **Partial token swap** — palette aliases swapped, target tints flow through `MechArchetypes.color_for()`. UX preserved (slot-machine roll + 3 cards + portraits + equipped slots). Subtitle/portrait/equipped labels still show raw weapon names — could be polished to archetype names |
| `MechOptionsPanel.gd` | **Reverted to original** — Claude's restyle made it too messy and hard to read. Untouched. Cream key chips + dark panel + connector line to mech |
| `GoldCounter.gd` | **Original, untouched** — small dark pill top-right at `Vector2(20, 88)` (clears the XPBar) |
| `RepairMinigame.gd` | Original, not yet touched |
| `HealthBar3D.gd` / `DamageNumber.gd` | World-space, different visual language — leave alone |

Pending if asked: finish UpgradePicker labels (archetype names in subtitle/portrait/equipped), GoldCounter token swap.

## Working preferences (read this — these are the patterns the user has corrected before)

- **Restyle, don't redesign.** When the user asks to update visuals, never change UX behavior. Preserve layout, structure, and interactions exactly. Only swap colors/fonts/spacing to UITheme tokens. The user has rolled back full rewrites three times this project.
- **No agent fan-outs for "redesign" tasks.** Agents over-engineer and break UX. Do small, targeted edits yourself. If you must use an agent, scope it to *one* file and instruct it explicitly: layout untouched, only token swaps.
- **Minimal scope.** A bug fix doesn't need surrounding cleanup. Don't add features the user didn't ask for. Don't add error handling for impossible cases. The user is solo and reads every diff.
- **Don't write comments narrating what the code does.** Only comment WHY (hidden constraints, non-obvious tradeoffs). Don't reference the current task.
- **Verify in Godot before reporting done.** The Godot MCP is available — use `mcp__godot__run_project` + `get_debug_output` to confirm parse/compile cleanliness. Cosmetic warnings (integer division, etc.) are usually fine; parse errors are not.
- **The user wants reversibility.** Commit to git often. When in doubt, run `git checkout HEAD -- <file>` to restore a known-good state and apply minimal swaps from there, rather than fighting through bad code.
- **"Mechs should shine"** — make mech identity visible (archetype names + tints) but never at the expense of readability. The user has rejected loud archetype-tinted UI when it made the panel feel busy.

## Recent gameplay fixes (don't undo these)

- **Drone dash** uses `Input.is_key_pressed(KEY_SPACE)` polling in `_process`, not `_input` events. Events were dropping when WASD was already held. The dash also re-reads WASD each frame so the player can steer mid-dash.
- **Gun ult** aims along a sloped vector toward `mech_pos + dir*CONE_LEN + (0, ENEMY_HIT_Y, 0)` to compensate for the muzzle being at y=2.0 vs enemies at y=0.8. Without the slope, ult bullets passed cleanly over every enemy.

## Rare upgrades — IMPLEMENTED (memory file `project_rare_upgrades.md` is now obsolete)

| ID | Title | Effect | Mechanism |
|---|---|---|---|
| `gun_pierce` | Hollow Rounds | Bullets pierce 2 extra enemies | `Bullet.gd` `_pierce_remaining` + `_hit_enemies` set |
| `garlic_sanctuary` | Sanctuary | Mechs in aura regen 2 HP/s | `Mech._update_bulwark_status` accumulates `aura_regen_per_sec` from nearby Garlic mechs |
| `beam_overcharge` | Overcharge | +50% damage, +2 bounces, +30% range | Stat-stick on `damage_mult` / `projectile_count_bonus` / `range_mult` |

Each is `rarity=2`, `unique=true`. Pick weights `[70, 25, 5]`.

## Figma workflow

- Figma is **downstream** of code. Never invent flavor, names, or numbers in Figma — pull from `src/Upgrades.gd ALL`, weapon constants, etc.
- Figma file: `3xJlWrUy817S5a3u3t36ZW` ("Conga mech"). URL: https://www.figma.com/design/3xJlWrUy817S5a3u3t36ZW/Conga-mech
- Two MCPs available *if registered locally*:
  - `figma` (read-only, npx-based) — needs the user's PAT in MCP config
  - `claude-talk-to-figma` (write, plugin bridge) — needs `bun socket` running locally + Figma plugin "Connect" + manual channel-ID paste
- If MCPs aren't set up on this machine, defer Figma work and just do the Godot side.

## Game design doc

Canonical: `docs/gdd.html` on master. Single self-contained HTML, responsive grid, dark theme. Update after meaningful gameplay changes — re-read affected source, edit the matching panel, commit. Do not invent content for sections that don't exist in code; document the gap honestly with a `<p class="gap-callout">`.

The Figma node 2:2 has an older non-auto-layout copy — it drifts. HTML is truth.

## Common commands

```bash
# Run the project headlessly to check for parse errors:
# (Use the Godot MCP — mcp__godot__run_project then get_debug_output)

# Standard git flow on this repo:
git status
git add <specific files>            # avoid `git add -A`
git commit -m "..."                 # use HEREDOC for multi-line messages
git push origin master
```

The user works on Windows with bash and the Godot MCP. No CI; commits are merged directly to master (solo dev).
