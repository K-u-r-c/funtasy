class_name LightLayers
extends RefCounted
## Canvas light layers and the gameplay light registry.
##
## Layers: occluders (walls, closed doors, props) cast shadows on LIT items only. Occluding
## objects and characters are drawn on SELF_LIT, so they are never swallowed by a shadow (a door
## seen from the south, or a player pressed against a table, stays visible).
##
## Registry: every light that matters for gameplay (torches, carried torches, lava, spell
## lights, the local player's own small light) joins the "light_sources" group with a "radius"
## meta in pixels. Darkness is a mechanic: monsters are only visible while they are lit
## (see Visibility).

const LIT := 1  ## normal items: lit and shadowed
const SELF_LIT := 2  ## occluders and characters: lit, never shadowed
const ALL := LIT | SELF_LIT  ## range_item_cull_mask for every light
const GROUP := "light_sources"
## Lit radius covered by one unit of texture_scale (soft light texture: 128 px radius, of which
## roughly the inner 60% is bright enough to make things out).
const PX_PER_SCALE := 77.0


static func setup_light(l: Light2D) -> void:
	l.range_item_cull_mask = ALL
	l.shadow_item_cull_mask = LIT


## Sizes a light so its bright area covers `radius` px and registers it as a gameplay light.
static func register(l: PointLight2D, radius: float) -> void:
	l.texture_scale = maxf(radius, 1.0) / PX_PER_SCALE
	l.set_meta("radius", radius)
	l.add_to_group(GROUP)


static func unregister(l: Node) -> void:
	if l and l.is_in_group(GROUP):
		l.remove_from_group(GROUP)


## Is `pos` inside the bright area of any registered light? `exclude_personal` ignores the local
## player's own small vision light (it only exists on one machine, so host rules skip it).
static func is_lit(tree: SceneTree, pos: Vector2, exclude_personal: bool = false) -> bool:
	for l in tree.get_nodes_in_group(GROUP):
		if exclude_personal and l.has_meta("personal"):
			continue
		if l.is_visible_in_tree() and l.global_position.distance_to(pos) <= float(l.get_meta("radius", 0.0)):
			return true
	return false
