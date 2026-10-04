shader_type spatial;

// ==========================================
// UNIFORMS
// ==========================================
group_uniforms Textures;
uniform sampler2D noise_texture : hint_default_white;

group_uniforms Colors;
// Darker grass defaults
uniform vec4 grass_color : source_color = vec4(0.18, 0.42, 0.10, 1.0);
uniform vec4 grass_accent : source_color = vec4(0.35, 0.65, 0.20, 1.0); // Accent tint for random triangles
// Brighter rock default
uniform vec4 rock_color : source_color = vec4(0.55, 0.52, 0.48, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.32, 0.24, 0.16, 1.0);

group_uniforms Triangle_Styling;
uniform bool enable_triangle_colors = true;
uniform float triangle_scale = 1.0;                                // Scale/size of the triangles
uniform float triangle_color_variation : hint_range(0.0, 1.0) = 0.4; // Random color variation per triangle

group_uniforms Felt_Effect;
uniform bool enable_felt = true;
uniform float felt_coverage : hint_range(0.0, 1.0) = 0.35;        // Percentage of triangles that look like felt (0% to 100%)
uniform float felt_fuzziness : hint_range(0.0, 1.0) = 0.5;       // Intensity of the micro-fiber noise and matte roughness

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
// Pseudo-random hash producing a [0.0, 1.0] float from a 3D vector ID
float hash31(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

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

// Calculates a unique random factor [0.0, 1.0] for each triangle cell (Color)
float get_triangle_cell_2d(vec2 uv) {
    vec2 coord = uv * triangle_scale;
    vec2 skewed = vec2(coord.x + coord.y * 0.57735027, coord.y * 1.15470054);
    vec2 cell = floor(skewed);
    vec2 f = fract(skewed);
    float sub_tri = (f.x > f.y) ? 1.0 : 0.0;
    return hash31(vec3(cell, sub_tri));
}

// Calculates an independent random factor [0.0, 1.0] for each triangle cell (Felt Selection)
float get_triangle_felt_2d(vec2 uv) {
    vec2 coord = uv * triangle_scale;
    vec2 skewed = vec2(coord.x + coord.y * 0.57735027, coord.y * 1.15470054);
    vec2 cell = floor(skewed);
    vec2 f = fract(skewed);
    float sub_tri = (f.x > f.y) ? 1.0 : 0.0;
    // Shift seed offset so felt placement is independent of color variation
    return hash31(vec3(cell + vec2(17.3, 43.1), sub_tri + 7.9));
}

// Triplanar projection of per-triangle cell random factors
float triplanar_triangle_cells(vec3 p, vec3 n) {
    vec3 weights = abs(n);
    weights = max(weights, vec3(0.00001));
    weights /= (weights.x + weights.y + weights.z);

    float cx = get_triangle_cell_2d(p.zy);
    float cy = get_triangle_cell_2d(p.xz);
    float cz = get_triangle_cell_2d(p.xy);

    return cx * weights.x + cy * weights.y + cz * weights.z;
}

// Triplanar projection of felt selection mask
float triplanar_triangle_felt(vec3 p, vec3 n) {
    vec3 weights = abs(n);
    weights = max(weights, vec3(0.00001));
    weights /= (weights.x + weights.y + weights.z);

    float fx = get_triangle_felt_2d(p.zy);
    float fy = get_triangle_felt_2d(p.xz);
    float fz = get_triangle_felt_2d(p.xy);

    return fx * weights.x + fy * weights.y + fz * weights.z;
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

    // 2. Base Grass Color
    vec3 grass_base = grass_color.rgb;
    vec3 grass_final = grass_base * (0.85 + combined_noise * 0.3);

    // 3. Per-Triangle Color Variation (Grass Only)
    vec3 varied_grass = grass_final;
    if (enable_triangle_colors) {
        float tri_random = triplanar_triangle_cells(world_position, norm);
        varied_grass = mix(grass_final, grass_accent.rgb, (tri_random - 0.5) * triangle_color_variation);
    }

    // 4. Felt Effect (Selected Triangles)
    float felt_mask = 0.0;
    if (enable_felt) {
        float felt_rand = triplanar_triangle_felt(world_position, norm);
        // Determine if this triangle is selected for felt
        felt_mask = step(1.0 - felt_coverage, felt_rand);
        
        // Sample high-frequency micro-grain noise for the felt weave look
        float micro_fuzz = texture_triplanar(noise_texture, world_position, norm, detail_scale * 8.0).r;
        
        // Apply fibrous micro-grain tint to felt triangles
        vec3 felt_color = varied_grass * (1.0 - (micro_fuzz - 0.5) * felt_fuzziness * 0.35);
        varied_grass = mix(varied_grass, felt_color, felt_mask);
    }
    
    // 5. Base Rock & Dirt Colors (Brighter Rock)
    vec3 rock_final = rock_color.rgb * (0.75 + combined_noise * 0.35);
    vec3 dirt_final = dirt_color.rgb * (0.8 + combined_noise * 0.3);

    // 6. Slope & Dirt Masks
    float noisy_normal_y = norm.y + (combined_noise - 0.5) * edge_noise_strength;
    float grass_mask = smoothstep(slope_threshold - slope_blend, slope_threshold + slope_blend, noisy_normal_y);
    float dirt_mask = smoothstep(0.5 - dirt_width, 0.5, grass_mask) - smoothstep(0.5, 0.5 + dirt_width, grass_mask);

    // 7. Final Color Assembly
    vec3 terrain_color = mix(rock_final, varied_grass, grass_mask);
    terrain_color = mix(terrain_color, dirt_final, dirt_mask);

    ALBEDO = terrain_color;

    // 8. Dynamic PBR Roughness (Felt triangles get near 1.0 matte roughness)
    float base_grass_roughness = mix(0.70, 0.98, felt_mask * felt_fuzziness);
    ROUGHNESS = mix(0.85, base_grass_roughness, grass_mask);
}