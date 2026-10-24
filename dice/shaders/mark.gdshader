shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Glossy candy X or O: darker underneath, bright on top, a fresnel rim.
// `glow` makes it pulse (a winning line), `flash` washes it white, `dim`
// greys it out (the losing side).

uniform vec4 mark_color : source_color = vec4(1.0, 0.7, 0.1, 1.0);
uniform float half_height = 0.11;
instance uniform float glow : hint_range(0.0, 3.0) = 0.0;
instance uniform float flash : hint_range(0.0, 1.0) = 0.0;
instance uniform float dim : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 c = mark_color.rgb;
	float h = clamp((local_pos.y + half_height) / (2.0 * half_height), 0.0, 1.0);
	vec3 base = mix(c * 0.45, c, smoothstep(0.0, 0.8, h));
	vec3 grey = vec3(dot(base, vec3(0.3, 0.55, 0.15))) * 0.55;
	base = mix(base, grey, dim);
	ALBEDO = mix(base, vec3(1.0), flash);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.03;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = (c * (0.18 + glow * 0.6) + c * fresnel * 0.55) * (1.0 - dim)
		+ vec3(1.0) * flash * 1.5
		+ vec3(1.0) * fresnel * glow * 0.5;
}
