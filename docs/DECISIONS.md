# Design decisions and assumptions

Decisions taken while building the MVP where `CLAUDE.md` left room for interpretation.
Each one is an assumption that can be changed; most are a single value in `data/`.

## Technical

| Topic | Decision | Where |
| --- | --- | --- |
| Resolution | Base viewport **960x540**, stretch `canvas_items`, aspect `keep`, 2D transform/vertex snapping on, nearest filter. A 64x64 character is ~8% of the screen height, which suits a dungeon crawler. | `project.godot` |
| Tile size | **32 px** tiles. Characters stand on one tile; corridors are 2 tiles wide; doors span 2-3 tiles. | `data/balance.json` `world.tile_size` |
| Data format | **JSON** in `data/` (CLAUDE.md allows `.tres` or JSON). Easier to hand-edit; validated at startup by `GameData` (missing keys / unknown references are reported as errors). | `autoload/game_data.gd` |
| Asset swapping | Every texture/sound is looked up by key in `data/assets.json`. Character/monster art is a folder per set with one sheet per animation: rows = 8 directions (E, SE, S, SW, W, NW, N, NE), columns = frames. Frame counts/fps are in the same file. | `data/assets.json`, `tools/gen_placeholders.gd` |
| Renderer | Default Forward+ (works on Windows/Linux/macOS 4.x). 2D lights with shadows, glow via `WorldEnvironment` in canvas mode. | `scripts/dungeon/game.gd` |
| Headless audio | Nothing is played in headless runs (dummy audio driver reports playing streams as leaks, which would hide real errors in test logs). | `autoload/audio_manager.gd` |

## Networking

| Topic | Decision |
| --- | --- |
| Movement authority | **Client-side prediction with host validation**: the owning client simulates its own movement and streams position/facing/aim (`OwnerSync`, unreliable, 20 Hz). The host clamps the replicated position to the player's legal speed (`player.movement_tolerance`) and grants short allowances for dodge/charge/knockback. Everything else (HP, resource, cooldowns, inventory, XP, life state, hit detection) is host-only. This is the "local prediction + position sync" option from CLAUDE.md; full server reconciliation is out of MVP scope. |
| Intents | Clients only send intents: `request_skill(slot, aim)`, `request_dodge`, `request_interact(node)`, `request_revive`, `request_use_quick`, `request_assign_quick`, `request_equip/unequip/drop`, `request_learn_talent/reset_talents`. The host checks the RPC sender owns the player. |
| Projectiles | Simulated on the host; peers get `projectile(id, sprite, pos, dir, speed, life)` and `projectile_end(id)` and fly a cosmetic copy (straight lines are deterministic). No node per projectile is replicated. |
| Floors | Only the seed is sent; every peer generates the same layout. Doors and props get deterministic names so the host addresses them by RPC. Enemies, players and ground items use `MultiplayerSpawner`s. |
| Mid-run joins | Rejected (the lobby is closed once the run starts, Steam lobby set non-joinable). |
| Character data trust | Each player owns their save file; when joining a lobby the client sends its character to the host (co-op, no anti-cheat). During the run the host is authoritative and sends snapshots back to the owner, who saves them (floor transitions, level-ups, talent changes, boss kill, wipe). |
| Steam testing | App id 480 (Spacewar) is shared by everyone, so lobbies are tagged `game=funtasy` and filtered. One Steam account can't join its own lobby, so automated tests cover lobby creation, listing and the Steam peer; a real 2-account test is manual (see README). |

## Gameplay

