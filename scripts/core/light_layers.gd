class_name LightLayers
extends RefCounted
## Canvas light layers. Occluders (walls, closed doors, props) cast shadows on LIT items only;
## the occluding objects themselves are drawn on SELF_LIT so they are never hidden by their own
## shadow (otherwise a door or table seen from the south would vanish into its own shade).

const LIT := 1  ## normal items: lit and shadowed
const SELF_LIT := 2  ## occluding props/doors: lit, never shadowed
const ALL := LIT | SELF_LIT  ## range_item_cull_mask for every light


static func setup_light(l: Light2D) -> void:
	l.range_item_cull_mask = ALL
	l.shadow_item_cull_mask = LIT
