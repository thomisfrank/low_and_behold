shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform float pixel_size : hint_range(1.0, 16.0) = 2.0;
uniform float scanline_darkness : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_spacing : hint_range(1.0, 10.0) = 3.0;

uniform float curvature_amount : hint_range(0.0, 1.0) = 0.1;
uniform float aberration_amount : hint_range(0.0, 0.05) = 0.01;
uniform float noise_amount : hint_range(0.0, 0.2) = 0.04;

uniform float overlay_strength : hint_range(0.0, 1.0) = 0.5;

float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
    vec2 centered_uv = UV - vec2(0.5);
    float len = length(centered_uv);
    vec2 warped_uv = UV + centered_uv * pow(len, 2.0) * curvature_amount;

    // Clamp warped UV to avoid out-of-bounds sampling
    warped_uv = clamp(warped_uv, vec2(0.0), vec2(1.0));

    vec2 grid_uv = floor(warped_uv * TEXTURE_PIXEL_SIZE / pixel_size)
                 * pixel_size / TEXTURE_PIXEL_SIZE;

    vec2 offset = centered_uv * aberration_amount;
    float r = texture(TEXTURE, grid_uv - offset).r;
    float g = texture(TEXTURE, grid_uv).g;
    float b = texture(TEXTURE, grid_uv + offset).b;
    float a = texture(TEXTURE, grid_uv).a;

    vec4 effect_color = vec4(r, g, b, a);
    vec4 scene_color = texture(TEXTURE, warped_uv);

    if (mod(FRAGCOORD.y, scanline_spacing) < 1.0) {
        effect_color.rgb *= (1.0 - scanline_darkness);
    }

    float noise = (rand(UV + TIME) - 0.5) * noise_amount;
    effect_color.rgb += vec3(noise);

    vec4 blended = mix(scene_color, effect_color, overlay_strength);
    blended.a = 1.0; // Force full alpha to ensure visibility
    COLOR = blended;
}
