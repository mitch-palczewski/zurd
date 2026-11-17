shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Subtle lines along a cloud object's ridges (Cloud-Formation Design Doc §4.2), so its shape reads
// from far away: thin, a darker cool tint of the cloud, partly see-through, and fading out on
// edges that are only a few pixels long on screen, so a far-off cloud doesn't turn into a
// scribble. CloudSky hangs them under each object's mesh. The line maths is in
// edge_outline.gdshaderinc. cloud_ridges.tres draws after the clouds' objects and puffs
// (render_priority 2), so the lines lie on top of them; the objects' depth hides ridges behind.

#include "res://assets/shaders/edge_outline.gdshaderinc"

// Colour, and in alpha how strongly the line shows.
uniform vec4 ridge_color : source_color = vec4(0.42, 0.47, 0.6, 0.35);
// Line width in pixels.
uniform float width = 1.5;
uniform float depth_pull = 0.003;
// Edges shorter than this on screen (pixels) fade out, fully gone at half of it.
uniform float fade_below = 12.0;

varying float v_fade;

void vertex() {
	float screen_length;
	POSITION = outline_corner(MODELVIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE, VERTEX, vec3(UV.x, UV.y, UV2.x), UV2.y, width, depth_pull, screen_length);
	v_fade = smoothstep(fade_below * 0.5, fade_below, screen_length);
}

void fragment() {
	ALBEDO = ridge_color.rgb;
	ALPHA = ridge_color.a * v_fade;
}
