shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Draws lines of a fixed width on screen along a model's edges. The mesh is built by
// ReflectingPool.build_outline_mesh: one quad per edge, each corner holding its own end of the
// edge (VERTEX), the other end (UV.x, UV.y, UV2.x) and which side of the line it sits on (UV2.y).

uniform vec4 outline_color : source_color = vec4(0.55, 0.18, 0.85, 1.0);
// Line width in pixels.
uniform float width = 3.0;
// Pulls the line toward the camera by this share of its distance, so the faces it lies on don't
// hide half of it.
uniform float depth_pull = 0.003;

void vertex() {
	vec3 view_a = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 view_b = (MODELVIEW_MATRIX * vec4(UV.x, UV.y, UV2.x, 1.0)).xyz;
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
	vec4 clip_dir_a = PROJECTION_MATRIX * vec4(dir_a, 1.0);
	vec4 clip_dir_b = PROJECTION_MATRIX * vec4(dir_b, 1.0);
	vec2 screen_a = clip_dir_a.xy / clip_dir_a.w * VIEWPORT_SIZE;
	vec2 screen_b = clip_dir_b.xy / clip_dir_b.w * VIEWPORT_SIZE;
	vec2 along = screen_b - screen_a;
	along = length(along) > 0.0001 ? normalize(along) : vec2(1.0, 0.0);
	vec2 across = vec2(-along.y, along.x);

	// Half the width to each side, and half the width past the end so corners close.
	vec2 offset_px = (across * UV2.y - along) * width * 0.5;
	vec4 clip = PROJECTION_MATRIX * vec4(view_a, 1.0);
	clip.xy += offset_px * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
