shader_type canvas_item;
render_mode blend_add, unshaded;
// #74: the aura of a corrupted monster or an ascended boss - a flat ring of swirling, flickering
// light on the floor around it (drawn on a square sprite squashed to the 3/4 view).

uniform vec4 aura_color : source_color = vec4(0.6, 0.36, 1.0, 1.0);
uniform float strength = 1.0;
uniform float speed = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 c = UV - vec2(0.5);
	float r = length(c) * 2.0;
	float a = atan(c.y, c.x);
	float t = TIME * speed;
	float swirl = noise(vec2(a * 3.0 + t * 1.3, r * 4.0 - t * 2.0));
	float ring = smoothstep(0.55, 0.8, r) * (1.0 - smoothstep(0.85, 1.0, r));
	float core = (1.0 - smoothstep(0.0, 0.75, r)) * 0.35;
	float flick = 0.75 + 0.25 * sin(t * 6.0 + a * 4.0);
	float v = (ring * (0.5 + swirl) + core * swirl) * flick * strength;
	// Pixel-snapped steps keep it reading as pixel art.
	v = floor(v * 5.0) / 5.0;
	COLOR = vec4(aura_color.rgb * v, v * aura_color.a);
}
