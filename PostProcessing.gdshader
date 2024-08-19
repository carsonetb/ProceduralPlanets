shader_type spatial;
render_mode unshaded;

uniform sampler2D depth_texture : source_color, hint_depth_texture, filter_nearest;
uniform sampler2D color_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D wave_normal_a;
uniform sampler2D wave_normal_b;
uniform float wave_speed;
uniform float wave_normal_scale;
uniform float wave_strength;
uniform vec3 ocean_center;
uniform float ocean_radius;
uniform float depth_multiplier;
uniform float alpha_multiplier;
uniform vec4 color_a : source_color;
uniform vec4 color_b : source_color;
uniform vec3 dir_to_sun;
uniform float smoothness;

uniform bool BEGIN_ATMOSPHERE;
uniform float atmosphere_radius;
uniform int num_inscattering_points;
uniform int num_optical_depth_points;
uniform float density_falloff;
uniform vec3 wave_lengths;
uniform float scattering_strength;

varying mat4 CAMERA;
varying vec3 view_vector;

vec2 ray_sphere(vec3 center, float radius, vec3 ray_origin, vec3 ray_dir) {
	vec3 offset = ray_origin - center;
	const float a = 1.0;
	float b = 2.0 * dot(offset, ray_dir);
	float c = dot(offset, offset) - radius * radius;
	
	float discriminant = b*b-4.0*a*c;
	if (discriminant > 0.0) {
		float s = sqrt(discriminant);
		float dstToSphereNear = max(0.0, (-b - s) / (2.0 * a));
        float dstToSphereFar = (-b + s) / (2.0 * a);

        if (dstToSphereFar >= 0.0) {
            return vec2(dstToSphereNear, dstToSphereFar - dstToSphereNear);
        }
	}
	
	return vec2(4000.0, 0.0);
}

vec3 UnpackNormal(vec4 packed_normal) {
	return packed_normal.xyz * 2.0 - 1.0;
}

vec3 blend_rnm(vec3 n1, vec3 n2) {
	n1.z += 1.0;
	n2.xy = -n2.xy;
	return n1 * dot(n1, n2) / n1.z - n2;
}

vec3 triplaner_normal(vec3 position, vec3 normal, float scale, vec2 offset, sampler2D sample_map) {
	vec3 tnormalX = UnpackNormal(texture(sample_map, position.zy * scale + offset));
	vec3 tnormalY = UnpackNormal(texture(sample_map, position.xz * scale + offset));
	vec3 tnormalZ = UnpackNormal(texture(sample_map, position.xy * scale + offset));
	
	// Swizzle surface normal or smth.
	tnormalX = blend_rnm(vec3(normal.zy, abs(normal).x), tnormalX);
	tnormalY = blend_rnm(vec3(normal.xz, abs(normal).y), tnormalY);
	tnormalZ = blend_rnm(vec3(normal.xy, abs(normal).z), tnormalZ);
	
	// Apply input normal sign to tangent space Z
	vec3 axis_sign = sign(normal);
	tnormalX.z *= axis_sign.x;
	tnormalY.z *= axis_sign.y;
	tnormalZ.z *= axis_sign.z;
	
	// Calculate blend weight
	vec3 weight = clamp(pow(normal, vec3(4.0)), 0.0, 1.0);
	weight /= dot(weight, vec3(1.0));
	
	// Swizzle tangent normals or smth.
	return normalize(tnormalX.zyx * weight.x + tnormalY.xzy * weight.y + tnormalZ.xyz * weight.z);
}

float density_at_point(vec3 density_sample_point) {
	float height_above_surface = length(density_sample_point - ocean_center) - ocean_radius;
	float height01 = height_above_surface / (atmosphere_radius - ocean_radius);
	float local_density = exp(-height01 * density_falloff) * (1.0 - height01);
	return local_density;
}

float optical_depth(vec3 ray_origin, vec3 ray_dir, float ray_length) {
	vec3 density_sample_point = ray_origin;
	float step_size = ray_length / float(num_optical_depth_points - 1);
	float optical_depth = 0.0;
	
	for (int i = 0; i < num_optical_depth_points; i++) {
		float local_density = density_at_point(density_sample_point);
		optical_depth += local_density * step_size;
		density_sample_point += ray_dir * step_size;
	}
	
	return optical_depth;
}

vec3 calculate_light(vec3 ray_origin, vec3 ray_dir, float ray_length, vec3 original_col, vec3 scattering_coefficients) {
	vec3 in_scatter_point = ray_origin;
	float step_size = ray_length / float(num_inscattering_points - 1);
	vec3 in_scattered_light = vec3(0.0);
	float view_ray_optical_depth = 0.0;
	
	for (int i = 0; i < num_inscattering_points; i++) {
		float sun_ray_length = ray_sphere(ocean_center, atmosphere_radius, in_scatter_point, dir_to_sun).y;
		float sun_ray_optical_depth = optical_depth(in_scatter_point, dir_to_sun, sun_ray_length);
		view_ray_optical_depth = optical_depth(in_scatter_point, -ray_dir, step_size * float(i));
		vec3 transmittance = exp(-(sun_ray_optical_depth + view_ray_optical_depth) * scattering_coefficients);
		float local_density = density_at_point(in_scatter_point);
		
		in_scattered_light += local_density * transmittance * scattering_coefficients * step_size;
		in_scatter_point += ray_dir * step_size;
	}
	float original_col_transmittence = exp(-view_ray_optical_depth);
	return original_col * original_col_transmittence + in_scattered_light;
}

