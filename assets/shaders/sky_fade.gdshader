shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

// The mega trees' trunks: a plain grey-pink trunk that melts away as it rises, so no trunk ever
// shows where it ends (the trees are too tall to see the tops of). Between fade_start and fade_end
// (world heights) it turns see-through along a slightly uneven line that drifts very slowly, so
// it vanishes into whatever is behind it: the sky, or the canopy (sky_canopy.gdshader).
// The solid part still writes depth (depth_prepass_alpha), so it hides what is behind it like any
// solid object. The material's render_priority is below the canopy's, so trunks draw first and the
// canopy lies over their faded tops.

#include "res://assets/shaders/noise.gdshaderinc"

group_uniforms trunk;
uniform vec3 base_color : source_color = vec3(0.62, 0.53, 0.55);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
// How much darker the trunk is at its foot than higher up.
uniform float foot_shade : hint_range(0.0, 1.0) = 0.25;
// Height (world) where the trunk reaches its full colour.
uniform float foot_shade_height = 300.0;

group_uniforms fade;
// World heights where the trunk starts fading and where it is gone.
uniform float fade_start = 250.0;
uniform float fade_end = 800.0;
// How far (metres) the fade line moves up and down; 0 makes it a straight line.
uniform float fade_wobble = 40.0;
// Metres across one bump of the uneven fade line.
uniform float wobble_size = 120.0;
uniform float wobble_speed = 0.01;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float wobble = (value_noise(world_pos / wobble_size + vec3(0.0, TIME * wobble_speed, 0.0)) * 2.0 - 1.0)
			* fade_wobble;
	float fade = smoothstep(fade_start, fade_end, world_pos.y + wobble);
	float shade = mix(1.0 - foot_shade, 1.0, clamp(world_pos.y / foot_shade_height, 0.0, 1.0));

	ALBEDO = base_color * shade;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	ALPHA = 1.0 - fade;
}
