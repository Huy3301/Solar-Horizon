#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, r32f) uniform writeonly image2D height_map;

layout(push_constant, std430) uniform Params {
    vec2 patch_offset; // 0..1 range within the face
    float patch_scale; // size of the patch in 0..1 space
    int face_index;
    int res; // resolution
    int body_type; // 0 = Earth, 1 = Moon
} params;

// Exact same noise as CPU
vec3 hash33(vec3 p) {
    p = p * 0.1031;
    p -= floor(p);
    float dot_val = dot(p, vec3(p.z + 39.346, p.y + 39.346, p.x + 39.346));
    p += vec3(dot_val);
    vec3 res = vec3(p.x + p.y, p.x + p.z, p.y + p.z);
    return res - floor(res);
}

float get_noise_3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = p - i;
    vec3 u = f * f * (3.0 - 2.0 * f);
    
    float n000 = hash33(i).x;
    float n100 = hash33(i + vec3(1.0, 0.0, 0.0)).x;
    float n010 = hash33(i + vec3(0.0, 1.0, 0.0)).x;
    float n110 = hash33(i + vec3(1.0, 1.0, 0.0)).x;
    float n001 = hash33(i + vec3(0.0, 0.0, 1.0)).x;
    float n101 = hash33(i + vec3(1.0, 0.0, 1.0)).x;
    float n011 = hash33(i + vec3(0.0, 1.0, 1.0)).x;
    float n111 = hash33(i + vec3(1.0, 1.0, 1.0)).x;
    
    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    
    return mix(nxy0, nxy1, u.z) * 2.0 - 1.0;
}

float fbm(vec3 p, int octaves) {
    float value = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < octaves; i++) {
        value += amp * get_noise_3d(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return value;
}

float crater_noise_3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = p - i;
    float min_dist = 10.0;
    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec3 cell = vec3(float(x), float(y), float(z));
                vec3 h = hash33(i + cell);
                vec3 feature_pt = cell + h * 0.65;
                float d = length(f - feature_pt);
                min_dist = min(min_dist, d);
            }
        }
    }
    float rim = smoothstep(0.52, 0.38, min_dist) * smoothstep(0.22, 0.38, min_dist);
    float bowl = smoothstep(0.36, 0.0, min_dist);
    float peak = smoothstep(0.08, 0.0, min_dist) * 0.35;
    return rim * 1.5 - bowl * 0.85 + peak;
}

float sample_height(vec3 dir, int body) {
    if (body == 1) {
        float highlands = fbm(dir * 1.8, 3) * 0.25;
        float c_large = crater_noise_3d(dir * 4.8) * 0.38;
        float c_med = crater_noise_3d(dir * 13.5 + vec3(3.7, 8.2, 5.1)) * 0.22;
        float c_small = crater_noise_3d(dir * 30.0 + vec3(9.1, 14.5, 2.3)) * 0.10;
        return clamp(0.35 + highlands + c_large + c_med + c_small, 0.0, 1.0);
    }
    vec3 warp = vec3(
        fbm(dir + vec3(1.2, 3.4, 5.6), 4),
        fbm(dir + vec3(7.8, 9.0, 1.2), 4),
        fbm(dir + vec3(3.4, 5.6, 7.8), 4)
    );
    float noise_val = fbm(dir * 3.2 + warp, 6);
    float ridged = 1.0 - abs(noise_val);
    return pow(ridged, 2.2);
}

vec3 get_spherified_dir(int face, vec2 face_uv) {
    vec2 p = face_uv * 2.0 - 1.0;
    vec3 v;
    if (face == 0) v = vec3(1.0, -p.y, -p.x);
    else if (face == 1) v = vec3(-1.0, -p.y, p.x);
    else if (face == 2) v = vec3(p.x, 1.0, p.y);
    else if (face == 3) v = vec3(p.x, -1.0, -p.y);
    else if (face == 4) v = vec3(p.x, -p.y, 1.0);
    else if (face == 5) v = vec3(-p.x, -p.y, -1.0);
    else v = vec3(0.0);
    
    float x2 = v.x * v.x;
    float y2 = v.y * v.y;
    float z2 = v.z * v.z;
    return normalize(vec3(
        v.x * sqrt(max(0.0, 1.0 - y2/2.0 - z2/2.0 + y2*z2/3.0)),
        v.y * sqrt(max(0.0, 1.0 - x2/2.0 - z2/2.0 + x2*z2/3.0)),
        v.z * sqrt(max(0.0, 1.0 - x2/2.0 - y2/2.0 + x2*y2/3.0))
    ));
}

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= params.res || id.y >= params.res) return;
    
    vec2 local_uv = vec2(id) / float(params.res - 1);
    vec2 face_uv = params.patch_offset + local_uv * params.patch_scale;
    
    vec3 dir = get_spherified_dir(params.face_index, face_uv);
    float h = sample_height(dir, params.body_type);
    
    imageStore(height_map, id, vec4(h, 0.0, 0.0, 1.0));
}
