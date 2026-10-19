# Data schemas

Every gameplay number and definition lives in `data/` as JSON and is loaded and validated once at
startup by `autoload/game_data.gd`. Validation reports **broken references** (an unknown skill,
status, effect type, behaviour, mechanic, hook or asset key) as errors; optional keys may be missing.
This file lists the schemas added for the full GDD (see `docs/DECISIONS.md` D1-D38).

## Damage types and creature types (`data/damage_types.json`)

```json
{"types": {"fire": {"name": "Fire", "color": "#ff7a2a"}, "physical": {"armor": true}, "true": {"true": true}},
 "school_default": {"melee": "physical", "ranged": "physical", "spell": "arcane"},
 "creature_types": ["undead", "demon", "beast", "construct", "humanoid", "aberration", "elemental"]}
```

- An effect's `damage_type` defaults to its skill's `damage_type`, then to `school_default[school]`.
- `physical` is reduced by armor; every other type except `true` by `magic_resist` and the target's
  `resist[type]` (minus the attacker's `magic_pen`); `true` ignores all mitigation but absorbs.

## Skills (`data/skills/<class>.json`, `data/skills/monsters.json`)

Existing keys: `id, name, icon, school, description, cooldown, cost, cast_time, anim, sfx,
threat_mult, resource_on_hit, effects`. New keys:

| Key | Meaning |
| --- | --- |
| `damage_type` | default damage type of the skill's effects |
| `element` | Mage school (fire, frost, earth, lightning, light, dark, arcane) for school-based procs and Counterspell lockouts |
| `primary_ok` | may be slotted on the primary attack (D2) |
| `passive` / `toggle` | passive: never slotted, its `mods` / `procs` apply once unlocked; toggle: slotted, switches a status on and off |
| `charges` | number of stored uses (Blink with Warpstrider) |
| `charge_time` | hold to charge, release to fire (Power Shot); numbers scale with charge; cost and cooldown are paid on the release (#54) |
| `channel` | `{duration, tick, cost_per_second, move_cancels}`: hold to channel, effects run per tick |
| `usable_if` | `{target_hp_below, status, proc}`: conditions checked at cast |
| `cost_hp_pct`, `consumes_all_resource`, `generates` | Dark Bargain, Execute, Fury on use |
| `cooldown_on_kill_reset` | the cooldown resets when the skill kills |
| `ally_target` | the skill picks an ally near the cursor / aim ray (fallback self) |

Effect objects: `{"type": <primitive>, ...}`. The list of primitives is `Combat.EFFECT_TYPES`; an
unknown type is a validation error. `on_hit`, `on_arrive`, `effects` (traps, delayed, channel ticks)
and `explode` nest effects and are validated recursively. Every `status` they name must exist.

## Status effects (`data/status_effects.json`)

`{id: {name, kind, tick, max_stacks, color, icon, debuff, flags, stats, stack_stats, damage_type,
dr_category, breaks_on_damage, cleanse, charges}}`

- `kind`: `dot`, `hot`, `stat`, `cc`, `absorb`, `mark`, `reactive`, `proc`, `transform`, `aura`.
- `flags`: behaviour switches read by code (`rooted`, `stunned`, `silenced`, `blinded`, `feared`,
  `disoriented`, `asleep`, `cc_immune`, `knockback_immune`, `untargetable`, `invulnerable`,
  `stealthed`, `revealed`, `cannot_sprint`, `invert_move`, `ink_obscure`, `damage_floor`, ...).
- `stats` apply once; `stack_stats` apply per stack (armor shred, taint, venom).
- `dr_category`: players get diminishing returns per category (`balance.status.dr`).
- `cleanse`: category for Purify / Stoneform / Survival Instinct (`poison`, `curse`, `disease`,
  `magic`, `bleed`, `enrage`, `movement`).

## Monsters and bosses (`data/monsters/*.json`, `data/bosses/*.json`)

New keys on both: `creature_type`, `biome`, `resist {type: fraction}`, `immune [types]`,
`behaviors [{"id": <script in scripts/enemies/behaviors/>, ...params}]`.
Bosses: `music`, `arena {template, objects}`, `phases[].mechanics [{"id": <script in
scripts/enemies/boss_mechanics/>, "every": s, ...params}]`.

## Floor types (`data/floor_types/*.json`)

New keys: `architecture` (generator profile), `order` (depth cycle position), `bosses [ids]`
(seeded pick, D21), `boss_music` per boss in the boss file, `floor_mechanics [{"id": <script in
scripts/dungeon/mechanics/>, ...}]`, `hazards {id: {per_room: [a, b]}}`, `vision_mult`,
`torch_radius_mult`, `light_color`, `secret_container`, `bookshelves_per_room`, `lore_origin`.

## Talent trees v3 (`data/talents/<class>.json`, #47)

```json
{"version": 3, "tier_points": 2,
 "branches": [{"id": "berserker", "name": "Berserker", "description": "..."}],
 "nodes": [{"id": "w_s_cleave", "branch": "berserker", "tier": 0, "col": 0, "type": "skill", "skill": "warrior_cleave", "starter": true},
           {"id": "w_brutal_cleave", "branch": "berserker", "tier": 1, "col": 0, "type": "passive", "max_rank": 3, "requires": ["w_s_cleave"], "mods": [...]},
           {"id": "w_s_whirlwind", "branch": "berserker", "tier": 2, "col": 0, "type": "skill", "requires": ["w_brutal_cleave"], "requires_rank": 3},
           {"id": "w_s_feral_ferocity", "branch": "berserker", "tier": 1, "col": 1, "type": "skill", "requires": ["w_s_bloodthirst"], "exclusive": "berserker_f1"},
           {"id": "w_k_butcher", "branch": "berserker", "tier": 5, "col": 1, "type": "keystone", "requires": ["w_bloodbath"], "requires_rank": 2, "branch_points": 16, "mods": [...], "procs": [...]}]}
```

- `tier` (0-5) and `col` (lane 0-3) place the node; no two nodes of a branch share a cell.
- `requires`: the node's prerequisite, one lower-tier node of the same branch (tier-0 nodes have
  none, they are the roots). `requires_rank` (default 1): the ranks the prerequisite needs.
- `exclusive`: a fork. The two nodes sharing the group are siblings of one prerequisite; learning
  one closes the other (and what grows under it) until a reset.
- A node also needs `N x tier_points` points in its branch for tier N, or its own `branch_points`
  when that is higher (the tier-5 keystones need 16).
- `type: skill` unlocks the skill (starter nodes are free and pre-learned, D1); `passive` has
  ranks; `keystone` has one rank and ends its path (nothing may require it).
- `GameData.tree_problems` checks all of this at load, including that every gate can be paid
  whichever side of each fork is taken.

## Procs (talents, keystones, passives, legendaries, statuses)

`procs: [{"event": <name>, "chance": 0-1, "icd": s, "if": {...}, "do": [effects]} | {"hook": <id>, ...}]`.
Events: `on_hit, on_crit, on_kill, on_damaged, on_block, on_dodge, on_skill_cast, on_heal,
on_low_hp, on_fatal, on_status_applied, on_floor_start, aura_tick, on_move`. `do` uses the same
effect primitives as skills. `hook` names a function in `scripts/items/legendary_affixes.gd` for
the few affixes a recipe cannot express.

## Economy and merchants

- `data/merchants.json`: Archibald's stock rules and prices, Malphas's tithe options and contract pool.
- `data/items/pact_consumables.json`: the 10 pact potions `{id: {name, cost [{stat, value}], duration, effects}}`.
- `data/elite_modifiers.json`: elite modifiers `{id: {name, color, stats, procs}}` (D10).
- `balance.json` sections `gold`, `elite`, `merchant`, `lore`, `legendary`.

## Legendaries (`data/items/legendaries.json`)

`[{"id", "name", "class", "slot", "base", "description", "stats": {...}, "armor", "dps", "affix":
"text", "procs": [...], "mods": [...], "flags": [...], "icon"}]`. Stats are level-30 values (D7).

## Lore (`data/lore_books.json`)

Generated by `tools/import_lore.py` from `.design/lore_books/*.md`:
`[{"id": "lore_001", "number": 1, "title", "origin", "biome", "classification": "standard" |
"tome" | "legendary", "effect": {"stat": "strength", "value": 2} | {"talent_points": 1,
"stat_points": 5} | {}, "effect_text", "text"}]`.
