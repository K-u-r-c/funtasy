shader_type canvas_item;
// Body layer of a CharacterSprite: hides the body pixels covered by worn gear, so no skin or
// underwear shows under or around a piece. Each mask is that piece's "hide" sheet (same layout
// as the body sheet, so the atlas UV of the current frame lines up).

uniform sampler2D hide_head : filter_nearest;
uniform sampler2D hide_chest : filter_nearest;
uniform sampler2D hide_legs : filter_nearest;
uniform sampler2D hide_boots : filter_nearest;
uniform sampler2D hide_gloves : filter_nearest;
uniform bool on_head = false;
uniform bool on_chest = false;
uniform bool on_legs = false;
uniform bool on_boots = false;
uniform bool on_gloves = false;

void fragment() {
	float h = 0.0;
	if (on_head) { h = max(h, texture(hide_head, UV).a); }
	if (on_chest) { h = max(h, texture(hide_chest, UV).a); }
	if (on_legs) { h = max(h, texture(hide_legs, UV).a); }
	if (on_boots) { h = max(h, texture(hide_boots, UV).a); }
	if (on_gloves) { h = max(h, texture(hide_gloves, UV).a); }
	if (h > 0.5) {
		COLOR.a = 0.0;
	}
}
