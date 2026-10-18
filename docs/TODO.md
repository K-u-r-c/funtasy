# TODO

Status of the game (see `CLAUDE.md` for scope). Verified = covered by `tools/run_tests.sh` or a
manual run noted here. The MVP is done (below); the full GDD follows the roadmap of
`.design/IMPLEMENTATION_PLAN.md` section 7. Every phase ends with `./run_tests.sh all` green and a
screenshot review at 1920x1080 and 3440x1440.

## Full GDD roadmap

- [x] **0. Scope and decisions**: CLAUDE.md scope, DECISIONS D1-D38, this roadmap, data schemas
      (damage types, statuses, behaviours, bosses v2, floor types v2, talents v2, legendaries, lore,
      merchants, gold), `GameData` validation (verified: full suite green, no visual change)
- [x] **1. Combat foundations**: damage types / resists, status expansion (CC flags, stacking debuffs,
      marks, reactive buffs, procs, transforms, diminishing returns), new effect primitives, ally
      targeting, channel / charge input, dynamic obstacles, corpses, creature types; generic test
      harness (every skill of a class, every monster) (verified: `skills-*`, `primitives`, `monsters`
      suites, full suite green, combat tour screenshots at 1920x1080 and 3440x1440)
- [x] **2. Progression and economy**: stat points, talent tree v2 + Skill Book loadout (save
      migration), gold, Gold Key, elites + altars, merchant chamber, Archibald, Malphas (tithe,
      contracts, pact potions), run mods, lore import / book items / reader / codex (verified: `economy`,
      `economy-lan`, `lore`, `ui-layout` suites, full suite green, screenshots of menus, merchants, lore)
- [x] **3. Classes**: 120 skills, 4 talent trees with keystones, icons, VFX, SFX keys, tooltips
      (verified: `skills-warrior/ranger/mage/priest`, `skills-lan` suites, full suite green, screenshots
      of skills, talents, Skill Book)
- [x] **4. Crypt complete**: 4 new + 3 extended monsters, Morvath + Vespera, hazards (pressure
      plates; pendulums removed in #5), props, mechanics (unlit regen, urn miasma), lore drops (verified: `monsters`,
      `bosses`, `biomes`, `boss` + `boss-vespera` LAN pairs, full suite green, biome tour screenshots at
      1920x1080 and 3440x1440). Visual checkpoint asked on 2026-10-16 and **approved by the user** (look, scale,
      method), then the other four biomes got PixelLab art.
- [x] **5. Sewers** (tileset, props, hazards, mechanics, 7 monsters, Murk Amalgam + Krazik, lore, music keys)
      (verified: `biomes-sewers`, `monsters`, `bosses`, `boss-amalgam` + `boss-krazik` LAN pairs, sewers
      tour screenshots). Art: PixelLab (tiles, monsters, bosses, props; see DECISIONS "Biome art").
- [x] **6. Foundry** (platforms over molten lakes, grates, flame jets, cauldrons, heat armor loss, magma
      geysers, 7 monsters, Ignis + Vulkania) (verified: `biomes-foundry`, `monsters`, `bosses`, `primitives`,
      `boss-ignis` + `boss-vulkania` LAN pairs, foundry tour screenshots). Art: PixelLab.
- [x] **7. Archives** (library grid, round reading rooms, bookshelf doors, spatial anomalies, void rifts,
      silence runes, animated books, 7 monsters, Malazar + the Memory Devourer, Tome Prison side arena)
      (verified: `biomes-archives`, `monsters`, `bosses`, `boss-malazar` + `boss-devourer` LAN pairs, archives
      tour screenshots). Art: PixelLab.
- [x] **8. Kurgan** (caverns, blood pools, sprouting thorns, root snares, dread totems, ground fog, 7 monsters,
      Cernunnos + Isolde) (verified: `biomes-kurgan`, `monsters`, `bosses`, `boss-cernunnos` + `boss-isolde` LAN
      pairs, kurgan tour screenshots). Art: PixelLab.
