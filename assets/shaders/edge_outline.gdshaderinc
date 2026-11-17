// Lines a fixed number of pixels wide along a model's edges. The mesh comes from
// EdgeLines.build_outline_mesh: one quad per edge, each corner holding its own end of the edge
// (VERTEX), the other end (UV.x, UV.y, UV2.x) and which side of the line it sits on (UV2.y).
// A shader's vertex() calls outline_corner() for POSITION; shaders can't read built-ins inside
// functions, so they're passed in.

// The clip-space position of one corner. depth_pull pulls the line toward the camera by that share
// of its distance, so the faces it lies on don't hide half of it. screen_length gets the edge's
// length on screen, in pixels.
vec4 outline_corner(mat4 modelview, mat4 projection, vec2 viewport, vec3 own, vec3 other, float side, float width, float depth_pull, out float screen_length) {
	vec3 view_a = (modelview * vec4(own, 1.0)).xyz;
	vec3 view_b = (modelview * vec4(other, 1.0)).xyz;
	view_a *= 1.0 - depth_pull;
	view_b *= 1.0 - depth_pull;

	// The line's direction on screen, from the part of the edge in front of the camera.
	float front = -0.05;
	vec3 dir_a = view_a;
	vec3 dir_b = view_b;
	if (dir_a.z > front && dir_b.z < front) {
		dir_a = mix(dir_b, dir_a, (front - dir_b.z) / (dir_a.z - dir_b.z));
	} else if (dir_b.z > front && dir_a.z < front) {
		dir_b = mix(dir_a, dir_b, (front - dir_a.z) / (dir_b.z - dir_a.z));
	}
	vec4 clip_dir_a = projection * vec4(dir_a, 1.0);
	vec4 clip_dir_b = projection * vec4(dir_b, 1.0);
	vec2 screen_a = clip_dir_a.xy / clip_dir_a.w * viewport;
	vec2 screen_b = clip_dir_b.xy / clip_dir_b.w * viewport;
	vec2 along = screen_b - screen_a;
	// Screen positions here are doubled (-1..1 times the viewport), so halve for pixels.
	screen_length = length(along) * 0.5;
	along = length(along) > 0.0001 ? normalize(along) : vec2(1.0, 0.0);
	vec2 across = vec2(-along.y, along.x);

	// Half the width to each side, and half the width past the end so corners close.
	vec2 offset_px = (across * side - along) * width * 0.5;
	vec4 clip = projection * vec4(view_a, 1.0);
	clip.xy += offset_px * 2.0 / viewport * clip.w;
	return clip;
}
