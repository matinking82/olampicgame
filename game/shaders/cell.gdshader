shader_type spatial;

// A board cell: a rounded square with a soft vertical gradient and a
// faintly lit rim, cut out of a plane.

uniform vec4 cell_color : source_color = vec4(0.17, 0.13, 0.38, 1.0);
uniform float corner = 0.2;

void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	vec2 q = d - vec2(1.0 - corner);
	float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
	if (sdf > 0.0) {
		discard;
	}
	float rim = smoothstep(-0.16, -0.02, sdf);
	vec3 c = cell_color.rgb * (0.85 + 0.3 * (1.0 - UV.y));
	ALBEDO = c;
	ROUGHNESS = 0.35;
	EMISSION = cell_color.rgb * 0.15 + mix(cell_color.rgb, vec3(1.0), 0.4) * rim * 0.35;
}
