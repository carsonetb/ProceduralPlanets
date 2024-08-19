#[compute]
#version 450

layout(local_size_x = 512, local_size_y = 1, local_size_z = 1) in;

layout(binding = 0) restrict buffer VerticesBuffer {
    float data[];
}
vertices_buffer;

layout(binding = 1) restrict buffer Parameters {
    float num_vertices;

    float ocean_floor_depth;
    float ocean_floor_smoothing;
    float ocean_depth_multiplier;
    float mountain_blend;

    float continent_noise_num_layers;
    float continent_noise_scale;
    float continent_noise_persistence;
    float continent_noise_lacunarity;
    float continent_noise_multiplier;
    
    float mountain_noise_offset_x;
    float mountain_noise_offset_y;
    float mountain_noise_offset_z;
    float mountain_noise_num_layers;
    float mountain_noise_persistence;
    float mountain_noise_lacunarity;
    float mountain_noise_scale;
    float mountain_noise_multiplier;
    float mountain_noise_gain;
    float mountain_noise_power;
    float mountain_noise_vertical_shift;

    float mask_noise_num_layers;
    float mask_noise_scale;
    float mask_noise_persistence;
    float mask_noise_lacunarity;
    float mask_noise_multiplier;
    float mask_vertical_shift;
} 
parameters;

layout(binding = 2) restrict buffer HeightsBuffer {
    float data[];
}
heights_buffer;

float smooth_min(float a, float b, float k) {
    k = max(0, k);
    float h = max(0, min(1, (b - a + k) / (2 * k)));
    return a * h + b * (1 - h) - k * h * (1 - h);
}

float smooth_max(float a, float b, float k) {
	 k = min(0, -k);
	 float h = max(0, min(1, (b - a + k) / (2 * k)));
	 return a * h + b * (1 - h) - k * h * (1 - h);
}

vec4 permute(vec4 x){return mod(((x*34.0)+1.0)*x, 289.0);}
vec4 taylorInvSqrt(vec4 r){return 1.79284291400159 - 0.85373472095314 * r;}

