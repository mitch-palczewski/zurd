shader_type spatial;
render_mode blend_mix;

// Stylised cloud shader.
// - Soft, bluish-grey shading instead of hard Lambert falloff (works with your DirectionalLight3D)
// - Optional fbm vertex "billow" displacement (needs a reasonably dense mesh; the puff spheres are fine)
// - Rim light for the silver-lining look
// - Reads INSTANCE_CUSTOM.xyz as a per-puff noise seed, so every MultiMesh sphere billows differently.
//   (On a normal MeshInstance3D that value is zero, so it just works there too.)
group_uniforms transparency;
uniform float transparency_min : hint_range(0.0, 1.0) = 0.40;
uniform float transparency_max : hint_range(0.0, 1.0) = 0.6;
uniform float transparency_speed : hint_range(0.0, 5.0) = .1;

group_uniforms colors;
uniform vec4 lit_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 shadow_color : source_color = vec4(0.62, 0.70, 0.85, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.93, 0.8, 1.0);

group_uniforms shading;
uniform float shade_threshold : hint_range(0.0, 1.0) = 0.5;
uniform float shade_softness : hint_range(0.01, 1.0) = 0.6;
uniform float noise_shading : hint_range(0.0, 1.0) = 0.25;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.5;

group_uniforms shape;
uniform float displace_strength : hint_range(0.0, 1.0) = 0.12;
uniform float noise_scale = 2.0;
uniform float billow_speed : hint_range(0.0, 1.0) = 0.08;

varying float v_billow;

// --- 3D gradient noise (iq) -------------------------------------------------
vec3 hash33(vec3 p) {
	p = vec3(
		dot(p, vec3(127.1, 311.7, 74.7)),
		dot(p, vec3(269.5, 183.3, 246.1)),
		dot(p, vec3(113.5, 271.9, 124.6)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float gnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(
			mix(dot(hash33(i + vec3(0.0, 0.0, 0.0)), f - vec3(0.0, 0.0, 0.0)),
				dot(hash33(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0)), u.x),
			mix(dot(hash33(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0)),
				dot(hash33(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0)), u.x),
			u.y),
		mix(
			mix(dot(hash33(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0)),
				dot(hash33(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0)), u.x),
			mix(dot(hash33(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0)),
				dot(hash33(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0)), u.x),
			u.y),
		u.z);
}

float fbm(vec3 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amp * gnoise(p);
		p = p * 2.03 + vec3(11.0, 5.0, 17.0);
		amp *= 0.5;
	}
	return value;
}
// ----------------------------------------------------------------------------

void vertex() {
	vec3 seed = INSTANCE_CUSTOM.xyz * 37.0;
	vec3 p = VERTEX * noise_scale + seed + vec3(0.0, TIME * billow_speed, 0.0);
	float n = fbm(p);
	v_billow = n;
	VERTEX += NORMAL * n * displace_strength;
}

void fragment() {
	float billow = clamp(v_billow * 0.5 + 0.5, 0.0, 1.0);

    ALBEDO = mix(
        lit_color.rgb,
        shadow_color.rgb,
        (1.0 - billow) * noise_shading
    );

    ROUGHNESS = 1.0;
    SPECULAR = 0.0;

    // Smoothly pulse between two transparency levels.
    float pulse = (sin(TIME * transparency_speed * 6.28318) + 1.0) * 0.5;
    ALPHA = mix(transparency_min, transparency_max, pulse);

    float rim = pow(
        1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0),
        rim_power
    );

    EMISSION = rim_color.rgb * rim * rim_strength;
}

void light() {
	// Half-lambert, then a soft step so shadows fall off like a cloud's underside
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float lit = smoothstep(
		shade_threshold - shade_softness * 0.5,
		shade_threshold + shade_softness * 0.5,
		ndl);
	vec3 tint = mix(shadow_color.rgb, vec3(1.0), lit);
	DIFFUSE_LIGHT += tint * LIGHT_COLOR * ATTENUATION / PI;
}
