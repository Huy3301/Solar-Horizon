#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

// Output transform array for MultiMesh
struct InstanceData {
    vec4 row0;
    vec4 row1;
    vec4 row2;
};

layout(set = 0, binding = 0, std430) readonly buffer Heightmap {
    float data[];
} heightmap;

layout(set = 0, binding = 1, std430) writeonly buffer Instances {
    InstanceData data[];
} instances;

layout(set = 0, binding = 2, std430) buffer Counter {
    uint count;
} counter;

layout(push_constant, std430) uniform Params {
    int max_instances;
    int grid_size;
    float scale_min;
    float scale_max;
    float height_threshold;
    float density;
    float cell_size;
} params;

float hash(uint n) {
    n = (n << 13U) ^ n;
    n = n * (n * n * 15731U + 789221U) + 1376312589U;
    return float(n & 0x7fffffffU) / float(0x7fffffff);
}

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= params.max_instances) return;
    
    // Pseudo-random position within the patch
    float r1 = hash(id);
    float r2 = hash(id + 1000000);
    
    // Check density probability
    if (hash(id + 4000000) > params.density) return;
    
    float x = r1 * float(params.grid_size - 1);
    float z = r2 * float(params.grid_size - 1);
    
    int ix = clamp(int(x), 0, params.grid_size - 1);
    int iz = clamp(int(z), 0, params.grid_size - 1);
    int h_index = iz * params.grid_size + ix;
    
    float h = heightmap.data[h_index];
    
    // Biome/Height rule: e.g. above threshold
    if (h > params.height_threshold) {
        uint idx = atomicAdd(counter.count, 1);
        if (idx < params.max_instances) {
            float s = mix(params.scale_min, params.scale_max, hash(id + 2000000));
            float angle = hash(id + 3000000) * 6.2831853;
            
            float c = cos(angle);
            float s_rot = sin(angle);
            
            float world_x = x * params.cell_size;
            float world_z = z * params.cell_size;
            
            // Format for MultiMesh 3D Transform (12 floats)
            instances.data[idx].row0 = vec4(s * c, 0.0, s * -s_rot, world_x);
            instances.data[idx].row1 = vec4(0.0, s, 0.0, h);
            instances.data[idx].row2 = vec4(s * s_rot, 0.0, s * c, world_z);
        }
    }
}
