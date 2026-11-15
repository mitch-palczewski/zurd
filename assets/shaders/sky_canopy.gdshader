shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// The canopy above the mega trees: a sheet of soft, faintly gold haze with an organic outline that
// slowly changes shape. SkyCanopy draws a few stacked shells with it (instance uniform layer) and
// bakes into each vertex's COLOR.r how much canopy belongs there (1 over the trees, 0 at the rim),
// so the canopy only exists over the trees and thins out raggedly at its edge.
// The shape is domain-warped fractal noise, with time as its third axis so the outline morphs
// instead of sliding; the whole pattern also drifts slowly with the wind. Its colour starts from
// the sky behind it (sky_match) and leans toward cloud_tint, so it always sits in the sky.
// Note: TIME rolls over every hour (Project Settings: rendering/limits/time), when the shape
// jumps once.

#include "res://assets/shaders/sky_match.gdshaderinc"
#include "res://assets/shaders/noise.gdshaderinc"

// Which shell this is, 0 the lowest. Set by SkyCanopy.
instance uniform float layer = 0.0;

group_uniforms shape;
// Metres across one big lump of canopy.
uniform float shape_size = 700.0;
// How much of the area over the trees is covered.
uniform float coverage : hint_range(0.0, 1.0) = 0.65;
// How soft the outline is.
uniform float edge_softness : hint_range(0.01, 0.5) = 0.15;
// How strongly the noise shapes the outline: higher gives a more ragged edge and more gaps,
// lower lets the outline follow the trees more smoothly.
uniform float shape_contrast : hint_range(0.5, 4.0) = 2.2;
// How much the noise bends itself: higher is more swirly and organic.
uniform float warp_strength : hint_range(0.0, 4.0) = 1.3;
// How fast the shape changes (noise units per second; 0.004 is a slow change over a minute or two).
uniform float morph_speed = 0.004;
// Wind: metres per second the pattern drifts.
uniform vec2 drift = vec2(1.0, 0.4);

group_uniforms look;
uniform vec4 cloud_tint : source_color = vec4(1.0, 0.9, 0.72, 1.0);
// How far the colour moves from the sky toward cloud_tint: low keeps the gold very subtle.
uniform float cloud_strength : hint_range(0.0, 1.0) = 0.5;
// Brightness of the cloud colour against the sky's brightest channel: above 1 is a sunlit haze.
uniform float cloud_brightness : hint_range(0.0, 3.0) = 1.4;
// How much brighter the thick middles are than the thin edges.
uniform float thickness_shade : hint_range(0.0, 1.0) = 0.15;
uniform float opacity : hint_range(0.0, 1.0) = 0.85;
// Each higher shell is this much more see-through than the one below.
uniform float layer_fade : hint_range(0.0, 0.5) = 0.15;

group_uniforms paint;
// Detail painted over the canopy, laid out flat across the world: mid-grey leaves the colour as
// it is, lighter brightens, darker darkens. An empty slot changes nothing. (Read as plain values,
// not as a colour, so that mid-grey really is the middle.)
uniform sampler2D canopy_texture : filter_linear_mipmap, repeat_enable, hint_default_transparent;
// Metres per repeat of the texture.
uniform float texture_scale = 600.0;
uniform float texture_strength : hint_range(0.0, 1.0) = 0.25;

varying vec3 world_pos;
varying float footprint;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	footprint = COLOR.r;
}

void fragment() {
	if (footprint <= 0.001) {
		discard;
	}
	vec2 flat_pos = world_pos.xz - drift * TIME;
	vec3 p = vec3(flat_pos / shape_size, TIME * morph_speed) + vec3(7.31, 3.17, 1.9) * layer;
	vec2 warp = vec2(fbm(p, 3), fbm(p + vec3(5.2, 1.3, 2.7), 3)) * 2.0 - 1.0;
	float n = (fbm(p + vec3(warp * warp_strength, 0.0), 4) - 0.5) * shape_contrast + 0.5;

	// Less canopy toward the rim: the noise itself decides where the edge falls.
	float threshold = 1.0 - coverage * footprint;
	float density = smoothstep(threshold - edge_softness, threshold + edge_softness, n);
	float thickness = clamp((n - threshold) / 0.25, 0.0, 1.0);

	vec3 sky = sky_color(world_pos - CAMERA_POSITION_WORLD);
	float brightness = max(sky.r, max(sky.g, sky.b));
	vec3 cloud = brightness * cloud_tint.rgb * cloud_brightness
			* mix(1.0 - thickness_shade, 1.0 + thickness_shade, thickness);
	vec3 color = mix(sky, cloud, cloud_strength);

	vec4 paint = texture(canopy_texture, flat_pos / texture_scale);
	color *= mix(vec3(1.0), paint.rgb * 2.0, texture_strength * paint.a);

	ALBEDO = color;
	ALPHA = clamp(density * opacity * (1.0 - layer * layer_fade), 0.0, 1.0);
}
