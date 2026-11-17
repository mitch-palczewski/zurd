shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back;

// The mega trees' trunks: a plain grey-pink trunk that melts away as it rises, so no trunk ever
// shows where it ends (the trees are too tall to see the tops of). Between fade_start and fade_end
// it turns see-through along a slightly uneven line that drifts very slowly, so it vanishes into
// whatever is behind it: the sky, or the canopy (sky_canopy.gdshader).
// Heights are metres above the trunk's foot (the mesh's lowest point, foot_offset), so moving or
// scaling a tree, or the terrain under it, keeps the look.
// The solid part still writes depth (depth_prepass_alpha), so it hides what is behind it like any
// solid object. The material's render_priority is below the canopy's, so trunks draw first and the
// canopy lies over their faded tops.

#include "res://assets/shaders/noise.gdshaderinc"

// The trunk's foot below the model's origin, in the model's own units (mega_tree.glb: -1.873).
uniform float foot_offset = -1.873;

group_uniforms trunk;
uniform vec3 base_color : source_color = vec3(0.62, 0.53, 0.55);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
// How much darker the trunk is low down than higher up.
uniform float foot_shade : hint_range(0.0, 1.0) = 0.25;
// Heights (metres above the foot) between which the trunk goes from dark to its full colour.
uniform float shade_bottom = 0.0;
uniform float shade_top = 300.0;

group_uniforms fade;
// Heights (metres above the foot) where the trunk starts fading and where it is gone.
uniform float fade_start = 600.0;
uniform float fade_end = 2000.0;
// How far (metres) the fade line moves up and down; 0 makes it a straight line.
uniform float fade_wobble = 40.0;
// Metres across one bump of the uneven fade line.
uniform float wobble_size = 120.0;
uniform float wobble_speed = 0.01;

// World X and Z, and the height above the foot.
varying vec3 trunk_pos;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float foot = (MODEL_MATRIX * vec4(0.0, foot_offset, 0.0, 1.0)).y;
	trunk_pos = vec3(world_pos.x, world_pos.y - foot, world_pos.z);
}

void fragment() {
	float height = trunk_pos.y;
	float wobble = (value_noise(trunk_pos / wobble_size + vec3(0.0, TIME * wobble_speed, 0.0)) * 2.0 - 1.0)
			* fade_wobble;
	float fade = smoothstep(fade_start, fade_end, height + wobble);
	float shade = mix(1.0 - foot_shade, 1.0,
			clamp((height - shade_bottom) / max(shade_top - shade_bottom, 0.001), 0.0, 1.0));

	ALBEDO = base_color * shade;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	ALPHA = 1.0 - fade;
}