- [x] **9. Legendaries**: 108 items + affix hooks + icons + drop rules + tooltips (verified: `economy-lan` (a client equips a legendary through the host and its proc fires), `legendaries-warrior/
      ranger/mage/priest` suites prove every affix, `primitives`, `skills-*`, `economy`, `ui-layout`, legendary
      tour screenshots at 1920x1080 and 3440x1440). Icons: 7 Pixen sheets of 16 cut by `tools/cut_icon_sheet.py`.
- [x] **10. Integration**: balance pass (`balance-<class>` suites, blood pool fix), audio keys + Suno prompt
      list (`docs/SUNO_PROMPTS.md`), README / DECISIONS / TODO, full test suite, LAN pairs for every boss +
      Steam smoke test (init, lobby, tag, host peer), final screenshot tours of every biome and boss at
      1920x1080 and 3440x1440 and the legendary item cards

## Playtest issues (GitHub #1-#14)

- [x] #1 Simple start: primary + one basic skill, empty slots, easier floors 1-3 (`classes-*`,
      `balance-*` fresh-hero pass, `economy`, `economy-lan`, `ui-layout`, `full-wm`)
- [x] #2 Telegraphed monster leaps / charges: wind-up + cast bar + ground marker, 1.5 s grace, lower
      damage (`monsters`, `bosses`, `full-wm` client check, `boss-cernunnos`)
- [x] #3 The carried torch only burns out (shriek / vermin swarm keep it; `monsters`, `bosses`,
      `primitives`, `darkness`, `boss-vespera`)
- [x] #4 Burrowers / hidden monsters: 2.5 s per dive, walk speed, surfacing telegraph, 4 s+ above
      (`monsters`, `biomes-sewers`, `biomes-kurgan`)
- [x] #5 Pendulum traps removed (PNG kept; `biomes*` suites check every biome has none)
- [x] #6 One seeded merchant per floor in its own room, no portal / altarpiece, Gold Key only on
      Archibald floors (`economy`, `economy-lan`, `biomes*`)
- [x] #7 Doors / props lit and shadowed like walls (LIT layer, occluders off the art; lighting tour of
      all 5 biomes reviewed; `biomes`, `darkness`, `art-check`, `full-*`)
- [x] #8 Balance: kill XP curve (2-3 levels per floor, solo and 4 players), monster tiers gated by
      depth, easier floors 1-3, item level from one function, 3% upgrade drops (`balance-*` progression
      and pacing probes, `biomes`, `economy`)
- [x] #9 Priest primary is the melee Holy Strike (Intellect-powered); melee swings burst doors open;
      Smite learnable (`classes-*`, `skills-priest`, `ui-layout`, `skills-lan`, `full-pr`)
- [x] #10 Every class starts with a Common class weapon, drawn on the sprite (`classes-*`, `wipe`,
      `continue*`, `full-wm`)
- [x] #11 Item card compares against every item equipping would take off (2H vs both hands, off-hand vs
      2H; `economy`, `ui-layout`)
- [x] #12 Amalgam grab: held state (status, look, Burst it down bar), 4 s max, released on death; boss
      arena guard (`boss-amalgam` LAN pair, `bosses`, `boss-krazik`)
- [x] #13 Main menu cleanup: no tagline / Steam status / Codex button, "v0.1" (`gamepad-menu`,
      `ui-layout`, screenshot)
- [x] #14 Character preview arrows turn the way they point (`gamepad-menu`)

## Visual polish issues (GitHub #15-#21)

