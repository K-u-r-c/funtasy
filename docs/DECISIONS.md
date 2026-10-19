# Design decisions and assumptions

Decisions taken where `CLAUDE.md` or the GDD left room for interpretation (MVP first, then the full GDD: D1-D38 below).
Each one is an assumption that can be changed; most are a single value in `data/`.

## Technical

| Topic | Decision | Where |
| --- | --- | --- |
| Resolution / aspect | Base viewport **960x540**, stretch `canvas_items`, aspect **`expand`** (changed from `keep` for the UI overhaul), 2D transform/vertex snapping on, nearest filter. 960x540 is the smallest logical view; wider or taller windows *add* view space instead of letterboxing: 1:1 -> 960x960, 16:9 -> 960x540, 21:9 -> 1280x540, 32:9 -> 1920x540. HUD blocks are pinned to the screen edges, modals are centered with a max size. A 64x64 character is ~12% of the screen height at 16:9. | `project.godot` |
| Camera on odd aspects | The visible world is clamped between `camera.min_view_*` and `camera.max_view_*` (and never exceeds the dungeon bounds): 32:9 zooms in to show ~1400x394 world px instead of 1920x540, so ultrawide gives no extra vision and never shows the void past the map; 1:1 keeps its taller view. | `game_camera.gd`, `balance.camera` |
| Tile size | **32 px** tiles. Characters stand on one tile; corridors are 2 tiles wide; doors span 2-3 tiles. | `data/balance.json` `world.tile_size` |
| Data format | **JSON** in `data/` (CLAUDE.md allows `.tres` or JSON). Easier to hand-edit; validated at startup by `GameData` (missing keys / unknown references are reported as errors). | `autoload/game_data.gd` |
| Asset swapping | Every texture/sound is looked up by key in `data/assets.json`. Character/monster art is a folder per set with one sheet per animation: rows = 8 directions (E, SE, S, SW, W, NW, N, NE), columns = frames. Frame counts/fps are in the same file. | `data/assets.json`, `tools/gen_placeholders.gd` |
| Renderer | Default Forward+ (works on Windows/Linux/macOS 4.x). 2D lights with shadows, glow via `WorldEnvironment` in canvas mode. | `scripts/dungeon/game.gd` |
| Spawner order | In `game.tscn` the `MultiplayerSpawner`s come **before** the nodes they spawn into. With the opposite order, Godot 4.7.2 *release* builds print "Attempt to disconnect a nonexistent connection ... tree_exiting" for every spawned node when the scene is freed (engine bug, reproduced in a minimal project; debug builds are fine). | `scenes/dungeon/game.tscn` |
| Lobby settings | The "GameSettings resource" is a plain Dictionary (id -> value) built from `data/game_settings.json`; the host replicates it with one RPC and the lobby UI is generated from the same list, so adding a setting = adding a JSON entry. | `autoload/game_state.gd`, `scripts/ui/lobby.gd` |
| Test isolation | `--profile=<name>` redirects saved games and settings to `user://profiles/<name>/`; the test runner uses throw-away `test_*` profiles. | `autoload/save_system.gd` |
| Session teardown | Godot 4.7.x *release* builds print "Attempt to disconnect a nonexistent connection ... 'tree_exited'" for every RPC-using node when the peer is reset ([godot#123751](https://github.com/godotengine/godot/issues/123751)). So: autoload RPCs go through a per-session relay node (`SessionRpc`, whitelisted methods); leaving a run freezes the game, the host tells clients first, network polling is paused, the scene is switched (freeing all networked nodes), the relay is freed, and only then the peer is reset. Verified clean with the exported Linux release binary (full, boss, wipe, host-leave, client-leave pairs). | `scripts/net/session_rpc.gd`, `network_manager.gd` |
| Light layers | Occluding objects (props, doors, wall torches) and characters draw on light layer 2, which every light illuminates but never shadows; the floor and walls are on layer 1 (lit + shadowed). Gameplay lights sit at the feet of the player who carries them: collisions keep feet out of every occluder, so standing against a door or table never puts the light inside a shadow caster (which used to black out everything, the player included). | `scripts/core/light_layers.gd` |
| UI theme | "Obsidian Glass", built in code (`UITheme`): translucent slate panels `#0d111af0`, 1-2 px gold/cyan borders with 1 px chamfered corners and a rim light, drawn as plain rectangles by a scripted `StyleBox` (pixel exact at any scale). Installed on the root window **and merged into the engine default theme**, because Controls under a `CanvasLayer` (HUD, overlays) don't inherit the root window's theme. Important windows get a gilded 9-slice frame (PixelLab art). Buttons never scale (scaling shimmers with nearest filtering); the 1 px press offset is the `pressed` style's content margin. | `scripts/ui/ui_theme.gd`, `data/assets.json` `ui` |
| UI font | 16 px pixel font generated with PixelLab (`assets/fonts/funtasy_pixel.ttf`), antialiasing/hinting/subpixel off. Sizes 16/32/48 are pixel exact; 12 is used for dense numbers. It has no brackets, `#`, `&`, `<`, `>`, `|` - those fall back to the engine font. A generated 8 px font was rejected (several wrong glyphs). | `UITheme.font()` |
| Safe zone | HUD and menus keep `ui.safe_margin` (10 px) from the screen edges; modals are capped at `ui.modal_max_*`. Platform safe areas (notches/TV overscan) don't apply to the desktop targets. | `balance.ui` |
| Button prompts | Prompts are drawn glyphs (pad face buttons as colored discs, shoulders/triggers as pills, D-pad as a cross, keys as key caps, mouse buttons as a mouse) for the device used last; they follow rebinding live. The keyboard counts as "focus navigation" too, so the animated focus bracket shows for keyboard and gamepad, not for the mouse. | `input_glyph.gd`, `prompt_bar.gd`, `focus_bracket.gd` |
| Inventory drag and drop | Mouse drag only maps onto the existing host-validated intents: backpack -> paper doll = equip (the host picks the slot), paper doll -> backpack = unequip, out of the window = drop on the ground, consumable -> Q/E = assign. Reordering the backpack is not supported (no intent for it). Gamepad: A equip/unequip, X drop, Y potion on E. | `inventory_panel.gd`, `item_slot.gd` |
| Final art (PixelLab) | Every sprite comes from PixelLab and lives in `assets/sprites/pixellab/` next to the untouched placeholders; `data/assets.json` points at it. Heroes and monsters are PixelLab v3 characters animated with template animations (see "Character art pipeline"). Tiles, props, icons, projectiles and effects were generated in batches (objects, tiles pro, pixflux, vfx_workbench). Light, shadow blob and the 1-px particle stay generated technical textures; audio stays placeholder (Suno). | `assets/sprites/pixellab/`, `tools/` |
| Character scale | Heroes are ~43-44 px tall figures (48 px PixelLab canvas centred on a **64x64** cell, feet 9 px above the cell bottom), about 1.35 tiles. The ghoul, skeleton archer and cultist are the same size (44-45 px, 64 px cells); the Bone Lord is ~72 px (76 px canvas on a 112 px cell), about 1.6x a hero. Collision radii stay 8-9 px (16 for the boss). Overhead bars and name labels use each entry's `height` / `feet_offset`. | `data/assets.json`, `CharacterSprite` |
| Monster art | Monsters and the boss are PixelLab v3 characters animated with templates (idle, walk, death; ghoul attack = cross-punch, cultist attack = lead-jab, cast = fireball) and v3 custom clips (archer bow shot, boss overhead smash); W / NW / SW are mirrors. dash = walk, hit = two idle frames, downed = the last death frame. `tools/build_monster.py tools/monsters_sources.json <work dir>` rebuilds the sheets and prints the asset entries. | `tools/build_monster.py`, `tools/monsters_sources.json` |
| Character art pipeline | One naked base body per gender, every animation drawn from PixelLab templates: batch 1 = idle 2, walk 4, attack 5 (cross-punch), death 4 frames; batch 2 = cast 5 (fireball, its flame removed by `strip_glow`), dash 4 (running), hit 3 (taking-punch) frames - 15 / 12 frames, one `transfer_outfit` call per direction and batch. Each gear set (plate: helm, chest, greaves, boots, gauntlets; cloth: hood, robe) is a PixelLab state of the same character used as the reference for **`transfer_outfit` on the base body's own frames**, so the outfit lines up pixel for pixel. W / NW / SW are mirrors of E / NE / SE (the unarmed body is symmetric; saves 3 calls per set and avoids template colour drift). Downed is the only derived animation: the last (drawn) death frame, so a downed hero lies in their worn gear. The ghost is drawn too: a PixelLab "Ghost" state of the base body animated with breathing-idle (4 frames, gear is not drawn on ghosts, the game draws it at 45% alpha); `build_hero.py` falls back to a pale copy of idle when the sources list no ghost. Stray template pixels (a red eye dot in the female ghost) are repainted by the `replace_color` import step listed under `fix_colors`. `hero_shots` also writes check sheets of every held item (`h04c_held_items.png`) and of downed / ghost (`h04d_downed_ghost.png`) in 8 directions. `tools/build_hero.py` downloads the sources listed in `tools/hero_<gender>_sources.json` and runs `tools/gear_cut.gd` (cuts the outfit into slot layers by body region, writes hide masks, applies frame patches and feet alignment) and `tools/bake_gear.gd` (held items). Recolouring the body is gone. | `tools/build_hero.py`, `tools/gear_cut.gd`, `tools/body_regions.gd`, `tools/hero_*.json` |
| Template clean-up | Template frames can sit 1-3 px higher or lower than the walk cycle and a few frames drift: `gear_cut` shifts each direction of idle / attack / cast / dash / hit so its median feet row matches walk's (body, layers and masks alike), and `patches` replace a broken frame (male south death frame 0). `build_monster.py` aligns standing clips to idle the same way (`align_feet`). | `tools/gear_cut.gd`, `tools/pixellab_import.gd` |
| Body regions | `tools/body_regions.gd` labels every pixel of a naked frame: head (hair + skin within 7 px of it), torso (shirt), arms / hands (skin touching the shirt, the last 3 px of each limb), legs / feet (shorts + skin touching them, last 4 px). Colours come from the body palette plus HSV rules (template frames shade a little differently). An outfit pixel belongs to the region under it. | `tools/body_regions.gd` |
| No body under gear | Each worn layer has a hide mask (`<layer>/hide/<anim>.png`, same layout): the body pixels of the regions the piece replaces (plate: its whole region; robe: torso + arms; its skirt keeps only the changed pixels so legs show below the hem). Underwear or hair inside a piece's regions that the piece doesn't draw over is hidden too. The body layer's shader (`body_hide.gdshader`) drops masked pixels, portraits apply the same masks. Gaps up to 3 px next to the piece (thinner than the naked limb) are filled from the nearest gear pixel; uncovered hair (a ponytail under a helmet) is just hidden. The `art-check` test counts, for every body, set, animation, direction and frame, the body pixels left showing (full plate: any; hood + robe: shirt / shorts / hair): all 0. | `CharacterSprite`, `gear_cut.gd` |
| Held items | Weapons / shields / trinkets are the item icons placed at the hand found by the body regions (the "hands" pixel farthest along the direction's hand vector; arms, then the torso edge when a running pose hides the hands), the grip snapped to a drawn pixel of the item and the hand pixel mapped exactly onto it (`art-check` verifies every held layer frame is drawn and touches the hand), resting tip-down (blades), upright (bows, staves) or flat (shields, orbs), mirrored on directions whose hand is on the left of the screen, and swung through attack / cast frames. Weapons and off-hands draw behind the body when facing away. | `tools/bake_gear.gd`, `tools/hero_*.json` "held" |
| Action timing | One-shot animations (attack, cast, hit) last their own sheet's frames / fps (`CharacterSprite.anim_length`), so monsters and heroes with different clip lengths play them to the end. | `actor.gd` `play_action` |
| Camera lean | The camera leans toward the aim by at most `camera.aim_lookahead` (28 px). With the mouse the lean comes from the cursor's place on the screen (dead zone `camera.look_deadzone` around the centre, eased curve), not from its world position, which moves with the camera and fed back into the lean; with a pad it follows the aim stick. The lean eases on its own (`camera.look_smoothing`, frame-rate independent) on top of the normal follow smoothing. | `game_camera.gd`, `data/balance.json` |
| Ground effects | Zones, traps, AoE rings and telegraphs are drawn at `GROUND_Z` (above the floor, under every actor), so enemies standing in a Consecration stay visible. Volumetric effects (explosions, projectiles) stay above. | `combat_fx.gd` |
| Lobby layout | Three numbered steps left to right: 1 choose the hero (name, body, class in a 2x2 grid, description; a saved game lists its heroes instead), 2 the big live preview with turn / class-gear controls and the gold "Confirm hero" button with a ready line under it ("Update hero" once confirmed), 3 "Start run" in the bottom bar (host). The game choice, party and settings share the right column. Gamepad focus follows the same order. | `lobby.gd` |
| Gear tint | Item tint (base tint mixed 30% with the rarity colour) is softened to `inventory.appearance_tint` (40%) because the worn art has its own colours. | `Inventory.appearance`, `data/balance.json` |
| Headless audio | Nothing is played in headless runs (dummy audio driver reports playing streams as leaks, which would hide real errors in test logs). | `autoload/audio_manager.gd` |
| Audio keys (GDD 3.13) | 5 biome tracks + 10 boss tracks + menu (16 music keys, plus the legacy MVP boss track as a fallback) and 93 SFX keys. Monster abilities, behaviours and arena mechanics name their own key (e.g. `hook_chain`, `slime_split`, `anvil`); keys without a file of their own copy a similar placeholder. `docs/SUNO_PROMPTS.md` (generated by `tools/gen_suno_prompts.py`) lists every key with its file path and a prompt; `tools/register_audio.py` hooks dropped-in files into `data/assets.json`. The optional merchant-room and Tome Prison themes are not added (the plan marks them optional). | `data/assets*.json`, `tools/` |

## Networking

| Topic | Decision |
| --- | --- |
| Movement authority | **Client-side prediction with host validation**: the owning client simulates its own movement and streams position/facing/aim (`OwnerSync`, unreliable, 20 Hz). The host clamps the replicated position to the player's legal speed (`player.movement_tolerance`) and grants short allowances for dodge/charge/knockback. Everything else (HP, resource, cooldowns, inventory, XP, life state, hit detection) is host-only. This is the "local prediction + position sync" option from CLAUDE.md; full server reconciliation is out of MVP scope. |
| Intents | Clients only send intents: `request_skill(slot, aim)`, `request_dodge`, `request_interact(node)`, `request_revive`, `request_use_quick`, `request_assign_quick`, `request_equip/unequip/drop`, `request_learn_talent/reset_talents`. The host checks the RPC sender owns the player. |
| Projectiles | Simulated on the host; peers get `projectile(id, sprite, pos, dir, speed, life)` and `projectile_end(id)` and fly a cosmetic copy (straight lines are deterministic). No node per projectile is replicated. |
| Floors | Only the seed is sent; every peer generates the same layout. Doors and props get deterministic names so the host addresses them by RPC. Enemies, players and ground items use `MultiplayerSpawner`s. |
| Mid-run joins | Rejected (the lobby is closed once the run starts, Steam lobby set non-joinable). |
| Saved games | Saves belong to a **game**, not to characters. The host stores each game (`user://games/<id>.json`): its party size, the floor reached and its heroes. In the lobby the host picks *New game* (everyone creates a level 1 hero) or a saved game; a saved game can only be continued by **exactly** its party size, and every player takes one of its heroes, so a hero can never be carried into another party. The game is saved at every floor start, level-up, talent change and boss kill; continuing starts at the beginning of the saved floor. A game can only be continued by the host who saved it. |
| Steam testing | App id 480 (Spacewar) is shared by everyone, so lobbies are tagged `game=funtasy` and filtered. One Steam account can't join its own lobby, so automated tests cover lobby creation, listing and the Steam peer; a real 2-account test is manual (see README). |

## Gameplay

| Topic | Decision | Where |
| --- | --- | --- |
| Darkness and vision | Darkness is a mechanic. The ambient light is nearly black and gets darker on every floor (`lighting.ambient_darken_per_depth`). A cell (map discovery) or a monster is seen only when it is in the viewer's line of sight **and lit**: by the viewer's own small light (75 px), a wall torch, a carried torch, lava, or a spell (projectile lights, impact flashes, telegraphs, zones). Each player sees through their own sight; the host setting `shared_vision` (default off) adds every teammate's sight. Monsters perceive players regardless of light. | `scripts/dungeon/visibility.gd`, `scripts/core/light_layers.gd`, `balance.lighting` |
| Torches | Wall torches light rooms. A player can **take** one (Interact): it burns in their hand for 120 s, gutters in its last 15 s and goes out; taking another refills it. Any hit (melee, AoE, a projectile stopped by the wall next to it) **breaks** a lit wall torch. The start room (>= 2 torches) and the boss room (4) are always lit; other rooms are lit with a chance that drops by 12% per floor (min 20%). The carried torch keeps burning across floors and is not saved. | `scripts/dungeon/torch.gd`, `player.gd`, `dungeon_generator.gd` |
| Fog memory | Seen cells stay "discovered" (dimmed) on the map/minimap; enemies are never drawn there. | `visibility.gd`, `minimap.gd` |
| Doors | Players toggle doors with Interact; a door can't be closed on someone standing in the doorway. Monsters open closed doors after `world.door_enemy_open_delay` (1.2 s); they don't break them. | `door.gd`, `enemy.gd` |
| Friendly fire | Lobby setting, default off. When on, players' projectiles, AoEs, explosions and traps also hit allies (never the caster). Melee never hurts allies. | `combat.gd` `hostile_in_radius` |
| Hazards vs FF | Lava, spikes and explosive barrels are environment damage: they hurt everyone in range (players and monsters) regardless of the friendly-fire setting, including the player who broke the barrel. That player still gets the XP contribution for monsters the blast hits. Friendly fire only concerns players' own projectiles, AoEs and traps. | `prop.gd`, `combat.gd` |
| Primary attack | Left mouse / RT uses the class's primary attack (a skill with a short cooldown scaled by haste). It restores a little mana on hit (Mage, Ranger, Priest) or generates Fury (Warrior). | `data/skills/*.json` |
| Resources | Mana: slow passive regen (`stats.mana_regen_*`, scaled by Intellect) + on-hit restore + potions. Fury: 0-100, +6 per damaging hit dealt, + damage taken relative to max HP, decays after 4 s out of combat. | `data/balance.json` |
| Cast times | Short cast times (0.3-0.6 s) resolve the effect after the delay; players can keep moving while casting, monsters stand still. | `actor.gd` |
| Damage formula | `(base + power x coef) x damage_mult`, power = weapon DPS + stat x 0.6 (Strength for melee, Agility for ranged, Intellect for spells). Crit multiplies by `1 + crit_damage` (base +50%). Armor reduces physical damage by `armor / (armor + 60 + 12 x attacker_level)`; Strength adds a small reduction against everything; total capped at 75%. Dodge chance negates a hit fully. Leech heals the attacker for a share of damage dealt. | `combat.gd`, `data/balance.json` |
| Aggro | Threat = damage x skill threat multiplier x class threat multiplier; healing/buffing an ally adds threat on enemies fighting that ally; taunts force the target for a few seconds. A new target is chosen only when its threat exceeds the current target's by **10%** if the challenger is in melee range or **30%** if it is farther away (hysteresis, classic MMO rule), and after a switch the new target is kept for at least **2 s** (`min_target_time`; taunts, threat drops and dead targets still switch at once) so a tank regaining threat right after a ranged burst does not ping-pong the monster. Measured in a real warrior + mage fight: see the `tank` test. | `threat_table.gd`, `balance.threat` |
| Two weapon slots | "Right hand" (main) and "Left hand" (off). One-handed weapons can go in either; off-hand weapons add 50% of their DPS. Two-handed weapons fill both slots. Shields and trinkets are off-hand only. | `inventory.gd`, `stats.gd` |
| Class weapons | Warrior: sword, axe, mace (1H), greatsword, greataxe, warhammer (2H), shield. Ranger: sling (1H), bow, crossbow (2H). Mage: Arcane Wand (2H) or Battle Staff (1H) + trinket. Priest: Holy Staff (2H) or Holy Wand (1H) + shield/trinket. CLAUDE.md gives wand/staff opposite handedness for Mage and Priest, so they are separate item bases. | `data/items/bases/` |
| Off-class penalty | Any weapon/off-hand not listing the class: **x0.2 damage, x1.5 cooldowns**. Armor and jewelry have no class. | `balance.off_class` |
| Item level | Item level = monster level where it dropped, capped at the level cap (#8); **required level = item level**. Monster level = `level_per_depth x (depth-1) + 0.5 x party_avg_level + 0.5`, rounded (`level_per_depth` 1.25 since #8). A rare upgrade drop (#8) comes 2-3 levels above that: the hero grows into it. | `item_generator.gd`, `game.gd` |
| Too-high-level gear | Shown before the player tries: backpack slots darken the icon with a red frame and a padlock "Lv N" badge, the item card shows a red "needs level N (you are M)" banner, the equip prompt says "Equip (needs level N)", ground items show "Requires level N" under their name and in the pick-up prompt. Trying anyway (click, A, drag onto the slot) is refused on the spot with a message in the inventory footer; the host still validates and its refusal names both levels. | `item_slot.gd`, `inventory_panel.gd`, `overhead.gd`, `inventory.gd` |
| Rarity stats | Common: only armor/DPS. Uncommon: +1 primary stat. Rare: 1-2 primary + 1 secondary. Epic: 2-3 + 1-2. Relic: 3 + 2-3. Secondary = crit damage, haste, dodge, leech. | `data/items/rarities.json` |
| Backpacks | Start with 12 slots. Bigger backpacks (16-32) drop rarely; picking one up upgrades capacity immediately (a smaller one stays on the ground for a teammate). | `balance.inventory`, `player.gd` |
| Consumables | Stack in the backpack; picking up a new kind auto-fills an empty Q/E slot. One shared potion cooldown. | `data/items/consumables.json` |
| Loot | Shared, first come first served. Monsters 28% chance for one drop, chests 2-3 (min Uncommon), boss 4-5 (min Rare). Weapons/off-hands of classes in the party get x3 weight. Rarity improves by 4% per floor. | `balance.loot` |
| XP sharing | Every player who **contributed** to a kill in the last 30 s gets the **full** monster XP (not split). Contribution = damage, debuffs, taunts, being hit by the monster (tanking), and healing/buffing a player the monster is fighting. | `game.gd` `on_enemy_killed`, `combat.gd` |
| Talents | 1 point per level from level 2; 8 nodes per class in 4 rows; row N needs 2N points spent; some nodes need a previous node. Reset is free. | `data/talents/*.json` |
| Downed / ghost | 0 HP -> downed for 10 s. A living teammate holds Interact nearby for 2 s to revive at 35% HP. Otherwise the player becomes a ghost: invisible to enemies, camera spectates living teammates until the next floor, where ghosts return at 50% HP. | `balance.player` |
| Party wipe | When no player is left standing (everyone downed or a ghost) the game is **over**: its save is deleted with its heroes and the party returns to the lobby to start a new game. | `game.gd` `_check_wipe`, `GameState.end_game` |
| Scaling | Per extra player: monster HP +60% (boss +70%), damage +12%, monster count +30%. Per monster level: HP +22%, damage +14%. Difficulty setting multiplies HP and damage (0.75 / 1.0 / 1.4). | `balance.scaling`, `game_settings.json` |
| Descending | When the boss dies a portal opens in the boss room. Walking into it does nothing: every living player has to **interact** with it to be ready (interacting again cancels), and the party descends once all living players are ready. Downed players and ghosts come along. |
| Choosing an interaction | Everything in reach is a candidate; with the mouse the candidate closest to the cursor is used, with a gamepad the one the character faces (nearer first on ties). The prompt shows which one it is. | `game.gd` `find_interactable` |
| Floor types | Floor type order cycles through `data/floor_types/` by depth (MVP: only `crypt`). The boss is defined by the floor type. | `game.gd` `start_floor` |
| Pause | The game never pauses (online co-op); the pause menu is an overlay that blocks the local player's input. | `pause_menu.gd` |

## Controls

| Topic | Decision |
| --- | --- |
| Default gamepad layout | Left stick move, right stick aim, RT attack, A/B/X/Y + RB skills 1-5, LT dodge, LB = quick slot Q, D-pad Right = quick slot E, D-pad Down = interact, View = inventory, D-pad Left = talents, D-pad Up = map, R-stick click = character, Menu = pause. (Since #39 the R-stick click picks an ally and since #41 D-pad Left locks an enemy; Character and Talents are game-menu tabs on the pad.) |
| Game menu | Character (C), Inventory (I), Talents (T) and Map (M) are tabs of one menu: same window size, a header with the panel title, a subtitle and a tab strip. While one is open, LB/RB (Q/E on the keyboard) or another panel's key switch tabs (contents crossfade), the open panel's own key, B or Esc closes it. The Character panel shows the hero at 3x, level/XP, every computed stat (hover for what it does) and the six skills as a compact list (icon, name, key glyph). |
| Skill tooltips | Hovering a skill row, or moving keyboard/gamepad focus onto it, opens an Obsidian Glass card beside it (left of it when the right side has no room, always inside the screen): name, key, description, effective cooldown, cost, cast time (haste), damage with its crit value, DoT per tick / total, healing / shields, area and reach in metres (1 tile = 1 m), crit chance and damage, leech, scaling power and the learned talents that change the skill. The numbers come from `Combat.skill_numbers` / `Combat.value_of` / `Combat.cast_time_for`, the same functions the host uses when the skill is cast, so they never drift; "damage before the target's armor". Clients rebuild the talent skill modifiers from the replicated talent ranks (`Stats.skill_mods_for`). The focus the panel grabs when it opens doesn't pop a tooltip. | `scripts/ui/skill_info.gd`, `skill_tooltip.gd`, `combat.gd` |
| Hero gender | The lobby offers a body (Male / Female, from `characters.genders` in `data/assets.json`) next to the class, with an animated preview that turns (buttons, mouse drag) and shows the class's typical gear (`preview_gear` in the class data; heroes still start without equipment). Gender is part of the hero: saved with it, sent in the roster and the spawn data, used for the world sprite, portraits and paper doll. Saves without it load as male. Both genders have the same layers, so every item looks right on either. | `game_state.gd`, `lobby.gd`, `hero_preview.gd`, `player.gd` |
| Dodge keys | Space **and** Shift are both bound by default (two keyboard slots); the player can clear either in Options. |
| Rebinding | Every gameplay action has 2 keyboard/mouse slots and 2 gamepad slots. Binding an input already used by another action removes it from that action (reported on screen). Saved in the `[input]` section of `user://settings.cfg`. Escape cancels a capture. |
| Quick slots | Tap Q/E (< 0.25 s) uses the item; holding opens the radial menu, aim with mouse/right stick, release to assign. |
| Gamepad aim | When the right stick is idle, the character aims where it is walking; ground-targeted skills land 150 px ahead. |

## Full GDD (D1-D38)

The Game Design Document (`.design/GAME_DESIGN_DOCUMENT.md`) replaces the MVP scope. These rows
resolve its gaps and contradictions. The proposals come from `.design/IMPLEMENTATION_PLAN.md`; where a
proposal left a choice open, the chosen option is stated, and any change to a proposal gives its reason.

| # | Topic | Decision | Where |
| --- | --- | --- | --- |
| D1 | 30 skills vs 5 slots | Skills are **unlocked in the talent tree** (each branch holds 10 of the class's 30 skills as unlock nodes on tiers 0-5) and **slotted** in the Skill Book (primary + 1-5). The loadout is saved with the hero; swapping is allowed out of combat only. **Start:** the six skills of the MVP kit (primary + 5, renamed to their GDD names) are tier-0 nodes that come unlocked for free, so a new hero has a full bar, exactly like before. Other tier-0 nodes cost one point. | `data/talents/<class>.json` (`starter: true`), `player.gd` |
| D2 | Primary attack | The LMB slot takes any unlocked skill tagged `primary_ok` (cooldown <= 1.2 s). Defaults: Fury Strike, Aimed Shot, **Frostbolt** for the Mage (Fireball's 2.5 s is too slow for LMB), Smite. | `data/skills/*.json` |
| D3 | Talent vs skill points | One pool: "talent points" unlock skills, rank up passives and buy keystones. The legendary tome gives +1 talent point. | `player.gd` |
| D4 | Passives and toggles | Passives (Feral Ferocity, Thrill of the Hunt, Crusader's Zeal) work as soon as they are unlocked and take no slot. Toggles (Mana Shield, Eagle Eye) take a slot and switch on and off (no cooldown beyond the GDD's 1-2 s). | `combat.gd` |
| D5 | Stat points | The class `per_level` growth is **halved** (data) and every level gives **5 free points** spent in the Character panel. No respec. Saved with the hero. | `data/classes/*.json`, `player.gd` |
| D6 | Legendary tier | Legendaries are **named uniques at tier 5**, shown as "Legendary" with the orange colour and a stronger glow. "Magic" = Uncommon in merchant text. No 6th tier. | `data/items/legendaries.json` |
| D7 | Legendary numbers | The GDD stats are the **level-30 values**, scaled linearly by item level (`legendary.scale_floor` + (1 - floor) x ilvl / 30, data). Flat-damage affix numbers scale the same way; percentages stay fixed. | `item_generator.gd` |
| D8 | Ring slots | Keep **2 ring slots**. Ring legendaries are unique: two copies of the same one cannot be worn. | `inventory.gd` |
| D9 | New weapon kinds | New bases: **quiver** (Ranger off-hand), **athame** (Mage 1H, main hand only), **scythe** (Priest 2H). Crosier = holy staff art. The Priest can use maces (Rebuke and Hammer of the Righteous are mace strikes). Grip of the Titan sets `two_hand_and_shield`. | `data/items/bases/` |
| D10 | Elites | Every floor rolls 1-3 **elite packs**: a named elite (+15% scale, x3 HP, +30% damage, 1-2 modifiers from `data/monsters/_elite_modifiers.json`), gold nameplate and glow. An **elite altar** appears where the elite dies (interact = book or loot). | `game.gd`, `enemy.gd` |
| D11 | Gold Key | Only on floors whose merchant is Archibald (#6): the floor rolls `elite.key_chance` (80% since #21) from the seed, on its own random stream (`Game.pick_key_carrier`), independent of how many elites the floor got. If it passes, exactly one elite carries the key; with no elite a chest does (the host remembers it in `key_chest` and drops the key when it is opened); with neither, the boss. So about 0.8 x 0.8 = 64% of all floors have a key (reading of #21: "80%" is per Archibald floor, since the key only matters there). It is a shared party item: Archibald trades with everyone once he gets it, and it is consumed. | `dungeon_generator.gd`, `game.gd` |
| D12 | Gold sharing | Every player has their **own wallet**. A gold pile picked up is split equally among all living party members. Saved with the hero. | `player.gd` |
| D13 | Demonic tithe | Paid **once per player per floor**, on the first entry, after a confirmation dialog. The loss is a run-permanent modifier (`run_mods`). | `merchant.gd` |
| D14 | Pact potion durations | The text duration where one is given (Void-Eye 45 s, Phantasmal 30 s, Serum 20 s), otherwise 60 s. | `data/items/pact_consumables.json` |
| D15 | Pact potion scale | The flat numbers are at hero level 30 and scale with hero level (same rule as D7). | `data/items/pact_consumables.json` |
| D16 | Serum of Damnation | HP cannot drop below 1 (statuses still apply). | `status_effects.json` `damage_floor` |
| D17 | Run | A run = a saved game until a wipe. Run modifiers live in the hero save (`run_mods`) and are applied by `Stats`. | `stats.gd` |
| D18 | Codex | Per profile (`user://codex.json`), **survives wipes** and new games. A Codex tab in the game menu and a main-menu entry. | `autoload/codex.gd` |
| D19 | Reading books | The inventory **Use** action (right click, or the pad's use button on the focused slot) opens the reader **for the reader only**. Tomes are consumed and grant their bonus to the reader (host-validated). | `inventory_panel.gd`, `lore_reader.gd` |
| D20 | Book drop rates | Roll the category first (80 / 18 / 2), then a book of that category from the floor's biome (+ "Ancient Lore" anywhere). Unread books (codex of the host) weigh x3. | `loot_manager.gd` |
| D21 | Floor order | Depth cycles Crypt -> Sewers -> Foundry -> Archives -> Kurgan -> Crypt (harder). The boss is a seeded pick from the biome's `bosses` list. | `game.gd`, `data/floor_types/` |
| D22 | Lava | Lava **lakes** (not walkable) and lava **channels / pools** (walkable, damaging). A player pushed into a lake takes 25% max HP and is put back on the last safe tile; monsters pushed in die. | `dungeon.gd`, `player.gd` |
| D23 | Blind | Player: vision radius shrinks to ~40 px plus a vignette. Monster: 50% miss chance and loses its target lock. | `visibility.gd`, `enemy.gd` |
| D24 | Silence | Blocks slots 1-5 and any primary with `school: spell`. Basic weapon primaries still work. | `combat.gd` |
| D25 | Fear / disorient / sleep | Fear: forced movement away from the source. Disorient: random wandering, no attacks. Sleep: stun broken by damage. Players get the same, plus diminishing returns per CC category (data). | `status_effects.gd` |
| D26 | Accuracy | `miss_chance` (default 0) is checked before dodge; accuracy debuffs add to it; "cannot miss" ignores it. | `combat.gd` |
| D27 | Block / parry | Shields add `block_chance` (frontal hits only, 120° cone) and `block_value` (flat reduction). Parry exists only through Riposte and the Overpower trigger. | `combat.gd` |
| D28 | Magic resist | `magic_resist` reduces every non-physical type; monsters have per-type `resist` and `immune`; `magic_pen` ignores a share of them. | `combat.gd` |
| D29 | Corpses | Dead monsters leave a host-side corpse record (position, id, time) for 20 s and a bone pile / corpse sprite. Abilities query and consume them. | `game.gd` |
| D30 | Movement-blocking terrain | A dynamic obstacle layer: AStarGrid2D solid points + StaticBody2D, host-spawned with a lifetime and replicated by an id'd spawn RPC. | `dungeon.gd` `obstacles` |
| D31 | Player copies | Reuse `CharacterSprite` with the copied hero's gender + appearance, tinted. Echoes of Regret keep a host-side 10 s ring buffer of positions and casts. | `enemy.gd` |
| D32 | Tome Prison | A prebuilt side arena inside the boss floor, not a new scene. A client-side monochrome post-process plus falling-ink telegraphs. | `boss_mechanics/dimension.gd` |
| D33 | Inverted controls / ink | Replicated status flags (`invert_move`, `ink_obscure`) read by the local input layer and an overlay shader. Gamepad and mouse are both affected. | `player.gd`, `hud.gd` |
| D34 | Revolving bookshelves | A door variant drawn as a bookshelf that opens by interaction. | `door.gd` |
| D35 | Heat armor loss | `-1 armor per 10 s` x level scaling (data), stacking up to -30%, reset 5 s after combat. | `floor_mechanics.gd` |
| D36 | Unlit regen penalty | Uses the light sampling: a player whose cell is below the light threshold has mana / fury regen halved. | `floor_mechanics.gd` |
| D37 | Hazards vs friendly fire | Biome hazards are environment damage and hit players and monsters, except where the GDD says otherwise (blood pools heal monsters). | `combat.gd` |
| D38 | Sludge-resistant footwear | Boots flag `terrain_immune` (Boots of Unstoppable March have it; a rare random boots affix too). | `data/items/affixes.json` |

### Implementation notes for the GDD rows

| Topic | Decision | Where |
| --- | --- | --- |
| D19 read action | **Accept / click** on a book reads it (right click and the pad's X already mean Drop in the inventory). | `inventory_panel.gd` |
| D11 key per floor | An unused Gold Key is lost when the party descends (the shop of that floor stays locked). | `game.gd` |
| Merchant chamber safety | Monsters never path into the chamber (its cells are solid in the monsters' A*), never pick a hero standing inside as a target, and never open its doors. The chamber may have open archways (the room generator can't always make doors). | `dungeon.gd`, `enemy.gd` |
| Placeholder registry | `tools/gen_placeholder_icons.py` draws placeholder icons and copies placeholder sounds into `data/assets_placeholders.json`; `GameData` merges `data/assets.json` over it, so registering real art in `assets.json` always wins and no generated key is ever written into the hand-kept registry. | `game_data.gd` |
| Contracts and pacts | Each player can sign each of the floor's two contracts once; pact potions cost their stats at purchase (not when drunk) and stack in the backpack one per slot. Archibald buys everything except gold, keys and pact potions; books sell by category. | `merchants.gd`, `balance.merchant` |
| Elite altar loot | An altar gives a book (60%) or one Uncommon+ item, plus gold; once per altar. Secret sarcophagi give 1-2 Uncommon+ items, a book 40% of the time and gold. | `loot_table.gd`, `balance.lore` |

### Class skills (phase 3) - deviations and readings of the GDD

| Topic | Decision |
| --- | --- |
| Primary attacks (D2) | The primaries keep the MVP economy: **no cost**, a small resource restore on hit (Fury Strike +10 Fury), cooldowns 0.55-1.0 s. The GDD's 10-15 mana primaries would drain a level-1 mana pool in ~13 s. |
| Numbers | "X% weapon damage" = coefficient X/100 on the school's power (weapon DPS + stat x 0.6), plus a small base. Cooldowns, costs, ranges and durations are the GDD's, except the primaries above. |
| Skill-level readings | Intimidating Roar makes every enemy in range flee (the "minions cower" nuance is dropped). Feral Ferocity stacks on any melee hit. Rallying Cry heals about the health it adds. Elemental Cataclysm refunds 30 Mana instead of making the spell free. Eclipse doubles spell damage after 3 Light charges. Lightwell heals allies below half health who stand in it (no click). Hammer of the Righteous' shockwave reaches 72 px. Shadow Word: Death recoil = 5% of your maximum health. Bone Harpoon reels you only to bosses. |
| Passives and triggers | Active skills can carry trigger procs (Overpower after a dodge / parry, Victory Rush after an XP kill, Aimed Shot's crit refund); they work once the skill is learned, slotted or not. |
| Icons | 120 skill / keystone icons come from 8 PixelLab Pixen icon sheets (4x4 icons of 32 px each, 1 generation per sheet), cut by `tools/cut_icon_sheet.py`. Passive talent nodes show their initials. |
| Skill VFX | New skills use the shared effect visuals (rings, beams, chains, zones, projectiles). Bespoke animated effects (vfx_workbench) are a later polish item. |

### The Crypt (phase 4) - readings of the GDD

| Topic | Decision |
| --- | --- |
| Architecture | Profile `labyrinth_vaults` (`generator` block of the floor type): corridors bend through a jittered midpoint, 4 extra loops, 40% of normal rooms are pillared halls (a pillar every 3 cells). Corridors stay 2 cells wide: doors need 2-3 cell openings and the 48 px monsters must pass. |
| Hazards | The Crypt has no lava pools and no cyclic floor spikes (MVP hazards; lava moves to the Foundry); explosive barrels stay as a rare prop. Pressure plates: 0-2 per normal room, only players trigger them, 0.35 s click, spikes on the 3x3 cells around (`spikes_damage` 14), 4 s re-arm. Pendulum scythes were removed after the playtest (#5). |
| Chilling Breath (D36) | "Unlit" = outside every gameplay light (wall / carried torches, lava, spell lights, lit shrines) except the hero's own faint vision glow, which exists on one machine only. Checked twice a second; halves Mana / Fury regeneration and generation. |
| Grave urns | 15% to release a 56 px miasma cloud: 4% of max HP per second for 4 s, nature damage, hurts monsters too (D37). |
| Skeletal Footman | Collapses into a bone pile at 0 HP and stands up after 4 s with 30% HP; only area damage (AoE, zones, explosions) breaks a pile, and a killing blow from an area attack leaves no pile. |
| Crypt Ghoul | Pounces on the furthest player within 280 px every 9 s (0.6 s stun); devours a corpse within 150 px (1.2 s channel): +50% HP and Feeding Frenzy (+40% haste). |
| Tomb Cultist | Every 8 s, a 2 s chant raises a fallen footman / archer within 150 px at 50% HP (interrupted by any CC). |
| Dread Wight / Banshee | The door-shield takes 70% less damage in a 120 degree front arc (not DoTs). The Banshee takes 50% less physical damage; its shriek (200 px) silences for 2.5 s and snuffs wall torches for good and carried torches. |
| Carrion Crawler | Burrowed it is an untargetable mound moving 1.6x faster; under its target it bursts out (area damage + 2 stacks of Paralyzing Venom), fights for 6 s, burrows again. |
| Morvath | P1: Crushing Stomp (3 expanding rings), Ossuary Cage every 16 s (4 bone spear props, 22 HP each; the victim is rooted; after 6 s an execution deals 60% of max HP as true damage). P2: a bone shield of 25% max HP + 3% per skeleton corpse in the arena, sarcophagus lids under every player every 8 s (1.5 s red telegraph, the lid stays as cover for 8 s), Bone Whirlwind every 14 s for 4 s (reflects projectiles, pulls players in). His summon raises Skeletal Footmen. |
| Vespera | P1: Black Anointing every 12 s (5 s brand, 80 px, damage x (1 + allies inside)), Vermin Swarm every 15 s (3 s blind, carried torches out). P2 below 40%: every 40 s she flies for 20 s (melee can't reach her) while Chant of the Damned ramps on the party; two consecrated shrines rise at the arena's east and west edges, lighting both grounds her with a 3 s stun. |
| Boss pick | The host picks the floor's boss from the floor type's `bosses` list with the floor seed and sends the id with the floor build (tests pin one with `--boss=<id>`). Boss music comes from the boss's `music` key. |
| Art method | Monsters: PixelLab v3 characters (48 px; Vespera 72 px), template animations on 5 drawn directions, W / NW / SW mirrored (`tools/build_monster.py`). Props: `create_map_object` (1 generation each), trimmed; lit / open variants (shrine, Gilded Portal) are recoloured copies, not generations. |

### The Sewers (phase 5) - readings of the GDD

| Topic | Decision |
| --- | --- |
| Architecture | Profile `aqueducts`: winding corridors, 60% of normal rooms get a ragged pool of shallow sewage (half of them with a deep-sludge core), 35% get a 2-cell toxic canal across the room with a 2-cell catwalk; a canal never ends in a door, so connectivity holds. 30% of doors become floodgates with a rusty lever on each side (pulling one opens it for good; monsters can't pass a shut floodgate). |
| Cell kinds | `water` (walkable, A* weight 2), `sludge` (walkable, weight 2), `canal` (blocks movement on physics layer 128 only: sight, shots and spells pass), `bridge` (walkable). Shared by later biomes (lava lakes, grates). |
| Sewer Rot & Sludge Drag | Wading (water or sludge) = -25% movement unless the boots have `terrain_immune` (D38); deep sludge adds a Blighted Taint stack each second (-5% healing received, max 10); 3 s on dry stone clears it. Players only (monsters are at home here). |
| Sewer mist | The floor type's `vision_mult` 0.8 scales the FOV radius and the monster sight range. |
| Hazards | Acid spouts in any room wall spray 3 cells into the room on the floor clock (35% of a 5 s cycle, 8 nature damage + Corroded). Gas pockets go off when a hero comes within 34 px or hits them (70 px nature burst; monsters too). |
| Monsters | Ratman: below 30% it backflips 130 px and throws a blinding flask (once). Acid Slime splits into 3 Slimelings (60% size). Bloated Drowner: a 0.6 s swell at 50 px, then a burst + 10 s poison pool; killed early it still bursts. Flesh-Stitcher: every 8 s Foul Serum on nearby beasts (+30% damage, CC immune, bigger). Gutter Stalker starts submerged (stealthed, invisible), its first hit is a guaranteed crit (stealth rule), it re-submerges after 6 s without a hero near. Sludge Lobber: a mortar landing after 1.2 s anywhere (over walls) with a 5 s rooting mud zone. Abyssal Leech: latches (rides along, no dodge), drains 10 Fury / 15 Mana a second and keeps biting; another hero's melee hit knocks it off (1.5 s stun). |
| Murk Amalgam | P1: Tidal Flush every 18 s (2.5 s warning; three raised platforms in the arena are safe), Engulf every 22 s (the current target is swallowed for up to 8 s with acid ticks; 500 damage x the boss's HP multiplier from the party frees them, else 45% max HP). P2 at 50%: the core hides and the Bile Twin (immune to physical) and the Gristle Twin (immune to magic) take over; the boss dies when both twins are dead. |
| Krazik | P1: rides an ellipse along the arena edge; a green fog rises over time (party DoT by level, up to 8) and venting any of 3 exhaust valves clears it; every 20 s the Bell of Heresy sends a tinted phantom copy of every hero (12 s). P2 at 30%: the mount falls (on-foot sprite, +25% speed, +20% haste), incendiary flasks, a horde of 8 plague rats every 12 s. |
| Floor order (D21) | Floor types carry an `order` (Crypt 1, Sewers 2, ...); depth cycles in that order. Tests and tours pin a first floor with `--biome=<id>`. |

### The Foundry (phase 6) - readings of the GDD

| Topic | Decision |
| --- | --- |
| Architecture (D22) | Profile `platforms`: 55% of normal rooms become a molten lake (walkable lava that burns, A* weight 25) with a central platform, a platform at every door and 2-cell railing-less metal bridges from each door to the centre. Lava stays walkable on purpose: a knockback or a missed step lands you in it (the GDD's "knocked into the lava"). |
| Hazards | Collapsing grates (0-2 per normal room): a hero standing 0.8 s on one drops it - the cell turns to lava for 6 s (replicated by `Dungeon.set_cells`). Wall flame jets share the spout code with the Sewers' acid spouts (`wall_spout.gd`, numbers per kind in `balance.hazards.spouts`). Boiling cauldrons splash 56 px every 6 s. |
| Abyssal Heat (D35) | -3% armor per stack, a stack every 10 s while a monster with aggro is within 360 px, up to 10 stacks (-26%); 5 s out of combat clears it. |
| Magma Geysers | Every 6-10 s the lava nearest a hero (8 cells) lobs 3 globs at them: 1 s telegraphs, then burning floor for 5 s. |
| Monsters | Ash Imp blinks 140 px away when a hero gets within 56 px (5 s cooldown); its bolts leave burning patches. Magma Carapace: -60% physical until frost damage or a melee blow from a mace, warhammer or shield shatters the shell for good. Taskmaster: a red-hot hook pulls the hero in (negative knockback) and brands them. Brimstone Hound: leap + a fire cone stacking Scorched Armor (-15% armor per stack). Iron Punisher: permanently CC immune, its hammer (250%) shatters absorb shields. Hellfire Cultist: magma glyphs (2.5 s) and a heat shockwave when it dies. Flame Revenant: no wall collision, flies straight at its target, leaves a 4 s fire wall every 2.5 s, lava doesn't hurt it. |
| Ignis | P1: Anvil of Doom drops 4 white-hot ingots (obstacles that block everything, cover for 18 s); Slag Overflow telegraphs half of the arena and burns it for 6 s - standing next to an ingot ("high ground") is safe. P2 at 50%: White Heat (+50% haste) and 30% of every melee blow sears the attacker; a permanent fissure (burning terrain) opens under his target every 7 s. |
| Vulkania | P1: she dives (untargetable) for 7 s and surfaces for 7 s; while under, geysers erupt under every hero; Tail Sweep is a 180 degree cone with a big knockback. P2 at 60%: every 10 s boulders turn another outer ring of the arena into lava (2 rings, about 30% of a 19x15 arena); Molten Stare inflicts Molten Blood, a strong burn that drinking any potion (or a magic cleanse) puts out. Her lake is read as the arena itself: she rises and dives in place. |

### The Archives (phase 7) - readings of the GDD

| Topic | Decision |
| --- | --- |
| Architecture | Profile `library_grid`: half of the normal rooms get rows of bookshelves (they block sight) every 3 rows with a 3-cell aisle; 30% of large rooms become round reading rooms (cells outside an ellipse turn to wall, 2-cell aisles keep every door joined to the centre); 25% of doors are revolving bookshelves (D34: a door drawn as a bookshelf, "Turn the bookshelf"). |
| Spatial anomalies | 30% of normal rooms are anomaly zones: every skill cast by a hero inside rolls its cost x0.7-1.3, shown above the hero ("Cost x1.15"). |
| Hazards | Void Rifts (2-4 per floor): permanent zones that pull everyone within 110 px and burn with shadow. Silence Runes (3-6): one-shot floor traps, 3 s silence. Animated books: when furniture breaks, every bookshelf within 120 px either fires 3 rune bolts at the nearest hero or bursts (60 px arcane). |
| Monsters | Mimic: a lectern until a hero comes within 40 px (or hits it); its bite bleeds and silences. Astral Warden: a 4 s prism (100% projectile reflection) every 10 s. Void Weaver: 3 one-hit phantoms that cast weak missiles and have no ground shadow. Cursed Scribe: tethers the two nearest heroes for 8 s, each loses 3 Intellect and 3 Strength every 2 s (up to 5 stacks). Gargoyle: a statue (untargetable) that dives on a hero casting or channelling within 300 px (or anyone within 90 px), interrupting. Echo of the Unwritten: spawns wearing a random hero's look and fights with a small kit of that class. Ink Horror: an invulnerable pool that flows behind its target, surfaces for 4 s; its lash blots the hero's screen (ink overlay) for 3 s. |
| Malazar | P1: Forbidden Inversion every 15 s, alternating inverted movement (4 s) and inverted healing (direct heals deal damage); Rune of Damnation paints 7 armed runes that detonate when stepped on. P2 at 50%: Tome Prison (D32) - the party is moved into a sealed side arena carved in the floor (monochrome screen shader, ink drops every 1.4 s), Malazar is out of reach; breaking the 4 Authorial Seals returns everyone and the Archivist takes +50% damage. If a floor rolled no room for the side arena the prison happens in the boss room; after 40 s the prison collapses on its own (30% max HP to the party, no weakness). |
| Memory Devourer | P1: Chronostasis zones (-70% movement, -70% haste, -70% projectile speed for the hero's own shots); Echoes of Regret (D31) - a 10 s ring buffer of each hero's position and facing; their echo replays the old path for 6 s and fires a shadow bolt along the old facing every second. P2 at 45%: Death Paradox - a downed hero leaves a temporal prism (40 HP, heroes only) that blasts the whole party after 6 s unless shattered; laser grids of 3 lines sweep the arena every 9 s after a 1.2 s telegraph. |

### The Kurgan (phase 8) - readings of the GDD

| Topic | Decision |
| --- | --- |
| Architecture | Profile `caverns`: in 70% of normal rooms a 2-cell rim is randomly walled, smoothed by two cellular-automata passes, and pockets cut off from the centre are filled; door zones and the core never change, so the floor stays connected. Thorn bushes and petrified trees block sight. |
| Ground fog | The floor type's `torch_radius_mult` 0.65 shrinks wall torches and carried torches (-35%). |
| Blood-Cursed Earth | Every slain monster leaves a 36 px blood pool for 20 s: monsters inside regenerate 3% max HP a second, heroes take 5% of their melee weapon power a second as physical damage. Swarm critters and summons leave no pool, and bosses regenerate at 20% of the rate (balance pass: Isolde's own blood ticks burst into pools that healed her faster than a party could hurt her). |
| Sprouting thorns | Every 8 s, if a hero is fighting (a monster with aggro within 300 px), a 3-cell thorn wall rises 56 px from them for 6 s (blocks movement and shots). |
| Hazards | Root snares (4-8 per floor): one-shot traps, 2 s root + bleed. Dread Totems (a prop): a 120 px fear wave every 12 s; breakable. |
| Monsters | Bloodhound: ignores threat for the nearest bleeding hero in 360 px and runs at double speed at heroes below 40% HP. Brier Thrall: 12 thorn projectiles in a ring when it dies. Barrow Hag: Wither Hex (6 s) turns 5% of the hexed hero's max HP a second into absorb shields on monsters within 220 px. Rotwood Treant: knockback-immune, a stake line (damage + bleed + a 6 s stake wall). Abomination: a tendon grapple reels the hero in (negative knockback + 0.6 s stun), its maw drains health. Will-o'-the-Blight: erratic flight; within 60 px it blinds and detonates the hero's remaining Mana / Fury as physical damage (8 s cooldown). Bramble Warden: camouflaged (stealthed, invisible) until it shoots; barbed javelins bleed and cripple. |
| Cernunnos | P1: four stone dolmens stand in the arena; Antler Stampede every 14 s charges straight at a hero, smashing dolmens on the way; slamming a wall stuns him 3 s. Creeping Briar: every 60 s the outer ring of the arena becomes living briar (2 rings at most, about 10% of the arena each). P2 at 50%: he drinks every corpse in the arena (+15% max HP, again every 30 s); Shower of Thorns every 12 s hits every hero not within 36 px of a dolmen (new dolmens rise if fewer than 2 stand). |
| Isolde | P1: Blood-Thread Bond links two random heroes for 10 s; more than 150 px apart and it snaps for 90% of both heroes' max HP (needs 2 living heroes). Brood Nursery hatches 4 blood ticks every 14 s (they latch on and burst after a 3 s fuse). P2 at 40%: the cocoon tears (spider sprite), permanent Frenzy of the Feast: +100% leech (every hit heals her for the damage dealt), +25% haste, +15% damage, CC immune. |

### Legendaries (phase 9) - readings of the GDD

| Topic | Decision |
| --- | --- |
| Data | `data/items/legendaries.json`: 108 items (27 per class), each with GDD stats, affix text, `mods` (stats or per-skill modifiers), `flags`, `procs` (the shared proc system: event, `if`, `icd`, effect list or a `hook` in `scripts/items/legendary_affixes.gd`) and a `test` block run by `tests/legendary_suite.gd`. |
| Scaling | The GDD numbers are the level-30 values. Stats and flat proc numbers scale with the item level: `scale_floor + (1 - scale_floor) * min(level / 30, 1)` with `balance.legendary.scale_floor` 0.35. Percent effects never scale. |
| Drops | Legendary (Relic, tier 5) chance per source in `balance.legendary.drop_chance`: boss 40%, elite 6%, secret 5%, altar 5%, chest 2%. Classes in the party weigh x3 (`party_class_weight`), any class can drop. |
| Unique rings (D8) | Two copies of the same legendary ring cannot be worn. |
| Quiver | New off-hand base `quiver` (ranger) that can be worn with a two-handed bow / crossbow. Titan's grip (warrior) lets a two-handed weapon and a shield be worn together. |
| Slippers of Grace | Heroes already move at full speed while casting, so the "does not slow" part is always true; the flag also keeps healing channels alive while moving. |
| Boots of the Flame Trail | The burning trail zones are lit like every zone (they count as light for the darkness rules). |
| Vestment of the Merciful Mother | When Power Word: Shield breaks or runs out it heals the target for 100% of the shield's starting value. |
| Stormweaver Grips | The stacks (max 3, -20% cost each) are spent by the next cast. |
| Wasteland Marksman Hauberk | Standing still 1.5 s keeps a short "Steady Aim" buff refreshed (+50% to the next shot); moving lets it lapse. |
| Tome of Dire Anathema | A healing spell aimed within 32 px of an enemy (in range) deals twice the heal as shadow damage to it instead of healing. |
| Void Needle Athame | Drain Soul also hits the enemy nearest the first target (within the skill's range). |
| Visage of the Dark Singularity | Paranoia (3 s, charm DR) makes the monster change sides: it fights the nearest monsters and heroes cannot hurt it until it ends. Bosses keep their side (their arena mechanics assume it); CC-immune monsters ignore it. |
| Exorcist's Iron Striders | Checked on the 1 s aura tick: undead / demons within 30 px are stunned 1 s and take 100 (scaled) holy damage. |

### Balance pass (phase 10)

(Updated by the playtest fixes: see "#8 Balance" below for the hero level, the depths and the
current numbers.) The GDD gives no pacing targets, so the balance pass measures and records them instead of guessing.
`tests/balance_suite.gd` (suites `balance-<class>`) puts a hero of level = depth in rare gear of that item
level, all stat points in the main stat, against every monster and both bosses of the biome at depths
1, 2, 3, 4, 5, 8, 12, 16, 20, using the real host damage code (primary attack only, monster behaviour
modules off). Bands in `balance.json` "probe": a normal monster dies in 0.3-12 s (one-hit critters under
20 HP excepted) and needs at least 4 s to kill the hero; a boss takes 12-240 s alone and at least 3 s to
kill the hero. Results (2026-10-16): normals 0.5-8 s to kill, bosses 17-53 s for one hero with the
primary attack only (more players scale boss HP by +70% each, skills and talents shorten it), the
fastest boss kill on a hero is about 11 s (Vulkania / Ignis on a mage). All four classes are inside the
bands. The one change the pass needed: blood pools (Kurgan) no longer let a boss heal from its own
hatchlings (see "The Kurgan").

### Skill groups per talent branch (D1)

Tier in brackets. **Bold** = starter (free) skill.

| Class | Branch A | Branch B | Branch C |
| --- | --- | --- | --- |
| Warrior | **Berserker**: **Cleave** (0), Bloodthirst (0), Feral Ferocity (1), Victory Rush (1), Whirlwind (2), Berserker Rage (2), Overpower (3), Mortal Strike (3), Execute (4), Avatar (5) | **Juggernaut**: **Fury Strike** (0), **Shield Slam** (0), **Taunting Shout** (0), Riposte (1), Stoneform (1), Thorns of Steel (2), Shield Wall (2), Devastate (3), Iron Will (4), Last Stand (5) | **War Leader**: **Deadly Charge** (0), **Battle Cry** (0), Hamstring (1), Heroic Throw (1), Earthshaker (2), Skull Crack (2), Armor Sunder (3), Intimidating Roar (3), Heroic Leap (4), Rallying Cry (5) |
| Ranger | **Sniper**: **Aimed Shot** (0), **Power Shot** (0), **Multishot** (0), Hunter's Mark (1), Piercing Bolt (1), Rapid Fire (2), Double Tap (3), Eagle Eye (3), Trickshot (4), Shadow Ballista (5) | **Toxicologist**: **Viper Arrow** (0), **Snare Trap** (0), **Explosive Trap** (0), Arterial Shot (1), Acid Flask (1), Caltrops (2), Serpent's Grip (2), Rain of Arrows (3), Gore Arrow (4), Venomous Vapors (5) | **Shadow Strider**: Disengage (0), Bola Throw (0), Shadow Flare (1), Concussive Blast (1), Smoke Screen (2), Tranquilizer Dart (2), Thrill of the Hunt (3), Survival Instinct (3), Bone Harpoon (4), Shadow Meld (5) |
| Mage | **Pyromancer & Stormcaller**: **Fireball** (0), **Chain Lightning** (0), **Meteor Strike** (0), Flame Wave (1), Static Charge (1), Combustion (2), Lightning Orb (2), Living Bomb (3), Thunderstorm (4), Time Warp (5) | **Glacial & Tectonic Warden**: **Frostbolt** (0), **Frost Nova** (0), Earth Spike (1), Ice Barrier (1), Granite Armor (2), Deep Freeze (2), Tremor (3), Mana Shield (3), Blizzard (4), Boulder Crush (5) | **Void & Solar Weaver**: **Blink** (0), Shadow Bolt (0), Luminance (1), Dark Bargain (1), Drain Soul (2), Blinding Radiance (2), Counterspell (3), Grasp of the Void (3), Solar Prism (4), Singularity (5) |
| Priest | **Divine Shepherd**: **Flash Heal** (0), **Power Word: Shield** (0), **Prayer of Healing** (0), Renew (1), Purify (1), Leap of Faith (2), Holy Nova (2), Lightwell (3), Guardian Spirit (4), Apotheosis (5) | **Paladin Bastion**: **Consecration** (0), **Rebuke** (0), Divine Aegis (1), Judgement (1), Hammer of the Righteous (2), Blessing of Might (2), Crown of Thorns (3), Crusader's Zeal (3), Bastion Sigil (4), Martyrdom (5) | **Dark Inquisitor**: **Smite** (0), Shadow Word: Pain (0), Holy Fire (1), Mind Blast (1), Chastise (2), Penance (2), Exorcism (3), Shackle Undead (3), Vampiric Embrace (4), Shadow Word: Death (5) |

The MVP skill ids are kept (saves and tests reference them) and renamed: `warrior_strike` = Fury Strike,
`warrior_shield_bash` = Shield Slam, `warrior_charge` = Deadly Charge, `ranger_shot` = Aimed Shot,
`ranger_poison_arrow` = Viper Arrow, `mage_bolt` = Frostbolt, `mage_lightning` = Chain Lightning,
`mage_meteor` = Meteor Strike, `priest_heal` = Flash Heal, `priest_holy_shield` = Power Word: Shield,
`priest_renewal` = Prayer of Healing.

### Biome art (after the phase-4 checkpoint)

The user approved the Crypt's look, scale and method on 2026-10-16. The other four biomes use the same
style at a lower cost per monster:

| Topic | Decision |
| --- | --- |
| Humanoid monsters and bosses | PixelLab v3 characters (48 px, bosses 64 px), **three** template animations (walk, attack, death) on 5 drawn directions, W / NW / SW mirrored: ~17 generations instead of the Crypt's ~22. Idle is two walk frames, hit is the start of the death fall, downed its last frame, cast and dash reuse attack and walk. Casters attack with the `fireball` template, the sludge lobber and bramble warden with `throw-object`. Built by `tools/build_monster_zip.py` from the character download. |
| Shapeless creatures | Slimes, leeches, the ink horror, the mimic, rats, ticks, the wisp, the Murk Amalgam, Krazik on his mole-rat, Vulkania, the magma carapace, the brimstone hound and Isolde's spider form are one PixelLab map object each (1 generation), animated by `tools/build_blob.py` with squash / stretch / bob / fade frames on all 8 rows (mirrored for the facing). |
| Reuse | Hellfire cultist = cultist (tinted), barrow bloodhound = brimstone hound (tinted), Krazik on foot = plague ratman (larger, tinted through the new phase `tint`), the Amalgam twins = the Amalgam (scaled, tinted), void phantoms = the void weaver, the gargoyle statue = the gargoyle's rotation in grey, the rusty lever "on" = the lever flipped. |
| Tiles | One `create_tiles_pro` call per biome (16 tiles of 32 px), cut into the same 4x3 atlas layout as the Crypt. |
| Props | One `create_map_object` per prop (46), trimmed by `fetch_props.sh`; open / used variants generated or derived. |
| Sources | Every PixelLab id is listed in `tools/biome_art_sources.json` so a sheet can be rebuilt. |

### Budget deviation (PixelLab)

(Superseded by the user's checkpoint approval and a later Tier 2 upgrade; kept for the record.) The goal caps PixelLab spend at 2500 generations, but the account had **919** left at the start
(used 1081 of 2000, reset 2026-11-14), and the plan estimates 2000-2800 for all art. Art is therefore
spent **Crypt first** (phase 4, then the visual checkpoint), and every asset the allowance cannot cover
stays a placeholder (recolours / scaled reuse of existing monsters, drawn shapes, workbench art) with its
key in `data/assets.json`, so the user can swap files later without code changes. The ledger is in
`docs/TODO.md`.

## Playtest fixes (GitHub issues #1-#14)

### #1 Simple start

| Topic | Decision |
| --- | --- |
| Starting kit | A new hero knows only the primary attack and ONE basic skill (class data `skills`): Cleave, Power Shot, Fireball, Flash Heal. Slots 2-5 start empty (`""`); a loadout may hold empty slots, never in slot 0. |
| Other tier-0 skills | The old free starters (Shield Slam, Taunting Shout, Deadly Charge, Battle Cry, Multishot, Viper Arrow, both traps, Frost Nova, Chain Lightning, Blink, Meteor Strike, Power Word: Shield, Consecration, Rebuke, Prayer of Healing) are ordinary tier-0 skill nodes: one talent point each, learned in the tree and slotted in the Skill Book. Talent data marks them `legacy_starter`. |
| Old saves | A character saved without `"kit"` is a hero from before the simple start (`Player.legacy_kit`, replicated): its `legacy_starter` nodes stay free and unlocked, so its saved loadout is kept. New heroes are saved with `"kit": 2` (`GameState.KIT_VERSION`). |
| Easy first floors | `balance.json` `scaling.early_depths` scales monster and boss HP / damage on depths 1-3 (0.65 / 0.5, 0.75 / 0.4, 0.9 / 0.7). The balance probe's fresh-hero pass (`BalanceSuite.run_fresh`) checks a brand-new level 1 hero, primary attack only, against every monster and boss of the floor 1-2 pools: each normal monster dies within `probe.fresh_ttk_max` (8 s) and needs at least `probe.fresh_ttd_min` (16 s) to kill the hero alone; each boss dies within 150 s and needs at least 6 s. |

### #2 Telegraphed leaps and charges

| Topic | Decision |
| --- | --- |
| Wind-up | A skill's `windup` (s, data) is a cast time that haste cannot shorten. Pounce, Blazing Leap, Shield Charge 1.0 s, Stone Dive 1.1 s, Echoed Charge 0.9 s; Cernunnos's Antler Stampede `windup` 1.2 s (boss data). During it the monster stands still under a cast bar. |
| Ground marker | `CombatFx.windup_marker` (reliable RPC, so every peer draws it): a leap marks its landing circle (radius of its landing blast), a charge its whole path, both computed from the aim locked at the start of the wind-up, which is where the move goes. |
| Grace | `ai.lunge_grace` (1.5 s): a monster refuses leaps and charges until that long after it first noticed a hero (`Enemy.aggro_age`); the ghoul retries on its next think, the gargoyle wakes without diving and dives through its normal AI once the grace is over. |
| Damage | Landing / path damage lowered (Pounce 2 + 0.9x, Blazing Leap 2 + 0.85x, Stone Dive 2 + 1.0x, Shield Charge 2 + 0.7x). The monster suite checks that even a crit at monster level 1, without the floor-1 easing, stays below the lowest fresh level 1 hero's health. |

### #3 The carried torch

Only its burn-out time (`lighting.carried_torch_duration`) ends a hero's carried torch. The `extinguish`
effect (Banshee's Mournful Shriek) snuffs wall torches only, and Vespera's Vermin Swarm only blinds. No
status, monster skill, boss or floor mechanic touches `torch_left`; wall torches can still be broken
(projectiles, the shriek) or taken. Tests: the monster suite (a shrieked hero keeps the torch), the
Vespera mechanic check (the swarm leaves the torch burning) and the `test_extinguish` primitive.

### #4 Burrowing and hidden monsters

| Topic | Decision |
| --- | --- |
| Carrion Crawler (`burrow`) | While it hunts a target it stays underground for at most `under` 2.5 s per dive (the clock includes the `warn` 0.6 s surfacing telegraph; a crawler with no target lies dormant and its clock waits). It moves at its walk speed (`speed_mult` 1.0, capped at 1), surfaces next to its target or when the time is up after a ground marker (the same `windup_marker` as #2), bursts out, and stays up for `surface` 5 s (never below 4) before the next dive. |
| Gutter Stalker / Bramble Warden (`submerged_stealth`) | The same rules for their stealth statuses: at most `under` 2.5 s hidden while hunting, a `warn` 0.6 s marker before they surface (in reach of their target or when the time is up), then their first ability - still a critical strike from stealth - and at least `surface` 4 s above before they can hide again (plus the old `rest` 6 s with no hero within 120 px). While hidden and hunting they neither attack nor switch targets; a hit reveals them at once. |
| Vulkania | Her magma dive is a boss phase mechanic (she stays in place, geysers telegraph), not a burrowing behaviour, and is unchanged. |

### #5 No pendulum traps

The Crypt's pendulum scythes are removed completely: `pendulum.gd`, the generator placement, the
dungeon / game wiring, the floor data (`pendulums`), the balance keys (`hazards.pendulum_*`), the
`props.pendulum` asset key and placeholder, and their tests and screenshot. The PixelLab PNG stays on
disk (`assets/sprites/pixellab/props/pendulum.png`, user assets are never deleted). The biome suite
checks that the generated floors of every biome have none. Crypt layouts differ from before for the same
seed because the generator no longer draws random numbers for pendulums.

### #6 One merchant per floor

| Topic | Decision |
| --- | --- |
| Pick | Every floor has exactly one merchant, Archibald or Malphas: a seeded pick (`DungeonGenerator.pick_merchant`, its own random stream) weighted by `merchants.json` `floor_pick` (4 : 1, i.e. 80% Archibald / 20% Malphas since #21; was 1 : 1). The host sends it with the floor (`Game._build_floor`), so every peer builds the same one; tests pin it with the `force_merchant` meta. |
| Room | The generator places one extra room per floor and makes it the merchant room (the candidate closest to 11 x 9 that has an ordinary door; a candidate without a 2-3 cell door is skipped). The merchant stands in its middle. It stays safe ground: no monsters, hazards or loose props, monsters never path in or target a hero inside, and its doors are ordinary doors that monsters don't open. |
| No portal, no altarpiece | The Gilded Portal and the Demon Altarpiece are gone (their props; the PNGs stay on disk). Archibald trades once the party hands him the floor's Gold Key (talking to him uses it up); Malphas asks for the tithe when a hero first talks to him. Buying / selling only works on an Archibald floor, the tithe, contracts and pacts only on a Malphas floor. |
| Gold Key | The key carrier only exists on Archibald floors (80% of them since #21, see D11). |
| Cave rooms | Building the extra room exposed a generator bug: Kurgan cave rooms could wall off a corridor that entered through a wide opening. The cells where a corridor enters a cave room now stay open. |

### #7 Doors and props in the light

Door and prop sprites were drawn on the `SELF_LIT` layer (lit, never shadowed) so their own
occluders would not black them out, which made them glow flat-bright wherever any light reached them,
even through walls and inside shadows. They are now on `LIT`, like the walls and floor, and their
occluders moved off the art: a 4 px band across the top of the drawn sprite (props: the width of the
footprint; horizontal doors: the opening) or, for side doors drawn edge-on, a line down the middle of
the opening. Light from the front reaches the whole door or prop, light from behind is blocked, and the
opening stays closed to light (a closed door may let a few pixels of light into the cell just behind
it). The screenshot tour `--scenario=tour --tour=lighting --biome=<id>` shows a door beside a wall
torch, a door beside the carried torch and a prop beside the carried torch; all five biomes were
reviewed at 1280x720. Characters, wall torches and wall spouts stay on `SELF_LIT`; no prop or door
uses an additive material (the additive ones are particles, the portal and item glows).

### #8 Balance: weaker early monsters, monster tiers, 2-3 levels per floor

| Topic | Decision |
| --- | --- |
| Kill XP | `Game.kill_xp`: base XP x `progression.xp_mult` 0.55 x monster level ^ `monster_xp_exponent` 1.25 (it grows with the XP a level needs, so a floor is worth about the same number of levels at any depth), x `elite.xp_mult`, divided by `1 + count_per_extra_player x party_xp_share (0.6) x (players - 1)`: a bigger party faces more monsters, so each hero's share is evened out (not fully, because elites and the boss don't multiply). Everyone who contributed still gets the full share. Replaces `monster_xp_per_level`. |
| Levels per floor | `BalanceSuite.run_progression` clears floors 1-5 kill by kill with the game's own `kill_xp` / `monster_level_at` (packs, elites, the boss; splitting slimes and summoned adds are left out), 4 seeds, solo and 4 players. Band `probe.levels_per_floor` [2, 3]. Result (2026-10-16): solo +2.51, +2.25, +2.64, +2.69, +2.27; four players +2.42, +2.19, +2.57, +2.52, +2.07. Solo level at the start of depths 1-12: 1, 3.5, 5.8, 8.4, 11.1, 13.3, 15.3, 17.3, 19.4, 21.8, 24.1, 26.0 (cap 30 around depth 14). |
| Monster level and scaling | `scaling.level_per_depth` 1.25 (was 1.0): monsters stay about the party's level at the new pace. Per level +36% HP and +18% damage (was +22% / +14%): the party now levels 2.5 times faster, so the same hero-vs-monster relation needs steeper per-level steps. `Game.spawn_mults` is the one place that builds the spawn multipliers. |
| Easier first floors | `scaling.early_depths` (normal HP / damage / boss HP): depth 1 0.55 / 0.5 / 0.65, depth 2 0.55 / 0.4, depth 3 0.42 / 0.45 / 0.6. A normal monster at the party's mid-floor level against the numbers before the playtest fixes (one level per floor, the old formulas): floor 1 HP x0.75 / damage x0.59 (was x1.00 / x1.00), floor 2 x1.14 / x0.62 (was x1.44 / x1.28), floor 3 x1.33 / x0.94 (was x1.66 / x1.42). The balance probe checks every floor is at least 15% lower on both. |
| Tiers | Every monster has a `tier` (1 basic, 2 stronger, 3 the biome's heavies: Dread Wight, Gutter Stalker, Magma Carapace, Iron Punisher, Astral Warden, Barrow Abomination, Rotwood Treant). `scaling.tier_depths` [1, 3, 6] are the first depths of tiers 1, 2, 3: floors 1-2 spawn only tier 1, tier 2 joins on depth 3, tier 3 on depth 6 (the second lap of the biomes). `DungeonGenerator.spawnable` gates the packs, the balance probe and the fresh-hero probe. Summons, splits and boss adds ignore tiers. |
| Item level | Drops, chests, altars, gold and Archibald's stock use `Game.item_level()` (the monster level, capped at 30), so items follow the same curve. |
| Upgrade drops | `loot.upgrade_chance` 0.03: an equipment drop comes `loot.upgrade_levels` [2, 3] levels above the item level (never past the cap) and `loot.upgrade_rarity` 1 tier higher (at most Relic); the required level comes with it, so it is an item to grow into. The economy suite checks the rate over 20 000 seeded rolls and on chest loot. |
| Pacing bands | The probe now puts the hero at the progression curve's mid-floor level in rare gear of the floor's item level and measures only the monsters that can spawn there, on depths 1-10, 12, 16, 20 (tier 3 first appears on 6-10). The one-hit floor (`normal_ttk_min`) applies from `normal_ttk_min_from_depth` 4: on the eased floors 1-3 trash may die to one hit. Vespera's HP 880 -> 1150 and the ash imp's 32 -> 38 keep them in the bands. All four classes pass. |

### #9 The priest strikes in melee

| Topic | Decision |
| --- | --- |
| Primary | The priest's primary attack is Holy Strike (`priest_holy_strike`): a melee arc like Fury Strike (48 px, 100 degrees, up to 3 enemies, 1 + 1.0x, holy damage, 0.7 s, 3 mana on hit). It is a melee hit (melee procs, reflection) but its power comes from Intellect: a skill's `power_school` picks the power stat when it differs from its school. |
| Known from the start | A class's primary attack is always known (`Player.unlocked_skills`), so Holy Strike needs no talent node; the priest's tree keeps its 30 skills. |
| Smite | Smite stays a tier-0 Dark Inquisitor skill node, now learned for one point (`legacy_starter`: free for priests saved before, so their loadouts with Smite as the primary keep working). It is still `primary_ok`. |
| Doors | A hero's melee swing (any class) bursts a closed door in its arc open, so a melee primary meets props, barrels and doors alike; rusted floodgates stay shut and monsters' swings don't open doors. |

### #10 Starting weapons

A new hero (`GameState.new_character` -> `starting_equipment`) wears only underwear plus the class's
Common starting weapon from class data `starting_weapon` {base, name}, item level 1, in the main hand:
warrior Worn Sword (1H `sword`), ranger Short Bow (2H `bow`), mage Apprentice Wand (2H `arcane_wand`),
priest Acolyte Staff (2H `holy_staff`). Their worn art (`weapon_sword`, `weapon_bow`, `weapon_wand`,
`weapon_staff`) already exists, so the weapon shows on the sprite at once. Heroes saved before keep
their saved equipment. CLAUDE.md's "characters start in their underwear" now means underwear plus this
one weapon.

### #11 Item comparison

The backpack item card compares an item with everything equipping it would take off
(`Inventory.replaced_by`, the same slot rules as equipping): a 2H weapon against the main hand and the
off hand together (their DPS, armor and stats are summed, so the off-hand relic's stats show as red
losses), an off-hand item against a worn 2H weapon, a 1H weapon against the 2H weapon it would replace
and against nothing when it goes into the empty left hand. The header reads "vs A + B".

### #12 The Amalgam's grab and the arena guard

| Topic | Decision |
| --- | --- |
| Cause | Engulf teleported the victim onto the boss every frame (a reliable RPC to the owner each frame) while both kept their collision: the physics kept shoving the boss, which jumped around and could be pushed through walls out of the map, leaving the floor unfinishable. |
| Held | The victim gets `Player.held_by` (the boss's path, replicated): the host and the owner pin the hero to the boss locally, collision is off while held, no per-frame RPCs. The Engulfed status (stunned + rooted, no longer untargetable, so it is never removed and re-added) shows as a status icon and gives the hero a green, see-through, lifted look drawn over the boss. |
| Burst it down | `Boss.burst_bar` (replicated: progress, seconds left) drives a green bar under the boss bar on every screen: "You are held / X is held - Burst it down! 3.4 s". The burst needed is now 300 (x the boss's HP multiplier). |
| Time limit | At most 4 s (`duration` 4 in data, capped at 4 in code). The hero is released when the time is up (taking the `fail` damage), when the party bursts the boss, when the hero falls, when the phase ends and when the boss dies (its mechanics stop). |
| Arena guard | Every 0.25 s the host checks a floor boss (and the Amalgam's twins, `role` boss_part) against the boss room it spawned in (one tile of slack) and walkable ground; outside, it is put back in the middle of the room. Bosses spawned elsewhere (tests, previews) are not guarded. Krazik needed no change (his mechanics never move him out of the room). |

### #13 Main menu

The title screen shows only the logo, Play / Options / Quit and the version, read from
`application/config/version` in `project.godot` ("v0.1"). The tagline, the Steam status line and the
Codex button are gone; the Codex stays a tab of the in-game menu (the Steam buttons on the Play page
are still disabled when Steam isn't running).

### #14 Preview arrows

The character preview's arrows turn the hero toward the screen side they point at: from facing the
camera, ">" shows the hero looking right and "<" looking left (`HeroPreview.turn`; the direction index
counts clockwise on screen, so turning right steps it back). The gamepad menu test presses both arrows.

### #21 Merchant and Gold Key odds

| Topic | Decision |
| --- | --- |
| Merchant pick | `floor_pick` archibald 4 / malphas 1: Archibald on 80% of floors. |
| Key chance | `elite.key_chance` 0.8, rolled per Archibald floor (D11). The old roll only ran when the floor had an elite and shared the elite picker's random stream; it now has its own stream (seed + 211) and falls back to a chest, then the boss, so the rate is exactly the data value. Real floors always roll 1-3 elites, so the fallback is a safety net. |
| Test | `EconomySuite.merchant_odds`: 2000 seeded floors (real layouts): Archibald share 82.5%, key on 80.9% of Archibald floors, 0 keys on Malphas floors, deterministic per seed, and the same floors stripped of elites get the key from a chest. A live chest marked as the key chest drops the key once. |

### #17 Co-op animation sync

| Topic | Decision |
| --- | --- |
| One-shot actions | `Actor.play_action` (host -> all, `call_local`) is now **reliable**: an unreliable packet lost the whole attack / cast / hit animation on that peer. It is sent by the host only (Combat, monster behaviours, boss mechanics). A "hit" no longer cuts a running attack or cast short; the white flash still shows. |
| Dash | The owner simulates its own dodge and forced dashes, so the host and other clients never saw "dash". The owner now streams `dash_sync` in `OwnerSync` (owner -> all, unreliable, every 0.05 s, next to the position); remote peers draw "dash" from it. |
| Held poses | `Actor.held_anim` (host -> all, `StateSync` on change): the skill's anim while a cast time, channel or charge-up runs (`Actor.host_tick`), drawn in place of idle / walk until it ends (a non-looping anim holds its last frame). Players and monsters. |
| Downed / ghost | Derived from the replicated `life_state` on every peer: going down plays the "death" fall once, then the "downed" loop; a ghost plays "ghost" (others don't see ghosts). No separate revive animation yet (see #18). |
| Walk flicker | Remote actors move in steps as packets arrive; "walk" is held 0.12 s after the last visible step so it doesn't flicker to idle between packets. |
| Local player | The owner does not predict its own one-shots: it plays the host's echo once (the test checks a single start per action). On LAN the delay is one round trip. |
| Test | `AnimSuite` (`anim-lan` pair, warrior host + mage client): each side attacks / casts, dodges and is hit while the other records the hero's `CharacterSprite.anim` sequence and direction; the owner sees its own action start exactly once; a cast-time pose is held on both sides; the downed fall, downed loop and ghost reach the client; a monster's attack and hit reach the client. Packet loss isn't simulated: ENet has no loss switch, and the reliable RPC makes delivery the transport's job. |

### #15 Hero pieces losing pixels

| Topic | Decision |
| --- | --- |
| Frame sync | A layer added or swapped mid-animation (equipping in the dungeon, a look replicated while walking) started on frame 0 while the body was on another frame. The body shader cuts the body with the hide masks of the *body's* frame, so the piece was drawn one frame off its holes: missing pixels and stray skin until the next animation change. `CharacterSprite._sync_to_body` starts every new or swapped layer on the body's frame and progress. |
| Removed layers | `set_layer(slot, "")` only queued the node: it still drew for that frame (with the previous look and tint), and a slot re-added in the same frame (quick class switches in the lobby, a replicated look arriving twice) got a renamed second node next to it. The node now leaves the tree at once. No persistent tint bug was found: tints are set on every `set_layer`; the stale node was the "previous class's colour". |
| Hide masks | Masks hid body pixels that no piece drew over: interior holes (1-33 per set and gender) and a trimmed outline (up to 250 px, female plate) next to helmets, chests and gloves. `gear_cut.gd` ends with `_refill_all` (also `--refill` on the finished sheets, idempotent): a masked body pixel the piece doesn't draw is drawn in the colour of the piece's nearest pixel. Hair and the outline around it (`BodyRegions.is_hairish`) stays hidden under hoods and helmets, as decided in "No body under gear", unless it would be an interior hole. Re-run on the current art: no regeneration. |
| Lobby preview | The preview's pixel scale came from the body height only, so the plate clipped swords, shields and bows held out to the side. `HeroPreview._place` now fits everything the look draws in idle in any direction (`CharacterSprite.used_rect`) on both axes. |
| Tests | `HeroArtSuite` (`hero-art`): 40 seeded class / gender / gear switches (some twice in one frame, with turns) compose (`CharacterSprite.compose`, a software composite of exactly what is drawn) pixel-identical to a fresh preview, and every layer stays on the body's frame; pieces put on mid-walk start on the body's frame; audit of every layer x animation x direction x frame (a worn piece may be empty only where its mask is too, e.g. hands behind a running body) and of interior holes / trimmed outline for both worn sets. `anim-lan` also compares both geared heroes on host and client with fresh sprites. `--scenario=preview_grid --shot=<png>` renders the lobby preview of every class x gender in 8 directions (reviewed). |

### #16 / #18 / #19 Hero animation set and weapon rendering (decided before generating)

The audit is `docs/ART_AUDIT.md`. Every animation multiplies across 2 genders x 8 directions x every
worn outfit, so the set below is fixed before any art is made.

| Topic | Decision |
| --- | --- |
| Measured costs (2026-10-17 probe) | PixelLab body animation, v3 custom, 8 frames on the 48 px base (64 px canvas): **1 generation per direction**. Template animation: 1 per direction. `transfer_outfit` (an outfit onto up to 15 frames of 64 px): **10 generations per call** (9 frames cost 10). The transfer kept every pose pixel-exact on a fast slash. So the outfits dominate: cost = 10 x ceil(frames per direction / 15) x 5 drawn directions x 2 genders per outfit. |
| Animation set (frames per direction) | idle 4, walk 8, dash 4, hit 3, death 5 (+ downed: the last death frame with a 1 px breath, + revive: death played backwards, both derived), and the attacks: **slash** 6 (one-handed swing), **cleave** 6 (two-handed overhead into the ground), **bash** 4 (shield / fist shove), **shoot_bow** 6 (draw, hold, release), **shoot_crossbow** 3 (aim, shot, recoil), **sling** 6 (whirl, throw), **cast** 6 (both hands push the spell forward), **flick** 5 (one-handed wand / pointing cast), **empower** 5 (shouts, self-buffs, novas: arms flung up and out), **throw** 4 (thrown weapons, flasks, traps). 75 frames: exactly 5 transfers of 15 per outfit, gender and direction (batches walk+idle+hit, slash+death+dash, cleave+bash+empower, shoot_bow+shoot_crossbow+cast, sling+flick+throw). Ghost stays body-only (gear is not drawn on ghosts). |
| Derived, no art | **spin** (Whirlwind) = slash played while the facing turns a full circle; **charge / leap** = dash (a leap adds a code lift arc); **slam** (Earthshaker) = cleave; channels hold the skill's pose (`held_anim`, #17); thrust is dropped (no spear weapons). |
| Body sources | idle / walk / dash / hit / death use all frames of the existing PixelLab clips (breathing-idle 4, walking-8-frames 8, running-4 4, taking-punch 6 -> 3, falling-back-death 7 -> 5): no new generation. The new attacks are v3 custom animations of the empty-handed base body described as pure body motion (naming the weapon made v3 draw it), the bow draw is a PixMiniMax animation (v3 kept aiming sideways), throw is the `throw-object` template; frames where the model still drew a bow or a spell glow are skipped per direction (`pick_dir`) or cleaned (`strip_glow`, specks); cast is redrawn (the fireball template left flames and a flipped frame). 5 drawn directions + 3 mirrors. |
| Outfits (#20) | Four worn families, each one `transfer_outfit` reference state per gender cut into head / chest / legs / boots / gloves layers: **plate** (existing state), **cloth** (existing robe + hood state), **leather** and **mail** (new states). Tier / item-level looks of a family are palette variants (free). |
| Budget | Body: 10 new animations x 5 directions x 2 genders = 100. Outfits: 4 x 2 genders x 5 directions x 5 transfers x 10 = 2000. Re-rolls ~10%. Icons, weapon pictures and legendary art (#20) ~200. Total about 2400 of the 2800 cap. Vertical slice first (warrior, sword + shield, plate, both genders): 100 body + 500 plate = 600. |
| Mirrors | W / SW / NW are mirrors of E / SE / NE for the body, every outfit and the attacks, so a hero facing west is left-handed and the sword and shield swap together. Drawing all 8 directions would cost 60% more. |
| Weapon rendering (#16) | **Baked full-frame sheets aligned to the body** (`tools/bake_gear.gd`), generated for each weapon look from the item picture, not drawn per look by hand. Hands are found by `tools/body_regions.gd` (blobs in the nape seen from behind are ignored) and **followed through the whole source clip** (`--track`, the full 9-frame PixelLab clip written by `tools/build_hero_v2.py`; frame 0 is the rest pose where the direction's hand vectors tell the hands apart, then nearest-blob linking that lets both fists share a blob on a two-handed grip), then read at the picked frames. The weapon hand of a direction is the one that swings in its `slash` clip, so a sword never changes hands between idle and attack; in an animation with an `active_hand` (bash: off, bow: main...) the hand that gets furthest from its rest place does it. Angle: resting animations use a fixed screen angle (blade tip down and forward, staff upright, shield as drawn); attacks follow the shoulder -> fist line ("radial") plus an offset, so the blade traces the arm's arc. Each held layer is split per pixel into a **front** sheet and a **back** sheet (`back/<anim>.png`, drawn under the body): a pixel over the body goes behind when its hand is the far hand in that direction (`near_hand`) or covers the gripping hand (fingers close over the grip). A runtime anchor system was rejected because rotating pixel art at draw time breaks the pixel grid. The bow in `shoot_bow` uses the `extended` hand (`hand_anim`): the arm point reaching furthest sideways above the hips, i.e. the bow fist of the draw, because the tracker loses that fist where the arm crosses the body and the bow then followed the drawing hand. The female wand in `flick` uses it per direction (SE, SW, W, NW, N) for the same reason; below 11 px of sideways reach (rest frames) the item stays in its tracked hand. Picked frames where the body art itself drew a blade (female slash SE / S / N, male slash S) show a neighbouring frame instead (`dup`); a stray blade tip on the impact frame (male slash N) is cleared from the body and every outfit (`erase`). The held wand is drawn at 0.6 scale so it reads at 64 px. Where the arms hang (idle / walk / dash) a hand blob above the top 32% of the figure is ignored: the bare shoulders, neck and face of the tank-top body read as hands and put the female shield and staff at head height. Female slash east (and west) comes from a re-drawn clip (`from_dir` swing_e3: the first one drew a blade into the body and kept the swing behind her) and female crossbow south from aim_s2 (it was a T-pose); in both the outfits were re-transferred. A crossbow shot (both genders, all but S / N) and the female 1H slash east / west hold the weapon in the `forward` hand: the arm point reaching furthest the way the hero faces, above the hips, because the tracked weapon hand can be the arm thrown back. Female slash SE shows frame 3 on the impact frame 2 (the blade was still low). Female cleave south comes from chop_s2 (the arms rise in a V and never cross the head, so a head piece worn alone is never cut with the forearms) and female crossbow south-east from aim_se2 (it spread the arms wide). In the female cleave the hand blobs inside the head's box or deep in the trunk are ignored (`no_face_hands`: cheeks, neckline and midriff read as fists) and two-handed weapons and staves of both genders use the `high` hand in the cleave: a fist raised above the middle of the head on the weapon's side holds the weapon in the wind-up; female cleave SE frame 1 shows frame 0 (the arms crossed over the head there). Female walk S frame 5 shows frame 4 (`dup`): the body regions missed the head there (dark hair read as outline, shirt shading as hair), so the cut put the plate's pauldrons on the head and the hood on the chest of anyone not wearing the full set; the hero_art suite now checks that the head tops every idle / walk / dash body frame. The female body also misreads its midriff and legs as hands, so where the arms hang her fists are looked for within 8 px of per-direction anchors (`rest_hands` in `tools/hero_female.json`, measured on idle frame 0 and moved with the body's bob; the main hand is the side the sword is on at slash frame 0), else held at the anchor; the suite checks that a held item keeps its side of the body in every idle / walk frame facing south and north (art_check accepts those anchors as the hand there: the fists beside the shorts read as arm or leg). The body regions keep the hair blobs centred in the top 28% of an upright figure when the biggest brown blob lies below it: shirt shading on a raised arm had been taken for the hair, so in 21 female attack frames (slash S / NW / NE, cleave, cast, empower, throw, bash) a helmet or hood worn without its set's gloves was cut down to a visor and its top went onto the arms. |
| Attack selection (#19) | Data-driven: an item base names its `attack_anim` (sword / axe / mace slash, greatsword / greataxe / warhammer cleave, bow shoot_bow, crossbow shoot_crossbow, sling sling, wand flick, staff cast, shield bash) and its `cast_anim` (wand flick, else cast). A skill's `anim` "attack" means the main-hand weapon's `attack_anim`, "cast" its `cast_anim`, any other name is used as is; no hero animation name is hard-coded in skill code. Unarmed: bash. |
| Impact frames (#19) | Each animation has an `impact` frame in `data/assets.json` `characters.anims`. The host applies a skill's effects (damage, projectiles, VFX, SFX) at the impact frame's time after the animation starts, with the aim taken at the press. |
| Quiver (#20) | The quiver is a worn look (`offhand_quiver`) baked like a held item but with `anchor: back`: hung from the shoulder line found on the direction's idle frame and moved with the body's trunk (arms left out, since they cover the chest in attacks), behind the body except when the hero faces away. |
| Walk pace (feet never slide) | (Superseded by "#25 Walk and run cadence" below.) Each body entry has a `stride`: the ground one walk cycle covers, measured on the walk sheet (step = widest foot spread minus one foot, x 2: male 28 px, female 24 px). The walk plays at (smoothed visible speed / stride) cycles per second, between 0.6x and `walk_pace_max` (2.3x) of its data fps, so hasted or slowed heroes and remote players keep their feet on the ground. |

### #20 Item look variety

Data: `data/items/looks.json`; code: `scripts/items/item_looks.gd`; shader: `assets/shaders/gear_variant.gdshader`.

| Topic | Decision |
| --- | --- |
| Worn families | Plate, mail, leather and cloth (hood + robe), each a full set of hidden layers per gender (the outfits row above). An armour base lists the families it can roll per rarity band (a plate helm is mail at 1-3 and plate at 2-5; greaves, boots and gloves are leather 1-2, mail 2-4, plate 3-5; a hood is leather or cloth). The host picks the family with the item's seeded roll and stores `family` / `appearance` on the item, so it replicates and saves like any other item field. |
| Colour variants | Five variants per family, picked by rarity (metal: rusty, iron, steel, blackened, gilded; leather / cloth: worn, oiled, dyed, night-dyed, embossed). The shader remaps grey (metal) pixels onto a three-colour ramp and shifts hue / saturation / value of coloured pixels; the outline stays as drawn. Weapons use the metal variants. |
| Icons | One icon per family and slot (Pixen 32 px), recoloured on the CPU with the same maths as the shader, so the inventory shows the colours the hero wears. |
| Missing art | A family not drawn for a gender falls back to a drawn appearance (`fallback`), never to an empty layer. |
| Legendaries | A legendary wears its class's family (warrior plate; priest mail with a cloth hood and robe; ranger leather; mage leather with a cloth hood and robe; `legendary_overrides` where the art says otherwise, e.g. the priest's gold cuirass is plate). The class family wins over the base's families whenever it has art for the slot. Its colours come from its own icon: the icon's dark / mid / light tones become the metal ramp, its main hue the leather / cloth hue, its brightest saturated tone a glow. Legendary weapons are the base weapon's baked sheet in those colours (no separate held sprite per legendary). |
| Lobby preview | The class preview wears the class's family from the same `legendary_families` table (warrior plate, ranger leather with a quiver, mage cloth hood and robe, priest robe), so the four classes read apart at a glance. |
| Legendary icons | 108 individual Pixen 32 px icons (`icons/legendary_v2/`, the old sheet cuts kept beside them), each drawn from the legendary's description with the slot's object first ("two empty gloves side by side, fingers up, no body", "pair of empty boots, side view", "plate armour cuirass with pauldrons"...). That stops the model drawing figures or shields, and the colours are named so the icon, and with it the worn look, keeps the item's identity. The hero art suite checks that every worn legendary gets its own colours and can write a review sheet (`FUNTASY_REVIEW_DIR`). |

### #19 Skill animations (reviewed list)

Generated by `tools/skill_anim_table.py` from the skill and weapon data. "weapon attack" / "weapon
cast" play the main-hand weapon's `attack_anim` / `cast_anim` (sword, axe, mace, holy wand: slash;
greatsword, greataxe, warhammer, staves: cleave; bow: shoot_bow; crossbow: shoot_crossbow; sling:
sling; arcane wand: flick; unarmed: bash; casts with a wand: flick, else cast). Shouts, self-buffs
and novas around the hero use empower; traps, flasks, bolas and thrown weapons use throw; shield
skills bash; Whirlwind spins (slash while turning); charges and leaps dash. Every hero skill lands on
its animation's impact frame (data `impact`); channels and cast times hold the skill's pose.

| Class | Skill | Animation |
| --- | --- | --- |
| warrior | Fury Strike | weapon attack: cleave / slash |
| warrior | Cleave | weapon attack: cleave / slash |
| warrior | Shield Slam | bash |
| warrior | Taunting Shout | empower |
| warrior | Deadly Charge | dash |
| warrior | Battle Cry | empower |
| warrior | Whirlwind | spin |
| warrior | Execute | weapon attack: cleave / slash |
| warrior | Riposte | bash |
| warrior | Shield Wall | bash |
| warrior | Earthshaker | cleave |
| warrior | Bloodthirst | weapon attack: cleave / slash |
| warrior | Berserker Rage | empower |
| warrior | Hamstring | weapon attack: cleave / slash |
| warrior | Stoneform | empower |
| warrior | Armor Sunder | weapon attack: cleave / slash |
| warrior | Intimidating Roar | empower |
| warrior | Heroic Throw | throw |
| warrior | Last Stand | empower |
| warrior | Heroic Leap | dash |
| warrior | Thorns of Steel | empower |
| warrior | Overpower | weapon attack: cleave / slash |
| warrior | Iron Will | empower |
| warrior | Mortal Strike | weapon attack: cleave / slash |
| warrior | Rallying Cry | empower |
| warrior | Victory Rush | weapon attack: cleave / slash |
| warrior | Skull Crack | weapon attack: cleave / slash |
| warrior | Devastate | weapon attack: cleave / slash |
| warrior | Avatar | empower |
| ranger | Aimed Shot | weapon attack: shoot_bow / shoot_crossbow / sling |
| ranger | Power Shot | weapon attack: shoot_bow / shoot_crossbow / sling |
| ranger | Multishot | weapon attack: shoot_bow / shoot_crossbow / sling |
| ranger | Viper Arrow | weapon attack: shoot_bow / shoot_crossbow / sling |
| ranger | Snare Trap | throw |
| ranger | Explosive Trap | throw |
| ranger | Hunter's Mark | flick |
| ranger | Disengage | dash |
| ranger | Rain of Arrows | weapon cast: cast |
| ranger | Arterial Shot | weapon attack: shoot_bow / shoot_crossbow / sling |
| ranger | Shadow Flare | throw |
| ranger | Serpent's Grip | flick |
| ranger | Smoke Screen | throw |
| ranger | Piercing Bolt | weapon attack: shoot_bow / shoot_crossbow / sling |
| ranger | Rapid Fire | empower |
| ranger | Acid Flask | throw |
| ranger | Tranquilizer Dart | throw |
| ranger | Bola Throw | throw |
| ranger | Shadow Meld | empower |
| ranger | Double Tap | empower |
| ranger | Caltrops | throw |
| ranger | Eagle Eye | weapon cast: cast |
| ranger | Concussive Blast | weapon attack: shoot_bow / shoot_crossbow / sling |
| ranger | Venomous Vapors | throw |
| ranger | Trickshot | weapon attack: shoot_bow / shoot_crossbow / sling |
| ranger | Gore Arrow | weapon attack: shoot_bow / shoot_crossbow / sling |
| ranger | Survival Instinct | empower |
| ranger | Bone Harpoon | weapon attack: shoot_bow / shoot_crossbow / sling |
| ranger | Shadow Ballista | throw |
| mage | Fireball | weapon cast: cast / flick |
| mage | Flame Wave | weapon cast: cast / flick |
| mage | Combustion | weapon cast: cast / flick |
| mage | Meteor Strike | weapon cast: cast / flick |
| mage | Living Bomb | weapon cast: cast / flick |
| mage | Frostbolt | weapon cast: cast / flick |
| mage | Frost Nova | empower |
| mage | Ice Barrier | empower |
| mage | Deep Freeze | weapon cast: cast / flick |
| mage | Blizzard | weapon cast: cast / flick |
| mage | Earth Spike | weapon cast: cast / flick |
| mage | Granite Armor | empower |
| mage | Tremor | empower |
| mage | Boulder Crush | weapon cast: cast / flick |
| mage | Chain Lightning | weapon cast: cast / flick |
| mage | Lightning Orb | weapon cast: cast / flick |
| mage | Static Charge | weapon cast: cast / flick |
| mage | Thunderstorm | weapon cast: cast / flick |
| mage | Luminance | weapon cast: cast / flick |
| mage | Blinding Radiance | empower |
| mage | Solar Prism | weapon cast: cast / flick |
| mage | Shadow Bolt | weapon cast: cast / flick |
| mage | Drain Soul | weapon cast: cast / flick |
| mage | Grasp of the Void | weapon cast: cast / flick |
| mage | Dark Bargain | empower |
| mage | Blink | flick |
| mage | Mana Shield | weapon cast: cast / flick |
| mage | Counterspell | weapon cast: cast / flick |
| mage | Time Warp | empower |
| mage | Singularity | weapon cast: cast / flick |
| priest | Holy Strike | weapon attack: cleave / slash |
| priest | Smite | weapon cast: cast / flick |
| priest | Flash Heal | weapon cast: cast / flick |
| priest | Renew | weapon cast: cast / flick |
| priest | Power Word: Shield | weapon cast: cast / flick |
| priest | Consecration | weapon cast: cast / flick |
| priest | Rebuke | weapon attack: cleave / slash |
| priest | Blessing of Might | weapon cast: cast / flick |
| priest | Prayer of Healing | empower |
| priest | Divine Aegis | empower |
| priest | Purify | weapon cast: cast / flick |
| priest | Judgement | weapon cast: cast / flick |
| priest | Holy Nova | empower |
| priest | Shadow Word: Pain | weapon cast: cast / flick |
| priest | Crown of Thorns | empower |
| priest | Leap of Faith | weapon cast: cast / flick |
| priest | Holy Fire | weapon cast: cast / flick |
| priest | Penance | weapon cast: cast / flick |
| priest | Bastion Sigil | weapon cast: cast / flick |
| priest | Chastise | weapon cast: cast / flick |
| priest | Guardian Spirit | weapon cast: cast / flick |
| priest | Hammer of the Righteous | weapon attack: cleave / slash |
| priest | Mind Blast | weapon cast: cast / flick |
| priest | Lightwell | weapon cast: cast / flick |
| priest | Exorcism | weapon cast: cast / flick |
| priest | Vampiric Embrace | empower |
| priest | Shackle Undead | weapon cast: cast / flick |
| priest | Martyrdom | empower |
| priest | Shadow Word: Death | weapon cast: cast / flick |
| priest | Apotheosis | empower |

### #22 No full damage-type immunity

| Topic | Decision |
| --- | --- |
| Rule | A monster or boss "immune" to a damage type (data `immune`, statuses `immune_<type>`) takes `combat.immunity_reduction` (0.8) less of it instead of nothing, with a "Resisted" note over the hit. A solo hero of any class can therefore finish every fight; the right type is still five times better. Heroes' own immunity statuses (none today) would still block fully. |
| Reviewed | Murk Amalgam's Bile Twin (physical) and Gristle Twin (fire, frost, earth, ...): every class's primary now hurts both (`skills-*` suites). Other "resistant" monsters were already partial (Magma Carapace -60% physical, Banshee -50% physical, door-shields): unchanged. The warded test dummy now checks the 80% reduction. |

## Second playtest round (GitHub issues #23-#32)

### #24 Merchant prices

| Topic | Decision |
| --- | --- |
| Buying | `balance.merchant.buy_mult` 1.0 -> 3.0: every item and consumable Archibald sells costs three times the old price (value x 3). |
| Selling | `sell_mult` stays 0.3, so a hero gets the same gold as before; buying an item back costs 10x what it fetched. |
| Malphas | Prices nothing in gold (tithe, contracts and pact potions cost stats), so he is unchanged. |

### #26 Skills fire at once

| Topic | Decision |
| --- | --- |
| Rule | A skill (any slot but the primary) pressed while the hero's primary swing waits for its impact frame (#19) cancels that blow and starts in the same frame; its animation replaces the swing at once. The skill keeps its own impact frame / cast time from data. |
| Still waiting | The primary pressed during any pending swing (holding LMB would otherwise cut itself off), and a skill pressed while another skill's blow is pending (it would waste the first skill's cooldown and cost). Casts, channels and charges stay exclusive as before. |
| No wasted swing | The swing is only cut when the new skill would start (cooldown, charges, cost, silence, target checks pass); otherwise the press is refused and the swing lands. |
| Tests | `skills-<class>`: up to six skills per class pressed mid-swing start in the same frame and cut the swing; `skills-lan`: the client's Flash Heal tapped mid-swing starts on the host as soon as the press arrives (one round trip). |

### #30 Boss chamber at the end of the floor (and the sealed-leaf generator for #23 / #31)

| Topic | Decision |
| --- | --- |
| Graph distance | "Farthest along the room graph" = most rooms passed: rooms are nodes, two rooms are joined when a corridor runs between them without entering a third room (read from the carved grid, `DungeonGenerator.room_graph`). |
| Construction | The ordinary rooms (start + normal) get the MST + extra loops as before; every corridor keeps a wall's width away from the boss and merchant rectangles (L shape, the other corner, then a grid search around them). The merchant room then hangs off a nearby room that is not the deepest, and the boss chamber off the deepest ordinary room (ties: the longest walk), each through its own corridor that touches no other floor and opens into its target only. So the boss is strictly one room deeper than anything else and both are dead ends. |
| One entrance | Each leaf's corridor leaves through a 2-cell gap in the middle of its bottom wall: a horizontal door, drawn face-on and seen from the corridor (side doors are drawn edge-on; see #23 / #31), recorded as door `kind` "boss" / "merchant". These doors never become floodgates or bookshelf doors, and the room a leaf hangs off is never rounded into a reading room (it would wall off the way in). |
| Retry | A layout whose leaves can't be attached (rare) is redrawn from `seed + k * 104729`, deterministic on every peer; after 16 tries the generator reports an error (the tests would fail). |
| Tests | `biomes` (+ `biomes-<id>`): 150 seeds per biome, read from the carved grid: every room reachable, the boss chamber strictly farthest in rooms, one opening and one neighbour, one horizontal door of kind boss, unreachable with that door shut; the merchant room the same with a merchant door. |

### #25 Walk and run cadence (decided before any art)

| Topic | Decision |
| --- | --- |
| Measurement | On the side view (east; west mirrors it) the contact foot of the 8-frame walk moves back 3.0 px per frame (male) / 3.2 px (female) while planted: one cycle covers 24 px. Planted feet at the normal 120 px/s therefore need 5 cycles (10 steps) a second; the old cap (2.3x, 3.75 cycles/s) made the legs spin *and* let the feet slide. The male's data stride (28) was also longer than his art (24). No frame picking or retiming can calm the cadence: with planted feet it is always speed / stride, and the walk art's stride is short. |
| Choice | 120 px/s is a running pace, so the hero runs. The `run` animation is the drawn `running-4` clip already used for the dodge (`from: dash`), present in the body, every worn outfit and every baked held item: **0 PixelLab generations**. Its contact foot moves 14.5 px (male) / 14.0 px (female) per frame, so a cycle covers 58 / 56 px: 2.07 / 2.14 cycles (about 4 steps) a second at 120 px/s. The 8-frame walk stays for slow movement. |
| Rejected | A new 8-frame long-stride run would need a transfer for every worn outfit: 4 families x 2 genders x 5 directions x 10 = 400 generations (the whole goal cap). A slower ground speed would change the game's balance. |
| Pace | `characters.anims.run` (4 frames, 8 fps) and per-body `stride: {walk, run}` in `data/assets.json`; both play at speed / stride cycles a second (`CharacterSprite.pace_for`, capped at `walk_pace_max` 3.0x), so a hasted, slowed or remote hero keeps planted feet. The hero runs from 60 px/s and walks again below 50 (`run_speed`, hysteresis): a walk is calm (2 cycles a second) only up to ~48 px/s. Monsters are unchanged (no run stride). |
| Tests | `hero-art` measures the contact foot on the sheets of both genders and checks the body's travel in the planted frames against it (within 1.5 px over the cycle) at 36 / 48 px/s (walk) and 72 / 120 / 156 / 192 px/s (run), and that the cadence at up to the normal speed stays at or under 2.5 cycles a second. Review: `--scenario=tour --tour=gait` shots of both genders running, hasted and slowed. |

### #28 Merchants and the boss chamber on the map

| Topic | Decision |
| --- | --- |
| Discovery | Per peer, from its own fog-of-war memory: a chamber is marked once its door or any of its cells has been seen (`Dungeon.map_markers`). Nothing is replicated; a client's discoveries never show on the host's map. |
| Marks | Merchant room: the merchant's sign (Archibald a gold coin, Malphas a blood drop) with a small padlock while its door is sealed (#23). Boss chamber: a skull on a pulsing red glow. Same icons on the minimap and the map (`ui.map_*` in `data/assets.json`; placeholders until the UI art batch). |
| Tests | `economy`: on both merchant floors no mark before discovery, the right sign after seeing the door, the boss mark after seeing a chamber cell, and walking up to the door through the real fog of war; `economy-lan`: the client's map shows the boss and Malphas marks it found itself, the host's map has no boss mark. Review: `--tour=map_marks`. |

### #27 Deeper talent trees, 3 talent and 10 stat points per level (points and tiers changed by #45)

| Topic | Decision |
| --- | --- |
| "Skill points" | Read as the free stat points (D5). Per level: `progression.talent_points_per_level` 1 -> 3, `stat_points_per_level` 5 -> 10 (back to 1 and 5 since #45). One point is still one point of a primary stat. |
| New nodes | 83 passives (21 per class, 20 for the ranger: his sniper branch has room for 6 more nodes at 4 per tier): percentage stats and passive effects on stats the game reads (`*_damage_pct` per school and damage type, crit chance / damage, haste, dodge, leech and leech healing, max health / mana, armor, block, threat, cooldowns, mana regeneration, Fury generation, damage taken by school, crowd control on you, boss damage, armor / magic penetration, trap radius and count) plus a few skill modifiers (shout, Renew, Shadow Word: Pain, Blizzard / Frost Nova durations, Flame Wave / Living Bomb radius, poison skill damage). At most 4 nodes per branch and tier, so the panel keeps its width. Every passive has an icon (83 new + 32 older ones that showed initials; 8 Pixen sheets). |
| Tiers | (#45 set `tier_points` back to 2.) `tier_points` 2 -> 4: tier N of a branch opens after 4N points in it (tier 5 after 20, about level 8 if every point goes there; 5 would lock the sniper branch, whose tier 0 holds only 4 ranks). A tree holds 107-111 ranks, more than the 87 points of a level 30 hero, so it is never full. Heroes saved under the old costs keep nodes now above their tier (grandfathered); a reset re-applies the rule. |
| Old saves | Unspent points are derived on load (`level x per-level - spent`), so an old hero gets the missing talent and stat points at once, and loading twice gives nothing more. (#45: a pool spent beyond the total is refunded.) |
| Balance | The pacing probe (all free points in the main stat) found heroes too strong with 10 points: warrior and priest killed Krazik under the 12 s boss minimum, the ranger one-shot ordinary monsters from depth 12 (agility feeds both ranged power and crit). Changes: Krazik's base health 950 -> 1250; `crit_per_agility` 0.002 -> 0.0015 and `ranged_power_per_agility` 0.6 -> 0.35 (the ranger's hit on floor 16 is back to the baseline's ~400 with twice the points). All four `balance-*` suites are green (the ranger three times in a row). The probe models no talents, so heroes in real play gain more from 3 talent points per level than the probe shows. |
| Tests | `talents-<class>` (new): 3 / 10 points per level, an old level 10 save gets its missing points with its spending kept, every passive is learnable once its branch has the points and each of its mods moves its stat or skill modifier, at least 20 new passives with icons and numbers, the tree is never full by level 30, and the panel shows every node with all of them reachable by arrow keys / d-pad inside the window. |

### #23 / #31 Sealed merchant door and the boss door

| Topic | Decision |
| --- | --- |
| One entrance | The generator's sealed-leaf rule (#30): the merchant room and the boss chamber each get one 2-cell door in the middle of their **bottom** wall (in the 3/4 view a door's front faces south, so it is seen from the corridor that leads to it). Door types live in `data/doors.json` (`boss`, `archibald`, `malphas`): art keys, seal, warning light, monster-proof. |
| Seal | A merchant door starts sealed on every peer (the layout is the same everywhere). Sealed means shut whatever tries: Interact, a hero's swing (#9), a monster, a lever; it blocks movement, sight and monsters like any closed door. `Door.host_unseal` (host) replicates the broken seal (`_sync_seal`) and opens the door; afterwards it is an ordinary monster-proof door. |
| Archibald | Interact at his vault door with the party's Gold Key: the key is used up at the door, the door opens and Archibald trades with the whole party (no key handed over inside any more). Without a key the door stays shut with a notice. |
| Malphas | His door's price is the floor's **blood price**: one entry of `merchants.json` `malphas.tithe` (the old per-player tithe table: -3 to a primary stat or -10 maximum health, for the rest of the run, D13), picked from the floor seed so every peer's prompt shows the same price. Interact asks for confirmation; the hero who accepts pays it and the door opens for everyone. It replaces the old per-player tithe: once the seal is broken every hero can sign contracts and buy pact potions (assumption: one payer per floor, since the issue asks for a door that opens, not a per-hero toll). |
| Prompts | "Unlock the vault (Gold Key)" / "Break the blood seal (-3 Strength)"; the boss door just opens (no text, the warning is visual). |
| Art | PixelLab map objects (7) and their "open" states (7): Archibald's round gilded vault door (96 px), Malphas's black iron door with a bleeding pentagram under a horned skull (96 px), and a 128 px boss gate per biome (crypt: skull arch with red banners; sewers: slimy round hatch with red lanterns and bone piles; foundry: molten steel gate under a demon forge face; archives: rune-bound doors under a stone eye with skulls on lecterns; kurgan: root-bound barrow doors under a stag skull with skulls on stakes). Asset keys only in `data/assets.json` (`props.door_<type>[_open]`, `door_boss[_open]_<biome>`). |
| Readability | Typed doors are drawn at a fixed brightness (unshaded) with their own flickering light (boss: red, 210 px, with embers; Archibald: gold; Malphas: blood red). The art is taller than the wall row: the part above it is drawn over the fog of war once the door has been seen (dimmed while out of sight) and fades while the local hero is inside the chamber, so it never hides the fight. |
| Tests | `biomes`: one bottom-wall door of the right kind per leaf over many seeds; `economy`: Archibald's door sealed with its prompt and art, holds against Interact without a key, a forced open, a monster waiting at it, blocks sight / movement, opens with the key used at the door; Malphas's door only names the price from inside / from Interact, takes the blood price once at the door and opens; `economy-lan`: the client sees both doors sealed then open, the same blood price in its prompt, and its own payment opens the host's door. Review: `--tour=merchants` and `--tour=boss_doors` (every biome, near and from 5 cells down the corridor). |

### #29 UI overhaul: icons over text

| Topic | Decision |
| --- | --- |
| Art | 5 Pixen icon sheets (80 icons: equipment slot silhouettes, tab / menu icons, class crests, HUD icons, the 12 talent branch emblems, option-tab and lobby icons) and 4 ornaments (gold filigree divider, bronze item well, iron gauge frame with skull caps, title ribbon), plus 13 stat icons and the talent icons of #27. Cut by `tools/cut_icon_sheet.py` / PIL, registered in `data/assets.json` `icons` (`assets/sprites/pixellab/icons/ui/`, `.../stats/`). A sheet whose cells came out on coloured backdrops (coins, key, stairs) was redrawn rather than cleaned. |
| Shared pieces | `UITheme.icon / icon_label / section / divider / chip / card_line / slot_style` and `STAT_ICONS`: every screen uses the same section header (icon, gold title, filigree divider), stat icons, value chips (icon + number, green / red for gains and losses) and icon-led item-card lines (`ItemGenerator.describe` lines carry an optional icon key). `UIFx.pulse` makes unspent points glow. Textures are loaded outside `_draw` (a texture first loaded inside a draw call renders as a white quad). |
| Screens | Game menu: a title icon per panel and icon tabs (only the open tab spells its name). Character: class crest, level crown, XP star gauge, gold chip, "+" stat buttons shown by the stat's icon, icon rows for every stat, run blessings / curses as chips, empty skill slots as dim rune stones. Inventory: slot silhouettes (helmet, breastplate, greaves, boots, gauntlet, amulet, ring, sword, shield, flask) instead of words, bronze wells, stats as icon + value. Talents: branch emblems, a pulsing points chip, a reset icon, rank chips with the stat's icon and the current total. Skill Book: icon sections, empty slots as rune stones, the primary marked by crossed swords. Map: chamber marks in the legend. Codex: scroll / padlock per book, origin sections, a progress gauge. HUD: heart / mana / fury icons, the iron gauge frame, crown + level, XP star, talent / stat point hints with icons and counts, gold pouch, Gold Key, potion / rune silhouettes in empty slots, tracker lines led by a skull / stairs and a torch. Menus, pause, options (screen / speaker / pad tabs), lobby (class crests on the class buttons, check / crown / crest in the party list, setting icons from `data/game_settings.json`), shops (coin price chips, red when unaffordable, green when selling; contracts and pact costs as stat chips), the blood-price dialog (price chip), the lore reader (book kind icon) and the radial menu (an empty flask for "clear"). |
| Not added | No new options or explanatory paragraphs; text stays where a name or a rule must be read (item names, skill and talent descriptions, lore). |
| Checks | `ui-layout` (183 checks incl. 1:1 to 32:9 sizes), `gamepad-menu`, `gamepad`, `economy`, `lore`, `talents-*` green; before / after screenshot review of every screen at 1920x1080 (shots flow, `menus`, `merchants`, `lore`, `map_marks` tours). |

### #32 Polish localization and the language option

| Topic | Decision |
| --- | --- |
| Rule | Code, identifiers, data and docs stay English; the English text is the translation key. Polish lives only in `data/i18n/translations.csv` (Godot CSV translation, columns `keys,pl`; Godot builds `translations.pl.translation` on import, which is generated and not in git). CLAUDE.md updated. |
| Keys | `tools/i18n_extract.py` collects every player-facing string: code literals that read like text (filters plus `tools/i18n_ignore.txt`), the text fields of every data file (`name`, `title`, `description`, `text`, `origin`, `effect_text`, `label`, `message`, `affix`, `suffix`, `group`), affix stat names, setting options, ids shown capitalized (element, school, creature type, status flags), hero body names, and the interaction prompts built from a prop's verb and name. It keeps existing Polish, drops stale keys and `--check` fails on a stale CSV, an empty entry or format placeholders that differ from the key (GDScript's `%` has no positional arguments). `run_tests.sh` runs the check and imports first. |
| Runtime | `Loc.t` (a key), `Loc.f` (a key, then its arguments: names are translated, a stat mod becomes "+3 Siła"), `Loc.name` (item names built from a base and a suffix, backpacks, elite monster names = modifiers + monster), `Loc.plural` (Polish "few\|many" forms split by "\|"). Data and saves keep English: item names, display names and stored values are translated only where they are shown, so a save or a peer never carries Polish. |
| Network | Host messages (broadcasts, notices, refusals, floating numbers, the book note) travel as an English key plus arguments and each peer shows them in its own language, so a Polish host and an English client both read their own (`i18n-lan`). |
| Option | Options -> Video -> Language (English / Polski), each name in its own language, saved in the `[game]` section of `user://settings.cfg`; `--lang=<locale>` overrides it (tests, screenshots). Applied live: the options window rebuilds at once; the main menu reloads when Options close; in a run the HUD rebuilds when the overlay closes (the pause menu returns to the game after a language change). |
| Font | `assets/fonts/funtasy_pixel_pl.ttf`: the pixel font plus ą ć ę ł ń ó ś ź ż Ą Ć Ę Ł Ń Ó Ś Ź Ż built with fontTools from the font's own letters and accent marks, so they match its pixel style. The Polish text uses only characters of this font (plain quotes and hyphens instead of typographic ones); the test checks every Polish character. |
| Grammar (assumptions) | Adjectives that are combined at runtime stay masculine (elite prefixes "Wampiryczny Ghul", rarity "Rzadki"); the item kind line becomes "Rzadki - Głowa" ("%s %s" -> "%s - %s") to avoid wrong agreement. Item suffixes are genitive nouns ("Miecz Sokoła"). Counts use colon forms ("Plecak powiększony: 16 miejsc") or `Loc.plural`. A long header subtitle is cut at a word with "..." instead of widening a window (Polish is ~25% longer). |
| Tests | `i18n` (new): every key has Polish, every Polish character is in the pixel font, switching the language changes a UI label, an item tooltip, a skill tooltip and a lore book, the language option from the pause menu switches and saves the language and the HUD rebuilds in Polish, and no visible text of the HUD, the six game menus, pause, options, both merchants, the lore reader and the main menu shows an English word that has a translation; `i18n-lan`; `ui-layout-pl` (the 183 layout checks with `--lang=pl`). Review: shots flow and the `menus`, `merchants`, `lore`, `skills`, `options` tours in Polish. |

## Third playtest round (GitHub issues #33-#39)

### #38 Closing a book returns to where it was opened

| Topic | Decision |
| --- | --- |
| Return | A lore reader opened over a game menu panel (reading a book from the inventory, or Accept on a read book in the codex) remembers that panel (`UIModal.save_state`: the inventory's focused slot, the codex's book); closing the reader with Cancel / Back / B reopens it with that selection (`HUD._back_to`). Opening any other overlay forgets the way back. The main menu's codex opens its reader the same way and comes back to the book. |
| Tests | `lore`: inventory -> read -> Cancel lands on the inventory with the book's slot focused; codex -> Accept -> Cancel lands on the same book. |

### #35 Several things at one spot

| Topic | Decision |
| --- | --- |
| Choice | `Game.find_interactable(p, pick)`: the thing the hero points at, plus everything else whose aim point lies within `world.interact_stack_radius` (30 px) of it, form a stack. Order: an item the hero can take, then doors / chests / the rest by distance, items they can't take last. `pick` cycles through the stack; a different set of things in reach starts again from the first. |
| Action | New rebindable action `interact_next` "Next thing to interact with": **G** on the keyboard, **left stick click** on the gamepad (the only free pad button). The HUD prompt adds a cycle icon, "1/2" and that button's glyph when there is more than one thing. |
| Refusals | Checked on the hero's own copy of the inventory: a full backpack ("Backpack is full") or a backpack no bigger than the one carried ("You already have a backpack this big"). Such an item doesn't hide the door and its prompt says why; the host still decides on pickup. Gold and the Gold Key are always takeable. |
| Doorways | `LootManager.drop_item` moves anything landing within `world.door_drop_margin` of a doorway to the nearest floor cell beside it (kills, chests, and items players drop). |
| Tests | `interact`: item in a doorway first, `interact_next` to the door, the door opens / closes, the item is picked up; full backpack and a too-small backpack put the door first with the reason; loot dropped on a doorway lands beside it. `interact-lan`: the client sees the same order and opens the door through its switched choice. Review: `--tour=interact` in English and Polish. |

### #37 Teammates' effects on the party frames

| Topic | Decision |
| --- | --- |
| Icons | Every status effect has an `"icon"` asset key in `data/status_effects.json`: the icon of the skill, pact potion or legendary that applies it where one exists (113), else a new icon (`icons.st_<id>`, 76 from 5 Pixen sheets). The local buff bar and the party frames draw it; initials only as a last resort. |
| Frame | Under the bars, up to 7 16-px chips, then "+N": debuffs first (red border), then buffs (their colour), the soonest to end first, effects without an end last; stack count on the chip, the remaining time as a thin bar, tooltip "name xN - 5s" (translated) on hover. The HUD isn't focusable in play, so the tooltip is mouse-only (assumption). |
| Network | Uses the replicated `Status:shown` of each player, so every peer sees the same. |
| Tests | `party`: every status has an icon, the ordering; `party-lan`: a buff and a stacked debuff on the client appear on the host's frame (debuff first, stacks, tooltip) and the host's effects on the client's frame, and both clear when they end. Review: `--tour=party` at 1920x1080 and 3840x1080 in English and Polish. |

### #39 Friendly targeting

| Topic | Decision |
| --- | --- |
| Picking | New rebindable action `target_ally` "Target next ally": **Tab**, gamepad **right stick click**. It cycles through the living party within `combat.friendly_target_range` (700 px), yourself included, then back to no pick. A left click within `combat.friendly_click_radius` (16 px) of a teammate's body picks them (that click doesn't swing); a click on a party frame picks that teammate (a second click clears). The pick clears itself when the teammate falls or leaves the range. |
| Pad button | Every gamepad button was taken, so the Character panel lost its own pad button (right stick click): it stays reachable from any game menu with LB / RB, and from the keyboard (C). Assumption: picking an ally mid-fight matters more than a direct button for the character sheet. |
| Spells | Skills with an `aim_ally` effect (Flash Heal, Renew, Power Word: Shield, Purify, Guardian Spirit, Crown of Thorns, Leap of Faith...) go to the picked teammate regardless of the cursor. `aim_any` skills (Smite, Penance: heal an ally or hurt an enemy, whichever you point at) and all damage skills keep following the cursor, so a priest can still smite while a teammate is picked. |
| Host | The owner sends the picked peer with each `request_skill`; the host resolves it to a living teammate (`Actor.friendly_target`), checks reach (the ally effect's range) and line of sight before paying anything ("Target out of range", "Target not in line of sight"), aims the cast at them, and `select_targets` prefers them for `aim_ally`. |
| Marks | World: a gold ring under the picked teammate and a bobbing gold chevron over them (replacing the cursor's green suggestion ring while a pick is active). HUD: their party frame gets a gold border and a target icon before the name. |
| Tests | `target-lan` (two priests): without a pick the heal follows the cursor; with the client picked, Flash Heal and Power Word: Shield land on them while the cursor points away; out of reach the cast is refused with a message and costs nothing; on the client Tab cycles party -> self -> none, the frame is marked, the client's real key press heals the host; a click on the teammate picks, a click on the picked frame clears. Review: `--tour=target` in English and Polish. |

### #33 Visible effects on allies

| Topic | Decision |
| --- | --- |
| Art | Six animated effects made in PixelLab's free vfx workbench and imported as one-row strips by `tools/import_vfx.py` (`fx.heal_burst`, `fx.hot_glow`, `fx.shield_bubble`, `fx.shield_break`, `fx.buff_flash`, `fx.cleanse_flash` in `data/assets.json`, each with frames, fps, its origin anchor and loop). No generations spent. |
| Roles | `data/fx.json` maps roles to effects, their place on the actor (centre / feet), size and a coloured light that lights the hero for the effect's time (so it reads in the dark): `actor` one-shots (heal, big_heal >= 25% of max health, buff, cleanse, shield_break) and `loop`s (hot, shield). |
| One-shots | The host asks every peer to play them on the actor (`CombatFx.actor_fx`, unreliable RPC): a direct heal from a skill (Flash Heal, Prayer of Healing, beams, AoE heals) plays a heal burst (not drains, zone ticks or heals over time, which have their own look); a non-debuff status a skill puts on a teammate, or on the whole party including the caster (Blessing of Might, Battle Cry, Rallying Cry, Time Warp...), plays a buff flash; a cleanse plays a cleanse flash on each target. |
| Loops | `ActorFx` on every actor reads replicated state on each peer: a glow while any heal over time (`kind: hot`) is in `Status:shown`, a bubble while `Health:absorb` > 0 (any shield: Power Word: Shield, Divine Aegis, Ice Barrier, wards) and a shatter when it drops to 0 while alive. The old gold ring on a new shield was dropped (the bubble replaces it). |
| Tests | `fx-lan` (priest host, warrior client): Flash Heal burst, Renew glow on and off, Power Word: Shield bubble while it holds and its shatter, Blessing of Might flash on both heroes, Purify flash, each on the host and seen by the client on itself. Review: `--tour=allyfx` (each effect at its peak next to training dummies). |

### #34 AoE and zone looks per element

| Topic | Decision |
| --- | --- |
| Elements | Nine looks: physical, fire, frost, lightning, earth, holy, shadow, nature, arcane. An area takes the element of its effect's `fx` when that names one, else its `damage_type`, else the skill's damage type; a heal-only area is holy; aliases fold the rest in (`true` -> physical, `poison` -> nature, `explosion` -> by damage type). Every AoE / zone / delayed area of the skills, monster and boss skills, legendary and status procs resolves to one. Player, monster and boss areas use the same looks; telegraphs stay the red warning ring first. |
| Art | 18 animated effects from PixelLab's free vfx workbench (no generations): bursts (dust shockwave, fire blast, ice spikes and shards, lightning strike, ground cracks and debris, golden sky beam, violet void poof, green gas, arcane rays) and lingering grounds (falling arrow streaks, ring of flames, frost mist and snow, crackling arcs, churning earth, golden seal, void pool, bubbling toxic pool, arcane seal). `data/fx.json` `burst` / `zone` map each element to its effect, its ground width (`span`, scaled to the area's diameter) and its blend: smoke, dust and dark pools and the blue frost / lightning are drawn as they are (unshaded), the light ones glow (additive). |
| Edges | The old ring stays as the area's edge: faint under a burst, steady (no pulse) around a zone, so players see where the area ends. |
| Tests | `fx`: the data scan (every area resolves, every look has its art) and a fire burst, a frost burst and a heal zone cast in game show their own looks; `fx-lan`: Holy Nova's burst and Consecration's ground on the host and the client. Review: `--tour=elements` (the nine bursts, then the nine zones, side by side). |

### #36 Wall spouts come out of a pipe or vent

| Topic | Decision |
| --- | --- |
| Sides | Spouts sit in any of a room's four walls (`DungeonGenerator._place_spouts`: a wall cell with two open floor cells in front of it, away from the corners) and spray into the room. No other effect comes out of a wall in the five biomes (magma geysers rise from lava channels, miasma from urns, thorns from the floor). |
| Art | North walls show their face: a PixelLab map object (48x48, drawn at 0.75 on the face, mouth at the wall's foot), a corroded drain pipe dripping green slime (`props.sewer_drain_pipe`) or a black iron furnace vent with a glowing grille (`props.foundry_wall_vent`). East, west and south walls show their tops, so a second, top-down map object per kind (64x32, drawn mouth-right) lies on the wall top with its mouth at the room edge, mirrored for east walls and turned for south walls: a slimed drain pipe (`props.sewer_drain_pipe_top`) and a nozzle recoloured to heated metal so it reads on the dark wall tops (`props.foundry_wall_vent_top`). `top_scale` / `top_offset` in `hazards.spouts` place it. The 16 px nozzles they replace stay in the project unused. |
| Spray | Leaves the mouth (`mouth` offset) and runs straight (no particle gravity), so on every side it covers the same strip as its damage. The flame jet sprays additive sparks, thicker (`spray_texture`, `spray_amount`, `spray_scale`, `spray_spread` in `hazards.spouts`). |
| Telegraph | The last `warn_time` (0.9 s) before each spray: the mouth drips acid / sheds embers, tints toward the spray colour and its light swells; computed from the shared floor clock like the spray, so every peer sees the same timing. |
| Tests | `spouts-sewers` / `spouts-foundry`: every spout has its pipe / vent art and sprays from its mouth; a warning runs right before every spray; every spout shows the art of its wall side (face or top) with the spray at its mouth; over 40 generated floors of the biome spouts face all four sides. Review: `--tour=spouts --biome=<sewers|foundry>` (from across the room idle, warning, spraying) and `--tour=spout_sides` (a spraying spout on each wall side). |

### #45 Balance: 5 stat points and 1 talent point per level

| Topic | Decision |
| --- | --- |
| Points | Playtest: the game is too easy. `progression.stat_points_per_level` 10 -> 5 and `talent_points_per_level` 3 -> 1, the values before #27. Tomes and other bonus points are unchanged. The level-up message says "+1 talent point" in the singular. |
| Tiers | `tier_points` 4 -> 2 in all four trees (the pre-#27 gate): with one point a level, 4 a tier would open tier 5 only at level 21 (floor 8-10 at 2-3 levels a floor). At 2 a tier, tier 2 (first keystone) opens at level 5 and tier 5 (second keystone) at level 12 if every point goes into one branch. Every branch has enough ranks below each tier to pay its gate. A level 30 hero has 29 talent points against 107-111 ranks: picking a branch matters more than before. |
| Old saves | Points are still derived on load (`level x per-level + bonus - spent`). A pool spent beyond its new total (a hero saved under the #27 rules) is refunded whole: the stat allocation or the talents are cleared, the points come back to spend again, the loadout falls back to the default kit when a slotted skill is no longer learned, and two seconds after spawning the owner reads a short message naming what was refunded ("Talent and stat points refunded: spend them again."). A pool spent within the total is kept. Nothing is written until the next save, and loading again gives the same result. |
| Balance | All four `balance-*` probes stay inside their pacing bands with 5 points a level (they put every free point in the main stat and model no talents). |
| Tests | `talents-<class>`: 1 / 5 points a level; a level 10 save with 27 talents and 90 stat points spent loads refunded (9 / 45 to spend, a valid loadout, the message), twice; a level 10 save within the totals keeps its spending; every branch's tiers can be paid and the top tier opens by level 12. `balance-*`, `economy`, `continue` green. |

### #40 Clearing the friendly target with a click

| Topic | Decision |
| --- | --- |
| Clicks | A left click on a teammate (or yourself) picks them; a click on the picked one clears the pick (toggle); neither swings. A click on empty space clears the pick and attacks as usual. "Empty" means no living teammate under the cursor (`friendly_click_radius` 16 px around the body), no enemy the player can see (`Player.enemy_at`: within `max(1.5 x radius, combat.enemy_click_radius 14)` of the body) and no HUD control that takes clicks (`gui_get_hovered_control` with `MOUSE_FILTER_STOP`). A click taken by a party frame sets `_click_select` first, so it never counts as empty ground. |
| Gamepad | Unchanged from #39: the target action (right stick click) cycles through the party and then to no pick, so the pick can always be cleared. The party frame's tooltip says how to pick and clear, naming the current device's binding. |
| Marks | The pick is local (only the picker sees its markers), so clearing removes the world ring / chevron and the frame's gold border at once on that peer. |
| Tests | `target-lan`: on the host and on the client, a picked teammate is marked and the frame's tooltip names the binding; a click on empty ground clears the pick and the marker and still attacks; a click on the teammate picks them, a second click clears it. Review: `--tour=target_clear` (before / after, English and Polish). |

### #41 Enemy targeting (the lock)

| Topic | Decision |
| --- | --- |
| Picking | New rebindable action `target_enemy` "Target next enemy": **R**, gamepad **D-pad Left**. It locks the nearest enemy this player can see (`Player.visible_enemies`: the fog-of-war `visible` flag, within `vision.max_sight`), then the next farther one, then none. A left click on a visible enemy locks it and is still an attack on it. |
| Pad button | No pad button was free (the issue suggested a long press of the right stick). Long presses can't be rebound like other actions, so Talents gave up D-pad Left, as the Character panel gave up its button in #39: Talents stays one press away as a tab of the game menu (Back opens the inventory, RB moves to Talents) and on the keyboard (T). The HUD's talent-point hint shows "?" for the pad, like the character hint. |
| Aiming | While a lock holds, aimed attacks go to it regardless of the cursor or the right stick: the owner aims at it and sends the enemy's node name (the same on every peer) with `request_skill`; the host overrides the aim. "Aimed attack" comes from the skill's data (`SkillShape.of`: projectile, melee, cone, single target, chain, line, aimed area, dash); self-centred skills and buffs ignore the lock, and ally spells keep following the friendly target (#39) or the cursor. A held left button that locked an enemy keeps hitting it wherever the cursor goes; a new click on empty ground is an attack at the cursor and clears the lock (#40). |
| Host | Before paying anything the host checks the enemy exists ("Invalid target"), lives, is within `vision.max_sight` and in line of sight ("Target not in line of sight"; the host doesn't run each player's fog, so sight is the range plus the same line-of-sight ray as ally spells) and within the skill's reach: `SkillShape.reach` (range plus the area at its end) + the enemy's radius + 16 px ("Target out of range"). These refusals are always shown, at most once a second, also for the primary attack. |
| Clearing | The lock drops when the enemy dies or stops being targetable, leaves this player's sight or `vision.max_sight`, on a click on empty ground, or when the cycle comes back to none. The lock is local, like the friendly pick. |
| Marks | World: a ring of rotating red dashes under the enemy's feet, red corner brackets around its body, and its health bar always shown, framed in red with a small red crosshair before it (the friendly pick is a solid gold ring and a gold chevron). Boss: a red crosshair before the boss's name and the gilded frame of the boss bar tinted blood red. |
| Tests | `hostile-lan` (two rangers, three training dummies, one behind a wall within sight range): the cycle offers only the visible enemies, nearest first, then none (host and client); a click locks; the held primary keeps hitting the locked dummy and Viper Arrow lands on it with the cursor pointing away (host and client); Cleave at a locked dummy out of reach is refused with a message and costs nothing; the host refuses an out-of-sight enemy and a name that doesn't exist; a click on empty ground clears the lock; the lock drops when its enemy dies (host and client). `gamepad-menu`: D-pad Left opens no menu, Back then RB opens Talents. Review: `--tour=hostile` (a locked dummy next to the friendly pick, a locked boss, the new action in the rebinding list; English and Polish). |

