shader_type spatial;

uniform vec3 water_color : source_color = vec3(0.02, 0.05, 0.06);
uniform float roughness : hint_range(0.0, 1.0) = 0.02;
uniform sampler2D ripple_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float ripple_size = 20.0;          // meters per texture repeat
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.1;
uniform float ripple_speed = 0.02;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 uv = world_pos.xz / ripple_size;
    vec3 n1 = texture(ripple_normal, uv + vec2(TIME * ripple_speed, 0.0)).rgb;
    vec3 n2 = texture(ripple_normal, uv * 1.7 - vec2(0.0, TIME * ripple_speed * 0.6)).rgb;

    ALBEDO = water_color;
    METALLIC = 0.0;
    ROUGHNESS = roughness;
    SPECULAR = 0.5;
    NORMAL_MAP = mix(n1, n2, 0.5);
    NORMAL_MAP_DEPTH = ripple_strength;
}