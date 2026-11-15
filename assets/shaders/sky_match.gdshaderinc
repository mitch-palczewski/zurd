// The sky's colour in a direction, so a surface can take its colour from the sky behind it (the
// canopy over the mega trees). It reads the same panorama the WorldEnvironment's
// PanoramaSkyMaterial shows, mapped the way Godot maps a panorama sky. Godot draws the background
// from a lower-resolution copy of the sky, so this is a little sharper than the sky itself; a
// surface painted with it alone doesn't vanish completely (fade with ALPHA for that).
// Keep the two uniforms in step with the PanoramaSkyMaterial in scenes/world/environment.tscn
// (its panorama and energy_multiplier); the sky's rotation is assumed to be 0.

uniform sampler2D sky_panorama : source_color, filter_linear, repeat_enable, hint_default_black;
// The PanoramaSkyMaterial's energy_multiplier.
uniform float sky_energy = 0.4;

// The sky seen looking along world_dir (any length).
vec3 sky_color(vec3 world_dir) {
	vec3 dir = normalize(world_dir);
	vec2 coords = vec2(atan(dir.x, -dir.z), acos(clamp(dir.y, -1.0, 1.0)));
	if (coords.x < 0.0) {
		coords.x += TAU;
	}
	coords /= vec2(TAU, PI);
	return texture(sky_panorama, coords).rgb * sky_energy;
}
