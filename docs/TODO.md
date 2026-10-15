# TODO

Status of the MVP (see `CLAUDE.md` for scope). Verified = covered by `tools/run_tests.sh` or a
manual run noted here.

## Done (MVP)

- [x] Foundation: folders, pixel-perfect settings, y-sort, autoloads, asset registry, generated placeholders
- [x] Input: all actions via InputMap, KB/mouse + gamepad defaults, full rebinding (2 KB + 2 pad slots per action),
      conflict resolution, reset, saved to `user://settings.cfg` (verified: rebind survives restart)
- [x] Networking: ENet + Steam behind `NetworkManager`, lobby with name/class, saved characters, host-only settings
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
- [x] Progression: downed (10 s) -> revive / ghost spectate, wipe -> lobby, contribution-based shared XP,
      levels, talent trees, saving (verified over LAN)
- [x] Lighting (vision light with shadows, torches, lava, item and spell lights), glow, particles, screen shake
- [x] Audio manager with crossfaded floor/boss music and pooled SFX (placeholder files)
- [x] HUD, minimap, map, inventory, talents, pause, options; gamepad navigation (verified in-game overlays)
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

## Not verified / open

- [ ] Windows and macOS builds export fine but could not be *run* here (Linux dev machine, no Wine). Smoke-test
      them (`funtasy.exe --headless -- --auto=solo --scenario=classes --quit=60` works on any platform).
- [ ] macOS export is unsigned (codesign/notarization off): Gatekeeper needs right-click -> Open.
- [ ] Steam with two real accounts (automated test covers lobby creation/listing and the Steam peer only).
- [x] Physical gamepad: Xbox Series controller over Bluetooth (Linux) works in game (confirmed by the user).
      `tools/pad_test.gd` walks through every control; `data/joy_mappings.txt` can override SDL mappings
      for pads with an unusual layout (the entry for this pad is commented out: not needed).
- [ ] Final art (Pixellab) and music (Suno): replace placeholders via `data/assets.json`.
- [ ] Balance pass: numbers in `data/balance.json` are first guesses.
- [ ] Confirm the wipe rules (currently: lose equipped items + backpack, keep level/talents).

## Known limitations

- Movement is client-predicted; the host only clamps speed (no full reconciliation).
- Monsters path on a tile grid (AStarGrid2D) and use simple separation; large packs can bunch up in corridors.
- Spikes animate from each peer's floor clock (resynced every 5 s); visual timing can differ by a frame or two.
- Doors are drawn with placeholder sprites; vertical (side) doors are approximated.
- The `mcp_bridge_game.gd` autoload (editor tooling) is part of the project and also opens a local
  debug port in exported builds; remove it from the autoloads before shipping.
- Every monster streams its position at 20 Hz; fine for LAN/Steam at MVP sizes, but a candidate for
  relevance filtering if bandwidth becomes an issue.
