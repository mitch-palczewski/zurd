shader_type spatial;

// Checkerboard in object space: no UVs needed, and the pattern sticks to the model and scales
// with it. Each face takes the two axes it faces least along (a floor uses X and Z, a wall Z and Y
// or X and Y), so squares stay square on floors, walls and slopes. The checker is filtered by the
// pixel's footprint, so distant squares blend to the average colour instead of flickering.

uniform vec3 color_a : source_color = vec3(0.16, 0.32, 0.78);
uniform vec3 color_b : source_color = vec3(0.95, 0.76, 0.64);
// Side of one square, in model units.
uniform float square_size = 5.0;
// Shifts the pattern, in model units, to line a square up with an edge.
uniform vec3 offset = vec3(0.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;

varying vec3 object_pos;

void vertex() {
	object_pos = VERTEX;
}

// 0 or 1 for the two colours, box-filtered over the pixel's footprint (by Inigo Quilez).
float filtered_checker(vec2 p, vec2 ddx, vec2 ddy) {
	vec2 w = max(abs(ddx), abs(ddy)) + 0.0001;
	vec2 i = 2.0 * (abs(fract((p - 0.5 * w) * 0.5) - 0.5) - abs(fract((p + 0.5 * w) * 0.5) - 0.5)) / w;
	return 0.5 - 0.5 * i.x * i.y;
}

void fragment() {
	vec3 p = (object_pos + offset) / max(square_size, 0.0001);
	vec3 dx = dFdx(p);
	vec3 dy = dFdy(p);
	// The face's own normal, from the derivatives, so smooth shading can't switch axes mid-face.
	vec3 n = abs(normalize(cross(dFdx(object_pos), dFdy(object_pos))));

	float floor_checker = filtered_checker(p.xz, dx.xz, dy.xz);
	float side_x_checker = filtered_checker(p.zy, dx.zy, dy.zy);
	float side_z_checker = filtered_checker(p.xy, dx.xy, dy.xy);

	float checker = side_z_checker;
	if (n.y >= n.x && n.y >= n.z) {
		checker = floor_checker;
	} else if (n.x >= n.z) {
		checker = side_x_checker;
	}

	ALBEDO = mix(color_a, color_b, checker);
	ROUGHNESS = roughness;
}
