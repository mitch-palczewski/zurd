shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

// Look of an object fused into a sculpture mass (Sculpture-Mass Design Doc §4.4, §4.9).
// Each mass has its own copy of this material and sets cloud_amount to its cloud progress.
// - cloud_amount 0..1: the object's own vertex-colour look blends toward cloud_color, with a
//   subtle transparency. base_* are per object (instance uniforms copied from its original
//   material), so one material serves every object in the mass.
// - cloud_form 0..1: PLACEHOLDER for the dramatic look at 100%; the real cloud look is still to
//   be designed. Tweened in when the mass becomes a cloud.
// - flash_amount: the blink when a Zurd eats an object (red) or two masses merge.

instance uniform vec4 base_tint : source_color = vec4(1.0);
instance uniform float base_roughness = 1.0;
instance uniform float base_metallic = 0.0;

group_uniforms cloud_blend;
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 cloud_color : source_color = vec4(1.0);
uniform float max_transparency : hint_range(0.0, 1.0) = 0.2;

group_uniforms cloud_look;
uniform float cloud_form : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_glow : hint_range(0.0, 1.0) = 0.3;
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.8, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.6;

group_uniforms flash;
uniform vec4 flash_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Matches the original StandardMaterial3D: vertex colour (taken as linear) times albedo colour.
	vec3 albedo = mix(COLOR.rgb * base_tint.rgb, cloud_color.rgb, cloud_amount);
	float alpha = 1.0 - max_transparency * cloud_amount;
	float softness = max(cloud_amount, cloud_form);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = mix(albedo, flash_color.rgb, flash_amount * 0.5);
	ROUGHNESS = mix(base_roughness, 1.0, softness);
	METALLIC = mix(base_metallic, 0.0, softness);
	EMISSION = (cloud_color.rgb * cloud_glow + rim_color.rgb * rim * rim_strength) * cloud_form
			+ flash_color.rgb * flash_amount;
	ALPHA = mix(alpha, cloud_alpha, cloud_form);
}
