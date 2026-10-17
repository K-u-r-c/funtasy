# Art audit (#18)

Done before any regeneration, 2026-10-17. Contact sheets and the automatic motion report come from
`tools/contact_sheet.gd`:

    godot --headless --path . -s tools/contact_sheet.gd -- <out_dir> 2            # heroes
    godot --headless --path . -s tools/contact_sheet.gd -- <out_dir> 1 --monsters  # monsters, bosses

Hero sheets: one PNG per gender x look (bare, plate, cloth, and each held weapon / off-hand), rows =
animation x 8 directions, columns = frames, composed as `CharacterSprite` draws them (hide masks
applied; magenta = a masked body pixel no piece draws, red frame edge = an empty layer frame).
`report_heroes.txt` / `report_monsters.txt` list empty frames, feet that jump more than 2 px between
consecutive frames of a standing clip, and silhouettes whose height pops more than 4 px.
`HeroArtSuite.audit` (`hero-art` test) repeats the per-frame checks on every run.

## Heroes (body male / female, 7 worn layers, 13 held layers each)

| Animation | Frames (game / PixelLab source) | Findings |
| --- | --- | --- |
| idle | 2 / 4 | Too few frames: a 2-frame breathing toggle reads as a twitch. The source has 4. |
| walk | 4 / 8 | Too few frames: feet skip positions (a hop rather than steps). The source has 8. |
| attack | 5 / 6 | `cross-punch` template: every weapon "attack" is a punch (#19); swords are pushed, bows punched. Body and layers otherwise clean. |
| cast | 5 / 6 | `fireball` template with its flame removed by `strip_glow`, which missed some directions: **female NW / NE** keep a white flame in the hands in every frame and **female N** an orange arc; **male NW / NE** keep a white speck in the last frames (also baked into the plate / cloth layers). **Frame 2 turns the body to another direction** in NW / N / NE (both genders): the silhouette flips for one frame. |
| dash | 4 / 4 | Running template, airborne frames lift the feet 3-5 px (correct for a run). Plate gloves empty in E / W frames 0-1 (hands behind the body; mask empty too, allowed). |
| hit | 3 / 6 | Fine; male N frame 1 and female N frame 1 drop the head 5-6 px (the punch reaction), female E / W frame 2 feet +3 px. |
| death | 4 / 7 | Too few frames: the fall skips from standing to half-way down. Plate gloves empty in NW / NE frame 0 (allowed). Male S frame 0 was already patched. |
| downed | 2 (derived) | The last death frame twice: no breathing. |
| ghost | 4 | Fine (gear is not drawn on ghosts). |
| (none) | - | No revive animation. |

Worn layers: no empty frame where the body part shows, no interior hole or trimmed outline after the
#15 refill (`hero-art`). Hair hidden under helmets / hoods is intended (DECISIONS "No body under
gear").

Held layers (all 13 types, both genders): drawn in every frame and touching the hand (`art-check`),
but placed by one rule: weapons and off-hands go fully behind the body when facing NW / N / NE, so a
sword or bow vanishes there (#16); facing the camera, staves and bows float in front of the torso;
W / SW / NW are mirrors of E / SE / NE, so the weapon changes hands there. Attacks swing the picture
through a straight arc (`swing`), which together with the punch body reads as a push (#19).

## Monsters and bosses (49 sheets)

| Sheet | Finding | Fix |
| --- | --- | --- |
| flesh_stitcher | **No E / W rows** in idle, walk and dash: the PixelLab walk was never drawn east, so the monster is invisible facing E / W while standing or moving (attack, death fine). | Draw walk east (1 generation), rebuild with `build_monster_zip.py`. |
| cultist, hellfire_cultist | Attack has 3 frames (choppy staff jab). | Acceptable for trash casters (they mostly cast); left as is. |
| abyssal_leech, acid_slime, blood_tick, ink_horror, isolde_spider, krazik, magma_carapace, murk_amalgam, plague_rat, tomebound_mimic, vulkania, will_o_blight, brimstone_hound, barrow_bloodhound | "feet jump" / "height pops" on attack, hit, walk: shapeless forms and animated objects (squash and stretch, a rider bobbing) | Intended motion, not errors. |
| carrion_crawler, gutter_stalker, sludge_lobber, memory_devourer, rotwood_treant, bramble_warden, ignis, vespera | 1-9 feet jumps of 3-4 px in attack / cast / dash (lunges, crawls) | Intended motion of the template (lunges); reviewed on the sheets, no broken frame. |
| all | No ghost sheet | Monsters never become ghosts (not drawn). |

No empty frame, missing direction or broken frame besides the flesh stitcher was found.
