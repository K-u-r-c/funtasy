shader_type canvas_item;
// Rarity-colored pulsing outline for items lying on the ground.

uniform vec4 glow_color : source_color = vec4(1.0);
uniform float width = 1.0;
uniform float pulse_speed = 3.0;
uniform float intensity = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE * width;
	float a = texture(TEXTURE, UV + vec2(px.x, 0.0)).a + texture(TEXTURE, UV - vec2(px.x, 0.0)).a
		+ texture(TEXTURE, UV + vec2(0.0, px.y)).a + texture(TEXTURE, UV - vec2(0.0, px.y)).a;
	float outline = clamp(a, 0.0, 1.0) * (1.0 - c.a);
	float pulse = 0.65 + 0.35 * sin(TIME * pulse_speed);
	vec4 o = vec4(glow_color.rgb * (1.0 + pulse * intensity), outline * pulse);
	COLOR = mix(o, c, c.a);
}
