shader_type canvas_item;
// Diagonal light sweep across bright glyph pixels (logo / titles). Outlines and shadows are dark
// and stay untouched. Quantized to whole pixels so the band reads as pixel art.

uniform vec4 shine : source_color = vec4(1.0, 0.96, 0.8, 1.0);
uniform float period = 5.0;
uniform float span = 480.0;
uniform float band = 10.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	vec2 p = floor(local_pos);
	float sweep = fract(TIME / period) * (span * 1.6) - span * 0.3;
	float d = abs((p.x + p.y * 0.6) - sweep);
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float k = step(d, band) * step(0.35, luma) * 0.75;
	COLOR = vec4(mix(c.rgb, shine.rgb, k), c.a);
}
