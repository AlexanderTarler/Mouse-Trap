shader_type canvas_item;

// --- EXPOSED INSPECTOR PARAMETERS ---
uniform float warp_amount : hint_range(0.0, 1.0) = 0.18;
uniform float vignette_strength : hint_range(0.0, 2.0) = 0.55;
uniform int scanline_count : hint_range(60, 480) = 240;
uniform float scanline_opacity : hint_range(0.0, 1.0) = 0.25;
uniform float flicker_intensity : hint_range(0.0, 0.2) = 0.03;
uniform float aberration_amount : hint_range(0.0, 0.02) = 0.004;

// Helper function to handle CRT glass barrel distortion
vec2 barrel_distort(vec2 uv) {
    vec2 transformed_uv = uv - 0.5;
    float r2 = dot(transformed_uv, transformed_uv);
    transformed_uv *= 1.0 + (warp_amount * r2);
    return transformed_uv + 0.5;
}

void fragment() {
    // 1. Apply screen curvature warping
    vec2 distorted_uv = barrel_distort(UV);
    
    // 2. Out-of-bounds clip check
    if (distorted_uv.x < 0.0 || distorted_uv.x > 1.0 || distorted_uv.y < 0.0 || distorted_uv.y > 1.0) {
        // Pixel is off the edge of the curved glass tube — render absolute black padding
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } 
    else {
        // Pixel is on the screen surface — execute all 90s visual passes safely
        vec4 tex_color = vec4(1.0);
        
        // 3. Chromatic Aberration channel splitting
        tex_color.r = texture(TEXTURE, distorted_uv + vec2(aberration_amount, 0.0)).r;
        tex_color.g = texture(TEXTURE, distorted_uv).g;
        tex_color.b = texture(TEXTURE, distorted_uv - vec2(aberration_amount, 0.0)).b;
        tex_color.a = texture(TEXTURE, distorted_uv).a;
        
        // 4. Horizontal Retro Scanline Simulation
        float scanline = sin(distorted_uv.y * float(scanline_count) * PI * 2.0);
        scanline = (scanline + 1.0) * 0.5; // Remap from [-1, 1] to [0, 1]
        tex_color.rgb -= scanline * scanline_opacity;
        
        // 5. Analog Voltage Flicker (Generator noise)
        float flicker = sin(TIME * 120.0) * cos(TIME * 40.0);
        tex_color.rgb += flicker * flicker_intensity;
        
        // 6. Vignette Corner Darkening
        vec2 vignette_uv = distorted_uv * (1.0 - distorted_uv.yx);
        float vig = vignette_uv.x * vignette_uv.y * 15.0;
        vig = pow(vig, vignette_strength);
        tex_color.rgb *= clamp(vig, 0.0, 1.0);
        
        COLOR = tex_color;
    }
}