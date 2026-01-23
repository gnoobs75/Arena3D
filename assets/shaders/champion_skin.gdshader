shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Champion colors
uniform vec3 primary_color : source_color = vec3(0.5, 0.5, 0.5);
uniform vec3 secondary_color : source_color = vec3(0.6, 0.6, 0.6);
uniform vec3 team_color : source_color = vec3(0.2, 0.5, 0.8);
uniform float team_blend : hint_range(0.0, 1.0) = 0.2;

// Material properties
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float metallic : hint_range(0.0, 1.0) = 0.1;

// Effects
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float damage_flash : hint_range(0.0, 1.0) = 0.0;
uniform float heal_flash : hint_range(0.0, 1.0) = 0.0;

// Fresnel for edge glow
uniform float fresnel_power : hint_range(0.0, 5.0) = 2.0;
uniform float fresnel_intensity : hint_range(0.0, 1.0) = 0.3;

// Time for animated effects
uniform float time_offset = 0.0;

void fragment() {
	// Base color with team blend
	vec3 base = mix(primary_color, team_color, team_blend);

	// Fresnel effect for edge highlighting
	float fresnel = pow(1.0 - dot(NORMAL, VIEW), fresnel_power);
	vec3 fresnel_color = mix(base, secondary_color, fresnel * fresnel_intensity);

	// Apply damage flash (red)
	vec3 damaged = mix(fresnel_color, vec3(1.0, 0.2, 0.2), damage_flash);

	// Apply heal flash (green)
	vec3 healed = mix(damaged, vec3(0.2, 1.0, 0.3), heal_flash);

	ALBEDO = healed;
	ROUGHNESS = roughness;
	METALLIC = metallic;

	// Emission for glow effects
	vec3 emission = glow_color * glow_intensity;
	emission += fresnel_color * fresnel * glow_intensity * 0.5;
	EMISSION = emission;
}