void vertex() {
	POSITION = vec4(VERTEX, 1.0);
	view_vector = vec3(UV * 2.0 - 1.0, 0.0);
}

void fragment() {
	vec4 original_col = texture(color_texture, SCREEN_UV);
	
	float non_linear_depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, non_linear_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_depth = -view.z;
	
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 ray_pos = world.xyz / world.w;
	vec3 ray_dir;
	
	if (distance(ray_pos, CAMERA_POSITION_WORLD) > 1000.0) {
		ray_dir = normalize(ray_pos - CAMERA_POSITION_WORLD);
		ray_pos = CAMERA_POSITION_WORLD;
	}
	else {
		ray_dir = normalize(CAMERA_POSITION_WORLD - ray_pos);
	}
	vec2 hit_info = ray_sphere(ocean_center, ocean_radius, ray_pos, ray_dir);
	float dst_to_ocean = hit_info.x;
	float dst_through_ocean = hit_info.y;
	
	float ocean_view_depth = min(dst_through_ocean, linear_depth - dst_to_ocean);
	vec3 ray_ocean_intersect_pos = ray_pos + ray_dir * ocean_view_depth;
	
	if (distance(ray_pos, CAMERA_POSITION_WORLD) > 1000.0) {
		ray_ocean_intersect_pos = -ray_ocean_intersect_pos;
	}
	
	if (ocean_view_depth > 0.0) {
		float optical_depth_01 = 1.0 - exp(-ocean_view_depth * depth_multiplier) * 2.0;
		float alpha = 1.0 - exp(-ocean_view_depth * alpha_multiplier);
		vec3 ocean_normal = normalize(ray_pos + ray_dir * ocean_view_depth);
		
		// Waves n' stuff.
		vec2 wave_offset_a = vec2(TIME * wave_speed * 0.5, TIME * wave_speed * 0.4);
		vec2 wave_offset_b = vec2(TIME * wave_speed * -0.4, TIME * wave_speed * -0.15);
		vec3 wave_normal = triplaner_normal(ray_ocean_intersect_pos, ocean_normal, wave_normal_scale, wave_offset_a, wave_normal_a);
		wave_normal = triplaner_normal(ray_ocean_intersect_pos, wave_normal, wave_normal_scale, wave_offset_b, wave_normal_b);
		wave_normal = normalize(mix(ocean_normal, wave_normal, wave_strength));
		
		float specular_angle = acos(dot(normalize(normalize(dir_to_sun) + ray_dir), wave_normal));
		float specular_exponent = specular_angle / (1.0 - smoothness);
		float specular_highlight = clamp(exp(-specular_exponent * specular_exponent), 0.0, 999.0);
		float diffuse_lighting = clamp(dot(normalize(dir_to_sun), ocean_normal), 0.01, 1.0);
		vec4 ocean_col = mix(color_a, color_b, optical_depth_01);
		ocean_col *= diffuse_lighting;
		ocean_col += specular_highlight * 2.0;
		ALBEDO = ((original_col.xyz * (1.0 - alpha)) / 100.0 + ocean_col.xyz * alpha);
	}
	else {
		ALBEDO = original_col.xyz;
	}
	
	// Begin atmosphere section
	original_col = vec4(ALBEDO, 1.0);
	
	// We already have ray_pos and ray_dir
	
	float scatter_r = pow(400.0 / wave_lengths.x, 4.0) * scattering_strength;
	float scatter_g = pow(400.0 / wave_lengths.y, 4.0) * scattering_strength;
	float scatter_b = pow(400.0 / wave_lengths.z, 4.0) * scattering_strength;
	vec3 scattering_coefficients = vec3(scatter_r, scatter_g, scatter_b);
	
	vec2 atmosphere_hit_info = ray_sphere(ocean_center, atmosphere_radius, ray_pos, ray_dir);
	float dst_to_atmosphere = atmosphere_hit_info.x + (distance(ray_pos, CAMERA_POSITION_WORLD) == 0.0 ? 0.0 : dst_through_ocean);
	float dst_through_atmosphere = atmosphere_hit_info.y;
	
	if (dst_through_atmosphere > 0.0) {
		vec3 point_in_atmosphere = ray_pos + ray_dir * dst_to_atmosphere;
		vec3 brightness = calculate_light(point_in_atmosphere, ray_dir, dst_through_atmosphere, original_col.rgb, scattering_coefficients);
		ALBEDO = brightness;
	}
}

