# Funtasy

A dark fantasy co-op (1-4 players) 2D dungeon crawler for Godot 4: light 3/4 view,
8-direction 64x64 characters, dynamic lighting and fog of war, an infinite procedural dungeon
with a boss on every floor, shared random loot, four classes and talent trees.

The game implements the full Game Design Document: 5 biomes, 35 monsters with behaviour modules,
elites and altars, 10 bosses with phases and arena mechanics, 120 class skills, 3-branch talent trees
with keystones and a Skill Book loadout, damage types and resistances, gold, merchants (Archibald's
shared shop, Malphas's tithe, contracts and pact potions), 108 legendaries and 105 lore books with a
permanent codex. All art is PixelLab pixel art (sources in `tools/biome_art_sources.json` and the
PixelLab tools in `tools/`); every sound is a placeholder until the Suno files are dropped in (see
`docs/SUNO_PROMPTS.md`).

## Requirements

- Godot **4.7** (standard build, GDScript only).
- The GodotSteam GDExtension is bundled in `addons/godotsteam/` (Windows, Linux, macOS).
  Steam features need the Steam client running; everything else works without it.

## Running

```sh
godot --path .            # or open project.godot in the editor and press F5
```

Main menu -> **Play**:

| Option | What it does |
| --- | --- |
| Solo | Offline game (you are the host). |
| Host LAN game | Hosts on UDP port **7777** (ENet). |
| Join LAN game | Enter the host's IP (and port) and connect. |
| Host Steam lobby | Creates a public Steam lobby (test app id 480 / Spacewar). |
| Join Steam lobby | Lists lobbies tagged for this game; pick one. |

In the **lobby** the host picks **New game** or one of their **saved games**:

- *New game*: every player enters a name and picks a class (a fresh level 1 hero, in underwear).
- *Saved game*: it must be continued by exactly the same number of players; every player takes one
  of its heroes (level, items and talents are kept) and the party resumes on the floor it reached.

Heroes only exist inside their game, so they can't be taken into another party, and a party wipe
ends the game for good (its save is deleted). Only the host can change the game settings
(friendly fire, difficulty, shared vision) and start the run once the party is ready.

### Hosting over LAN

1. Host: *Host LAN game*. Allow UDP 7777 through the firewall.
2. Others: *Join LAN game* -> host's LAN IP (e.g. `192.168.1.20`) -> *Connect*.
3. For internet play without Steam, forward UDP 7777 on the host's router and join its public IP.

### Hosting over Steam

1. Start the Steam client and log in on both machines (two different accounts).
2. Host: *Host Steam lobby*. Others: *Join Steam lobby* -> select the lobby.
3. The project uses Valve's public test app **480 (Spacewar)**; Steam may show you as playing
   "Spacewar". To ship, set your own app id in `autoload/network_manager.gd` (`APP_ID`).

## Controls (all rebindable in Options -> Controls)

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Move | W A S D | Left stick |
| Aim | Mouse cursor | Right stick |
| Primary attack | Left mouse | RT |
| Skills 1-5 | 1 2 3 4 5 | A B X Y RB |
| Dodge (i-frames) | Space or Shift | LT |
| Quick items Q / E (tap: use, hold: radial menu) | Q / E | LB / D-pad Right |
| Interact / revive (hold): the target under the cursor, or the one you face on a pad | F | D-pad Down |
| Character / Inventory / Talents / Map | C / I / T / M | R-Stick click / View / D-pad Left / D-pad Up |
| Skill Book / Codex | K / L | (menu tabs, LB / RB) |
| Switch menu tab (while a menu is open) | Q / E | LB / RB |
| Menu | Esc | Menu |

In menus: arrows / D-pad / left stick to move, Enter / A to confirm, Esc / B to go back,
Q/E or LB/RB to switch tabs. In the inventory: confirm = equip/unequip, X / right click = drop
on the ground (that's how you give items to teammates), R / Y = put a potion on E.

## Gameplay summary

- **Classes**: Warrior (Fury, melee tank/DPS), Ranger (Mana, ranged, traps, poison),
  Mage (Mana, elemental spells), Priest (Mana, holy tank/healer). 30 skills per class: talent
  nodes unlock them, the Skill Book picks which 5 sit on keys 1-5. Three talent branches of 6 tiers
  each, with keystones at tiers 2 and 5. Every level also gives 5 stat points.
- **Biomes** (one per floor type, picked by depth): the Forgotten Crypt, the Sewers, the Infernal
  Foundry, the Shrouded Archives and the Blighted Kurgan, each with its own architecture, hazards,
  environment mechanics, 7 monsters and 2 bosses (one is picked per floor from the seed).
- **Merchant chamber** on every floor: Archibald sells (prices in gold, shared stock), Malphas takes
  a tithe of your power for contracts and pact potions; a Gold Key makes Archibald trade. Each floor has one of them, in its own room.
- **Elites** carry modifiers and guard altars; **legendaries** (orange) have unique affixes.
- **Lore**: books drop in the dungeon; reading one adds it to the permanent Codex (all heroes).
- **Death**: at 0 HP you are downed for 10 s; a teammate holds Interact next to you to revive.
  Otherwise you become a ghost and spectate until the next floor. If nobody is left standing
  the party is wiped and that game is over (its save is deleted).
- **Darkness**: the dungeon is nearly pitch black and gets darker every floor. You only see
  monsters that are lit, by torches, lava or spells. Take a torch from a wall (Interact); it burns
  for about 2 minutes. Attacks break wall torches, so think before you swing near them.
- **Loot** is shared and lies on the ground, glowing in its rarity color
  (white, green, blue, purple, orange). Weapons of another class deal 80% less damage.
- **Floors**: kill the boss to open the portal; every living player interacts with it to get
  ready, and the party descends once everyone alive is ready. Difficulty scales with party size, level and depth.

## Project layout

```
autoload/        EventBus, GameData, SaveSystem, Settings, InputSettings, AudioManager,
                 NetworkManager, GameState, SceneManager, DevAuto (test driver)
scenes/          menus/, dungeon/game.tscn (everything else is built from scripts + data)
scripts/core/    Actor, Stats, Health, ResourcePool, StatusEffects, ThreatTable, Combat, CombatFx, ...
scripts/classes/ Player
scripts/enemies/ Enemy AI, Boss phases, behaviors/ (monster modules), boss_mechanics/ (arena mechanics)
scripts/items/   ItemGenerator, LootTable, Inventory, GroundItem, LootManager, LegendaryAffixes
scripts/dungeon/ DungeonGenerator, Dungeon, Door, Prop, Spikes, Torch, Portal, Visibility, Game,
                 Merchants, hazards (plates, spouts, grates), mechanics/ (biome rules)
scripts/ui/      theme, menus, lobby, options, HUD, overlays
scripts/net/     NetSync (synchronizer helper)
data/            balance, classes, skills, talents, items (bases, affixes, legendaries), monsters, bosses,
                 floor types, statuses, damage types, elites, merchants, lore books, settings, assets
tests/           test suites driven by DevAuto (skills, legendaries, monsters, bosses, biomes, economy,
                 lore) and the screenshot tours
assets/          placeholder sprites/audio + shaders
tools/           gen_placeholders.gd, check_scripts.gd, run_tests.sh,
                 pixellab_import.gd / pixellab_build_char.py (PixelLab art -> sheets),
                 build_hero.py + hero_<gender>[_sources].json (hero body + worn gear:
                 gear_cut.gd, body_regions.gd, bake_gear.gd), build_monster.py, build_monster_zip.py
                 (v3 monsters from a character download), build_blob.py (shapeless creatures from one
                 sprite), cut_icon_sheet.py, gen_suno_prompts.py, register_audio.py
docs/            DECISIONS.md, TODO.md, DATA.md, SUNO_PROMPTS.md
```

Everything tunable (stats, formulas, drop rates, scaling, skills, talents, monsters, boss
phases, floor generation parameters, lobby settings, default bindings) lives in `data/`.

## Replacing placeholder art and audio

All assets are referenced by key in **`data/assets.json`**; nothing else needs to change.

- **Characters / monsters** (Pixellab): one folder per set with one PNG per animation
  (`idle, walk, attack, cast, dash, hit, downed, death, ghost`). Each sheet: **8 rows** in the
  order **E, SE, S, SW, W, NW, N, NE**, one column per frame, 64x64 frames (monsters may use other
  sizes via `frame_size`). Frame counts and FPS are set in `characters.anims` (override per set
  with an `anims` key). Add `"normal": "res://.../normals/"` with the same sheet layout to light
  the set with normal maps. Heroes have one body per gender (`characters.genders`: `body_male`,
  ...) and equipment layers per gender (`m_head_helm`, `m_chest_robe`, `m_weapon_sword`, ...;
  key = gender prefix + the item's `appearance`) with the same layout. Worn pieces with
  `"hide": true` also ship hide masks (`<layer>/hide/<anim>.png`): the body pixels they cover,
  which the body shader drops so no skin shows under gear. Rebuild hero art with
  `python3 tools/build_hero.py tools/hero_male_sources.json <work dir>` (see
  `docs/DECISIONS.md` "Character art pipeline"); verify with the `art-check` test.
- **Tiles**: one atlas per floor type (`tiles.crypt`), cell coordinates listed in the registry.
- **Props, items, projectiles, icons, FX**: single PNGs (sheets for animated ones: `frames`).
- **Music / SFX** (Suno): save each file as `assets/audio/music/<key>.ogg` or
  `assets/audio/sfx/<key>.ogg` (`.mp3` / `.wav` work too) and run `python3 tools/register_audio.py`.
  The keys, paths and a prompt for each are in `docs/SUNO_PROMPTS.md` (regenerate it with
  `python3 tools/gen_suno_prompts.py`). Music always loops; floor music is set per floor type in
  `data/floor_types/*.json` and boss music per boss in `data/bosses/*.json`.
- Keep user-provided files next to the placeholders; `tools/gen_placeholders.gd` only writes
  into `placeholder/` folders.

Regenerate placeholders: `godot --headless --path . -s tools/gen_placeholders.gd` then
`godot --headless --path . --import`.

## Languages

The game is in English and Polish (Options -> Video -> Language, or `--lang=pl` on the command
line). English text in code and data is the translation key; the Polish lives in
`data/i18n/translations.csv`. After adding or changing player-facing text run
`python3 tools/i18n_extract.py` (adds new keys with an empty Polish entry, drops stale ones), fill
in the Polish, and check with `python3 tools/i18n_extract.py --check` (also run by
`tools/run_tests.sh`). Godot builds the `.translation` file from the CSV on import.

## Tests

```sh
./run_tests.sh              # same as tools/run_tests.sh
tools/run_tests.sh          # script check, solo class runs, UI layout (1:1..32:9), gamepad, rebinding, LAN pairs
tools/run_tests.sh quick    # without the LAN pairs
tools/run_tests.sh lan      # only the 2-instance LAN scenarios
tools/run_tests.sh steam    # Steam lobby smoke test (Steam client must be running)
```

Solo suites: every class's 30 skills and keystones, every legendary's affix, every monster's
behaviour, every boss phase and arena mechanic, every biome's hazards and mechanics, economy
(gold, shop, tithe, contracts, pacts, altars), lore and codex, UI layout and gamepad focus at
aspect ratios 1:1 to 32:9.

LAN pairs: full feature walk-through, a real fight against each of the 10 bosses, aggro (tank vs DPS),
skills and economy over the network, continuing a saved 2-player game, darkness, wipe + second run,
host ending the session, client leaving mid-run.

Visual tour (windowed): `godot --path . -- --scenario=shots --shot=/tmp/shots --class=mage` saves
screenshots of every screen. Feature tours: `godot --path . -- --nosteam --auto=solo --class=mage
--scenario=tour --tour=<combat|menus|merchants|lore|skills|biome|statuses|legendaries> [--biome=<id>]
[--boss=<id>] --window=1920x1080 --shot=/tmp/tour`.

The tests drive real game instances headless through `autoload/dev_auto.gd`
(`--auto=host|join|solo --scenario=...`); see that file for the scenarios. Note that test runs
use throw-away profiles (`user://profiles/test_*`), so your saves are never touched.

## Exporting

`export_presets.cfg` contains Windows, Linux and macOS presets (macOS is unsigned). Install the
Godot 4.7.2 export templates (Editor -> Manage Export Templates), then e.g.

```sh
godot --headless --path . --export-release "Linux" build/linux/funtasy.x86_64
```

The presets include `data/*.json` (non-resource files) and the Steam libraries.