| Topic | Decision | Where |
| --- | --- | --- |
| Vision | Each player sees enemies only through their **own** line of sight (default from CLAUDE.md). A host setting `shared_vision` (default off) uses every teammate's sight. Sight range 430 px, grid FOV radius 13 cells. | `data/game_settings.json`, `scripts/dungeon/visibility.gd` |
| Fog memory | Seen cells stay "discovered" (dimmed) on the map/minimap; enemies are never drawn there. | `visibility.gd`, `minimap.gd` |
| Doors | Players toggle doors with Interact; a door can't be closed on someone standing in the doorway. Monsters open closed doors after `world.door_enemy_open_delay` (1.2 s); they don't break them. | `door.gd`, `enemy.gd` |
| Friendly fire | Lobby setting, default off. When on, players' projectiles, AoEs, explosions and traps also hit allies (never the caster). Melee never hurts allies. | `combat.gd` `hostile_in_radius` |
| Hazards vs FF | Lava and spikes are environment damage and hurt everyone regardless of the setting. An explosive barrel destroyed by a player explodes *as that player* (so it follows the friendly-fire setting and still hurts monsters); destroyed by anything else it hurts everyone. | `prop.gd` |
| Primary attack | Left mouse / RT uses the class's primary attack (a skill with a short cooldown scaled by haste). It restores a little mana on hit (Mage, Ranger, Priest) or generates Fury (Warrior). | `data/skills/*.json` |
| Resources | Mana: slow passive regen (`stats.mana_regen_*`, scaled by Intellect) + on-hit restore + potions. Fury: 0-100, +6 per damaging hit dealt, + damage taken relative to max HP, decays after 4 s out of combat. | `data/balance.json` |
| Cast times | Short cast times (0.3-0.6 s) resolve the effect after the delay; players can keep moving while casting, monsters stand still. | `actor.gd` |
| Damage formula | `(base + power x coef) x damage_mult`, power = weapon DPS + stat x 0.6 (Strength for melee, Agility for ranged, Intellect for spells). Crit multiplies by `1 + crit_damage` (base +50%). Armor reduces physical damage by `armor / (armor + 60 + 12 x attacker_level)`; Strength adds a small reduction against everything; total capped at 75%. Dodge chance negates a hit fully. Leech heals the attacker for a share of damage dealt. | `combat.gd`, `data/balance.json` |
| Aggro | Threat = damage x skill threat multiplier x class threat multiplier; healing/buffing an ally adds threat on enemies fighting that ally; taunts force the target for a few seconds. A new target is chosen only when its threat exceeds the current target's by **15%** (hysteresis). | `threat_table.gd`, `balance.threat` |
| Two weapon slots | "Right hand" (main) and "Left hand" (off). One-handed weapons can go in either; off-hand weapons add 50% of their DPS. Two-handed weapons fill both slots. Shields and trinkets are off-hand only. | `inventory.gd`, `stats.gd` |
| Class weapons | Warrior: sword, axe, mace (1H), greatsword, greataxe, warhammer (2H), shield. Ranger: sling (1H), bow, crossbow (2H). Mage: Arcane Wand (2H) or Battle Staff (1H) + trinket. Priest: Holy Staff (2H) or Holy Wand (1H) + shield/trinket. CLAUDE.md gives wand/staff opposite handedness for Mage and Priest, so they are separate item bases. | `data/items/bases/` |
| Off-class penalty | Any weapon/off-hand not listing the class: **x0.2 damage, x1.5 cooldowns**. Armor and jewelry have no class. | `balance.off_class` |
| Item level | Item level = monster level where it dropped; **required level = item level**. Monster level = `1 x (depth-1) + 0.5 x party_avg_level + 0.5`, rounded. | `item_generator.gd`, `game.gd` |
| Rarity stats | Common: only armor/DPS. Uncommon: +1 primary stat. Rare: 1-2 primary + 1 secondary. Epic: 2-3 + 1-2. Relic: 3 + 2-3. Secondary = crit damage, haste, dodge, leech. | `data/items/rarities.json` |
| Backpacks | Start with 12 slots. Bigger backpacks (16-32) drop rarely; picking one up upgrades capacity immediately (a smaller one stays on the ground for a teammate). | `balance.inventory`, `player.gd` |
| Consumables | Stack in the backpack; picking up a new kind auto-fills an empty Q/E slot. One shared potion cooldown. | `data/items/consumables.json` |
| Loot | Shared, first come first served. Monsters 28% chance for one drop, chests 2-3 (min Uncommon), boss 4-5 (min Rare). Weapons/off-hands of classes in the party get x3 weight. Rarity improves by 4% per floor. | `balance.loot` |
| XP sharing | Every player who **contributed** to a kill in the last 30 s gets the **full** monster XP (not split). Contribution = damage, debuffs, taunts, being hit by the monster (tanking), and healing/buffing a player the monster is fighting. | `game.gd` `on_enemy_killed`, `combat.gd` |
| Talents | 1 point per level from level 2; 8 nodes per class in 4 rows; row N needs 2N points spent; some nodes need a previous node. Reset is free. | `data/talents/*.json` |
| Downed / ghost | 0 HP -> downed for 10 s. A living teammate holds Interact nearby for 2 s to revive at 35% HP. Otherwise the player becomes a ghost: invisible to enemies, camera spectates living teammates until the next floor, where ghosts return at 50% HP. | `balance.player` |
| Party wipe | When no player is left standing (everyone downed or a ghost) the run ends. **Assumption (to confirm):** every character loses its equipped items and backpack contents; level, XP and talents are kept. The party returns to the lobby. Toggle in `balance.wipe`. | `game.gd` `_check_wipe` |
| Run progress | Floors are not saved: every new run starts at floor 1. Characters are saved (`user://characters/`). | `save_system.gd` |
| Scaling | Per extra player: monster HP +60% (boss +70%), damage +12%, monster count +30%. Per monster level: HP +22%, damage +14%. Difficulty setting multiplies HP and damage (0.75 / 1.0 / 1.4). | `balance.scaling`, `game_settings.json` |
| Descending | When the boss dies a portal opens in the boss room; the party descends when every living player stands in it (or someone interacts with it and at least half are in it). | `game.gd` |
| Floor types | Floor type order cycles through `data/floor_types/` by depth (MVP: only `crypt`). The boss is defined by the floor type. | `game.gd` `start_floor` |
| Pause | The game never pauses (online co-op); the pause menu is an overlay that blocks the local player's input. | `pause_menu.gd` |

## Controls

| Topic | Decision |
| --- | --- |
| Default gamepad layout | Left stick move, right stick aim, RT attack, A/B/X/Y + RB skills 1-5, LT dodge, LB = quick slot Q, D-pad Right = quick slot E, D-pad Down = interact, View = inventory, D-pad Left = talents, D-pad Up = map, Menu = pause. |
| Dodge keys | Space **and** Shift are both bound by default (two keyboard slots); the player can clear either in Options. |
| Rebinding | Every gameplay action has 2 keyboard/mouse slots and 2 gamepad slots. Binding an input already used by another action removes it from that action (reported on screen). Saved in the `[input]` section of `user://settings.cfg`. Escape cancels a capture. |
| Quick slots | Tap Q/E (< 0.25 s) uses the item; holding opens the radial menu, aim with mouse/right stick, release to assign. |
| Gamepad aim | When the right stick is idle, the character aims where it is walking; ground-targeted skills land 150 px ahead. |
