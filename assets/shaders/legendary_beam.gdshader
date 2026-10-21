shader_type canvas_item;
render_mode blend_add, unshaded;
// #75: the tall beam of light over a legendary drop. Drawn on a quad whose UV x runs across the
// beam and y from its top (0) to its foot (1): a bright core, a soft halo, light flowing upwards
// and a top that fades into the dark. `fade` (0..1) brings it in and out.

uniform vec4 beam_color : source_color = vec4(1.0, 0.62, 0.18, 1.0);
uniform float fade = 1.0;
uniform float flow_speed = 1.6;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float core = exp(-x * x * 18.0);
	float halo = exp(-x * x * 3.0) * 0.55;
	float rise = 0.75 + 0.25 * sin((UV.y + TIME * flow_speed) * 18.0 - x * 4.0);
	float top = smoothstep(0.0, 0.55, UV.y);
	float foot = 1.0 - smoothstep(0.92, 1.0, UV.y) * 0.4;
	float a = (core * 1.3 + halo * rise) * top * foot * fade;
	COLOR = vec4(beam_color.rgb * (1.0 + core * 1.5), a * beam_color.a);
}
