#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform writeonly image2D transmittance_lut;
layout(set = 0, binding = 1, rgba16f) uniform writeonly image2D multiscattering_lut;
layout(set = 0, binding = 2, rgba16f) uniform writeonly image2D skyview_lut;

layout(push_constant, std430) uniform Params {
    vec3 rayleigh_scattering;
    float planet_radius;
    vec3 mie_scattering;
    float atmosphere_radius;
    vec3 sun_direction;
    float sun_intensity;
} params;

void main() {
    ivec2 texels = ivec2(gl_GlobalInvocationID.xy);
    
    // Transmittance LUT size: 256x64
    if (texels.x < 256 && texels.y < 64) {
        // Simplified dummy values for compilation
        vec4 transmittance = vec4(exp(-params.rayleigh_scattering), 1.0);
        imageStore(transmittance_lut, texels, transmittance);
    }
    
    // Multi-scattering LUT size: 32x32
    if (texels.x < 32 && texels.y < 32) {
        vec4 ms = vec4(params.rayleigh_scattering * 0.5, 1.0);
        imageStore(multiscattering_lut, texels, ms);
    }
    
    // Sky-view LUT size: 200x100
    if (texels.x < 200 && texels.y < 100) {
        vec4 sky = vec4(params.rayleigh_scattering * params.sun_intensity * max(0.0, dot(vec3(0.0, 1.0, 0.0), params.sun_direction)), 1.0);
        imageStore(skyview_lut, texels, sky);
    }
}
