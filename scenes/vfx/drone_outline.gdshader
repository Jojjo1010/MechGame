// Drone x-ray outline. Same shell trick as mech_outline.gdshader, but with
// depth test + depth draw disabled so the outline is always visible — including
// when the drone is behind trees, mechs, or other objects.
shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, depth_draw_disabled;

uniform vec4 outline_color : source_color = vec4(0.55, 0.95, 1.00, 0.95);
uniform float outline_size : hint_range(0.0, 0.3) = 0.06;

void vertex() {
	VERTEX += NORMAL * outline_size;
}

void fragment() {
	ALBEDO   = outline_color.rgb;
	EMISSION = outline_color.rgb * 2.5;
	ALPHA    = outline_color.a;
}
