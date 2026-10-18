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

## Status after the fixes (2026-10-18)

| Finding | Status |
| --- | --- |
| Too few frames (idle 2, walk 4, death 4, downed 2) | Replaced by the v2 set for both genders: idle 4, walk 8, dash 4, hit 3, death 5, downed = last death frame with a breath, revive = death backwards (DECISIONS "#16 / #18 / #19"). |
| Walk feet sliding / hopping | Walk 8 frames, paced by the hero's real speed against the measured stride (male 28 px, female 24 px). |
| Every attack a punch | Ten attack animations (slash, cleave, bash, shoot_bow, shoot_crossbow, sling, cast, flick, empower, throw) picked per weapon and skill; drawn weapon / glow frames skipped (`pick_dir`) or replaced by a neighbour (`dup`: female shoot_bow S / SE / E, female flick E). |
| Cast flame remnants, body turning on frame 2 | Cast redrawn as a v3 animation, `strip_glow` with speck removal on every picked frame. |
| Weapons behind the body facing away, floating in front, swapping hands | Baked per pixel into front / back sheets from the tracked hand of the whole clip; the bow in the draw uses the extended hand (#16). Reviewed per weapon in 8 directions, idle and impact frame, both genders. |
| Worn layers | Four families (plate, cloth, leather, mail) for both genders on all 75 frames, no holes (`hero-art`). |
| flesh_stitcher missing E / W | Walk east drawn and the monster rebuilt (commit f4a582e). |
| Other monsters | Listed motion is intended (squash / stretch, lunges); cultist 3-frame attack accepted. |
| Second review (2026-10-18): female shield / staff at head height facing south, items changing sides each walk step | The tank-top body's shoulders, face, midriff and legs read as hands. Hand blobs above the chest are ignored where the arms hang, and the female fists are found near measured `rest_hands` anchors; `hero-art` checks that held items keep their side (S / N, idle and walk). |
| Second review: female walk S frame 5 baring the shirt, helmets / hoods cut to a visor in 21 female attack frames | The body regions missed the head (dark hair read as outline, shirt shading as hair). Walk S frame 5 shows frame 4; the regions keep the hair blobs on top of an upright figure, so pieces worn without their full set are cut on the right body part (`hero-art`: the head tops every idle / walk / dash frame). |
| Final per-family review (both genders, every weapon family, idle + impact in 8 directions): female slash E / W kept the blade behind her and had a drawn blade in the body, female crossbow S was a T-pose, crossbows E / W aimed backwards | Re-drawn clips with re-transferred outfits (83 generations), `forward` hand for the crossbow and the female E / W slash, `dup` for the female slash SE impact. |
| Female cleave S: a head piece worn alone took the raised forearms' sleeves; female crossbow SE / SW spread the arms; female two-handed wind-ups held the weapon low | Cleave S re-drawn with the arms in a V and crossbow SE re-drawn (82 generations, outfits re-transferred); `high` hand for the wind-ups, face / trunk skin no longer taken for fists (`no_face_hands`). No known leftover. |
