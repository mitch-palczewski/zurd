shader_type spatial;

// Mirror water with slight ripples. PlanarReflection renders the scene from a camera mirrored in
// the water and hands its picture over as reflection_texture; this shows it at each pixel's screen
// position, nudged by two scrolling layers of ripple normals. Without a reflection (in the
// editor), the water shows its colour and the sky's reflection.

uniform vec3 water_color : source_color = vec3(0.02, 0.05, 0.06);
uniform float roughness : hint_range(0.0, 1.0) = 0.05;
uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable;
// Metres per repeat of the ripple texture.
uniform float ripple_size = 8.0;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.3;
uniform float ripple_speed = 0.03;
// How far the ripples push the reflection, as a share of the screen.
uniform float distortion : hint_range(0.0, 0.1) = 0.01;
// Share of the reflection seen looking straight down; looking across the water it is all mirror.
uniform float mirror_straight_down : hint_range(0.0, 1.0) = 0.6;
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.9;

// Set by PlanarReflection.
uniform sampler2D reflection_texture : source_color, filter_linear, repeat_disable;
uniform bool reflection_active = false;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz / ripple_size;
	vec3 n1 = texture(ripple_normal, uv + vec2(TIME * ripple_speed, 0.0)).rgb;
	vec3 n2 = texture(ripple_normal, uv * 1.7 - vec2(0.0, TIME * ripple_speed * 0.6)).rgb;
	vec3 ripple = mix(n1, n2, 0.5);

	ALBEDO = water_color;
	METALLIC = 0.0;
	ROUGHNESS = roughness;
	NORMAL_MAP = ripple;
	NORMAL_MAP_DEPTH = ripple_strength;

	if (reflection_active) {
		// The mirror camera's picture is flipped left to right.
		vec2 mirror_uv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y);
		mirror_uv += (ripple.xy * 2.0 - 1.0) * distortion * ripple_strength;
		mirror_uv = clamp(mirror_uv, vec2(0.001), vec2(0.999));
		vec3 reflection = texture(reflection_texture, mirror_uv).rgb;

		float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float mirror = mix(mirror_straight_down, 1.0, pow(1.0 - facing, 5.0)) * reflection_strength;
		ALBEDO = water_color * (1.0 - mirror);
		EMISSION = reflection * mirror;
		// The reflection already holds the sky: no second sky reflection on top.
		SPECULAR = 0.1;
	} else {
		SPECULAR = 0.5;
	}
}
