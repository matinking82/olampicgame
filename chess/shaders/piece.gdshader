shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Glossy candy chess piece. Darker at the foot, bright at the top, a glowing
// team-coloured band around the base, a fresnel rim, and an optional rainbow
// (the Empress). `flash` washes it white for hits; `glow` lights it up when
// selected.

uniform vec4 piece_color : source_color = vec4(1.0, 0.8, 0.1, 1.0);
uniform vec4 trim_color : source_color = vec4(1.0, 0.85, 0.2, 1.0);
uniform float height = 1.0;
uniform float rainbow : hint_range(0.0, 1.0) = 0.0;
instance uniform float glow : hint_range(0.0, 3.0) = 0.0;
instance uniform float flash : hint_range(0.0, 1.0) = 0.0;
instance uniform float dim : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 c = piece_color.rgb;
	if (rainbow > 0.0) {
		vec3 shifting = mix(hue(fract(TIME * 0.3 + local_pos.y * 0.8 + atan(local_pos.z, local_pos.x) * 0.16)), vec3(1.0), 0.15);
		c = mix(c, shifting, rainbow);
	}
	float h = clamp(local_pos.y / height, 0.0, 1.0);
	vec3 base = mix(c * 0.45, c, smoothstep(0.0, 0.7, h));
	// The team band around the foot.
	float band = smoothstep(0.035, 0.05, local_pos.y) * (1.0 - smoothstep(0.1, 0.115, local_pos.y));
	base = mix(base, trim_color.rgb, band);
	vec3 grey = vec3(dot(base, vec3(0.3, 0.55, 0.15))) * 0.55;
	base = mix(base, grey, dim);
	ALBEDO = mix(base, vec3(1.0), flash);
	ROUGHNESS = 0.1;
	SPECULAR = 0.7;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.04;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = c * (0.12 + glow * 0.5) * (1.0 - dim)
		+ c * fresnel * 0.55 * (1.0 - dim)
		+ trim_color.rgb * band * 0.9 * (1.0 - dim)
		+ vec3(1.0) * flash * 1.5
		+ vec3(1.0) * fresnel * glow * 0.6;
}
