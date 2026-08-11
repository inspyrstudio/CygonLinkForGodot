shader_type spatial;

uniform vec3 albedo_color : source_color = vec3(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_tex = false;

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool use_normal_tex = false;

uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;

uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float uv_rotation = 0.0;

void fragment() {
	vec2 uv = UV * uv_scale;
	float ca = cos(-uv_rotation);
	float sa = sin(-uv_rotation);
	uv = vec2(uv.x * ca - uv.y * sa, uv.x * sa + uv.y * ca);
	uv += uv_offset;
	
	vec3 albedo = albedo_color;
	if (use_albedo_tex) {
		albedo *= texture(albedo_tex, uv).rgb;
	}
	ALBEDO = albedo;
	
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, uv).rgb;
	}
	
	METALLIC = metallic_value;
	ROUGHNESS = roughness_value;
}
