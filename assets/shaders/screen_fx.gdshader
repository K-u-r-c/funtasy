shader_type canvas_item;
// Full-screen status effects of the local hero: the Tome Prison's monochrome parchment world and
// the Ink Horror's blots. Both fade with their uniforms.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float mono : hint_range(0.0, 1.0) = 0.0;
uniform float ink : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453);
}

float blots(vec2 uv) {
	float v = 0.0;
	for (int i = 0; i < 7; i++) {
		vec2 c = vec2(hash(vec2(float(i), 1.0)), hash(vec2(float(i), 2.0)));
		float r = 0.08 + 0.12 * hash(vec2(float(i), 3.0));
		vec2 d = (uv - c) * vec2(1.6, 1.0);
		v = max(v, smoothstep(r, r * 0.6, length(d)));
	}
	return v;
}

void fragment() {
	vec4 col = texture(screen_tex, SCREEN_UV);
	float g = dot(col.rgb, vec3(0.3, 0.59, 0.11));
	vec3 parchment = mix(vec3(0.05, 0.04, 0.03), vec3(0.86, 0.8, 0.66), g * 1.4);
	col.rgb = mix(col.rgb, parchment, mono);
	float b = blots(SCREEN_UV) * ink;
	col.rgb = mix(col.rgb, vec3(0.01, 0.01, 0.02), b);
	COLOR = col;
}
