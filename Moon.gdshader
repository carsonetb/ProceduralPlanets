shader_type spatial;

uniform sampler2D main_tex;
uniform sampler2D normal_map;
uniform sampler2D steep_normal_map;
uniform float normal_scale_a;
uniform float normal_scale_b;
uniform float main_tex_scale;
uniform float normal_blend_sharpness;
uniform float light_brightness;
uniform float normal_map_strength;
uniform vec2 height_min_max;
uniform vec3 world_space_light_pos;
uniform vec3 light_color : source_color;
uniform vec3 primary_color : source_color;
uniform vec3 secondary_color : source_color;
uniform float metalic_a;
uniform float metalic_b;
uniform float roughness_a;
uniform float roughness_b;
uniform vec4 random_biome_values;

varying vec3 vertex_position;
varying vec4 terrain_data;

vec3 UnpackNormal(vec4 packed_normal) {
	return packed_normal.xyz * 2.0 - 1.0;
}

float remap01(float v, float minOld, float maxOld) {
	return clamp((v-minOld) / (maxOld-minOld), 0.0, 1.0);
}

vec2 remap01vec2(vec2 v, vec2 minOld, vec2 maxOld) {
	return clamp((v-minOld) / (maxOld-minOld), vec2(0.0), vec2(1.0));
}

float Blend(float start_height, float blend_dst, float height) {
	return smoothstep(start_height - blend_dst / 2.0, start_height + blend_dst / 2.0, height);
}

vec3 triplaner_normal(vec3 position, vec3 surface_normal, sampler2D sample_map, float normal_scale) {
	vec3 tnormalX = UnpackNormal(texture(sample_map, position.zy * normal_scale));
	vec3 tnormalY = UnpackNormal(texture(sample_map, position.xz * normal_scale));
	vec3 tnormalZ = UnpackNormal(texture(sample_map, position.xy * normal_scale));
	
	// Swizzle surface normal or smth.
	tnormalX = vec3(tnormalX.xy + surface_normal.zy, tnormalX.z * surface_normal.x);
	tnormalY = vec3(tnormalY.xy + surface_normal.xz, tnormalX.z * surface_normal.y);
	tnormalZ = vec3(tnormalZ.xy + surface_normal.xy, tnormalX.z * surface_normal.z);
	
	// Calculate blend weight
	vec3 weight = pow(abs(surface_normal), vec3(normal_blend_sharpness));
	weight /= dot(weight, vec3(1.0));
	
	
	// Swizzle tangent normals or smth.
	return normalize(tnormalX.zyx * weight.x + tnormalY.xzy * weight.y + tnormalZ.xyz * weight.z);
}

vec4 triplanar(vec3 position, vec3 surface_normal, sampler2D sample_map, float normal_scale) {
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
	vec4 world_pos = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	
	float height01 = remap01(length(world_pos.xyz), height_min_max.x, height_min_max.y);
	
	float steepness = 1.0 - dot(world_normal, normalize(world_pos.xyz));
	steepness = remap01(steepness, 0.0, 0.3);
	
	vec3 col_x = texture(main_tex, world_pos.zy).rgb;
	vec3 col_y = texture(main_tex, world_pos.xz).rgb;
	vec3 col_z = texture(main_tex, world_pos.xy).rgb;
	vec3 abs_world_normal = abs(world_normal);
	vec3 normal_weights = abs_world_normal / (abs_world_normal.x + abs_world_normal.y + abs_world_normal.z);
	vec3 col = col_x * normal_weights.x + col_y * normal_weights.y + col_z * normal_weights.z;
	
	vec4 texture_noise = triplanar(world_pos.xyz, world_normal, main_tex, main_tex_scale);
	
	vec3 lighting_normal_flat = triplaner_normal(world_pos.xyz, world_normal, normal_map, normal_scale_a);
	vec3 lighting_normal_steep = triplaner_normal(world_pos.xyz, world_normal, steep_normal_map, normal_scale_b);
	vec3 flat_and_steep_normal = mix(lighting_normal_flat, lighting_normal_steep, vec3(0.5));
	vec3 lighting_normal = mix(flat_and_steep_normal, lighting_normal_steep, vec3(steepness));
	
	// Blend between primary and secondary colors by height (plus some noise).
	float height_noise = -steepness * random_biome_values.x;
	float height_blend_weight = Blend(0.5, 0.6, height01 + height_noise);
	vec3 col_biome = mix(primary_color, secondary_color, height_blend_weight);
	
	vec3 to_light = normalize(world_space_light_pos - world_pos.xyz);
	float light_shading = clamp(dot(lighting_normal, world_space_light_pos), 0.0, 1.0);
	
	ALBEDO = col_biome * light_shading * light_brightness * light_color;
	METALLIC = mix(metalic_a, metalic_b, height_blend_weight);
	ROUGHNESS = mix(roughness_a, roughness_b, height_blend_weight);
}

void light() {}