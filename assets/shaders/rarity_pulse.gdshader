shader_type canvas_item;
// Rarity border for item slots (put on a ColorRect over the slot). Draws a crisp border in the
// rarity color with chamfered corners and a stepped 3 px inner glow that pulses. `strength`
// scales with the tier (0 = no glow, e.g. common items).

uniform vec4 rarity_color : source_color = vec4(1.0);
uniform float strength : hint_range(0.0, 1.5) = 0.6;
uniform float speed = 2.0;
uniform float border = 1.0;
uniform vec2 rect_size = vec2(40.0, 40.0);
uniform float highlight : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 px = floor(UV * rect_size);
	vec2 c = min(px, rect_size - 1.0 - px);
	float dist = min(c.x, c.y);
	float pulse = 0.5 + 0.5 * sin(TIME * speed);
	if (c.x + c.y < 1.0) {
		COLOR = vec4(0.0);
	} else if (dist < border) {
		vec3 col = mix(rarity_color.rgb, vec3(1.0), pulse * 0.3 * strength + highlight * 0.4);
		COLOR = vec4(col, rarity_color.a);
	} else {
		float band = floor(dist - border);
		float a = 0.0;
		if (band < 3.0) {
			a = (0.3 - band * 0.09) * strength * (0.4 + 0.6 * pulse) + highlight * (0.25 - band * 0.07);
		}
		COLOR = vec4(rarity_color.rgb, clamp(a, 0.0, 1.0));
	}
}
