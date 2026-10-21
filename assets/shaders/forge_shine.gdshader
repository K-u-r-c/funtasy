shader_type canvas_item;
render_mode blend_add, unshaded;
// #91: the forge card's success light - a warm diagonal band sweeping across the card, the rim
// lighting up and fading, in pixel-stepped levels so it sits with the pixel art.

uniform float progress = 0.0;  // 0..1 over the sweep
uniform vec4 tint : source_color = vec4(1.0, 0.72, 0.32, 1.0);
uniform vec2 px_size = vec2(256.0, 300.0);  // the card's size in pixels (for the stepping)

void fragment() {
	vec2 cell = floor(UV * px_size / 2.0) * 2.0 / px_size;  // 2 px blocks
	float pos = mix(-0.35, 1.35, progress);
	float d = (cell.x * 0.75 + cell.y * 0.35) - pos;
	float band = exp(-d * d * 60.0);
	float edge_d = min(min(cell.x, 1.0 - cell.x) * px_size.x, min(cell.y, 1.0 - cell.y) * px_size.y);
	float rim = edge_d < 3.0 ? 1.0 : 0.0;
	float fade = 1.0 - smoothstep(0.55, 1.0, progress);
	float glow = band * 0.6 + rim * 0.5 * fade + band * rim * 0.4;
	glow = floor(glow * 5.0) / 5.0;
	COLOR = vec4(tint.rgb * glow, 1.0);
}
