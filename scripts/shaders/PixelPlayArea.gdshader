shader_type canvas_item;

// Controls the overall strength of the glitch effect
uniform float strength : hint_range(0.0, 1.0) = 0.1;
// How much the color channels separate (chromatic aberration)
uniform float aberration_amount : hint_range(0.0, 1.0) = 0.05;

// A simple pseudo-random number generator
float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
    // Start with the original texture color
    vec4 original_color = texture(TEXTURE, UV);
    
    // Create a random value based on time and vertical position
    float random_val = rand(vec2(TIME, UV.y));
    
    // --- Block Shifting Effect ---
    // Check if our random value is less than the glitch strength
    if (random_val < strength) {
        // If it is, shift the UV coordinates horizontally
        vec2 shifted_uv = UV;
        // The shift amount is also random
        shifted_uv.x += (rand(vec2(TIME * 2.0, UV.y)) - 0.5) * 0.2;
        
        // Get the color from the new, shifted position
        original_color = texture(TEXTURE, shifted_uv);
    }
    
    // --- Chromatic Aberration Effect ---
    // Create offsets for the Red and Blue channels
    vec2 r_offset = vec2(aberration_amount * (rand(vec2(TIME * 0.3, UV.y)) - 0.5), 0.0);
    vec2 b_offset = vec2(aberration_amount * (rand(vec2(TIME * 0.5, UV.y)) - 0.5), 0.0);
    
    // Sample the texture at the offset positions for each color channel
    float r = texture(TEXTURE, UV + r_offset).r;
    float g = original_color.g; // Use the (possibly) shifted green channel
    float b = texture(TEXTURE, UV + b_offset).b;
    
    // Combine the shifted channels into the final color
    COLOR = vec4(r, g, b, original_color.a);
}