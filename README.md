# Funtasy

A dark fantasy co-op (1-4 players) 2D dungeon crawler for Godot 4: light 3/4 view,
8-direction 64x64 characters, dynamic lighting and fog of war, an infinite procedural dungeon
with a boss on every floor, shared random loot, four classes and talent trees.

This is the **MVP**: the full loop works (menu -> lobby -> dungeon -> combat -> loot -> boss ->
next floor) with placeholder art and silent placeholder music.

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
| Interact / revive (hold) | F | D-pad Down |
| Inventory / Talents / Map | I / T / M | View / D-pad Left / D-pad Up |
| Menu | Esc | Menu |

In menus: arrows / D-pad / left stick to move, Enter / A to confirm, Esc / B to go back,
Q/E or LB/RB to switch tabs. In the inventory: confirm = equip/unequip, X / right click = drop
on the ground (that's how you give items to teammates), R / Y = put a potion on E.

## Gameplay summary

- **Classes**: Warrior (Fury, melee tank/DPS), Ranger (Mana, ranged, traps, poison),
  Mage (Mana, elemental spells), Priest (Mana, holy tank/healer). 5 skills each, all on cooldown.
- **Death**: at 0 HP you are downed for 10 s; a teammate holds Interact next to you to revive.
  Otherwise you become a ghost and spectate until the next floor. If nobody is left standing
  the party is wiped and that game is over (its save is deleted).
- **Loot** is shared and lies on the ground, glowing in its rarity color
  (white, green, blue, purple, orange). Weapons of another class deal 80% less damage.
- **Floors**: kill the boss to open the portal; when everyone alive stands in it the party
  descends. Difficulty scales with party size, level and depth.

## Project layout

```
autoload/        EventBus, GameData, SaveSystem, Settings, InputSettings, AudioManager,
                 NetworkManager, GameState, SceneManager, DevAuto (test driver)
scenes/          menus/, dungeon/game.tscn (everything else is built from scripts + data)
scripts/core/    Actor, Stats, Health, ResourcePool, StatusEffects, ThreatTable, Combat, CombatFx, ...
scripts/classes/ Player
scripts/enemies/ Enemy AI, Boss phases
scripts/items/   ItemGenerator, LootTable, Inventory, GroundItem, LootManager
scripts/dungeon/ DungeonGenerator, Dungeon, Door, Prop, Spikes, Torch, Portal, Visibility, Game
scripts/ui/      theme, menus, lobby, options, HUD, overlays
scripts/net/     NetSync (synchronizer helper)
data/            balance, classes, skills, talents, items, monsters, bosses, floor types, settings, assets
assets/          placeholder sprites/audio + shaders
tools/           gen_placeholders.gd, check_scripts.gd, run_tests.sh
docs/            DECISIONS.md, TODO.md
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
  the set with normal maps. Equipment layers (`head_*`, `chest_*`, `weapon_*`, ...) use the same
  layout and are drawn on top of `body_human`; they are tinted by the item color, so light/grey
  art works best.
- **Tiles**: one atlas per floor type (`tiles.crypt`), cell coordinates listed in the registry.
- **Props, items, projectiles, icons, FX**: single PNGs (sheets for animated ones: `frames`).
- **Music / SFX** (Suno): drop `.ogg`/`.wav` files in `assets/audio/` and point `music.*` /
  `sfx.*` at them. Music always loops. Floor music and boss music are chosen per floor type in
  `data/floor_types/*.json`.
- Keep user-provided files next to the placeholders; `tools/gen_placeholders.gd` only writes
  into `placeholder/` folders.

Regenerate placeholders: `godot --headless --path . -s tools/gen_placeholders.gd` then
`godot --headless --path . --import`.

## Tests

```sh
tools/run_tests.sh          # script check, solo class runs, gamepad, rebinding, LAN host+client pairs
tools/run_tests.sh quick    # without the LAN pairs
tools/run_tests.sh lan      # only the 2-instance LAN scenarios
tools/run_tests.sh steam    # Steam lobby smoke test (Steam client must be running)
```

LAN pairs: full feature walk-through, a real boss fight, aggro (tank vs DPS), continuing a saved
2-player game, wipe + second run,
host ending the session, client leaving mid-run.

Visual tour (windowed): `godot --path . -- --scenario=shots --shot=/tmp/shots --class=mage` saves
screenshots of every screen.

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
