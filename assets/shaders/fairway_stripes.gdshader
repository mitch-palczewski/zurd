shader_type spatial;

uniform sampler2D noise_texture; // Added missing semicolon

uniform vec4 light_grass : source_color = vec4(0.35, 0.68, 0.22, 1.0);
uniform vec4 dark_grass : source_color = vec4(0.24, 0.52, 0.14, 1.0);
uniform float stripe_width = 5.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; // Added missing semicolon
}

void fragment() {
	float stripe = step(0.5, fract(world_position.z / (stripe_width * 2.0)));
	vec3 base_color = mix(light_grass.rgb, dark_grass.rgb, stripe);
	
	float noise = texture(noise_texture, world_position.xz * 0.2).r;

	ALBEDO = base_color * (0.85 + noise * 0.3);
	ROUGHNESS = 0.85;
}