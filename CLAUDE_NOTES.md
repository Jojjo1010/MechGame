# Conga Mechs — Claude Working Notes

Companion to `CLAUDE.md`. The main file is the cold-start brief (what the
project is, where files live, working preferences). This file is the
**field-experience log** — patterns that worked, traps that bit, and
shortcuts learned from working sessions. Read both before diving in.

---

## Working with the user (Harry)

### Communication

- **Discuss before implementing on design-shaped asks.** Prompts ending in
  "lets discuss" are real — they want options + tradeoffs laid out, then
  pick, then build. Skipping the discussion step has been corrected more
  than once.
- **Numeric tables read better than prose** for tuning. Before/after
  columns (HP, damage, TTK, etc.) let the user verify and push back fast.
- **Be terse on confirmations.** "push" → one-line confirm + git hash.
  "pull" → one-line confirm + delta summary. No recap, no advice unless
  asked.
- **Don't lecture after a decision.** Once they've picked an option, ship
  it. Don't re-litigate tradeoffs in the implementation message.
- **Surface logical gaps in specs upfront**, don't just implement
  literally. Example: a "consolidate pickups when > 10 spawn per kill"
  request when per-kill cap is 7 → ship a no-op. Better to flag the
  disconnect first.

### Workflow rhythm

- **Many short commits, pulled in often.** Two-dev project (Harry +
  Johanna). Long uncommitted local branches are a liability — Johanna may
  ship something overlapping. Pull → focused commit → push → repeat.
- **`git checkout HEAD -- <file>`** is the rollback friend. When an
  approach isn't working, restore known-good and apply a smaller delta
  rather than fighting through bad code.
- **Always check `git status` before commits** — `project.godot` collects
  editor-induced drift (UID renumbering, `mode.editor` toggles,
  `allow_hidpi` reordering). Revert it before staging unless you
  intentionally edited it.
- **`Game.tscn` collects similar drift** — UIDs, `unique_id=` attributes
  injected by the editor on open. Same revert-before-commit rule.

---

## Project-specific traps (the "this bit me" log)

### Rendering

- **Parse-check is not enough for visual changes.** `--headless --import`
  catches GDScript parse errors and shader compile errors, but NOT
  rendering bugs (z-fighting, depth interactions, transparency sorting).
  Run the actual game to verify visual work.
- **Inverted-hull outlines (`cull_front` + grow shader) rely on body's
  depth write** to clip the back-shell to just a rim. The moment the body
  goes alpha-blended (or `discard`s pixels without depth), the outline
  shows up as a full inside-out shell instead of a rim. Two failure modes
  hit during the dissolve work:
  - Body `TRANSPARENCY_ALPHA` + outline `depth_draw_opaque` → the outline
    occludes everything behind, including the drone you're trying to see.
  - Body `TRANSPARENCY_ALPHA` + outline `depth_draw_never` → both meshes
    write no depth, fight for color buffer order, **z-fighting flicker**.
  - Body opaque-with-`discard` + outline `depth_draw_never` → kept body
    pixels write depth, outline depth-tests against them, drone shows
    through holes. **This works.**
