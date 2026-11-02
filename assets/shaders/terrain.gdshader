shader_type spatial;

// Grass, dirt and rock by slope; sand along the shore; snow up high; a rippled seabed with
// moving caustics under the water. A world-space triangle grid tints and shades every
// triangle on land. Heights are the mesh's local y, so water_level matches a water plane
// placed in the same scene as the terrain.

// ==========================================
// UNIFORMS
// ==========================================
group_uniforms Textures;
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;

group_uniforms Colors;
// Darker grass defaults
uniform vec4 grass_color : source_color = vec4(0.18, 0.42, 0.10, 1.0);
uniform vec4 grass_accent : source_color = vec4(0.35, 0.65, 0.20, 1.0); // Accent tint for random triangles
uniform vec4 highland_grass : source_color = vec4(0.40, 0.44, 0.20, 1.0); // Drier grass the grass fades to up high
// Brighter rock default
uniform vec4 rock_color : source_color = vec4(0.55, 0.52, 0.48, 1.0);
uniform vec4 dirt_color : source_color = vec4(0.32, 0.24, 0.16, 1.0);
uniform vec4 sand_color : source_color = vec4(0.78, 0.70, 0.50, 1.0);
uniform vec4 snow_color : source_color = vec4(0.93, 0.95, 0.98, 1.0);

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

group_uniforms Height_Bands;
uniform float water_level = 0.0;                                  // Local height of the water surface
uniform float beach_height = 1.2;                                 // Sand reaches this far above the water (meters)
uniform float highland_height = 35.0;                             // Grass is fully highland_grass from here up
uniform float snow_height = 55.0;                                 // Snow line (local meters)
uniform float snow_blend = 5.0;                                   // Height over which snow fades in
uniform float snow_slope : hint_range(0.0, 1.0) = 0.6;            // Snow only settles where normal.y is above this
uniform float band_noise = 1.5;                                   // Meters of noise that break up the sand and snow lines

group_uniforms Rock_Strata;
uniform float strata_scale = 0.08;                                // Frequency of horizontal bands on cliffs
uniform float strata_strength : hint_range(0.0, 1.0) = 0.35;

group_uniforms Underwater;
uniform vec4 shallow_color : source_color = vec4(0.62, 0.58, 0.42, 1.0); // Seabed sand near the shore
uniform vec4 deep_color : source_color = vec4(0.08, 0.20, 0.22, 1.0);    // Seabed in deep water
uniform float deep_depth = 12.0;                                  // Depth where the seabed reaches deep_color
uniform float ripple_scale = 1.5;                                 // Sand ripple frequency (about 4 m apart)
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.25;
uniform float caustic_scale = 0.05;
uniform float caustic_strength : hint_range(0.0, 2.0) = 0.7;
uniform float caustic_speed = 0.02;

group_uniforms Noise_Tiling;
uniform float detail_scale = 0.2;                                 // Close-up micro detail scale
uniform float macro_scale = 0.03;                                 // Distant macro scale
uniform float macro_blend : hint_range(0.0, 1.0) = 0.5;          // Balance between detail and macro noise

// ==========================================
// VARYINGS
// ==========================================
varying vec3 world_position;
varying vec3 world_normal;
varying float local_height;

// ==========================================
// HELPER FUNCTIONS
// ==========================================
// Pseudo-random hash producing a [0.0, 1.0] float from a 3D vector ID
float hash31(vec3 p) {
    p = fract(p * vec3(443.897, 441.423, 437.195));
    p += dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}

// Triplanar Texture Sampling
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

// World plane the surface faces most. Projecting the triangle grid onto one plane keeps
// every triangle a single crisp value, where blending three planes would mix them.
vec2 dominant_plane(vec3 p, vec3 n) {
    vec3 a = abs(n);
    if (a.y >= a.x && a.y >= a.z) {
        return p.xz;
    }
    return (a.x >= a.z) ? p.zy : p.xy;
}

// Unique random factor [0.0, 1.0] for each triangle cell; offset selects an independent stream
float triangle_hash(vec2 uv, vec3 offset) {
    vec2 coord = uv * triangle_scale;
    vec2 skewed = vec2(coord.x + coord.y * 0.57735027, coord.y * 1.15470054);
    vec2 cell = floor(skewed);
    vec2 f = fract(skewed);
    float sub_tri = (f.x > f.y) ? 1.0 : 0.0;
    return hash31(vec3(cell, sub_tri) + offset);
}

// Bright web of light lines where two drifting noise layers cross
float caustics(vec2 p, float t) {
    vec2 uv = p * caustic_scale;
    float a = texture(noise_texture, uv + vec2(1.0, 0.7) * t * caustic_speed).r;
    float b = texture(noise_texture, uv * 1.37 + vec2(-0.8, 0.5) * t * caustic_speed).r;
    return pow(1.0 - abs(a - b), 10.0);
}

// ==========================================
// SHADER FUNCTIONS
// ==========================================
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = MODEL_NORMAL_MATRIX * NORMAL;
    local_height = VERTEX.y;
}

