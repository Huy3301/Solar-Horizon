#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) readonly buffer Heightmap {
    float data[];
} heightmap;

layout(set = 0, binding = 1, std430) writeonly buffer AOData {
    float data[];
} ao_data;

layout(push_constant, std430) uniform Params {
    int width;
    int height;
    float height_scale;
    float ao_radius;
} params;

void main() {
    ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
    if (pos.x >= params.width || pos.y >= params.height) return;
    
    int index = pos.y * params.width + pos.x;
    float h = heightmap.data[index];
    
    // Horizon AO calculation for mobile (baked in compute)
    float ao = 1.0;
    int radius = int(params.ao_radius);
    int sample_count = 0;
    float occlusion = 0.0;
    
    // Simple screen-space style ray marching in heightmap
    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            if (x == 0 && y == 0) continue;
            
            ivec2 sample_pos = pos + ivec2(x, y);
            if (sample_pos.x >= 0 && sample_pos.x < params.width && 
                sample_pos.y >= 0 && sample_pos.y < params.height) {
                
                int sample_index = sample_pos.y * params.width + sample_pos.x;
                float sample_h = heightmap.data[sample_index];
                
                float dist = length(vec2(x, y));
                float slope = (sample_h - h) / dist;
                
                if (slope > 0.0) {
                    occlusion += min(slope * params.height_scale, 1.0);
                }
                sample_count++;
            }
        }
    }
    
    if (sample_count > 0) {
        ao = 1.0 - clamp(occlusion / float(sample_count), 0.0, 1.0);
    }
    
    ao_data.data[index] = ao;
}
