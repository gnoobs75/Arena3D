shader_type spatial;
render_mode unshaded, cull_front;

// Outline properties
uniform vec3 outline_color : source_color = vec3(1.0, 0.85, 0.2);
uniform float outline_width : hint_range(0.0, 0.1) = 0.02;
uniform float pulse_speed : hint_range(0.0, 5.0) = 2.0;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.3;

void vertex() {
	// Expand vertices along normals for outline
	float pulse = sin(TIME * pulse_speed) * pulse_amount + 1.0;
	VERTEX += NORMAL * outline_width * pulse;
}

void fragment() {
	// Pulsing alpha for selection effect
	float alpha = 0.8 + sin(TIME * pulse_speed) * 0.2;
	ALBEDO = outline_color;
	ALPHA = alpha;
}
