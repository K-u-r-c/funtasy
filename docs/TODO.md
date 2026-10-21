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
- [x] #27 83 new passive talents with icons, 3 talent and 10 stat points per level (back to 1 and 5 in #45), old saves topped up (`talents-*`, `balance-*`)
- [x] #23 / #31 One sealed entrance per merchant room and boss chamber, door art per merchant and per biome (`biomes-*`, `economy`, `economy-lan`)
- [x] #29 UI overhaul: icons, ornaments, chips and gauges on every screen (`ui-layout`, tours)
- [x] #32 Polish localization (2369 keys incl. 105 lore books) and a live language option (`i18n`, `i18n-lan`, `ui-layout-pl`)
- [x] Bilingual screenshot review (English and Polish): shots flow, tours `menus`, `merchants`, `lore`, `skills`, `options`, `boss_doors` (every biome, near and far), `gait` (run, hasted, slowed) and `map_marks`; the Linux release build smoke-tested with `--lang=pl`

## Third playtest issues (GitHub #33-#39)

- [x] #38 Closing a book returns to the inventory / codex it was opened from (`lore`)
- [x] #35 Several things at one spot: switch with G / left stick click, takeable items first, the door when the item can't be taken, no loot in doorways (`interact`, `interact-lan`)
- [x] #37 Party frames show teammates' buffs and debuffs; every status has an icon (`party`, `party-lan`)
- [x] #39 Friendly targeting: Tab / right stick click / a click on a teammate or party frame; ally spells land on the pick (`target-lan`)
- [x] #33 Heal burst, heal-over-time glow, shield bubble and break, buff and cleanse flashes on allies (`fx-lan`)
- [x] #34 Nine element looks for AoE impacts and lingering zones (`fx`, `fx-lan`)
- [x] #36 Sewer drain pipes and Foundry furnace vents on every wall side, with a telegraph before each spray (`spouts-sewers`, `spouts-foundry`)
- [x] Screenshot review in English and Polish: tours `interact`, `party` (16:9 and 32:9), `target`, `bookback`, `allyfx`, `elements`, `spouts` and `spout_sides` (Sewers, Foundry, every wall side); the Linux release build checked with `--lang=pl`

## Fourth playtest issues (GitHub #40-#46)

