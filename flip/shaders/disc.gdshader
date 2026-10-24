shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// A two-sided candy disc: one team's colour on top, the other's underneath,
// a cream stripe round the rim and an embossed ring on each face. `glow`
// lights it (would-flip preview, a winning side), `flash` washes it white,
// `dim` greys it out.

uniform vec4 top_color : source_color = vec4(1.0, 0.75, 0.1, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.1, 0.8, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.88, 1.0);
instance uniform float glow : hint_range(0.0, 3.0) = 0.0;
instance uniform float flash : hint_range(0.0, 1.0) = 0.0;
instance uniform float dim : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	bool top = local_pos.y > 0.0;
	vec3 c = top ? top_color.rgb : bottom_color.rgb;
	float r = length(local_pos.xz);
	// The embossed ring and a bright centre on the faces.
	float ring = smoothstep(0.012, 0.0, abs(r - 0.27));
	vec3 face = mix(c, c * 0.72, ring) + c * 0.25 * smoothstep(0.2, 0.0, r);
	float side = 1.0 - smoothstep(0.35, 0.7, abs(local_normal.y));
	vec3 base = mix(face, rim_color.rgb, side * 0.85);
	vec3 grey = vec3(dot(base, vec3(0.3, 0.55, 0.15))) * 0.55;
	base = mix(base, grey, dim);
	ALBEDO = mix(base, vec3(1.0), flash);
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.03;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = (c * (0.16 + glow * 0.6) + c * fresnel * 0.5) * (1.0 - dim)
		+ vec3(1.0) * flash * 1.5
		+ vec3(1.0) * fresnel * glow * 0.5;
}
