shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

// The cloud look (Sculpture-Mass Design Doc §4.7, §4.9; Cloud-Formation Design Doc §4.2): a
// mostly solid white body, shaded by the light like the cloud puffs (white on the lit side, a cool
// blue-grey in shadow), with a hint of each object's own colour, a little glow and a thin warm rim.
// Toward its silhouette it darkens gently (a soft outline), and its bottom is darker and fully
// solid, like the base of a real cumulus. A mass swaps to its own copy of this material the moment
// it becomes a cloud, in place of sculpture_mass.gdshader; CloudSky sets cloud_middle_y and
// cloud_radius on that copy every frame.
// burst is that moment: at 1 the objects are a solid white-hot flash, and it falls to 0 over the
// manager's cloud_transition_time, settling into the cloud.

instance uniform vec4 base_tint : source_color = vec4(1.0);

group_uniforms cloud_look;
uniform vec4 cloud_color : source_color = vec4(1.0);
uniform vec4 shadow_color : source_color = vec4(0.62, 0.7, 0.85, 1.0);
// How much of the object's own colour shows through the white.
uniform float tint_keep : hint_range(0.0, 1.0) = 0.12;
uniform float cloud_alpha : hint_range(0.0, 1.0) = 0.9;
// A little light of its own, so the shadow side never goes dull grey.
uniform float cloud_glow : hint_range(0.0, 2.0) = 0.08;
// Where the light turns to shadow, and how softly (half-Lambert, 0 to 1).
uniform float shade_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float shade_softness : hint_range(0.01, 1.0) = 0.6;
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.8, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.2;

group_uniforms outline;
// The soft darkening toward the silhouette; cloud_ridges.gdshader uses the same tint for ridges.
uniform vec4 outline_color : source_color = vec4(0.42, 0.47, 0.6, 1.0);
uniform float outline_shade : hint_range(0.0, 1.0) = 0.25;
// Higher keeps it closer to the silhouette.
uniform float outline_power : hint_range(0.5, 8.0) = 4.0;

group_uniforms base;
uniform vec4 base_color : source_color = vec4(0.55, 0.58, 0.66, 1.0);
// How far the bottom shifts toward base_color.
uniform float base_strength : hint_range(0.0, 1.0) = 0.5;
// How much of the cloud's height, from the bottom, the darker base covers.
uniform float base_height : hint_range(0.01, 1.0) = 0.45;
// Set by CloudSky every frame: the cloud's middle height and radius (world). 0 radius: no base.
uniform float cloud_middle_y = 0.0;
uniform float cloud_radius = 0.0;

group_uniforms burst;
uniform float burst : hint_range(0.0, 1.0) = 0.0;
uniform vec4 burst_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float burst_glow : hint_range(0.0, 16.0) = 2.0;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	vec3 body = mix(cloud_color.rgb, COLOR.rgb * base_tint.rgb, tint_keep);

	// 1 at the cloud's bottom, 0 from base_height of the way up. World height, so it stays at the
	// bottom however the cloud tumbles.
	float low = 0.0;
	if (cloud_radius > 0.0) {
		float from_bottom = (world_y - (cloud_middle_y - cloud_radius)) / (2.0 * cloud_radius);
		low = 1.0 - smoothstep(0.0, base_height, from_bottom);
	}
	body = mix(body, base_color.rgb, low * base_strength);

	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	body = mix(body, outline_color.rgb, pow(1.0 - facing, outline_power) * outline_shade);

	ALBEDO = body;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - facing, rim_power) * (1.0 - low);
	EMISSION = body * cloud_glow + rim_color.rgb * rim * rim_strength + burst_color.rgb * burst * burst_glow;
	ALPHA = mix(mix(cloud_alpha, 1.0, low), 1.0, burst);
}

void light() {
	// Half-Lambert, then a soft step, so the shadow side falls off like a cloud's.
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = smoothstep(shade_threshold - shade_softness * 0.5, shade_threshold + shade_softness * 0.5, ndl);
	DIFFUSE_LIGHT += mix(shadow_color.rgb, vec3(1.0), lit) * LIGHT_COLOR * ATTENUATION / PI;
}
