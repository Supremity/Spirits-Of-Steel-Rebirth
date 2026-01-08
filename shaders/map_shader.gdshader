shader_type canvas_item;

// --- INPUTS ---
uniform sampler2D region_id_map : filter_nearest;
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
    return texture(state_colors, vec2(u, 0.0));
}

// --- BORDER SCANNING LOGIC (Restored from Old Version) ---
// Returns true if meaningful info was found
bool detect_border_at_distance(vec2 origin_uv, float dist_px, out vec4 out_color, out bool is_black) {
    vec2 pixel_size = 1.0 / tex_size;
    out_color = vec4(0.0);
    is_black = false;

    bool found_color = false;
    vec4 reference = vec4(0.0);

    for (int i = 0; i < 8; i++) {
        vec2 sample_uv = clamp(origin_uv + DIRS[i] * pixel_size * dist_px, vec2(0.0), vec2(1.0));
        int nid = get_id(sample_uv);

        // Touching sea -> mark black/coast
        if (nid == 0) {
            is_black = true;
            return true;
        }

        // Found a country
        if (nid > 1) {
            vec4 c = get_country_color(nid);
            if (!found_color) {
                reference = c;
                found_color = true;
            } else {
                // If we found a DIFFERENT country nearby, it's an international border (hard black)
                if (distance(reference.rgb, c.rgb) > 0.005) {
                    is_black = true;
                    return true;
                }
            }
        }
    }

    // If we only found one country color on all sides, it's an internal province border
    if (found_color) {
        out_color = mix(reference, vec4(0.0, 0.0, 0.0, 1.0), internal_border_darkness);
        return true;
    }

    return false;
}

void fragment() {
    int id = get_id(UV);
    vec4 final_color = vec4(0.0);

    // 1. SEA (New Water Logic)
    if (id == 0) {
        // --- PIXEL GRID SNAP ---
        vec2 grid_uv = floor(UV * tex_size / sea_pixel_size) 
                       * sea_pixel_size / tex_size;

        // --- TIME STEP ---
        float t = TIME * sea_speed; 

        // --- SINGLE NOISE SAMPLE ---
        float h = texture(ocean_noise, grid_uv + vec2(t, 0.0)).r;

        // --- REDUCED QUANTIZATION ---
        h = floor(h * sea_height_steps) / sea_height_steps;

        // --- COLOR MIX ---
        vec3 water = mix(water_color_deep.rgb, water_color_shallow.rgb, h);

        // --- GRID OVERLAY ---
        vec3 grid = texture(original_texture, grid_uv).rgb;
        water = mix(water, grid, grid_opacity);

        final_color = vec4(water, 1.0);
    }
    
    // 2. CLEAN LAND (Solid)
    else if (id > 1) {
        final_color = vec4(get_country_color(id).rgb, 1.0);
    } 
    
    // 3. BORDERS (Old Scanning Logic)
    else {
        // id == 1, or ambiguous pixels
        vec4 c_detect = vec4(0.0);
        bool must_be_black = false;
        bool decided = false;

        // Scan at 1px, then 2px, then 3px
        // This fixes thick borders looking like black blobs
        if (!decided && detect_border_at_distance(UV, 1.0, c_detect, must_be_black)) decided = true;
        if (!decided && detect_border_at_distance(UV, 2.0, c_detect, must_be_black)) decided = true;
        if (!decided && detect_border_at_distance(UV, 3.0, c_detect, must_be_black)) decided = true;

        if (decided) {
            if (must_be_black) {
                final_color = country_border_color;
            } else {
                final_color = c_detect; // Internal border color
            }
        } else {
			vec4 direct_lookup = get_country_color(id);
			if (direct_lookup.a < 0.1) {
                final_color = country_border_color;
            } else {
                final_color = direct_lookup;
            }
            // Fallback if scanning failed (very thick intersection)
        }
    }

    COLOR = final_color;
}