shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.3, 0.9, 1.0, 1.0);
uniform float outline_size : hint_range(0.0, 0.3) = 0.07;

void vertex() {
	VERTEX += NORMAL * outline_size;
}

void fragment() {
	ALBEDO   = outline_color.rgb;
	EMISSION = outline_color.rgb * 2.0;
}