- [x] #45 5 stat points and 1 talent point per level, tier gate 2, over-spent saves refunded with a message (`talents-*`, `balance-*`)
- [x] #40 A click on empty space or on the picked teammate clears the friendly target; the empty-ground click still attacks (`target-lan`, tour `target_clear`)
- [x] #41 Enemy lock: R / D-pad Left / a click on a visible enemy; aimed attacks go to it, host-validated; red reticle and boss bar frame (removed in #53, with its `hostile-lan` suite and `hostile` tour)
- [x] #42 Skills 1-5: tap casts on release, hold shows the aim preview from the skill data, release casts; refused casts preview in red with the reason (`preview`, `skills-*`, tour `previews`)
- [x] #43 Talent, Skill Book and bar tooltips with exact numbers from the data, per-rank / now / next for ranks, keystone triggers (`tooltips`, `tooltips-pl`, tour `talent_tips`)
- [x] #44 Long text never leaves the screen: HUD messages and prompts wrap, lobby rows wrap / ellipsize; every screen checked at 16:9, 32:9, 4:3 and 1:1 in both languages (`ui-fit*`)
- [x] #46 Doors stay visible lit from behind and still close their opening to light; prop shadows start at the foot (one-sided occluder lines; `lighting-rules`, tour `lighting_sides` in all biomes)
- [x] Screenshot review in English and Polish: tours `points`, `target_clear`, `hostile` (removed in #53), `previews`, `talent_tips` (all four classes), `lighting_sides` (all five biomes), the `ui-fit` shots (HUD and lobby, before / after)

## Fifth playtest issues (GitHub #47-#54)

- [x] #53 Enemy targeting removed; a click on an enemy is an attack, skills aim at the cursor, D-pad Left opens Talents again, old settings migrated (`target-lan`, `rebind`, `rebind-check`, `gamepad-menu`, tour `controls`)
- [x] #54 Charge-up skills pay their cost and cooldown on release; nothing spent when cancelled, interrupted or unaffordable; the HUD slot and aim preview show the charge (`preview`, `skills-lan`, tour `charge`)
- [x] #52 A quiver goes with every bow and crossbow, new and saved (`continue`, tour `quiver`)
- [x] #50 A closed door never shadows a torch-bearer next to it and lets no light past its sides (`lighting-rules`, tour `door_torch` in all five biomes)
- [x] #48 Level-up effect on the hero for every peer and an animated banner for its player, once per XP gain with the final level and all points (`levelup-lan`, tour `level_up`)
- [x] #49 Bone piles and corpses being raised show a mark with a countdown on every peer (`rise-lan`, tour `rise`)
- [x] #51 Sewers lever: PixelLab housing and arm, the arm swings from off to on with dust, sparks and a clunk, a red / green lamp readable from afar (`lever-lan`, tour `lever`)
- [x] #47 Talent trees as real trees: prerequisites, forks, keystones at path ends, a T5 keystone needs 16 points; a drawn tree panel with lines, node states and a learn animation; old saves refunded (`talents-*`, `talents-lan`, tour `talent_tree`)
- [x] LAN boss tests: against the Murk Amalgam's twins each hero goes for the twin its primary attack can hurt (two heroes left at the wrong twins stalled one run for 240 s)
- [x] LAN `tank` test steadied: the test tank fights with its tank kit (Taunting Shout, Shield Slam) and taunts when it peels a monster off the mage; the share had swung between 57% and 100% against the 70% bar (75-100% before this round too), now 77-100% over 8 runs
- [x] Screenshot review in English and Polish: tours `controls`, `charge`, `quiver`, `door_torch` (all five biomes), `level_up`, `rise`, `lever` (Sewers) and `talent_tree` (all four classes: locked, partly learned, a branch to its end, learn animation frames); the Linux release build smoke-tested with `--lang=pl`

## Sixth playtest issues (GitHub #55-#59)

- [x] #57 Next floor: every copy of a hero (host, owner, other clients) snaps to the start, stale position packets are held off by a teleport counter, the camera cuts instead of panning (`teleport-lan`, 3 instances, with a simulated slow link)
- [x] #56 The host keeps full speed out of focus: V-Sync off and a 60 fps cap while unfocused, restored on focus (`background-lan`; measured with a real hidden window on Hyprland: 1 -> 60 frames per second)
- [x] #58 Deeper floors grow a little: +2.5% rooms (and grid area) per floor, at most 1.5x from floor 21 (`biomes*` depths 1-40 in every biome, `teleport-lan` same layout on every peer)
- [x] #59 Your own hero: a cyan ring with turning ticks under the feet and a pin over the head on your screen only, teammates a faint ring in their class colour, kept while downed, an option to turn it off (`marker-lan`, 4 instances; screenshots of four windowed peers, marker on and off)
- [x] #55 A continued game resumes its floor: run seed and a floor snapshot in the save (monsters, boss / portal, items, props, chests, doors, torches, cells, Gold Key, merchant, every hero's place / HP / life state, every player's map), written on quit, window close, boss kill and every 20 s (`resume`, `resume-lan`; old saves still load)
- [x] #60 The lobby preview of a saved hero shows its saved gear (replicated with the game info), on the host and every client (`resume`, `resume-lan`; lobby screenshot before / after)

## Ninth playtest issues (GitHub #83-#100)

- [x] #83 Shots go where the cursor points: mouse aims take the ground point under the cursor for shots, beams, swings and target picks (shots drawn at chest height now pass through it), areas land on it, the preview draws shots at chest height, clients keep their aimed direction despite lag (`aim`, `aim-lan`)
- [x] #85 Long texts scroll inside fixed-width cards (inventory, talents, merchants, forge), cards rebuilt without a one-frame double; the talent book selects on click, previews on hover, learns with a Learn button / double-click / accept (`ui-stable`, `ui-stable-pl`)
- [x] #86 Stacks merge: drag a stack onto the same item's stack (up to the stack limit, the rest stays), or Merge stacks in the amount picker (keyboard / gamepad); host-checked (`stacks`, `stacks-lan`)
- [x] #87 Map screen: the floor modifier is a small badge in the header; its card only on hover / focus, floating over the map (`mods`)
- [x] #88 The floor modifier vote window closes when the floor changes, on every peer (`mods`, `mods-lan`)
- [x] #89 Forging is clicked through: forging again ends the running animation at once; the animation is 1.7 s instead of 3 (`forge`)
- [x] #90 The forge list only selects (hover previews); the Forge button upgrades the selected piece; accept on a row moves to the button (`forge`)
- [x] #91 The forge window never moves during or after an upgrade; no upgrade message; a warm light sweeps the card (pixel-stepped shader) with rising motes (`forge`)
- [x] #92 Forging costs 1.5x (base 15); a legendary kept current takes 63-93% of a hero's floor gold (`forge`)

## Eighth playtest issues (GitHub #70-#82)

- [x] #74 Deep variants: corrupted monsters from floor 8 (10% + 1.2%/floor up to 30%, data) with one of five warned abilities (Blightwalker, Splitting, Warding, Shadowstep, Volatile), the "Corrupted" name, tint, aura shader and better loot; ascended bosses (a boss met before, or from floor 11) with ten warned extra mechanics, a halo and golden aura, tougher and richer; saved with the floor; balance probe (`deep`, `deep-lan`)
- [x] #76 Five legendary tomes, one story: the Ownerless Book I-V (lore_105 + four new chapters on the dungeon's origin, its five houses and why it goes down, EN + PL), found in order on a run (chapter N only after N-1 was read, none twice), +1 talent / +5 stat points each once, the legendary beam and message, "Chapter II of V" in the reader with its own black-and-gold book, the cycle grouped first in the codex, a balance probe for the full cycle (`lore`)
- [x] #78 NPC speech bubbles: Archibald, Malphas, Rolf and the four prisoners speak a line (10+ each, EN + PL, biome / party aware) the first time the local hero itself sees them on a floor, never through walls or doors, "again" lines on later floors, a prisoner's thanks when freed; typed-out glass bubble that follows the speaker and keeps off the hero (`npc-talk`, `npc-talk-lan`)
- [x] #72 Special rooms and events, 1-3 a floor from floor 2 (seeded, data): the Arena (doors seal after a warning, three warned waves with a HUD counter, a rising trial chest), the Sealed Vault (a leaf opened by a lever elsewhere, linked on the map once seen), the Bargain Shrine (two floor-long bargains on choice cards with their price), the Cursed Chest (maybe a mimic with a subtle breath, a 1.3 s waking), the Prisoner (a caged adventurer, the cell key from a guard elite, freed as an ally or a reward); markers, tracker lines, tells, telegraphs, saved with the floor, balance probe (`events`, `events-lan`)
- [x] #77 The blacksmith's forge on half of the floors (seeded): a sealed leaf chamber with Rolf Hult (PixelLab sprite + strike / wipe / look-up animations, sparks, clang), hearth light, anvil, quench barrel, tool rack, its own door and map icon; gold upgrades one item level at a time up to min(hero level, floor item level), the item recomputed exactly as dropped at that level (legendaries, boon uniques, old saves), price by rarity, level and party size checked against floor gold; the Obsidian Glass forge window with the now -> after card and the forging animation (`forge`, `forge-lan`, `biomes`)
- [x] #81 Gameplay visual effects: dodge afterimages, avoid blur, parry / block sparks, crit streak + hit-stop, element hit flash, leech motes, absorb ripple, reflect spikes, a visual per status family, aggro pop, elite target lines and modifier signatures, interrupt shatter, knock dust, XP / gold / item flights, revive beam, footsteps, lava shimmer, decals, refused skill shake, low-health vignette + heartbeat; "Screen effects" option (`gfx`, `gfx-lan`)
- [x] #73 Boons: 54 per class + 44 shared (260, each with its own PixelLab icon), three per hero after every boss (stat / item / synergy, tag-weighted), cards with a pick flight and flare, portrait and Character panel badges, portal waits, saved with the hero, average boon set in the balance probes (`boons-*`, `boons-lan`, `balance-*`)
- [x] #71 Floor modifiers from floor 4 (Swarm, Elite floor, Dimmed, Restless, Hunted): seeded offer of two at the portal, party vote on large cards, host pick, HUD / banner / map badges, Restless meter and Hunted rift telegraphs, floor cost balance probe (`mods`, `mods-lan`, `balance-*`)
- [x] #75 Loot flies out of its source (arc, spin, rarity trail, bounce, puff, light and sound on landing), no pick-up mid-air, a named legendary guaranteed from each floor's enemies (boss tops it up), legendary beam and message (`drops`, `drops-lan`)
- [x] #70 Biome order shuffled per cycle from floor 6 (no repeats back to back), mixed floors from floor 6 (invader monsters and sometimes a hazard), boss alternates per biome, floor arrival banner with biome crests and badges (`biomes`, `teleport-lan`)
- [x] #82 Ghosts roam the floor: walk, open doors, map grows, own blue light for their own sight, untouchable and unable to act, faint to the living, alive again next floor (`ghost-lan`, 3 instances; windowed screenshots)
- [x] #80 Carried torches burn 5 minutes (warning at 10%); lobby setting Torches off: every hero carries a steady light of a torch's size, wall torches are decoration, no HUD torch line (`lighting-rules`, `darkness`)
- [x] #79 Light and hands stop at walls: wall faces stop lights behind them, torches / closed doors / spouts are drawn lit only when seen, no interaction through a wall or closed door (`lighting-rules`, `interact*`, windowed `leak_probe` in all biomes)
- [x] Playtest: the own-hero marker shows only while Dodge is held a moment (`marker-lan`); the HUD health fill is as wide as the resource bar (one gauge of the ornament sheet, caps outside the fill)
## Seventh playtest issues (GitHub #61-#62)

- [x] #61 Split item stacks: drop or split off part of a stack through an amount picker, host-checked (`stacks`, `stacks-lan`)
- [x] #69 Lore: 100 new books and all 105 rewritten, in English and proofread Polish (`lore`, `i18n`)
- [x] #68 Fewer extra monsters per room in a big party: x1.5 with four heroes instead of x1.9; +25% XP per kill (`biomes`, `balance-*`)
- [x] #67 Priest Smite: no casting through walls, nerfed heal and mana, a click on an ally picks and casts, a restrained light-ray effect (`smite-lan`)
- [x] #66 Every remaining English text translated; extractor finds the keys it missed; `pl-sweep` reads back cards, screens, hover texts and messages in Polish
- [x] #65 Rarer drops deeper, very slowly (Rare+ 14% -> 27% by floor 50); random Relics fixed at ~0.3%; named legendaries rare at any depth, bosses 18% (`loot-rarity`)
- [x] #64 Many more gear names (66 suffixes, stat pairs) and quality prefixes (fine / superior / flawless, +10/20/30% stats) agreeing with the gender in Polish (`gear-names`)
- [x] #63 Elite altars rise on open floor, never in a doorway or corridor; saved ones are moved off on restore (`altars`)
- [x] #62 Foundry: the magma eruptions under the heroes' feet are removed (`biomes-foundry`: 30 s beside lava without damage)

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

Third playtest goal (#33-#39), start 2026-10-18: **used 4317, remaining 489**, resets 2026-11-14.
Goal cap: 150 generations, 150 kept in reserve. Planned: status icons ~5 (Pixen sheets), spout pipes / vents per wall side ~8-12, effect sprites only where particles / shaders / the free workbenches fall short.

| Date | Batch | Used before | Used after | Spend | Goal spend |
| --- | --- | --- | --- | --- | --- |
| 2026-10-18 | (goal start) | 4317 | 4317 | 0 | 0 |
| 2026-10-18 | #37 status icons: 5 Pixen 128x128 sheets of 16 (76 statuses without a skill / potion / legendary icon to reuse; 113 others reuse those) | 4317 | 4322 | 5 | 5 |
| 2026-10-18 | #33 / #34 effects: 24 animations from the free vfx workbench (heal, heal over time, shield bubble and break, buff, cleanse; 9 element bursts and 9 zones) | 4322 | 4322 | 0 | 5 |
| 2026-10-18 | #36 wall spouts: 2 map objects 48x48 (Sewers drain pipe, Foundry furnace vent) | 4322 | 4324 | 2 | 7 |
| 2026-10-19 | #36 spouts on every wall side: 2 top-down map objects 48x48 (drain pipe, furnace nozzle); came out diagonal, unused | 4324 | 4326 | 2 | 9 |
| 2026-10-19 | #36 spouts on every wall side: 2 top-down map objects 64x32, straight, mouth right (drain pipe, furnace nozzle, the nozzle recoloured) | 4326 | 4328 | 2 | 11 |

Fourth playtest goal (#40-#46), start 2026-10-19: **used 4328, remaining 478**, resets 2026-11-14.
Goal cap: 60 generations, 150 kept in reserve. Spent none: target markers, aim previews and the lighting fix are drawn in code.

| Date | Batch | Used before | Used after | Spend | Goal spend |
| --- | --- | --- | --- | --- | --- |
| 2026-10-19 | (goal start) | 4328 | 4328 | 0 | 0 |
| 2026-10-19 | (goal end: markers, aim previews and lighting drawn in code; no generations needed) | 4328 | 4328 | 0 | 0 |

Fifth playtest goal (#47-#54), start 2026-10-19: **used 4328, remaining 478**, resets 2026-11-14.
Goal cap: 80 generations, 150 kept in reserve. Planned: the Sewers lever off / on states, talent tree
ornaments / node frames / branch art only where drawn UI falls short; effects from particles, shaders and
the free workbenches.

| Date | Batch | Used before | Used after | Spend | Goal spend |
| --- | --- | --- | --- | --- | --- |
| 2026-10-19 | (goal start) | 4328 | 4328 | 0 | 0 |
| 2026-10-20 | #51 Sewers lever: 2 map objects (iron gearbox housing on a stone plinth 48x48, lever arm 32x64; the arm swings in code) | 4328 | 4330 | 2 | 2 |
| 2026-10-20 | (goal end: level-up, rise marks, charge display and the talent trees drawn in code; no more generations) | 4330 | 4330 | 0 | 2 |


Sixth playtest goal (#55-#59), start 2026-10-20: **used 4330, remaining 476**, resets 2026-11-14.
Goal cap: only #59 if drawn markers fall short. Spent none: the hero marker is drawn in code.

| Date | Batch | Used before | Used after | Spend | Goal spend |
| --- | --- | --- | --- | --- | --- |
| 2026-10-20 | (#59 drawn in code; no generations) | 4330 | 4330 | 0 | 0 |

Eighth playtest goal (#70-#82), start 2026-10-21: **used 4330, remaining 476**, resets 2026-11-14.
Goal cap: 300 generations, 150 kept in reserve (the 300 cap binds: 476 - 150 = 326). The daily bonus is
never counted as headroom. Planned: boon icons (#73, ~250 icons at 16 per Pixen sheet: ~17 sheets), modifier
/ event / badge icons (#71, #72: ~3 sheets), the blacksmith (#77: character + idle / hammer animations, ~40),
forge props (map objects, ~8), legendary tome covers (#76, ~2); the ghost (#82), deep variants (#74) and the
gameplay effects (#81) from shaders, particles and the free vfx workbench; re-rolls ~10%.

| Date | Batch | Used before | Used after | Spend | Goal spend |
| --- | --- | --- | --- | --- | --- |
| 2026-10-21 | (goal start) | 4330 | 4330 | 0 | 0 |
| 2026-10-21 | Floor icons: 1 Pixen 128x128 sheet of 16 (5 biome crests, the overrun rift, 5 floor modifiers for #71, 5 events for #72), cut by `tools/cut_icon_sheet.py` | 4330 | 4331 | 1 | 1 |
| 2026-10-21 | #73 boon icons: 16 Pixen 128x128 sheets of 16 and one 64x64 sheet of 4 (260 boons), sheet 14 redrawn once without tile frames, cut by `tools/cut_icon_sheet.py` | 4331 | 4349 | 18 | 19 |
| 2026-10-21 | #81 gameplay effects: drawn in code (particles, shaders), no generations | 4349 | 4349 | 0 | 19 |
| 2026-10-21 | #77 the forge: Rolf Hult (1 Pixen 64x64 sprite, 2 Pixen pose edits, 4 animate_image clips: strike, wipe, look, a rejected first strike), the forge door (1 Pixen 96x96 + 1 edit for the open door), props (1 Pixen 128x128 sheet: hearth and rack used; 1 64x64 sheet: anvil, barrel, coals, ingots; 1 rejected 40x40 rack), 1 rejected map icon (drawn by hand instead) | 4349 | 4362 | 13 | 32 |
| 2026-10-21 | #72 events: 8 Pixen images (bargain shrine, cursed chest, chest mimic, prison cage, vault door, trial chest, arena brazier, cell key icon), 3 Pixen edits (open cage, open vault door, open trial chest), 5 animate_image clips (mimic idle, bite, hop, death; the chest waking into the mimic) | 4362 | 4378 | 16 | 48 |
| 2026-10-21 | #78 NPC bubbles: drawn in code, no generations | 4378 | 4378 | 0 | 48 |
| 2026-10-21 | #76 the Ownerless Book: 1 Pixen 32x32 icon, 1 Pixen 96x96 open-book cover | 4378 | 4380 | 2 | 50 |
| 2026-10-21 | #74 deep variants: the aura shader, halo and warnings drawn in code, no generations | 4380 | 4380 | 0 | 50 |

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
- [ ] **Music and SFX** (user, Suno): 17 music and 98 SFX keys, file paths and prompts in
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
