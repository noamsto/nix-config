#version 120

// Basic cursor trail shader for Ghostty
// Uses standard GLSL uniforms that should be available

uniform float time;
uniform vec2 resolution;
uniform vec2 cursor;
uniform vec2 prev_cursor;
uniform float cursor_time;

varying vec2 fragCoord;

void main() {
    vec2 uv = fragCoord / resolution;
    vec2 cursor_uv = cursor / resolution;
    vec2 prev_cursor_uv = prev_cursor / resolution;
    
    // Calculate time since cursor moved
    float t = clamp((time - cursor_time) / 0.3, 0.0, 1.0);
    
    // Create trail between current and previous cursor positions
    vec2 trail_vec = cursor_uv - prev_cursor_uv;
    float trail_length = length(trail_vec);
    
    if (trail_length > 0.001) {
        vec2 trail_dir = normalize(trail_vec);
        vec2 perp = vec2(-trail_dir.y, trail_dir.x);
        
        // Project current fragment onto the trail line
        vec2 to_frag = uv - prev_cursor_uv;
        float along_trail = dot(to_frag, trail_dir);
        float across_trail = abs(dot(to_frag, perp));
        
        // Check if we're within the trail bounds
        if (along_trail >= 0.0 && along_trail <= trail_length && across_trail < 0.01) {
            // Calculate fade based on position along trail and time
            float pos_fade = 1.0 - (along_trail / trail_length);
            float time_fade = 1.0 - t;
            float alpha = pos_fade * time_fade * 0.5;
            
            // Trail color (bright red/orange)
            vec3 trail_color = vec3(1.0, 0.5, 0.2);
            
            gl_FragColor = vec4(trail_color, alpha);
            return;
        }
    }
    
    // Default: transparent
    gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
}