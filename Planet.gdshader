shader_type spatial;

uniform sampler2D noise_texture;
uniform float noise_scale;
uniform float noise_scale_2;

// Flat terrain:
uniform vec4 shore_low : source_color;
uniform vec4 shore_high : source_color;

uniform vec4 flat_low_a : source_color;
uniform vec4 flat_high_a : source_color;
uniform vec4 flat_low_b : source_color;
uniform vec4 flat_high_b : source_color;

uniform float flat_col_blend;
uniform float flat_col_blend_noise;
uniform float shore_height;
uniform float shore_blend;
uniform float max_flat_height;

// Steep terrain
uniform vec4 steep_low: source_color;
uniform vec4 steep_high : source_color;

// Flat to steep transition
uniform float steepness_threshold;
uniform float flat_to_steep_blend;
uniform float flat_to_steep_noise;
uniform float steepness_cutoff;

// Snowy poles
uniform float use_snowy_poles;
uniform vec4 snow_col : source_color;
uniform float snow_longitude;
uniform float snow_blend;
uniform float snow_specular;
uniform float snow_highlight;
uniform float snow_noise_a;
uniform float snow_noise_b;

// Height data
uniform vec2 height_min_max;
uniform float ocean_level;


void vertex() {
	// Called for every vertex the material is visible on.
}

// Remap a float value (with a known mininum and maximum) to a value between 0 and 1
float remap01(float v, float minOld, float maxOld) {
    return clamp((v-minOld) / (maxOld-minOld), 0.0, 1.0);
}

float Blend(float startHeight, float blendDst, float height) {
    return smoothstep(startHeight - blendDst / 2.0, startHeight + blendDst / 2.0, height);
}

vec4 triplanar(vec3 position, vec3 surface_normal, float normal_scale, sampler2D sample_map) {
	vec2 uv_x = position.zy * normal_scale;
	vec2 uv_y = position.xz * normal_scale;
	vec2 uv_z = position.xy * normal_scale;
	
	vec4 col_x = texture(sample_map, uv_x);
	vec4 col_y = texture(sample_map, uv_y);
	vec4 col_z = texture(sample_map, uv_z);
	
	vec3 blend_weight = surface_normal * surface_normal;
	blend_weight /= dot(blend_weight, vec3(1.0));
	
	return col_x * blend_weight.x + col_y * blend_weight.y + col_z * blend_weight.z;
}

void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	
	// Calculate steepness.
	vec3 sphere_normal = normalize(world_pos);
	float steepness = 1.0 - dot(world_normal, sphere_normal);
	steepness = clamp(steepness / 0.6, 0.0, 1.0);
	
	// Calculate terrain heights.
	float terrain_height = length(world_pos);
	float real_shore_height = mix(height_min_max.x, 1.0, ocean_level);
	float above_shore_height_01 = remap01(terrain_height, shore_height, height_min_max.y);
	float flat_height_01 = remap01(above_shore_height_01, 0.0, max_flat_height);
	
	// Sampler noise texture at two different scales.
	vec4 tex_noise = triplanar(world_pos, world_normal, noise_scale, noise_texture);
	vec4 tex_noise_2 = triplanar(world_pos, world_normal, noise_scale_2, noise_texture);
	
	// Flat terrain color A and B 
	float flat_col_blend_weight = Blend(0.0, flat_col_blend, (flat_height_01 - 0.5) + (tex_noise.b - 0.5) * flat_col_blend_noise);
	vec3 flat_terrain_col_a = mix(flat_low_a.rgb, flat_high_a.rgb, clamp(flat_col_blend_weight, 0.0, 1.0));
	vec3 flat_terrain_col = mix(flat_terrain_col_a, ((flat_low_a + flat_high_a) / 2.0).rgb, tex_noise.b);
	//vec3 flat_terrain_col_b = mix(flat_low_b, flat_high_b, flat_col_blend_weight).rgb;
	//flat_terrain_col_b = mix(flat_terrain_col_b, ((flat_low_b + flat_high_b) / 2.0).rgb, tex_noise.b);
	
	// Shore
	float shore_blend_weight = 1.0 - Blend(shore_height, shore_blend, flat_height_01);
	vec4 shore_col = mix(shore_low, shore_high, remap01(above_shore_height_01, 0.0, shore_height));
	shore_col = mix(shore_col, (shore_low + shore_height) / 2.0, tex_noise.g);
	flat_terrain_col = mix(flat_terrain_col, shore_col.rgb, shore_blend_weight);
	
	// Steep terrain color
	vec3 sphere_tangent = normalize(vec3(-sphere_normal.z, 0.0, sphere_normal.x));
	vec3 normal_tangent = normalize(world_normal - sphere_normal * dot(world_normal, sphere_normal));
	vec3 steep_terrain_col = mix(steep_low.rgb, steep_high.rgb, above_shore_height_01);
	
	// Flat to steep color transition
	float flat_blend_noise = (tex_noise_2.r - 0.5) * flat_to_steep_noise;
	float flat_strength = 1.0 - Blend(steepness_threshold + flat_blend_noise, flat_to_steep_blend, steepness);
	float flat_height_falloff = 1.0 - Blend(max_flat_height + flat_blend_noise, flat_to_steep_blend, above_shore_height_01);
	flat_strength *= flat_height_falloff;
	if (flat_height_01 < steepness_cutoff)
	{
		flat_strength = 1.0;
	}
	
	// Snowy poles
	vec3 snowCol = vec3(0.0);
	float snow_weight = 0.0;
	float snow_line_noise = snow_noise_a * 0.01 * (tex_noise.b - 0.5) * snow_noise_b * 0.01;
	snow_weight = Blend(snow_longitude, snow_blend, abs(world_pos.y)) * use_snowy_poles;
	float snow_speckle = 1.0 - tex_noise_2.g * 0.5;
	snowCol = (snow_col * mix(1.0, snow_highlight, above_shore_height_01) * snow_speckle).rgb;
	
	vec3 composite_col = mix(steep_terrain_col, flat_terrain_col, flat_strength);
	composite_col = mix(composite_col, snowCol, snow_weight);
	
	ALBEDO = vec3(composite_col);
}