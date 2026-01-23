shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// Highlight properties
uniform vec4 highlight_color : source_color = vec4(0.2, 0.7, 0.3, 0.4);
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.5;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.15;
uniform float border_width : hint_range(0.0, 0.2) = 0.08;
uniform vec3 border_color : source_color = vec3(0.3, 0.9, 0.4);

varying vec2 world_uv;

void vertex() {
	// Pass UV for border calculation
	world_uv = UV;
}

void fragment() {
	// Calculate distance from edge for border effect
	float edge_x = min(world_uv.x, 1.0 - world_uv.x);
	float edge_y = min(world_uv.y, 1.0 - world_uv.y);
	float edge_dist = min(edge_x, edge_y);

	// Border detection
	float border = step(edge_dist, border_width);

	// Pulsing alpha
	float pulse = sin(TIME * pulse_speed) * pulse_amount;
	float base_alpha = highlight_color.a + pulse;

	// Mix fill and border colors
	vec3 final_color = mix(highlight_color.rgb, border_color, border);
	float final_alpha = mix(base_alpha, base_alpha + 0.3, border);

	ALBEDO = final_color;
	ALPHA = clamp(final_alpha, 0.0, 1.0);
}
