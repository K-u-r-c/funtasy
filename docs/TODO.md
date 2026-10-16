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
      plates, pendulums), props, mechanics (unlit regen, urn miasma), lore drops (verified: `monsters`,
      `bosses`, `biomes`, `boss` + `boss-vespera` LAN pairs, full suite green, biome tour screenshots at
      1920x1080 and 3440x1440). **Visual checkpoint asked of the user on 2026-10-16; art for other
      biomes waits for the answer (placeholders meanwhile).**
- [x] **5. Sewers** (tileset, props, hazards, mechanics, 7 monsters, Murk Amalgam + Krazik, lore, music keys)
      (verified: `biomes-sewers`, `monsters`, `bosses`, `boss-amalgam` + `boss-krazik` LAN pairs, sewers
      tour screenshots). **Art: placeholders** (recoloured Crypt tiles, existing monster sheets with tints,
      generated prop icons) until the checkpoint answer.
- [x] **6. Foundry** (platforms over molten lakes, grates, flame jets, cauldrons, heat armor loss, magma
      geysers, 7 monsters, Ignis + Vulkania) (verified: `biomes-foundry`, `monsters`, `bosses`, `primitives`,
      `boss-ignis` + `boss-vulkania` LAN pairs, foundry tour screenshots). **Art: placeholders.**
- [x] **7. Archives** (library grid, round reading rooms, bookshelf doors, spatial anomalies, void rifts,
      silence runes, animated books, 7 monsters, Malazar + the Memory Devourer, Tome Prison side arena)
      (verified: `biomes-archives`, `monsters`, `bosses`, `boss-malazar` + `boss-devourer` LAN pairs, archives
      tour screenshots). **Art: placeholders.**
- [x] **8. Kurgan** (caverns, blood pools, sprouting thorns, root snares, dread totems, ground fog, 7 monsters,
      Cernunnos + Isolde) (verified: `biomes-kurgan`, `monsters`, `bosses`, `boss-cernunnos` + `boss-isolde` LAN
      pairs, kurgan tour screenshots). **Art: placeholders.**
- [x] **9. Legendaries**: 108 items + affix hooks + icons + drop rules + tooltips (verified: `economy-lan` (a client equips a legendary through the host and its proc fires), `legendaries-warrior/
      ranger/mage/priest` suites prove every affix, `primitives`, `skills-*`, `economy`, `ui-layout`, legendary
      tour screenshots at 1920x1080 and 3440x1440). Icons: 7 Pixen sheets of 16 cut by `tools/cut_icon_sheet.py`.
- [x] **10. Integration**: balance pass (`balance-<class>` suites, blood pool fix), audio keys + Suno prompt
      list (`docs/SUNO_PROMPTS.md`), README / DECISIONS / TODO, full test suite, LAN pairs for every boss +
      Steam smoke test (init, lobby, tag, host peer), final screenshot tours of every biome and boss at
      1920x1080 and 3440x1440 and the legendary item cards

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
      release build runs headless (class test) and windowed with no errors
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
- [ ] **Art for the Sewers, Foundry, Archives and Kurgan** (tilesets, 28 monsters, 8 bosses, biome props):
      placeholders until the user answers the phase-4 visual checkpoint (look, scale, method). PixelLab
      left at the end of the goal: 771 of 2000 (reset 2026-11-14).
- [ ] **Music and SFX** (user, Suno): 17 music and 93 SFX keys, file paths and prompts in
      `docs/SUNO_PROMPTS.md`; drop the files in and run `python3 tools/register_audio.py`.
- [ ] Optional worn art: new armour sets beyond the plate / cloth layers (legendaries reuse them).
- [x] Balance pass: measured by the `balance-<class>` suites against data pacing bands (see DECISIONS
      "Balance pass").
- [x] Steam smoke test after the GDD work: Steam init, lobby creation, game tag listing and the Steam peer
      as host (`tools/run_tests.sh steam`, 2026-10-16). A second-account join was confirmed earlier; recheck
      it on two machines when convenient.

## Known limitations

- Movement is client-predicted; the host only clamps speed (no full reconciliation).
- Monsters path on a tile grid (AStarGrid2D) and use simple separation; large packs can bunch up in corridors.
- Spikes animate from each peer's floor clock (resynced every 5 s); visual timing can differ by a frame or two.
- Doors are drawn with placeholder sprites; vertical (side) doors are approximated.
- The `mcp_bridge_game.gd` autoload (editor tooling) is part of the project and also opens a local
  debug port in exported builds; remove it from the autoloads before shipping.
- Every monster streams its position at 20 Hz; fine for LAN/Steam at MVP sizes, but a candidate for
  relevance filtering if bandwidth becomes an issue.
