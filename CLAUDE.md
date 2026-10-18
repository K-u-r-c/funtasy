# CLAUDE.md — Dark Fantasy Co-op Dungeon Crawler

## What this project is

A multiplayer (co-op, 1–4 players) 2D dungeon crawler in a dark fantasy pixel art style, with a light 3/4 view (top-down with a touch of perspective). Infinite procedurally generated dungeon, a boss at the end of every floor, shared random loot, talent trees, and 4 character classes.

Current phase goal: **full Game Design Document** — the MVP loop (menu → lobby → dungeon → combat → loot → boss → next floor) is done; the game now grows to everything in the GDD (`.design/GAME_DESIGN_DOCUMENT.md`, a local, git-ignored workspace together with `.design/IMPLEMENTATION_PLAN.md` and `.design/lore_books/`). The GDD is the source of truth for content and numbers; its gaps and contradictions are resolved in `docs/DECISIONS.md` (D1–D38). Work follows the plan's phases 0–10 (`docs/TODO.md`).

## Language

- **The game is in English and Polish** (#32): English is the source language of every in-game text (UI, menus, item names, skills, talents, tooltips, enemy names, lore); a language option switches to Polish. Every player-facing string goes through the translation system (`Loc.t` / `tr()`, keys = the English source text); Polish lives **only** in the translation data (`data/i18n/translations.csv`).
- **All other files are in English**: code, comments, identifiers, docs (`README.md`, `docs/*`), commit messages, data files.
- Claude talks to the user in Polish in chat, but never writes Polish into the project outside the translation data.

## Stack and tools

- Engine: **Godot 4.x** (latest stable 4.x), language: **GDScript** (typed: `var hp: int = 0`, return types on functions).
- Platforms: **Windows, Linux, macOS**. **Gamepad support from the start** (not an afterthought).
- Art: pixel art generated externally in **Pixellab AI**; music/SFX in **Suno AI**. Claude does **not** generate these assets — it uses placeholders (colored shapes, simple sprites, silent audio files) and keeps asset paths in one place so swapping files requires no code changes.
- Networking: Godot **High-Level Multiplayer API**, **host-authoritative** model. Transports:
  - **LAN** (ENet, IP + port),
  - **Steam** (GodotSteam addon + `SteamMultiplayerPeer`). For testing use the Steam test app id (480 / Spacewar) and Steam lobbies.
  - The transport layer is **swappable** (`NetworkManager` hides ENet vs Steam; the rest of the game only uses Godot's multiplayer API).
  - Optional headless dedicated server from the same project (out of scope).
- Version control: git; small, descriptive commits; one commit = one logical change.

## Visual rules

- Style: pixel art, dark fantasy (muted palette, high-contrast lighting, deep shadows) **combined with modern effects** (glow, particles, shaders, bloom, restrained screen shake).
- Characters: **64x64 px** sprites, **8 directions** (animations: idle, walk, attack, cast, dash, hit, downed, death, ghost).
- Perspective: **light 3/4 view**. Y-sorting, collisions at the characters' feet.
- **Dynamic lighting**: `PointLight2D` / `DirectionalLight2D`, torches, lava light, item glow as real light, shadows (`LightOccluder2D`). Use normal maps where sensible (Pixellab can generate them).
- Project settings: texture filter **Nearest**, pixel snap on, stretch mode `canvas_items`, aspect `expand` (1:1 to 32:9, see `docs/DECISIONS.md`) — no pixel blurring.
- Camera follows the local player.

## Visibility and fog of war

- **Fog of war**: a player only sees what is in their line of sight. Enemies are visible **only** inside the local player's field of view (whether teammates' vision is shared is decided in `docs/DECISIONS.md`; default: each player sees through their own FOV only).
- Visited rooms stay on the minimap/map as "discovered", without enemies.
- **Environment props** (tables, chairs, barrels, pillars) can **block line of sight to enemies** and are **destructible** (HP, debris, effects).
- **Doors**: rooms have doors that **players can open and close freely** (interaction). Closed doors block sight and movement (enemies open them after a short delay or break them — default: simple enemies open them after a short delay).

## Controls (full rebinding, keyboard/mouse **and** gamepad)

Defaults (keyboard + mouse):

- Movement: **W / A / S / D** (free movement on the plane, no jumping)
- Primary attack / shoot: **left mouse button** (aim with cursor, projectiles fly toward the cursor)
- Skills: **1, 2, 3, 4, 5**
- Dodge (dash with i-frames): **Space** or **Shift** (player's choice in settings; both may be bound)
- Quick-use items: **Q** and **E** — **tap** uses the assigned item, **hold** opens a **radial menu** to pick the item for that slot
- Interact (pick up items, doors, levers, reviving a downed player): **F** (a separate action, not shared with dodge)
- Inventory / talents / map: separate actions (e.g. I / T / M)

Gamepad defaults: left stick — move, right stick — aim, RT — attack, face buttons/shoulders — skills 1–5 (e.g. A/B/X/Y + RB), dodge — dedicated button, Q/E — LB/D-pad with radial menu driven by the right stick, interact — separate button.

Requirements:

- All actions go through **InputMap** (never check raw keys in game logic).
- Options menu with **full rebinding** of every action (keyboard, mouse, gamepad), conflict detection, reset to defaults, saved to `user://settings.cfg`.
- Entire UI navigable with a gamepad (focus, navigation).

## Combat

- Attacks are **aimed at the cursor** (twin-stick); ranged attacks are **projectiles** (speed, collision, range). Melee uses a hitbox (cone/arc) in the cursor direction.
- **Dodge**: dash with **i-frames** and a **cooldown**. The _dodge chance_ stat is a separate mechanic (chance to fully avoid a hit).
- **All skills (1–5) have cooldowns** (plus a resource cost where it fits the class). Haste reduces cooldowns and cast times.
- **Aggro**: enemies have a threat system (threat table). Threat grows from damage, healing, taunts, and tank abilities; an enemy attacks the highest-threat target (with hysteresis so it doesn't flip between targets). The tank must be able to hold aggro.
- **Friendly fire**: a lobby option (default off). When on, projectiles, AoE, explosions, and traps hurt allies.
- **Player death**: the player is **downed** (lying on the ground). Living players have **10 seconds** to reach and **revive** them (interact F, short channel) — they return with a portion of HP. After 10 s without revive they become a **ghost** in **spectate mode until the end of the floor**. They return to play on the next floor. **Wipe** (everyone dead/ghost) → see "Save and wipe".
- Environmental damage sources: **explosive barrels**, **lava**, **spikes** (spikes may be cyclic), all processed through the same damage system on the host.

## Classes

Each class: **30 skills** (GDD section 3). Skills are unlocked in a **talent tree** (3 branches × 6 tiers with T2/T5 keystones, GDD section 8) and slotted in a **Skill Book loadout**: primary attack (LMB/RT) + 5 slots (keys 1–5). Passives work once unlocked; toggles take a slot.

### Warrior

- Melee weapons: swords, axes, maces, shields — all in 1H and 2H variants.
- Resource: **Fury** — generated by dealing **and** taking damage, **decays out of combat**.
- Role: flexible — tank or DPS.

### Ranger

- Ranged weapons: slings, bows, crossbows.
- Sets traps, applies poisons (DoT), main role: damage.
- Resource: **Mana**.

### Mage

- Weapons: 2H wand **or** 1H staff + 1H trinket.
- Damage spells, master of the elements.
- Resource: **Mana**.

### Priest

- Weapons: 2H staff **or** 1H wand + shield/trinket.
- Tank/healer hybrid.
- Resource: **Mana**.

### Resources

- **Mana** regenerates passively **very slowly**; stats (Intellect), items, talents, and skills are the main source of recovery.
- **Fury** grows from damage dealt and taken and **decays out of combat**.

## Stats

Primary:

| Stat      | Effect                              |
| --------- | ----------------------------------- |
| Strength  | melee damage + damage reduction     |
| Stamina   | max HP                              |
| Agility   | ranged damage + crit chance         |
| Intellect | magic damage + mana/fury generation |
| Armor     | default item stat                   |
| DPS       | default weapon stat                 |

Secondary (only on some items):

- **Crit damage** — extra critical damage
- **Haste** — shorter cooldowns and cast times, faster attacks
- **Dodge chance** — chance to avoid an attack
- **Leech** — heals for a portion of damage dealt

Implementation rules:

- All balance numbers (coefficients, curves, base values) live in **data resources** (`Resource` `.tres` or JSON in `data/`), never hardcoded.
- One `Stats` component computes final stats: class base + level + equipment + talents + buffs + penalties. The rest of the game only queries it.
- Damage, crit, dodge, leech, and aggro math is **host-side**.

## Items, equipment, and rarity

| Tier | Color  | Name     |
| ---- | ------ | -------- |
| 1    | White  | Common   |
| 2    | Green  | Uncommon |
| 3    | Blue   | Rare     |
| 4    | Purple | Epic     |
| 5    | Orange | Relic    |

- **Common**: only Armor (armor pieces) or DPS (weapons). Higher tiers: progressively more stats (primary, and from a certain tier also crit dmg / haste / dodge / leech) — counts and ranges in data.
- Every item has an **item level / required level** (level limit on the item). Exact rules in `docs/DECISIONS.md`.
- Characters **start in their underwear** plus one Common class weapon (base stats; see `docs/DECISIONS.md` #10).
- **Slots**: head, chest, legs, boots, gloves, left-hand weapon, right-hand weapon, ring ×2, necklace. A 2H weapon occupies both weapon slots.
- **Anyone can equip any item.** If a weapon is **not from the character's class**, the character gets **−80% damage** and **longer cooldowns** (values in data).
- **Backpack**: inventory as a slot grid/list with limited capacity. Larger backpacks can be **found** (monster drops).
- **Consumables** (potions, food — healing, regeneration, buffs) are assigned to quick slots **Q** and **E** (see Controls).
- **Appearance**: equipment changes the **character's look** — layered sprite architecture (body + a layer per slot), consistent with 64x64 × 8-direction animations.
- **Player-to-player trading**: dropping an item on the ground and another player picking it up. Ground items have a **rarity-colored glow** (shader + `PointLight2D` + particles), visible from afar.

## Loot

- **Loot is shared** (on the ground, first come first served; trade by dropping) and **fully random** — an item for a class not in the party can drop.
- **Drop rate boost** for items of classes present in the party (weight in the loot table; value in data).
- The floor boss drops additional, better loot.

## Progression

- XP for killing monsters, **shared by the whole party**.
- XP goes to everyone who **directly or indirectly** contributed to the kill (damage, healing, buffs, debuffs, tanking) — per-monster "contribution" tracking (host-side, time window).
- Levels → talent points → class talent tree.

## Difficulty scaling

Difficulty (HP, damage, enemy count, loot quality) depends on: **number of players**, **player level**, and **floor depth**. Formulas in data.

## Save and wipe

- Characters, equipment, and levels are **saved between sessions** (locally, `user://`).
- A **party wipe** erases progress according to the rules in `docs/DECISIONS.md` (to be confirmed: exactly what is lost).

## Dungeon

- **Procedurally generated**, **infinite**, deterministic from a **seed** (the host sends the seed).
- A floor = rooms with doors + corridors, destructible props, hazards (explosive barrels, lava, spikes), monsters, chests; **a boss at the end of the floor** + extra good loot, then the transition to the next floor.
- **Floor types** and **bosses** are **data-driven** (a separate resource per biome/type) so adding new ones requires no code changes. **5 biomes** (Crypt, Sewers, Foundry, Archives, Kurgan), each with its own architecture, lighting, environment mechanic, hazards, props, **7 monsters** and **2 bosses** (a seeded pick per floor).
- Every floor has one secure **merchant room** with one seeded merchant: Archibald the Gilded (trades for the floor's Gold Key) or Malphas the Soul Broker (blood tithe).

## Audio

- Music and ambience **per floor type** and **separately for the boss** (crossfade between them). One track per biome and one per boss (15), plus SFX keys; the user supplies the Suno files (`docs/SUNO_PROMPTS.md`). Suno files go in `assets/audio/` and are wired through data, not code.

## Lobby and game settings

- Pre-game lobby screen: players choose their **class** and **character name**.
- **Only the host** can change game settings (including **friendly fire**; the list must be easy to extend — settings as a `GameSettings` resource replicated to clients, UI generated from the option list).

## Architecture (recommended)

```
res://
  autoload/        # EventBus, GameState, NetworkManager (ENet/Steam), SaveSystem, InputSettings, AudioManager
  scenes/          # player, enemies, bosses, items, props, ui, dungeon, menus
  scripts/
	core/          # Stats, Health, ResourcePool (mana/fury), DamageSystem, ThreatTable
	classes/       # warrior, ranger, mage, priest + their skills
	items/         # ItemData, ItemGenerator, Inventory, Equipment, LootTable, Consumables
	dungeon/       # generator, rooms, doors, fog/visibility, hazards, floor manager
	net/           # lobby, spawn, sync, RPC helpers, transport
	ui/            # HUD, inventory, radial menu, talents, rebinding menu, lobby
  data/            # .tres/JSON: classes, skills, talents, items, monsters, bosses, floor types, settings
  assets/          # sprites/, audio/, shaders/, lights/ (placeholders → Pixellab/Suno)
```

- Component-based: `Health`, `Stats`, `ResourcePool`, `Hurtbox/Hitbox`, `Inventory`, `ThreatTable` as separate nodes.
- Loose coupling via **signals** and the `EventBus` autoload.
- Skills, enemies, bosses, and floor types as data resources + an executor script (data-driven).

## Networking rules

- **The host is authoritative**: damage, aggro, loot, XP, monster spawning, seed, door state, object destruction, dodge/hit validation.
- Clients send **intents** (movement, skill use, interaction), not outcomes.
- Player movement: local prediction + position sync; interpolation for remote players. Projectiles: simulated on the host and replicated.
- Every RPC clearly documented: who calls it, who executes it, reliable/unreliable.
- A feature is not "done" until it works over the network (2 instances: host + client), on LAN and — where possible — through Steam.

## Scope (what IS in: the full GDD)

- Everything from the MVP: lobby host/join (LAN + Steam), class/name/gender, host-only settings, 1–4 players, items and rarity, Q/E radial, downed/revive/ghost, shared XP, save/wipe, lighting, fog of war, rebinding, HUD.
- 5 biomes with architecture profiles, lighting, environment mechanics, hazards, props, a merchant chamber on every floor and a seeded boss pick.
- 35 monsters with behaviour modules, elite packs and elite altars; 10 bosses with phases and arena mechanics.
- 120 skills (30 per class): new effect primitives, ally targeting, channel/charge, toggles, passives, transforms, deployables.
- Talent trees: 3 branches × 6 tiers with T2/T5 keystones and skill unlocks, plus the Skill Book loadout.
- Damage types, resistances, creature types, expanded status effects with diminishing returns.
- 5 free stat points per level; run-permanent modifiers in the save.
- Gold, the Gold Key, Archibald (shared shop), Malphas (tithe, contracts, 10 pact potions).
- 108 legendaries with affix hooks and icons.
- 105 lore books: `tools/import_lore.py` → `data/lore_books.json`, reader modal, permanent codex, stat tomes.
- All new UI in the Obsidian Glass style, navigable with gamepad and keyboard.
- Audio: placeholder keys wired through data for 5 biome tracks, 10 boss tracks and the new SFX.

## Out of scope (do NOT do now)

Matchmaking, accounts and cloud, auction/trading UI, crafting, seasons, a story campaign, languages other than English and Polish, dedicated server, final soundtrack (the user makes it in Suno). (New worn armour sets are in scope since #20: leather and mail families next to plate and cloth, see `docs/DECISIONS.md`.)

## PixelLab budget

Every PixelLab generation is counted (`get_balance` before and after each batch; spend = counter difference) in the ledger in `docs/TODO.md`. Never exceed the account's remaining allowance or the goal cap. Cheap first: reuse, 5 drawn directions + mirrors, template animations, `create_map_object` for props, icon sheets cut by `tools/cut_icon_sheet.py`, the free workbenches, recolour/scale variants. Gameplay never waits for art: placeholders first.

## Working conventions for Claude

- Before a larger feature: a short plan (files, scenes, dependencies). Then small, working steps.
- After every step the project must **run without errors**; verify by running (`godot --headless --quit`, tests) instead of assuming.
- Code: typed GDScript, `snake_case` (functions/variables/files), `PascalCase` (classes/scenes); comments only where the "why" isn't obvious.
- Don't guess missing design decisions — record the assumption in `docs/DECISIONS.md` or ask.
- Don't add features outside the scope above. Don't refactor "while you're there".
- Keep `docs/DECISIONS.md` and `docs/TODO.md` up to date.
- Never delete or overwrite user-provided assets; add them next to placeholders and swap the references.
- Talk to the user in Polish; everything in the project (code, docs, in-game source text) in English, Polish only in `data/i18n/`.
