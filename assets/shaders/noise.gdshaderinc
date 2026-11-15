// Smooth 3D value noise and fractal noise built from it, for shaders that need organic shapes
// without a noise texture. Both return values in 0..1, around 0.5 on average.

float noise_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float x00 = mix(noise_hash(i), noise_hash(i + vec3(1.0, 0.0, 0.0)), u.x);
	float x10 = mix(noise_hash(i + vec3(0.0, 1.0, 0.0)), noise_hash(i + vec3(1.0, 1.0, 0.0)), u.x);
	float x01 = mix(noise_hash(i + vec3(0.0, 0.0, 1.0)), noise_hash(i + vec3(1.0, 0.0, 1.0)), u.x);
	float x11 = mix(noise_hash(i + vec3(0.0, 1.0, 1.0)), noise_hash(i + vec3(1.0, 1.0, 1.0)), u.x);
	return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

// Layers of value noise, each twice as fine and half as strong as the one before.
float fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amplitude = 0.5;
	float total = 0.0;
	for (int i = 0; i < octaves; i++) {
		sum += value_noise(p) * amplitude;
		total += amplitude;
		// Turn a little between layers so their grids don't line up.
		p = vec3(p.x * 1.6 + p.z * 1.2, p.y * 2.0, p.z * 1.6 - p.x * 1.2) + vec3(17.1, 3.7, 9.3);
		amplitude *= 0.5;
	}
	return sum / total;
}
