shader_type canvas_item;

// --- INPUTS ---
uniform sampler2D region_id_map : filter_nearest;
uniform sampler2D type_map : filter_nearest;
uniform sampler2D state_colors : filter_nearest;

// NOISE TEXTURE (Generated in World.gd)
uniform sampler2D ocean_noise : filter_nearest, repeat_enable;
// ORIGINAL TEXTURE (To show the grid)
uniform sampler2D original_texture : filter_linear_mipmap; 
uniform vec2 tex_size;

// --- COLORS ---
// Shallow/deep don't exist just named that way
uniform vec4 water_color_deep : source_color = vec4(0.10, 0.25, 0.45, 1.0);  
uniform vec4 water_color_shallow : source_color = vec4(0.25, 0.45, 0.65, 1.0); 
uniform vec4 sun_glint_color : source_color = vec4(0.9, 0.95, 1.0, 0.3); 
uniform vec4 country_border_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);

// --- WATER SETTINGS ---
uniform float sea_speed : hint_range(0.0, 0.2) = 0.02; 
uniform float wave_scale : hint_range(0.1, 5.0) = 1.5; 
uniform float distortion_strength : hint_range(0.0, 1.0) = 0.15; 
uniform float grid_opacity : hint_range(0.0, 1.0) = 0.3; 
uniform float sea_pixel_size = 2.0;       // 1 = native pixels, 2–4 = chunkier
uniform float sea_height_steps = 6.0;    // number of discrete wave levels
uniform vec2 ocean_offset;
// --- BORDER SETTINGS (From Old Version) ---
uniform float internal_border_darkness : hint_range(0.0, 1.0) = 0.2;

// 8 constant directions for scanning neighbors
const vec2 DIRS[8] = vec2[8](
    vec2(0.0, -1.0), vec2(0.0,  1.0),
    vec2(-1.0, 0.0), vec2(1.0,  0.0),
    vec2(-1.0, -1.0), vec2(1.0,  -1.0),
    vec2(-1.0, 1.0), vec2(1.0,  1.0)
);

// --- ID HELPERS ---
int get_id(vec2 uv) {
    vec2 cuv = clamp(uv, vec2(0.0), vec2(1.0));
    vec4 c = texture(region_id_map, cuv);
    int r = int(round(c.r * 255.0));
    int g = int(round(c.g * 255.0));
    return r + g * 256;
}

vec4 get_country_color(int id) {
    if (id <= 1) return vec4(0.0);
    float u = (float(id) + 0.5) / float(textureSize(state_colors, 0).x);
    vec4 col = texture(state_colors, vec2(u, 0.5));
    return col; // This will return alpha 0 for sea provinces now
}
// --- BORDER SCANNING LOGIC ---
bool detect_border_at_distance(vec2 origin_uv, float dist_px, out vec4 out_color, out bool is_black) {
    vec2 pixel_size = 1.0 / tex_size;
    out_color = vec4(0.0);
    is_black = false;

    bool found_color = false;
    vec4 reference = vec4(0.0);
    
    // Check if the ORIGIN pixel itself is touching sea
    // We use the type_map to determine "Sea-ness" now
    float origin_type = texture(type_map, origin_uv).r;

    for (int i = 0; i < 8; i++) {
        vec2 sample_uv = clamp(origin_uv + DIRS[i] * pixel_size * dist_px, vec2(0.0), vec2(1.0));
        float sample_type = texture(type_map, sample_uv).r;
        int nid = get_id(sample_uv);

        // 1. If any neighbor is SEA, this is a COASTLINE
        if (sample_type < 0.5) { 
            is_black = true; 
            return true; 
        }

        // 2. If neighbor is LAND
        if (nid > 1) {
            vec4 c = get_country_color(nid);
            if (!found_color) {
                reference = c;
                found_color = true;
            } else {
                // If touching a DIFFERENT country, it's an international border
                if (distance(reference.rgb, c.rgb) > 0.005) {
                    is_black = true;
                    return true;
                }
            }
        }
    }

    if (found_color) {
        out_color = mix(reference, vec4(0.0, 0.0, 0.0, 1.0), internal_border_darkness);
        return true;
    }
    return false;
}
void fragment() {
    float p_type = texture(type_map, UV).r;
    int id = get_id(UV);
    
    // 1. If type_map says Sea (0.0), render the animated water
    if (p_type < 0.5) {
        vec2 grid_uv = floor(UV * tex_size / sea_pixel_size) * sea_pixel_size / tex_size;
        float h = texture(ocean_noise, grid_uv + ocean_offset).r;
        h = floor(h * sea_height_steps) / sea_height_steps;
        vec3 water = mix(water_color_deep.rgb, water_color_shallow.rgb, h);
        COLOR = vec4(water, 1.0);
    } 
    // 2. If it's Land (type_map 1.0) and a real province
    else if (id > 1) {
        COLOR = vec4(get_country_color(id).rgb, 1.0);
    } 
    // 3. If it's Land (type_map 1.0) and ID 1 (Border)
    else {
        vec4 c_detect = vec4(0.0);
        bool must_be_black = false;
        bool decided = detect_border_at_distance(UV, 1.0, c_detect, must_be_black);
        
        if (!decided) decided = detect_border_at_distance(UV, 2.0, c_detect, must_be_black);

        if (decided) {
            COLOR = must_be_black ? country_border_color : c_detect;
        } else {
            COLOR = country_border_color;
        }
    }
}