float snoise(vec3 v){ 
  const vec2  C = vec2(1.0/6.0, 1.0/3.0) ;
  const vec4  D = vec4(0.0, 0.5, 1.0, 2.0);

  // First corner
  vec3 i  = floor(v + dot(v, C.yyy) );
  vec3 x0 =   v - i + dot(i, C.xxx) ;

  // Other corners
  vec3 g = step(x0.yzx, x0.xyz);
  vec3 l = 1.0 - g;
  vec3 i1 = min( g.xyz, l.zxy );
  vec3 i2 = max( g.xyz, l.zxy );

  //  x0 = x0 - 0. + 0.0 * C 
  vec3 x1 = x0 - i1 + 1.0 * C.xxx;
  vec3 x2 = x0 - i2 + 2.0 * C.xxx;
  vec3 x3 = x0 - 1. + 3.0 * C.xxx;

  // Permutations
  i = mod(i, 289.0 ); 
  vec4 p = permute( permute( permute( 
             i.z + vec4(0.0, i1.z, i2.z, 1.0 ))
           + i.y + vec4(0.0, i1.y, i2.y, 1.0 )) 
           + i.x + vec4(0.0, i1.x, i2.x, 1.0 ));

  // Gradients
  // ( N*N points uniformly over a square, mapped onto an octahedron.)
  float n_ = 1.0/7.0; // N=7
  vec3  ns = n_ * D.wyz - D.xzx;

  vec4 j = p - 49.0 * floor(p * ns.z *ns.z);  //  mod(p,N*N)

  vec4 x_ = floor(j * ns.z);
  vec4 y_ = floor(j - 7.0 * x_ );    // mod(j,N)

  vec4 x = x_ *ns.x + ns.yyyy;
  vec4 y = y_ *ns.x + ns.yyyy;
  vec4 h = 1.0 - abs(x) - abs(y);

  vec4 b0 = vec4( x.xy, y.xy );
  vec4 b1 = vec4( x.zw, y.zw );

  vec4 s0 = floor(b0)*2.0 + 1.0;
  vec4 s1 = floor(b1)*2.0 + 1.0;
  vec4 sh = -step(h, vec4(0.0));

  vec4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ;
  vec4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;

  vec3 p0 = vec3(a0.xy,h.x);
  vec3 p1 = vec3(a0.zw,h.y);
  vec3 p2 = vec3(a1.xy,h.z);
  vec3 p3 = vec3(a1.zw,h.w);

  //Normalise gradients
  vec4 norm = taylorInvSqrt(vec4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
  p0 *= norm.x;
  p1 *= norm.y;
  p2 *= norm.z;
  p3 *= norm.w;

  // Mix final noise value
  vec4 m = max(0.6 - vec4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
  m = m * m;
  return 42.0 * dot( m*m, vec4( dot(p0,x0), dot(p1,x1), 
                                dot(p2,x2), dot(p3,x3) ) );
}

float fractalNoise(vec3 point, float num_layers, float scale, float persistence, float lacunarity, float multiplier) {
    float noise = 0.0;
    float amplitude = 1.0;
    float frequency = scale;

    for (int i = 0; i < num_layers; i++) {
        noise += snoise(point * frequency) * amplitude;
        amplitude *= persistence;
        frequency *= lacunarity;
    }
    return noise * multiplier;
}

float fractalNoise(vec3 point, float num_layers, float scale, float persistence, float lacunarity, float multiplier, float vertical_shift) {
    return fractalNoise(point, num_layers, scale, persistence, lacunarity, multiplier) + vertical_shift;
}

float ridge_noise(vec3 pos, vec3 offset, float num_layers, float persistence, float lacunarity, float scale, float multiplier, float gain, float power, float vertical_shift) {
    float noise_sum = 0.0;
    float amplitude = 1.0;
    float frequency = scale;
    float ridge_weight = 1.0;
    
    for (int i = 0; i < num_layers; i++) 
    {
        float noise_val = 1.0 - abs(snoise(pos * frequency + offset));
        noise_val = pow(abs(noise_val), power);
        noise_val *= ridge_weight;
        ridge_weight = clamp(noise_val * gain, 0.0, 1.0);
        
        noise_sum += noise_val * amplitude;
        amplitude *= persistence;
        frequency *= lacunarity;
    }
    return noise_sum * multiplier + vertical_shift;
}

float Blend(float start_height, float blend_dst, float height) {
    return smoothstep(start_height - blend_dst / 2.0, start_height + blend_dst / 2.0, height);
}

// The code we want to execute in each invocation
void main() {
    // gl_GlobalInvocationID.x uniquely identifies this invocation across all work groups
    uint id = gl_GlobalInvocationID.x;

    if (id > parameters.num_vertices) { return; }

    vec3 vertexPos = vec3(vertices_buffer.data[3 * id], vertices_buffer.data[3 * id + 1], vertices_buffer.data[3 * id + 2]);

    // Noise for landmasses
    float continent_shape = fractalNoise(vertexPos, parameters.continent_noise_num_layers, parameters.continent_noise_scale, parameters.continent_noise_persistence, parameters.continent_noise_lacunarity, parameters.continent_noise_multiplier);

    // Flatten ocean bed and deepen oceans
    float ocean_floor_shape = -parameters.ocean_floor_depth + continent_shape * 0.15;
    continent_shape = smooth_max(continent_shape, ocean_floor_shape, parameters.ocean_floor_smoothing);
    continent_shape *= (continent_shape < 0.0) ? 1.0 + parameters.ocean_depth_multiplier : 1.0;

    // Create mountains
    float mountain_mask = Blend(0.0, parameters.mountain_blend, fractalNoise(vertexPos, parameters.mask_noise_num_layers, parameters.mask_noise_scale, parameters.mask_noise_persistence, parameters.mask_noise_lacunarity, parameters.mask_noise_multiplier, parameters.mask_vertical_shift));
    vec3 mountain_offset = vec3(parameters.mountain_noise_offset_x, parameters.mountain_noise_offset_y, parameters.mountain_noise_offset_z);
    float mountain_shape = ridge_noise(vertexPos, mountain_offset, parameters.mountain_noise_num_layers, parameters.mountain_noise_persistence, parameters.mountain_noise_lacunarity, parameters.mountain_noise_scale, parameters.mountain_noise_multiplier, parameters.mountain_noise_gain, parameters.mountain_noise_power, parameters.mountain_noise_vertical_shift) * mountain_mask;

    // Calculate final height 
    float final_height = 1.0 + (continent_shape + mountain_shape) * 0.01;
    heights_buffer.data[id] = final_height;
}