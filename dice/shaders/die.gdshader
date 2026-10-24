shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Glossy candy die with glowing pips, drawn on a rounded cube. Faces by
// local normal: +Y 1, +X 2, +Z 3, -Z 4, -X 5, -Y 6 (opposites add to 7).
// `glow` lights a held die, `flash` washes it white, `dim` greys it out
// (a bust), and `rainbow` cycles the colour during Fever.

uniform vec4 die_color : source_color = vec4(1.0, 0.65, 0.12, 1.0);
uniform vec4 pip_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float half_size = 0.36;
uniform float rainbow : hint_range(0.0, 1.0) = 0.0;
instance uniform float glow : hint_range(0.0, 3.0) = 0.0;
instance uniform float flash : hint_range(0.0, 1.0) = 0.0;
instance uniform float dim : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;
varying vec3 local_normal;

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

// Distance from p (face coordinates, -1..1) to the nearest pip of face n.
float pips(int n, vec2 p) {
	float d = 10.0;
	float a = 0.5;
	if (n == 1 || n == 3 || n == 5) {
		d = min(d, length(p));
	}
	if (n >= 2) {
		d = min(d, length(p - vec2(a, a)));
		d = min(d, length(p + vec2(a, a)));
	}
	if (n >= 4) {
		d = min(d, length(p - vec2(a, -a)));
		d = min(d, length(p + vec2(a, -a)));
	}
	if (n == 6) {
		d = min(d, length(p - vec2(a, 0.0)));
		d = min(d, length(p + vec2(a, 0.0)));
	}
	return d;
}

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 c = die_color.rgb;
	if (rainbow > 0.0) {
		vec3 shifting = mix(hue(fract(TIME * 0.35 + (local_pos.x + local_pos.y) * 0.5)), vec3(1.0), 0.2);
		c = mix(c, shifting, rainbow);
	}
	vec3 an = abs(local_normal);
	int n;
	vec2 uv;
	if (an.y >= an.x && an.y >= an.z) {
		n = local_normal.y > 0.0 ? 1 : 6;
		uv = local_pos.xz;
	} else if (an.x >= an.z) {
		n = local_normal.x > 0.0 ? 2 : 5;
		uv = local_pos.zy;
	} else {
		n = local_normal.z > 0.0 ? 3 : 4;
		uv = local_pos.xy;
	}
	float d = pips(n, uv / half_size);
	float face = smoothstep(0.9, 0.98, max(an.x, max(an.y, an.z)));
	float pip = (1.0 - smoothstep(0.15, 0.18, d)) * face;
	// A darker rim around each pip, like a dimple.
	float rim = (1.0 - smoothstep(0.18, 0.24, d)) * face - pip;

	vec3 body = mix(c * 0.75, c, 0.5 + 0.5 * local_normal.y);
	body = mix(body, c * 0.45, rim);
	vec3 col = mix(body, pip_color.rgb, pip);
	vec3 grey = vec3(dot(col, vec3(0.3, 0.55, 0.15))) * 0.5;
	col = mix(col, grey, dim);
	ALBEDO = mix(col, vec3(1.0), flash);
	ROUGHNESS = 0.1;
	SPECULAR = 0.7;
	CLEARCOAT = 1.0;
	CLEARCOAT_ROUGHNESS = 0.04;

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = (c * (0.12 + glow * 0.45) + c * fresnel * 0.5) * (1.0 - dim)
		+ pip_color.rgb * pip * (0.35 + glow * 0.3) * (1.0 - dim)
		+ vec3(1.0) * flash * 1.5
		+ vec3(1.0) * fresnel * glow * 0.5;
}
