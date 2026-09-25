// appearance.gdshader — a character's texture with its skin, hair and eyes recoloured (Scripts/appearance.gd, 2026-09-25).
// The mask (tools/blender/make_masks.py) says where each region is: red = skin, green = hair, blue = eyes. Each region
// keeps its own light and shade: a texel's brightness relative to the region's original colour (*_ref) is carried over
// to the new colour, so a highlight in the hair stays a highlight. *_on = 0 leaves that region as it was painted.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 skin_ref : source_color = vec3(0.8, 0.6, 0.5);
uniform vec3 skin_target : source_color = vec3(0.8, 0.6, 0.5);
uniform float skin_on = 0.0;
uniform vec3 hair_ref : source_color = vec3(0.3, 0.2, 0.1);
uniform vec3 hair_target : source_color = vec3(0.3, 0.2, 0.1);
uniform float hair_on = 0.0;
uniform vec3 eye_ref : source_color = vec3(0.3, 0.3, 0.3);
uniform vec3 eye_target : source_color = vec3(0.3, 0.3, 0.3);
uniform float eye_on = 0.0;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 recolour(vec3 col, vec3 ref, vec3 target) {
	// brightness relative to the region's own colour, applied to the new colour (kept below overexposure)
	float k = luma(col) / max(luma(ref), 0.001);
	return min(target * k, vec3(1.0));
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb;
	vec3 m = texture(mask_tex, UV).rgb;
	col = mix(col, recolour(col, skin_ref, skin_target), m.r * skin_on);
	col = mix(col, recolour(col, hair_ref, hair_target), m.g * hair_on);
	col = mix(col, recolour(col, eye_ref, eye_target), m.b * eye_on);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
