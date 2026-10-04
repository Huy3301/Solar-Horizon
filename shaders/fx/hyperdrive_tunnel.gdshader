shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec3 tunnel_color : source_color = vec3(0.1, 0.5, 1.0);
uniform float speed = 2.0;

void fragment() {
    vec2 uv = UV;
    float time = TIME * speed;
    
    // Simple tunnel math
    float r = length(uv - 0.5);
    float angle = atan(uv.y - 0.5, uv.x - 0.5);
    
    float depth = 1.0 / r;
    float z = fract(depth + time);
    
    float mask = smoothstep(0.0, 0.1, z) * smoothstep(1.0, 0.9, z);
    
    ALBEDO = tunnel_color * mask;
    ALPHA = mask * smoothstep(0.5, 0.1, r);
}
