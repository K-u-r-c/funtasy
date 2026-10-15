shader_type canvas_item;
// Radial cooldown sweep for skill slots (put on a ColorRect over the icon).
// `progress` = remaining fraction (1 = just used, 0 = ready). The dark wedge shrinks clockwise
// from 12 o'clock; a 1 px cyan edge marks the sweep. Evaluated per *pixel* of the slot so the
// edge stays crisp pixel art at any window scale.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.02, 0.03, 0.06, 0.74);
uniform vec4 edge_color : source_color = vec4(0.43, 0.89, 0.94, 0.95);
uniform vec2 rect_size = vec2(32.0, 32.0);

void fragment() {
	if (progress <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		vec2 px = floor(UV * rect_size) + 0.5;
		vec2 d = px - rect_size * 0.5;
		float a = fract(atan(d.x, -d.y) / 6.28318530718 + 1.0);
		float boundary = 1.0 - progress;
		float diff = abs(a - boundary);
		diff = min(diff, 1.0 - diff);
		float edge_px = diff * 6.28318530718 * length(d);
		if (progress < 0.999 && edge_px < 0.75 && length(d) > 1.0) {
			COLOR = edge_color;
		} else if (a >= boundary) {
			COLOR = tint;
		} else {
			COLOR = vec4(0.0);
		}
	}
}
