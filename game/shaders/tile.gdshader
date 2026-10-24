shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Glossy candy tile. The colour comes from tile_color; the shine is painted
// on: a darker base, a lighter top, a soft highlight blob, a bright bevel
// and a fresnel rim. The painted parts go through EMISSION so they bloom.

uniform vec4 tile_color : source_color = vec4(1.0, 0.25, 0.4, 1.0);
uniform float glow : hint_range(0.0, 2.0) = 0.12;
uniform float shine : hint_range(0.0, 2.0) = 1.0;
// 1.0 makes the tile cycle through the rainbow (wild tiles).
uniform float rainbow : hint_range(0.0, 1.0) = 0.0;
uniform float half_height = 0.21;
uniform float half_size = 0.45;

varying vec3 local_pos;
varying vec3 local_normal;

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 c = tile_color.rgb;
	if (rainbow > 0.0) {
		vec3 shifting = mix(hue(fract(TIME * 0.25 + (local_pos.x + local_pos.z) * 0.6)), vec3(1.0), 0.25);
		c = mix(c, shifting, rainbow);
	}
	float up = clamp(local_normal.y, 0.0, 1.0);
	float h = clamp((local_pos.y + half_height) / (2.0 * half_height), 0.0, 1.0);

	vec3 base = mix(c * 0.4, c, smoothstep(0.0, 0.85, h));
	ALBEDO = base;
	ROUGHNESS = 0.08;
	SPECULAR = 0.7;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.03;

	// Candy highlight: a soft blob and a small dot near the top-left corner.
	vec2 p = local_pos.xz / half_size;
	float blob = 1.0 - smoothstep(0.1, 0.32, length((p - vec2(-0.5, -0.5)) * vec2(1.0, 1.5)));
	float dot_ = 1.0 - smoothstep(0.03, 0.08, length(p - vec2(-0.12, -0.72)));
	float highlight = (blob * 0.75 + dot_ * 0.9) * smoothstep(0.9, 1.0, up);

	// Shiny band where the top rounds over into the sides.
	float bevel = smoothstep(0.35, 0.75, up) * (1.0 - smoothstep(0.9, 0.995, up));
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);

	EMISSION = c * glow
		+ vec3(1.0) * (highlight * 1.2 + bevel * 0.18) * shine
		+ c * fresnel * 0.4 * shine;
}
