shader_type canvas_item;
// Worn / held item look variants (#20): one sprite sheet, many looks. Greyish pixels (metal,
// stone) are remapped by brightness onto a 3-colour ramp (rusty iron, steel, blackened, gold...);
// coloured pixels (leather, cloth, gems) get a hue shift and saturation / brightness factors.
// The darkest pixels (outline) stay as drawn. Values come from data/assets.json "gear_variants"
// (and each legendary's "look").

uniform vec3 ramp_dark : source_color = vec3(0.1);
uniform vec3 ramp_mid : source_color = vec3(0.5);
uniform vec3 ramp_light : source_color = vec3(0.9);
uniform float metal_mix = 0.0;
uniform float hue_shift = 0.0;
uniform float sat_mult = 1.0;
uniform float val_mult = 1.0;
uniform float grey_limit = 0.28;  // saturation below this counts as metal
uniform vec4 glow_color : source_color = vec4(0.0);  // added light on bright pixels (legendaries)

varying vec4 tint;

void vertex() {
	tint = COLOR;  // the node's modulate, applied after the remap
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 hsv = rgb2hsv(c.rgb);
	vec3 rgb = c.rgb;
	if (hsv.z > 0.12) {
		if (hsv.y < grey_limit) {
			float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
			vec3 ramp = l < 0.5 ? mix(ramp_dark, ramp_mid, l * 2.0) : mix(ramp_mid, ramp_light, (l - 0.5) * 2.0);
			rgb = mix(c.rgb, ramp, metal_mix);
		} else {
			rgb = hsv2rgb(vec3(fract(hsv.x + hue_shift), clamp(hsv.y * sat_mult, 0.0, 1.0), clamp(hsv.z * val_mult, 0.0, 1.0)));
		}
		rgb += glow_color.rgb * glow_color.a * smoothstep(0.55, 0.95, hsv.z);
	}
	COLOR = vec4(rgb, c.a) * tint;
}
