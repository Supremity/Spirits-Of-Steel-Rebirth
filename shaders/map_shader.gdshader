shader_type canvas_item;

// --- TEXTURES ---
uniform sampler2D region_id_map : filter_nearest;
uniform sampler2D state_colors : filter_nearest;
uniform sampler2D original_texture : filter_nearest; 
uniform vec2 tex_size;

// --- BORDER SETTINGS ---
uniform vec4 country_border_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float internal_border_darkness : hint_range(0.0, 1.0) = 0.2;
uniform float border_scan_distance : hint_range(1.0, 5.0) = 2.0;

// --- COUNTRY BORDER GLOW SETTINGS ---
uniform float country_glow_radius : hint_range(1.0, 15.0) = 8.0;
uniform float country_glow_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float country_glow_falloff : hint_range(0.1, 5.0) = 1.8;

const vec2 DIRS[8] = vec2[8](
    vec2(0.0, -1.0), vec2(0.0, 1.0), vec2(-1.0, 0.0), vec2(1.0, 0.0),
    vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(-1.0, 1.0), vec2(1.0, 1.0)
);

// --- HELPER FUNCTIONS ---

int get_id(vec2 uv) {
    vec4 c = texture(region_id_map, uv);
    int r = int(round(c.r * 255.0));
    int g = int(round(c.g * 255.0));
    return r + g * 256;
}

vec4 get_country_color(int id) {
    if (id <= 1) return vec4(0.0);
    float u = (float(id) + 0.5) / float(textureSize(state_colors, 0).x);
    return texture(state_colors, vec2(u, 0.0));
}

// Optimized check: Does this UV sit on a "Hard Border" (Land-to-Sea or Land-to-Land)?
bool is_at_hard_border(vec2 uv, vec2 pixel_size, int current_id) {
    for (int i = 0; i < 8; i++) {
        int nid = get_id(uv + DIRS[i] * pixel_size);
        if (nid == 0) return true; // Sea neighbor
        if (nid > 1 && nid != current_id) return true; // Different country neighbor
    }
    return false;
}

void fragment() {
    vec2 pixel_size = 1.0 / tex_size;
    int id = get_id(UV);
    vec4 final_color = vec4(0.0);

    // --- 1. SEA LOGIC ---
    if (id == 0) {
        final_color = texture(original_texture, UV);
    }

    // --- 2. LAND LOGIC ---
    else if (id > 1) {
        vec4 base_color = get_country_color(id);
        final_color = base_color;

        float min_dist = country_glow_radius + 1.0;
        bool found_border = false;

        // GLOW LOOP: Search for the nearest "Hard Border" or "Sea"
        // Optimization: Step by 1.5 or 2.0 to reduce samples if radius is large
        for (float d = 1.0; d <= country_glow_radius; d += 1.0) {
            for (int i = 0; i < 8; i++) {
                vec2 sample_uv = UV + DIRS[i] * pixel_size * d;
                int nid = get_id(sample_uv);
                
                // If the sample hits Sea (0) or the ID-line (1) or a Different Country
                if (nid <= 1 || nid != id) {
                    min_dist = d;
                    found_border = true;
                    break;
                }
            }
            if (found_border) break;
        }

        if (found_border) {
            float strength = 1.0 - pow(min_dist / country_glow_radius, country_glow_falloff);
            vec4 glow_color = base_color * 1.6;
            final_color = mix(base_color, glow_color, clamp(strength * country_glow_intensity, 0.0, 1.0));
        }
    }

    // --- 3. BORDER/GRID LINE LOGIC (ID == 1) ---
    else if (id == 1) {
        // Look ahead to see if we should be a Country Border (Hard) or State Border (Soft)
        bool hard = false;
        vec4 neighbor_color = vec4(0.0);
        
        for (int i = 0; i < 8; i++) {
            int nid = get_id(UV + DIRS[i] * pixel_size);
            if (nid == 0) { hard = true; break; }
            if (nid > 1) {
                vec4 c = get_country_color(nid);
                if (neighbor_color.a == 0.0) neighbor_color = c;
                else if (distance(c.rgb, neighbor_color.rgb) > 0.01) { hard = true; break; }
            }
        }

        if (hard) {
            final_color = country_border_color;
        } else {
            final_color = mix(neighbor_color, vec4(0.0, 0.0, 0.0, 1.0), internal_border_darkness);
        }
    }

    COLOR = final_color;
}