- **Mesh `material_override` survives FBX import quirks**, but multi-
  surface meshes might need `surface_material_override[N]` if `_override`
  doesn't propagate. Check with a debug shader (force `dissolve_amount =
  0.78` permanently and see if every surface stipples).

### Tweens

- **Property paths with `/` are fragile.** `tween_property(mat,
  "shader_parameter/dissolve_amount", ...)` looks right but Godot 4's
  NodePath parser may misroute the slash. **Use `tween_method` + an
  inline lambda calling `set_shader_parameter` directly** for shader
  uniforms.
- **`set_parallel(true)` for batched tweens.** When tweening N properties
  at once, default sequential mode runs them one after another. Either
  call `.parallel()` per tween or `set_parallel(true)` on the tween.
- **Lambda capture works in GDScript 4** for tween callbacks, but type
  annotations on captured vars sometimes confuse the inferrer. If
  `var x := y.something()` fails to infer when `y` is Variant from
  `EnemyGrid.query()`, write `var x: int = ...` explicitly.

### Performance

- **`get_nodes_in_group("enemies")` is the most common perf trap.** Every
  per-frame full-tree scan compounds with bullets and weapons firing.
  `EnemyGrid.query(pos, radius)` exists for this — use it.
- **Splash damage is the hidden multiplier.** A single bullet impact
  with splash triggers a full enemy scan via `_apply_hit`. Combined with
  Twin Shot (multiple bullets) and Cluster Munition (sub-detonations), one
  rocket can kick off 4+ scans per impact.
- **`material_override` always-on alpha-blend is fine perf-wise** even at
  full alpha=1 — Godot's renderer handles ~16 alpha-blended meshes
  trivially. Worth it to avoid render-mode swaps mid-fade.
- **Per-spawn allocation is the AOE-clear stutter source**, not draw call
  count. `BurstVFX`, pickups, damage numbers all allocate fresh per spawn
  at high enemy counts. Pool or cap the active count.

### Audio / autoloads

- **`AudioManager` not visible to standalone `--check-only` script
  loading.** `--check-only` runs without autoloads, so any script
  referencing `AudioManager.play(...)` will report "Identifier not found"
  during a parse-check. **`--import` is the right command** for
  validation — it loads the project context including autoloads.
- **`get_tree().paused = true` cascades to all `PROCESS_MODE_INHERIT`
  nodes.** Anything that needs to run during pause (pause menu, repair
  minigame, upgrade picker) needs `PROCESS_MODE_ALWAYS`. Game.gd's
  `_input` doesn't fire while paused — useful for gating ESC so the pause
  menu can't open over an existing modal.

### Input

- **Polled input over event input for held-key combos.** `Drone._process`
  polls `Input.is_key_pressed(KEY_SHIFT)` for dash because event-based
  Shift detection drops when WASD is already held (engine-level keyboard
  rollover). The dash uses an edge-detect on the polled value.
- **Arrow keys mirror WASD** (recent Johanna commit) — when adding
  movement actions, both keysets need to be checked.

---

## Architecture patterns to match

### New enemy variant

- Stamp a `bool` flag on `Enemy.gd` (`is_elite`, `is_shielded`, ...) +
  set it pre-`add_child` from `WaveSpawner`.
- Branch in `_apply_wave_scaling` for HP / scale multiplier.
- Branch in `_palette_for(wave, elite)` for distinct visual palette.
- If the variant has a unique behavior (overshield, etc.), add the runtime
  state + a public method (`is_shielded_active()`,
  `hit_radius_bonus()`) so other systems can branch off it without
  knowing internals.
- Spawn cadence in `WaveSpawner._spawn_wave` after the regular spawns
  schedule. Mutually-exclusive variants (elite vs shielded) need separate
  spawn methods.

### New HUD pill

- CanvasLayer at `layer = 5` (above gameplay UI, below pause menu / death
  screen).
- `add_to_group("tutorial_late_ui")` so the tutorial's hide-then-reveal
  flow handles it for free.
- Anchor bottom-left, stack above `UltBar` with explicit gap constants —
  see `RepairHud.gd` and `RocketStrikeHud.gd` for the layout pattern.
- Poll Game.gd for state via `has_method` checks rather than direct
  references — keeps the HUD decoupled.

### New global key (like ROCKET strike R)

- Bind in `Game._input` after the existing `KEY_ESCAPE` branch.
- `get_viewport().set_input_as_handled()` so the press doesn't bleed.
- Find target via `_find_X_weapon()` helper that filters `_weapons` array
  by `weapon_name`.
- If the action is a "press once → mark, press again → commit" flow, the
  weapon's `activate_ult()` should self-detect mode and toggle.

### Per-weapon tunable

- Add `var foo: float = 1.0` to `BaseWeapon.gd` (default = neutral
  identity).
- Override in the specific weapon's `_on_setup()`.
- Multiplier-style (`knockback_mult`) reads cleaner than gate-style
  (`disable_knockback`) — supports half / off / scaled in the same
  parameter.

---

## Specific gotchas worth re-reading

- **The picker is uniform random.** Don't entertain "bias toward mech X"
  reports without the simulation evidence. Code path in
  `UpgradePicker._show_picker`: `randi() % available_targets.size()`.
  Statistical noise on small samples (~22 picks per run, σ ≈ 2 picks per
  mech) explains every "this mech got picked too much" complaint.
- **`AudioManager.play("name")` for sound; the audio file mapping is in
  `AudioManager.gd`.** No need to invent new sound names — reuse existing
  ones with pitch + volume args (e.g. `bullet_impact` at 1.6× pitch for
  shield-break).
- **Pickups consolidate via spatial bucket** (`Pickup.queue_xp` /
  `queue_gold`). Don't call `Pickup.spawn` directly from new enemy types —
  use `queue_xp` / `queue_gold` with a value, the system handles pile
  formation.
- **DamageNumber is throttled per-enemy + globally capped at 12.** Don't
  spawn raw damage numbers for AOE secondaries / DOT — pass `false` to
  `take_damage`'s `show_number` param.

---

## Things I'd do differently

- **Run the game earlier on visual changes.** The dissolve effort took
  4 round-trips because I confidently shipped logic that compiled but
  didn't render correctly. Two of those would have been caught by
  launching the actual game on the first attempt.
- **Skip option B and go straight to option C when the discussion
  surfaces it.** I had the dither-cutout shader as the right answer in
  the initial design talk, then bounced through alpha-fade first because
  the user picked B in the table. The B → C pivot cost a session.
- **Confirm spec gaps before coding.** When the user's spec assumes a
  trigger that doesn't fire ("when > 10 spawn per kill" but the cap is
  7), ask first.
- **Default to terser responses.** When the prompt is "push", "pull", or
  a one-word answer, the response should match.
- **Don't add features the user didn't ask for.** No defensive null
  checks, no incidental cleanup, no "while I'm here" refactors. The user
  reads every diff.

---

## Quick-reference numbers (current as of last commit)

These are useful for quick balance discussions without reading the source:

| Constant | Value | File |
|---|--:|---|
| `WAVE_INTERVAL` | 12.0 s | `WaveSpawner.gd` |
| `SPAWN_SPREAD` | 4.0 s | `WaveSpawner.gd` |
| `BASE_ENEMIES` | 5 | `WaveSpawner.gd` |
| Per-wave count growth | `+ (n-1) × 2` | `WaveSpawner.gd` |
| `WIN_WAVE` | 30 | `RunManager.gd` |
| Mech `max_health` | 100.0 | `Mech.gd` |
| Enemy `max_health` (baseline) | 40.0 | `Enemy.gd` |
| Enemy `ATTACK_DAMAGE` | **6.0** (was 8.0 pre-tune) | `Enemy.gd` |
| Enemy `ATTACK_INTERVAL` | 1.0 s | `Enemy.gd` |
| `HP_PER_WAVE` | 0.014 (cap 1.40 at wave ~30) | `Enemy.gd` |
| `ELITE_HP_MULT` | 2.0 | `Enemy.gd` |
| `SHIELD_HP_MULT` | 1.4 | `Enemy.gd` |
| Drone `DASH_HIT_RADIUS` / DAMAGE / KNOCKBACK | 1.6 / 18 / 24 | `Drone.gd` |
| `BASE_KNOCKBACK` | 4.0 (× weapon `knockback_mult`) | `BaseWeapon.gd` |
| GARLIC `knockback_mult` | **0.5** | `GarlicWeapon.gd` |
| GARLIC pulse damage | 10 (×wither × damage_mult) | `GarlicWeapon.gd` |
| GARLIC ult damage | 75 (×damage_mult) | `GarlicWeapon.gd` |
| Typical 30-wave run length | ~7–9 min | derived |
| Typical picks per run (level ~10) | ~9 | derived |

---

*Last updated: 2026-05-08, after the AEGIS-knockback / enemy-attack-tuning /
30-wave timing discussion.*
