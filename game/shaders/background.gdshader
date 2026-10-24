shader_type canvas_item;

// Screen background: a vertical gradient with slowly turning diagonal
// light bands, soft light spots drifting upwards, and a vignette.

uniform vec4 top_color : source_color = vec4(0.25, 0.14, 0.62, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.85, 0.3, 0.62, 1.0);
uniform vec4 spot_color : source_color = vec4(1.0, 0.85, 1.0, 1.0);
uniform int spot_count = 18;
// 0-1: Fever mode swirls rainbow colours through the gradient.
uniform float fever : hint_range(0.0, 1.0) = 0.0;

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

float rand(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.1, uv.y));

	float bands = sin((uv.x * aspect + uv.y) * 9.0 - TIME * (0.35 + 2.5 * fever)) * 0.5 + 0.5;
	col += vec3(0.035 + 0.05 * fever) * bands;
	vec3 swirl = hue(fract(uv.y * 0.6 + uv.x * 0.3 - TIME * 0.15)) * 0.9;
	col = mix(col, swirl, fever * 0.35);

	float spots = 0.0;
	for (int i = 0; i < spot_count; i++) {
		float fi = float(i);
		float speed = 0.012 + 0.02 * rand(fi + 3.1);
		vec2 c = vec2(rand(fi), fract(rand(fi + 7.7) - TIME * speed));
		float r = 0.02 + 0.06 * rand(fi + 1.3);
		vec2 d = (uv - c) * vec2(aspect, 1.0);
		float twinkle = 0.6 + 0.4 * sin(TIME * (1.0 + rand(fi + 5.0)) + fi);
		spots += (1.0 - smoothstep(r * 0.4, r, length(d))) * 0.09 * twinkle;
	}
	col += spot_color.rgb * spots;

	vec2 v = (uv - 0.5) * vec2(aspect, 1.0);
	col *= 1.0 - 0.35 * smoothstep(0.4, 1.1, length(v) / max(aspect, 1.0) * 1.4);
	COLOR = vec4(col, 1.0);
}
