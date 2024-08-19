#[compute]
#version 450

layout(local_size_x = 512, local_size_y = 1, local_size_z = 1) in;

layout(binding = 0) restrict buffer VerticesBuffer {
    float data[];
}
vertices_buffer;

layout(binding = 1) restrict buffer Parameters {
    float test_val;
    float num_vertices;
    float num_craters;
    float floor_height;
    float rim_steepness;
    float rim_width;
    float smooth_factor;

    float shape_noise_num_layers;
    float shape_noise_scale;
    float shape_noise_persistence;
    float shape_noise_lacunarity;
    float shape_noise_multiplier;

    float detail_noise_num_layers;
    float detail_noise_scale;
    float detail_noise_persistence;
    float detail_noise_lacunarity;
    float detail_noise_multiplier;

    float ridge_noise_offset_x;
    float ridge_noise_offset_y;
    float ridge_noise_offset_z;
    float ridge_noise_num_layers;
    float ridge_noise_persistence;
    float ridge_noise_lacunarity;
    float ridge_noise_scale;
    float ridge_noise_multiplier;
    float ridge_noise_gain;
    float ridge_noise_power;
    float ridge_noise_vertical_shift;
} 
parameters;

layout(binding = 2) restrict buffer HeightsBuffer {
    float data[];
}
heights_buffer;

layout(binding = 3) restrict buffer CraterCentersBuffer {
    float centers[];
}
crater_centers;

layout(binding = 4) restrict buffer CraterRadiusBuffer {
    float radius[];
}
crater_radius;

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


// The code we want to execute in each invocation
void main() {
    // gl_GlobalInvocationID.x uniquely identifies this invocation across all work groups
    uint id = gl_GlobalInvocationID.x;

    if (id > parameters.num_vertices) { return; }
    const float elevation_multiplier = 0.01;

    vec3 vertexPos = vec3(vertices_buffer.data[3 * id], vertices_buffer.data[3 * id + 1], vertices_buffer.data[3 * id + 2]);
    float crater_height = 0.0;

    for (int i = 0; i < min(parameters.num_craters, 10000); i++) {
        vec3 crater_center = vec3(crater_centers.centers[i * 3], crater_centers.centers[i * 3 + 1], crater_centers.centers[i * 3 + 2]);
        float x = length(vertexPos - crater_center) / crater_radius.radius[i];

        float cavity = x * x - 1.0;
        float rimX = min(x - 1.0 - parameters.rim_width, 0.0);
        float rim = parameters.rim_steepness * rimX * rimX;

        float crater_shape = smooth_max(cavity, parameters.floor_height, parameters.smooth_factor);
        crater_shape = smooth_min(crater_shape, rim, parameters.smooth_factor);
        crater_height += crater_shape * crater_radius.radius[i];
    }

    float shape_noise = fractalNoise(vertexPos, parameters.shape_noise_num_layers, parameters.shape_noise_scale, parameters.shape_noise_persistence, parameters.shape_noise_lacunarity, parameters.shape_noise_multiplier);
    float detail_noise = fractalNoise(vertexPos, parameters.detail_noise_num_layers, parameters.detail_noise_scale, parameters.detail_noise_persistence, parameters.detail_noise_lacunarity, parameters.detail_noise_multiplier);
    float ridged_noise = ridge_noise(vertexPos, vec3(parameters.ridge_noise_offset_x, parameters.ridge_noise_offset_y, parameters.ridge_noise_offset_z), parameters.ridge_noise_num_layers, parameters.ridge_noise_persistence, parameters.ridge_noise_lacunarity, parameters.ridge_noise_scale, parameters.ridge_noise_multiplier, parameters.ridge_noise_gain, parameters.ridge_noise_power, parameters.ridge_noise_vertical_shift);
    float noise_sum = (shape_noise + detail_noise + ridged_noise) * elevation_multiplier;
    float final_height = 1 + crater_height + noise_sum;
    heights_buffer.data[id] = final_height;
}