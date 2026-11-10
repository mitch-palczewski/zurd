shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Look of an object fused into a sculpture mass that isn't a cloud yet (Sculpture-Mass Design Doc
// §4.4, §4.9). Opaque, so a fused object stays as solid as a loose one and casts shadows.
// Each mass has its own copy of this material and sets cloud_amount to its cloud progress (0..1):
// the object's own look shifts part of the way toward cloud_color and a little toward matte, late
// rather than evenly, so progress shows while the object still reads as a thing. At 100% the mass
// swaps to sculpture_cloud.gdshader, so becoming a cloud is a jump, not the end of a fade.
// base_* are per object (instance uniforms copied from its original material), so one material
// serves every object in the mass.
// flash_amount: the blink when a Zurd eats an object (red) or two masses merge.

instance uniform vec4 base_tint : source_color = vec4(1.0);
instance uniform float base_roughness = 1.0;
instance uniform float base_metallic = 0.0;

group_uniforms cloud_blend;
uniform float cloud_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 cloud_color : source_color = vec4(1.0);
// How far toward cloud_color an object has moved just before its mass becomes a cloud.
uniform float max_whiten : hint_range(0.0, 1.0) = 0.45;
// How far toward fully matte (rough, not metallic) it has moved by then.
uniform float max_soften : hint_range(0.0, 1.0) = 0.3;
// 1 changes evenly with progress; higher keeps objects looking like themselves for longer and saves
// the change for the last stretch.
uniform float blend_curve : hint_range(0.5, 4.0) = 1.5;

group_uniforms flash;
uniform vec4 flash_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float blend = pow(clamp(cloud_amount, 0.0, 1.0), blend_curve);
	// Matches the original StandardMaterial3D: vertex colour (taken as linear) times albedo colour.
	vec3 albedo = mix(COLOR.rgb * base_tint.rgb, cloud_color.rgb, blend * max_whiten);

	ALBEDO = mix(albedo, flash_color.rgb, flash_amount * 0.5);
	ROUGHNESS = mix(base_roughness, 1.0, blend * max_soften);
	METALLIC = mix(base_metallic, 0.0, blend * max_soften);
	EMISSION = flash_color.rgb * flash_amount;
}
