shader_type canvas_item;
// #81: the screen-edge vignette (low health pulse, big-hit flash). `strength` 0..1 fades it in,
// `inner` is where it starts from the centre (0..1 of the half-diagonal).
uniform vec4 tint : source_color = vec4(0.63, 0.0, 0.06, 1.0);
uniform float strength = 0.0;
uniform float inner = 0.55;

void fragment() {
	vec2 d = (UV - vec2(0.5)) * vec2(1.6, 1.0);
	float r = length(d) / 0.95;
	float a = smoothstep(inner, 1.05, r) * strength;
	COLOR = vec4(tint.rgb, a * tint.a);
}