- [x] #15 Hero pieces lose pixels / wrong colours: layers start on the body's frame, removed layers leave at once, mask refill, preview fit (`hero-art`, `art-check`, `anim-lan`)
- [x] #16 Weapon placement in every direction: baked front / back sheets from the tracked hand, bow in the extended hand of the draw, reviewed per weapon in 8 directions (`art-check`, `hero-art`)
- [x] #17 Co-op animation sync: reliable one-shots, replicated dash / held poses, downed fall (`anim-lan`)
- [x] #18 Hero animation audit and fixes: `docs/ART_AUDIT.md`, v2 set of 75 frames for both genders, walk paced by stride (`hero-art`, `anim-lan`)
- [x] Second art review: female held items in the hand where the arms hang (`rest_hands`), walk S frame 5 and 21 attack frames cut on the right body part, new `hero-art` checks (head on top, held items keep their side)
- [x] Kill XP: a killing first hit earns its dealer the kill's XP (contribution counted before the blow; `classes` checks it); load- and layout-proof LAN door, ghoul leap, lunge landing, darkness and void rift checks
- [x] #19 Attack animations per weapon family and skill: data-driven per weapon / skill, impact frames, reviewed skill table (`skills-*`, `anim-lan`)
- [x] #20 Item look variety: four worn families for both genders, rarity colour variants, family icons, 108 legendary icons and colours, quiver (`hero-art`, `legendaries-*`)
- [x] #22 No full damage-type immunity: monsters take 80% less of an immune type (`skills-*`, `primitives`)
- [x] #21 Merchants 80 / 20, Gold Key on 80% of Archibald floors with a chest fallback (`economy`,
      `economy-lan`)

## Second playtest issues (GitHub #23-#32)

- [x] #24 Merchant buy prices x3, sell prices unchanged (`economy`)
- [x] #26 Skills fire at once: a skill cuts the primary swing (`skills-*`, `skills-lan`)
- [x] #30 Boss chamber is the graph-farthest dead end from the start (`biomes-*`)
- [x] #25 Walk / run cadence matches the ground speed, planted feet (`hero-art`, tour `gait`)
- [x] #28 Map and minimap mark discovered merchants by type and the boss chamber (`economy`, `economy-lan`)
- [x] #27 83 new passive talents with icons, 3 talent and 10 stat points per level, old saves topped up (`talents-*`, `balance-*`)
- [x] #23 / #31 One sealed entrance per merchant room and boss chamber, door art per merchant and per biome (`biomes-*`, `economy`, `economy-lan`)
- [x] #29 UI overhaul: icons, ornaments, chips and gauges on every screen (`ui-layout`, tours)
- [ ] #32 Polish localization (2369 keys incl. 105 lore books) and a live language option (`i18n`, `i18n-lan`, `ui-layout-pl`)

## PixelLab ledger

Start of the GDD goal (2026-10-15): **used 1081 / 2000, remaining 919**, resets 2026-11-14.
Goal cap: 2500 generations, and never more than the remaining allowance. Spend = difference of the
`used` counter before and after a batch.

| Date | Batch | Used before | Used after | Spend | Total spend |
| --- | --- | --- | --- | --- | --- |
| 2026-10-15 | (start) | 1081 | 1081 | 0 | 0 |
| 2026-10-16 | Skill icon sheets: 8 Pixen 128x128 sheets of 16 icons (96 skills, 24 keystones, 6 items, 2 statuses), cut by `tools/cut_icon_sheet.py` | 1081 | 1089 | 8 | 8 |
| 2026-10-16 | Crypt: 4 monsters (v3 48 px) + Vespera (v3 72 px) with template / v3 animations on 5 directions, 15 crypt props, 9 shared merchant-chamber / altar / lore props (map objects; lit / open / used variants recoloured, no generation) | 1089 | 1222 | 133 | 141 |
| 2026-10-16 | Legendary icons: 7 Pixen 128x128 sheets of 16 icons (108 legendaries + quiver), cut by `tools/cut_icon_sheet.py` | 1222 | 1229 | 7 | 148 |
| 2026-10-16 | Biome art after the checkpoint approval: 4 tiles-pro sets, 26 v3 monsters / bosses (3 template animations on 5 directions), 11 shapeless creatures and forms from map objects, 46 props, 10 pact potion icons (1 Pixen sheet) | 1229 | 1736 | 507 | 655 |
| 2026-10-16 | Terrain obstacles: Ignis's ingot and the arcane prism kind (2 map objects, replace the tinted blocks) | 1736 | 1738 | 2 | 657 |