void fragment() {
    vec3 norm = normalize(world_normal);

    // 1. Macro + Micro Triplanar Noise
    float detail_noise = texture_triplanar(noise_texture, world_position, norm, detail_scale).r;
    float macro_noise = texture_triplanar(noise_texture, world_position, norm, macro_scale).r;
    float combined_noise = mix(detail_noise, macro_noise, macro_blend);
    float noisy_height = local_height + (combined_noise - 0.5) * band_noise;

    // 2. Per-Triangle Random Values
    vec2 triangle_plane = dominant_plane(world_position, norm);
    float tri_random = enable_triangle_colors ? triangle_hash(triangle_plane, vec3(0.0)) : 0.5;
    float tri_shade = 1.0 + (tri_random - 0.5) * triangle_color_variation * 0.4;

    // 3. Grass: drier with altitude, accent tint per triangle
    float highland_mask = smoothstep(water_level + beach_height, highland_height, noisy_height);
    vec3 grass = mix(grass_color.rgb, highland_grass.rgb, highland_mask) * (0.85 + combined_noise * 0.3);
    grass = mix(grass, grass_accent.rgb, (tri_random - 0.5) * triangle_color_variation);

    // 4. Felt Effect (Selected Triangles)
    float felt_mask = 0.0;
    if (enable_felt) {
        float felt_rand = triangle_hash(triangle_plane, vec3(17.3, 43.1, 7.9));
        felt_mask = step(1.0 - felt_coverage, felt_rand);

        // Sample high-frequency micro-grain noise for the felt weave look
        float micro_fuzz = texture_triplanar(noise_texture, world_position, norm, detail_scale * 8.0).r;
        vec3 felt_color = grass * (1.0 - (micro_fuzz - 0.5) * felt_fuzziness * 0.35);
        grass = mix(grass, felt_color, felt_mask);
    }

    // 5. Rock with horizontal strata, and dirt
    float strata = texture(noise_texture, vec2(world_position.y * strata_scale, (world_position.x + world_position.z) * 0.003)).r;
    vec3 rock = rock_color.rgb * (0.75 + combined_noise * 0.35) * mix(1.0, 0.7 + strata * 0.6, strata_strength);
    vec3 dirt = dirt_color.rgb * (0.8 + combined_noise * 0.3);

    // 6. Slope & Dirt Masks
    float noisy_normal_y = norm.y + (combined_noise - 0.5) * edge_noise_strength;
    float grass_mask = smoothstep(slope_threshold - slope_blend, slope_threshold + slope_blend, noisy_normal_y);
    float dirt_mask = smoothstep(0.5 - dirt_width, 0.5, grass_mask) - smoothstep(0.5, 0.5 + dirt_width, grass_mask);

    vec3 land = mix(rock, grass, grass_mask);
    land = mix(land, dirt, dirt_mask);

    // 7. Sand along the shore on gentle ground, darker and glossier where wet at the water line
    float sand_mask = 1.0 - smoothstep(water_level + beach_height * 0.5, water_level + beach_height, noisy_height);
    sand_mask *= smoothstep(slope_threshold - slope_blend * 3.0, slope_threshold, noisy_normal_y);
    float wet_mask = 1.0 - smoothstep(water_level, water_level + beach_height * 0.3, local_height);
    vec3 sand = sand_color.rgb * (0.85 + combined_noise * 0.3) * mix(1.0, 0.65, wet_mask);
    land = mix(land, sand, sand_mask);

    // 8. Snow on high ground that is flat enough to hold it
    float snow_mask = smoothstep(snow_height - snow_blend, snow_height + snow_blend, noisy_height);
    snow_mask *= smoothstep(snow_slope - 0.1, snow_slope + 0.1, noisy_normal_y);
    land = mix(land, snow_color.rgb * (0.95 + combined_noise * 0.1), snow_mask);

    land *= tri_shade;

    // 9. Seabed: rippled sand fading to deep color, caustics in the shallows
    float depth_t = clamp((water_level - local_height) / deep_depth, 0.0, 1.0);
    float ripple_phase = dot(world_position.xz, vec2(0.8, 0.6)) * ripple_scale
        + texture(noise_texture, world_position.xz * 0.01).r * 12.0;
    float ripple_fade = 1.0 - clamp(fwidth(ripple_phase) / PI, 0.0, 1.0); // Fade out before ripples alias
    float ripples = (sin(ripple_phase) * 0.5 + 0.5) * ripple_strength * ripple_fade;
    vec3 seabed = mix(shallow_color.rgb, deep_color.rgb, depth_t) * (1.0 - ripples * (1.0 - depth_t * 0.5));
    seabed *= 1.0 + caustics(world_position.xz, TIME) * caustic_strength * (1.0 - depth_t);

    float underwater_mask = 1.0 - smoothstep(water_level - 0.4, water_level + 0.1, local_height);

    ALBEDO = mix(land, seabed, underwater_mask);

    // 10. Roughness (felt triangles near 1.0 matte; wet sand glossy)
    float grass_roughness = mix(0.70, 0.98, felt_mask * felt_fuzziness);
    float roughness = mix(0.85, grass_roughness, grass_mask);
    roughness = mix(roughness, mix(0.95, 0.35, wet_mask), sand_mask);
    roughness = mix(roughness, 0.55, snow_mask);
    ROUGHNESS = mix(roughness, 0.9, underwater_mask);
}
