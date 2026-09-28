shader_type spatial;

// ==========================================
// UNIFORMS
// ==========================================
group_uniforms Textures;
uniform sampler2D noise_texture : hint_default_white;

group_uniforms Colors;
uniform vec4 light_grass : source_color = vec4(0.35, 0.68, 0.22, 1.0);
uniform vec4 dark_grass : source_color = vec4(0.24, 0.52, 0.14, 1.0);
uniform vec4 rock_color : source_color = vec4(0.40, 0.38, 0.35, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.32, 0.24, 0.16, 1.0);

group_uniforms Mowing_Stripes;
uniform float stripe_width = 5.0;
uniform float stripe_angle_degrees : hint_range(0.0, 360.0) = 45.0;
uniform float stripe_warp : hint_range(0.0, 2.0) = 0.3;

group_uniforms Slope_Controls;
uniform float slope_threshold : hint_range(0.0, 1.0) = 0.5;      // Angle threshold where rock turns into grass
uniform float slope_blend : hint_range(0.001, 0.5) = 0.1;        // Smoothness of transition
uniform float edge_noise_strength : hint_range(0.0, 0.5) = 0.15; // Natural erosion distortion on slope edge
uniform float dirt_width : hint_range(0.0, 0.5) = 0.2;           // Width of the dirt transition border

group_uniforms Noise_Tiling;
uniform float detail_scale = 0.2;                                 // Close-up micro detail scale
uniform float macro_scale = 0.03;                                 // Distant macro scale
uniform float macro_blend : hint_range(0.0, 1.0) = 0.5;          // Balance between detail and macro noise

// ==========================================
// VARYINGS
// ==========================================
varying vec3 world_position;
varying vec3 world_normal;

// ==========================================
// HELPER FUNCTIONS
// ==========================================
// Feature 4: Triplanar Texture Sampling
vec4 texture_triplanar(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 uv_p = p * scale;
	vec3 weights = abs(n);
	weights = max(weights, vec3(0.00001));
	weights /= (weights.x + weights.y + weights.z);

	vec4 x = texture(tex, uv_p.zy);
	vec4 y = texture(tex, uv_p.xz);
	vec4 z = texture(tex, uv_p.xy);

	return x * weights.x + y * weights.y + z * weights.z;
}

// ==========================================
// SHADER FUNCTIONS
// ==========================================
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 norm = normalize(world_normal);

	// 1. Feature 4 & 5: Macro + Micro Triplanar Noise
	float detail_noise = texture_triplanar(noise_texture, world_position, norm, detail_scale).r;
	float macro_noise = texture_triplanar(noise_texture, world_position, norm, macro_scale).r;
	float combined_noise = mix(detail_noise, macro_noise, macro_blend);

	// 2. Feature 2: Rotatable & Warped Mowing Stripes
	float rad = radians(stripe_angle_degrees);
	mat2 rot = mat2(vec2(cos(rad), -sin(rad)), vec2(sin(rad), cos(rad)));
	vec2 rotated_pos = rot * world_position.xz;

	// Add noise warp to coordinate so lines follow terrain contours
	float stripe_coord = rotated_pos.y + (combined_noise - 0.5) * stripe_warp * stripe_width;
	float stripe = step(0.5, fract(stripe_coord / (stripe_width * 2.0)));
	vec3 grass_base = mix(light_grass.rgb, dark_grass.rgb, stripe);
	vec3 grass_final = grass_base * (0.85 + combined_noise * 0.3);

	// 3. Base Rock & Dirt Colors
	vec3 rock_final = rock_color.rgb * (0.75 + combined_noise * 0.35);
	vec3 dirt_final = dirt_color.rgb * (0.8 + combined_noise * 0.3);

	// 4. Feature 1: Noisy Slope Mask (Natural Erosion)
	float noisy_normal_y = norm.y + (combined_noise - 0.5) * edge_noise_strength;
	float grass_mask = smoothstep(slope_threshold - slope_blend, slope_threshold + slope_blend, noisy_normal_y);

	// 5. Feature 3: Dirt Transition Mask
	float dirt_mask = smoothstep(0.5 - dirt_width, 0.5, grass_mask) - smoothstep(0.5, 0.5 + dirt_width, grass_mask);

	// 6. Final Color Assembly
	vec3 terrain_color = mix(rock_final, grass_final, grass_mask);
	terrain_color = mix(terrain_color, dirt_final, dirt_mask); // Inject dirt border at transition

	ALBEDO = terrain_color;
	ROUGHNESS = mix(0.95, 0.85, grass_mask);
}