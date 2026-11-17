shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Draws solid lines of a fixed width on screen along a model's edges (the reflecting pool's
// outline). The line maths is in edge_outline.gdshaderinc; the mesh comes from
// EdgeLines.build_outline_mesh.

#include "res://assets/shaders/edge_outline.gdshaderinc"

uniform vec4 outline_color : source_color = vec4(0.55, 0.18, 0.85, 1.0);
// Line width in pixels.
uniform float width = 3.0;
// Pulls the line toward the camera by this share of its distance, so the faces it lies on don't
// hide half of it.
uniform float depth_pull = 0.003;

void vertex() {
	float screen_length;
	POSITION = outline_corner(MODELVIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE, VERTEX, vec3(UV.x, UV.y, UV2.x), UV2.y, width, depth_pull, screen_length);
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
