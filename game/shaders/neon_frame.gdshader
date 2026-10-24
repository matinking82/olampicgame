shader_type spatial;
render_mode unshaded;

// Rainbow neon that slowly travels around the board's edge.

uniform float speed = 0.06;
uniform float energy = 2.6;
uniform float whiteness : hint_range(0.0, 1.0) = 0.05;
// Pulls the rainbow toward one colour (alpha = how far); Merge Mate uses it
// to show whose turn it is.
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);

varying vec3 local_pos;

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	float around = atan(local_pos.z, local_pos.x) / 6.2831853 + 0.5;
	vec3 c = mix(hue(fract(around + TIME * speed)), vec3(1.0), whiteness);
	c = mix(c, tint.rgb, tint.a);
	ALBEDO = c * energy;
}