Visual polish goal (#15-#21), start 2026-10-17: **used 1738, remaining 3068**, resets 2026-11-14.
Goal cap: 2800 generations, never above the remaining allowance, 150 kept in reserve. Estimate
(DECISIONS "#16 / #18 / #19"): body animations 100, four outfits 2000, #20 art ~200, re-rolls ~10%.

| Date | Batch | Used before | Used after | Spend | Goal spend |
| --- | --- | --- | --- | --- | --- |
| 2026-10-17 | (goal start) | 1738 | 1738 | 0 | 0 |
| 2026-10-17 | Cost probes: v3 slash on the male base (1 direction), plate transfer_outfit onto it (9 frames); flesh stitcher walk east (missing direction, audit) | 1738 | 1750 | 12 | 12 |
| 2026-10-17 | Male body attacks (vertical slice): 9 v3 + 1 template animations x 5 directions, re-rolls (bow twice, then PixMiniMax; crossbow, sling once) | 1750 | 1812 | 62 | 74 |
| 2026-10-17 | Male plate outfit: 25 transfer_outfit calls (5 batches of 15 frames x 5 directions) | 1812 | 2062 | 250 | 324 |
| 2026-10-17 | Male cloth (hood + robe) outfit: 25 transfer_outfit calls | 2062 | 2312 | 250 | 574 |
| 2026-10-17 | Female body attacks: 10 animations x 5 directions (empower re-run after a failed job, bash SE re-roll) | 2312 | 2356 | 44 | 618 |
| 2026-10-17 | Female plate outfit (25 transfers), leather / mail outfit states for both genders (4), leather probe transfer (1), 13 family / quiver icons (Pixen 32 px, 2 re-rolls) | 2356 | 2639 | 283 | 901 |

Estimate before the next batches (2026-10-17): female cloth 21 + leather 49 + mail 50 transfers = 120 x 10 = 1200,
108 legendary icons (Pixen, 1 each) + re-rolls ~150: goal total about 2250 of the 2800 cap (2167 remaining).

| Date | Batch | Used before | Used after | Spend | Goal spend |
| --- | --- | --- | --- | --- | --- |
| 2026-10-17 | Female cloth outfit (21 transfers), male leather outfit (24), mail probe (male) and leather / mail probes (female), one transfer lost to a server error (cancelled at 95%), mail chest icon re-roll | 2639 | 3139 | 500 | 1401 |
| 2026-10-18 | Male mail (24 transfers), female leather (24) and mail (24 + 1 re-run of a dropped job), 108 legendary icons (Pixen 32 px) with ~40 re-rolls / prompt tests (bows: Pixen and Pixflux img2img), one more transfer lost to a server error (the re-run's charge posted late) | 3139 | 4054 | 915 | 2316 |
| 2026-10-18 | Blacksong Greatbow icon redrawn (2 Pixflux img2img tries) | 4054 | 4056 | 2 | 2318 |
| 2026-10-18 | Second art review: held-item anchors, body-region and dup fixes from existing frames (no generation) | 4056 | 4056 | 0 | 2318 |
| 2026-10-18 | Female slash east re-drawn (v3 probes swing_e2, swing_e3: no drawn blade) and crossbow south (aim_s2), batch 1 east + batch 3 south re-transferred for the 4 outfits (8 x 10) | 4056 | 4139 | 83 | 2401 |
| 2026-10-18 | Female cleave south re-drawn (chop_s2: arms in a V, never over the head) and crossbow south-east (aim_se2), batch 2 south + batch 3 south-east re-transferred for the 4 outfits (8 x 10) | 4139 | 4221 | 82 | 2483 |

Estimate before the next batch (female cleave S lifts the forearms over the head, so a head piece worn alone draws sleeves there; female crossbow SE / SW spreads the arms wide): v3 re-rolls of cleave south and shoot_crossbow south-east (1 each, up to 2 tries: <= 4) + transfer_outfit of batch 2 south and batch 3 south-east for the 4 outfits (8 x 10 = 80): <= 84, goal spend <= 2485 of 2800.


Estimate before the next batch (female slash east kept the blade behind her and drew a blade into the body; female crossbow south is a T-pose): v3 re-rolls of slash east and shoot_crossbow south (1 each, up to 3 tries: <= 6) + transfer_outfit of batch 1 east and batch 3 south for the 4 outfits (8 x 10 = 80): <= 86, goal spend <= 2404 of 2800.


Second playtest goal (#23-#32), start 2026-10-18: **used 4221, remaining 585**, resets 2026-11-14.
Goal cap: 430 generations, 150 kept in reserve, never above the remaining allowance. Planned spend
(DECISIONS "#25" decided the walk needs no art): talent and stat icons ~8, merchant and boss doors ~20,
UI frames / ornaments / icons ~60, re-rolls ~10%.

| Date | Batch | Used before | Used after | Spend | Goal spend |
| --- | --- | --- | --- | --- | --- |
| 2026-10-18 | (goal start) | 4221 | 4221 | 0 | 0 |
| 2026-10-18 | #27 talent icons: 6 Pixen 128x128 sheets of 16 (83 new passive talents + 13 stat icons for #29), cut by `tools/cut_icon_sheet.py` | 4221 | 4227 | 6 | 6 |
| 2026-10-18 | Icons for the 32 older passives that showed initials (2 Pixen sheets) | 4227 | 4229 | 2 | 8 |
| 2026-10-18 | #23 / #31 door probe: Archibald vault door v1 (map object, 96 px; not used) | 4229 | 4230 | 1 | 9 |
| 2026-10-18 | #23 / #31 doors: 7 map objects (Archibald's gilded vault, Malphas's blood seal, a boss gate per biome; 1 each) + 7 "open" object states (**10 each**, the cost was not known before the batch, so no estimate was written; states are not used again in this goal) | 4230 | 4307 | 77 | 86 |
| 2026-10-18 | #29 UI art: 5 Pixen icon sheets (equipment slot silhouettes, menu / tab icons, class crests and HUD, talent branch emblems, extras) + 4 ornaments (title banner, item slot, gold divider, gauge frame) + 1 unused corner | 4307 | 4317 | 10 | 96 |

## Done (MVP)

- [x] Foundation: folders, pixel-perfect settings, y-sort, autoloads, asset registry, generated placeholders
- [x] Input: all actions via InputMap, KB/mouse + gamepad defaults, full rebinding (2 KB + 2 pad slots per action),
      conflict resolution, reset, saved to `user://settings.cfg` (verified: rebind survives restart)
- [x] Networking: ENet + Steam behind `NetworkManager`, lobby with new/saved games (fixed party size), name/class or hero slots, host-only settings
      generated from `data/game_settings.json` (verified: host + client over LAN)
- [x] Combat core: Stats, Health, Mana/Fury, statuses, projectiles, melee arcs, AoE, zones, traps, crit, haste,
      dodge, leech, dash with i-frames, threat tables with hysteresis, taunts, friendly fire
- [x] 4 classes x 5 skills + primary attack (verified: every skill of every class goes through host validation)
- [x] Items: 5 rarities, affixes, 10 slots, 1H/2H rules, backpack + bigger backpacks, consumables on Q/E with radial
      menu, layered appearance, off-class penalty, level requirement (verified: trade + equip + appearance + penalty)
- [x] Loot: shared ground items, party-class weighting, rarity glow (shader + light + sparkles), drop to trade
- [x] Dungeon: seeded infinite floors, rooms + corridors, player doors (monsters open them after a delay),
      grid fog of war + LOS enemy visibility, destructible props (explosive barrels), lava, spikes, chests,
      3 monster types, phased boss + bonus loot + portal, scaling by players/level/depth
- [x] Progression: downed (10 s) -> revive / ghost spectate, wipe ends the saved game -> lobby, contribution-based shared XP,
      levels, talent trees, saving (verified over LAN)
- [x] Lighting (vision light with shadows, torches, lava, item and spell lights), glow, particles, screen shake
- [x] Darkness mechanic: dark ambient that deepens per floor, monsters/map only visible when lit, wall torches
      that can be taken (120 s) or broken, spells that light up the dark (`darkness` LAN test)
- [x] Audio manager with crossfaded floor/boss music and pooled SFX (placeholder files)
- [x] HUD, minimap, map, inventory, talents, pause, options; gamepad navigation (verified in-game overlays)
- [x] "Obsidian Glass" UI overhaul: pixel font + gilded frames (PixelLab), HP/resource/shield bars with damage
      trail, radial cooldown shader, rarity pulse shader, live portraits, paper-doll inventory with drag and drop,
      talent tree with links, live gamepad/keyboard glyph prompts, animated focus bracket, spring pop-ins, UI sounds
- [x] Unified game menu (Character / Inventory / Talents / Map tabs, shared title header) and the Character
      panel (hero, stats, skills) on C / R-stick click (verified: `ui-layout` test)
- [x] Final pixel art from PixelLab replaces every sprite placeholder: crypt tiles, walls, lava, props, doors,
      portal, item and skill icons, projectiles, slash/explosion/AoE effects, 3 monsters + boss, the player body
      with 9 animations and 20 baked equipment layers (sound is still placeholder)
- [x] Any aspect ratio from 1:1 to 32:9: stretch aspect `expand`, edge-pinned HUD in a safe margin, centered
      capped modals, camera view clamp (verified: `ui-layout` test at 720x720 .. 3840x1080; screenshots at
      720x720, 960x540, 1920x1080, 2560x1080 and a 32:9 window)
- [x] Export presets (Windows/Linux/macOS): all three export with the official 4.7.2 templates; the Linux
      release build runs headless (class test) and windowed with no errors. Re-exported 2026-10-16 after the playtest
      fixes (#1-#14): the presets keep `tests/` (the DevAuto autoload needs the suites), the Linux build
      passes `classes` and the `full` LAN pair
- [x] Steam: lobby creation, tagged lobby listing and SteamMultiplayerPeer hosting (automated, `run_tests.sh steam`)
- [x] Exported Linux release binary passes the LAN pair scenarios (full, real boss fight, wipe + second run,
      host ends session, client leaves) with no engine/script errors; ~60 FPS in the boss room (35 monsters)
- [x] Aggro in a real fight (warrior host vs mage client, both on skill rotations, 4 monsters): the warrior holds
      ~80-90% of targets, no back-and-forth switching within 2 s (`tank` test); priest tank: 100%
- [x] Real boss kill by two players with their skills (the harness teleports them to the boss and keeps them
      invulnerable so the test doesn't depend on balance), then portal -> floor 2
- [x] Gamepad drives menus end to end (main menu -> options rebinding -> lobby -> run -> overlays), simulated events
- [x] Character art rework: ~43 px heroes (64 px cells), male and female bodies, worn gear cut from PixelLab
      outfit transfers (plate and cloth sets) with hide masks so no body shows under gear (verified: `art-check`
      test, 0 body pixels in every frame), every animation drawn (cast/dash/hit too), held weapons in the hand in
      every frame (verified: `art-check`), drawn ghost (breathing idle), downed in worn gear, monsters and
      boss rescaled
- [x] Gender choice in the lobby with an animated, turnable preview (gamepad + mouse), saved with the hero
      (old saves default to male), replicated to every peer (verified: `gamepad-menu`, `continue`, `continue-lan`)
- [x] Lobby redesign: numbered steps, big preview, prominent "Confirm hero" with ready state (verified: `gamepad-menu`)
- [x] Ground spell effects (Consecration, traps, AoE rings) draw under enemies and heroes
- [x] Smooth, gentle mouse camera lean without feedback from the camera's own movement (verified: `ui-layout`)
- [x] Character panel: compact skill list, hover / focus tooltips with damage, healing, DoT, area, cooldown,
      cost, cast time and talent changes computed by the host formulas (verified: `ui-layout`)

## Not verified / open

- [x] Windows and macOS builds run (confirmed by the user on their machines).
- [ ] macOS export is unsigned (codesign/notarization off): Gatekeeper needs right-click -> Open.
- [x] Steam with two real accounts: a client joins through the test lobby (confirmed by the user).
- [x] Physical gamepad: Xbox Series controller over Bluetooth (Linux) works in game (confirmed by the user).
      `tools/pad_test.gd` walks through every control; `data/joy_mappings.txt` can override SDL mappings
      for pads with an unusual layout (the entry for this pad is commented out: not needed).
- [x] **Art for the Sewers, Foundry, Archives and Kurgan** (4 tilesets, 26 monsters + 3 recolour / reuse,
      8 bosses + Isolde's spider form and Krazik on foot, 46 props, 10 pact potion icons) after the user's
      checkpoint approval; sources in `tools/biome_art_sources.json`.
- [ ] **Music and SFX** (user, Suno): 17 music and 93 SFX keys, file paths and prompts in
      `docs/SUNO_PROMPTS.md`; drop the files in and run `python3 tools/register_audio.py`.
- [x] Worn art beyond plate / cloth: leather and mail families for both genders (#20).
- [x] Balance pass: measured by the `balance-<class>` suites against data pacing bands (see DECISIONS
      "Balance pass").
- [x] Steam smoke test after the GDD work: Steam init, lobby creation, game tag listing and the Steam peer
      as host (`tools/run_tests.sh steam`, 2026-10-16). A second-account join was confirmed earlier; recheck
      it on two machines when convenient.

- [x] Test hardening after the GDD runs (2026-10-16): the LAN door check picks a reachable door with an empty
      doorway (an open door never closes on someone standing in it), the blood tick's 3 s fuse gets a 5.5 s
      test window, the foundry splash check allows three pulses (one can be dodged), and the warded-dummy
      resist check prints both numbers if it ever misses (not reproduced in 8 reruns). The darkness check picks its dark spot with
      the same physics ray Visibility uses (a destructible prop could block sight while the grid check was
      clear), the tank check ignores taunt pulls, and the runner writes line-buffered logs.

- [x] Balance suite averages 400 hits per measurement instead of 24 (2026-10-18): damage ranges, crits and
      misses swung a hit by ±15% between runs, so rows near a band edge (ranger vs skeleton archer on floor 16,
      ttk ~0.3 s) failed at random; measured the same before and after the visual polish goal.

## Known limitations

- Movement is client-predicted; the host only clamps speed (no full reconciliation).
- Monsters path on a tile grid (AStarGrid2D) and use simple separation; large packs can bunch up in corridors.
- Spikes animate from each peer's floor clock (resynced every 5 s); visual timing can differ by a frame or two.
- Doors are drawn with placeholder sprites; vertical (side) doors are approximated.
- The `mcp_bridge_game.gd` autoload (editor tooling) is part of the project and also opens a local
  debug port in exported builds; remove it from the autoloads before shipping.
- Every monster streams its position at 20 Hz; fine for LAN/Steam at MVP sizes, but a candidate for
  relevance filtering if bandwidth becomes an issue.
