shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

// The cloud look (Sculpture-Mass Design Doc §4.7, §4.9): white, soft and see-through, glowing at the
// rim, with a hint of each object's own colour. A mass swaps to its own copy of this material the
// moment it becomes a cloud, in place of sculpture_mass.gdshader.
// burst is that moment: at 1 the objects are a solid white-hot flash, and it falls to 0 over the
// manager's cloud_transition_time, settling into the cloud.
// PLACEHOLDER: the real cloud look is still to be designed (Cloud-Formation Design Doc).

instance uniform vec4 base_tint : source_color = vec4(1.0);

group_uniforms cloud_look;
uniform vec4 cloud_color : source_color = vec4(1.0);
// How much of the object's own colour shows through the white.
uniform float tint_keep : hint_range(0.0, 1.0) = 0.12;
uniform float cloud_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_glow : hint_range(0.0, 2.0) = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.8, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.8;

group_uniforms burst;
uniform float burst : hint_range(0.0, 1.0) = 0.0;
uniform vec4 burst_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform float burst_glow : hint_range(0.0, 16.0) = 2.0;

void fragment() {
	vec3 own = COLOR.rgb * base_tint.rgb;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = mix(cloud_color.rgb, own, tint_keep);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	EMISSION = cloud_color.rgb * cloud_glow + rim_color.rgb * rim * rim_strength
			+ burst_color.rgb * burst * burst_glow;
	ALPHA = mix(cloud_alpha, 1.0, burst);
}
