# Conga Mechs — Weapons & Upgrades Reference

Auto-generated from the live source. Numbers reflect what the player actually
gets in-game. Sections are sized for FigJam stickies / text frames — paste
each block into its own node.

---

## Weapons

### GUN
- **Role:** single-target, ranged precision
- **Passive:** fires 1 bullet at the nearest enemy every **0.8 s**
- **Bullet damage:** **20** (base) × `damage_mult` × combo
- **Ult — Cone Burst (10 s cooldown):** mech enters aim mode; player picks
  direction with the mouse, click confirms. Fires **9 bullets** in a
  **50° cone** at **3× damage**, then a **second wave 0.1 s later** in the
  same direction.
- **Range:** 22 world units (× `range_mult`)

### GARLIC
- **Role:** AOE damage, crowd-control
- **Passive:** pulses every **0.65 s** in a **4.5 unit aura**, dealing
  **10 dmg** to every enemy inside.
- **Ult — Shockwave (14 s cooldown):** instant **12 unit radius** blast for
  **110 dmg** with a **38 force knockback** on every enemy hit.
- **Visualised** by a green ring on the ground around the mech.

### BEAM (Bouncy Beam)
- **Role:** chain damage, multi-target
- **Passive:** fires every **1.3 s** at the nearest enemy. Beam bounces up to
  **3 enemies**, dealing **18 dmg** per bounce.
- **Ult — Static Storm (12 s cooldown):** fires a beam that bounces **16
  times** at **2.2× damage** per bounce.
- **Bounce range:** 8 units between targets (× `range_mult`)

---

## Upgrade System

### Caps & Rules
- **Max types per mech:** 2 distinct upgrade types
- **Max stacks per common:** 3
- **Unique upgrades:** taken once, removed from pool for the rest of the run
- **Rarity weights:** Common 70 / Uncommon 25 / Rare 5

### Level-Up Flow (Hades-style)
1. XP fills → level up → time pauses
2. System rolls a random target (one mech) from those that still have
   available upgrades, with a slot-machine roll animation
3. 3 boons offered from that target's pool, weighted by rarity
4. Player picks one — no skip, no rerolls

### XP Curve
`xp_to_next = round(10 × 1.45^(level-1))`
→ `10, 15, 21, 30, 44, 64, 92, 134, …`

---

Every weapon has the same shape: 3 stat commons + 1 unique uncommon mechanic.
Every regular hit also applies a small base knockback (no upgrade required).

## Gun Upgrades

### Common
- **Rapid Gun** — +25% fire rate (stacks 3×)
- **Heavy Slugs** — +20% damage (stacks 3×)
- **Twin Shot** — +1 bullet per shot (stacks 3×)

### Uncommon (unique)
- **Explosive Rounds** — bullets do AOE on impact (2.5 unit splash, 50% dmg)

---

## Garlic Upgrades

### Common
- **Quick Pulse** — +25% pulse rate (stacks 3×)
- **Toxic Aura** — +20% damage (stacks 3×)
- **Wide Aura** — +20% radius (stacks 3×)

### Uncommon (unique)
- **Crippling Spores** — aura slows enemies 50% for 1.5s

---

## Beam Upgrades

### Common
- **Rapid Beam** — +25% fire rate (stacks 3×)
- **Hot Beam** — +20% damage (stacks 3×)
- **Long Chain** — +1 bounce (stacks 3×)

### Uncommon (unique)
- **Static Discharge** — bounces splash damage to nearby enemies (2 unit radius)

---

## Hit Effects (modifiers all weapons can stack)

| Multiplier              | What it scales                 | Applied to       |
|-------------------------|--------------------------------|------------------|
| `damage_mult`           | base hit damage                | every hit        |
| `fire_rate_mult`        | period between passive shots   | passive only     |
| `range_mult`            | search/aura/bounce range       | weapon-specific  |
| `projectile_count_bonus`| extra bullets / extra bounces  | passive + ult    |
| `dot_dps`               | damage-over-time on hit (3s)   | hits + splash    |
| `knockback_force`       | impulse on hit                 | hits             |
| `splash_radius`         | secondary AOE around hit       | hits (50% dmg)   |
| `slow_mult`             | enemy speed mult while slowed  | hits with slow   |
| `slow_duration`         | seconds slow lasts             | hits with slow   |

---

## Meta Progression (between runs)

- **Scrap** earned per run = `wave + floor(gold / 3)`
- **Mech-slot unlocks** at the Garage:
  - Slots 1–3 unlocked from start
  - **Slot 4:** 50 scrap
  - **Slot 5:** 120 scrap (must own slot 4 first)
- Save lives in `user://save.json`

---

## Drone Controls

| Key    | Action                                |
|--------|---------------------------------------|
| WASD   | Move drone                            |
| Space  | Dash (1.5 s cooldown, breaks daze)    |
| E      | Trigger ult on nearest mech in range  |
| F      | Start repair minigame on damaged mech |
| Q      | Toggle camera angle (front-right ↔ left) |
| Scroll | Zoom                                  |
