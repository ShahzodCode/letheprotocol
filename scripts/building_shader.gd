class_name BuildingShader
## The window shader for every building box (one MultiMesh). Windows are drawn from world coordinates, so a box needs no texture.
##   instance colour rgb = wall colour (sRGB), alpha = STYLE:
##     0.05 - 0.11  punched windows (the default old block)        0.12 - 0.16  shop front on the ground floor, punched windows above
##     0.17 - 0.22  old house: small windows                       0.34 - 0.67  ribbon windows
##     0.67 - 0.78  glass curtain wall with a lit crown            0.78 - 0.82  office tower: glass between pale vertical piers
##     0.97 and up  plain wall (interiors, furniture, floor slabs, parapets)
##   instance custom data: x = damage 0..1 (broken black windows, soot above them and from the ground, burnt-out floors),
##                         y = a per-building random number, z = burning (some broken windows glow and flicker), w = unused.

const CODE := """
shader_type spatial;
varying vec3 wpos;
varying flat vec3 onrm;
varying flat vec4 icol;
varying flat vec4 cust;
varying float topk;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	onrm = NORMAL;
	icol = COLOR;
	cust = INSTANCE_CUSTOM;
	topk = VERTEX.y + 0.5;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float floor_burnt_at(float row, float dmg, float seed) {
	return step(1.0 - dmg * 0.14, hash(vec2(row, seed * 1.3))) * step(0.5, dmg);
}

// is the window in this cell broken (or on a burnt-out floor)?
float broken_at(vec2 id, float dmg, float seed) {
	float b = step(1.0 - dmg * 0.42, hash(id + seed));
	float floor_burnt = step(1.0 - dmg * 0.14, hash(vec2(id.y, seed * 1.3))) * step(0.5, dmg);
	return max(b, floor_burnt);
}

void fragment() {
	vec3 base = pow(icol.rgb, vec3(2.2));
	float style = icol.a;
	float dmg = cust.x;
	float seed = cust.y * 37.0;
	float burning = cust.z;
	// far away (or at a grazing angle) a window is smaller than a pixel: fade to the average look instead of shimmering.
	// The derivatives are taken here, in uniform control flow.
	vec2 uv0 = abs(onrm.x) > 0.5 ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
	float cells_per_pixel = fwidth(uv0.x) / 2.8 + fwidth(uv0.y) / 1.8;
	float far = smoothstep(0.08, 0.4, cells_per_pixel);
	vec3 col = base;
	float rough = 0.9;
	float met = 0.0;
	vec3 emit = vec3(0.0);
	if (style < 0.97 && abs(onrm.y) < 0.5) {
		vec2 uv = abs(onrm.x) > 0.5 ? vec2(wpos.z, wpos.y) : vec2(wpos.x, wpos.y);
		bool shop = style > 0.12 && style < 0.16;
		bool house = style > 0.16 && style < 0.23;
		bool glassy = style >= 0.67;
		bool office = style > 0.78 && style < 0.82;
		vec2 cell = vec2(uv.x / 2.8, uv.y / 3.6);
		if (house) {
			cell = vec2(uv.x / 2.4, uv.y / 3.0);
		}
		vec2 f = fract(cell);
		vec2 id = floor(cell);
		float win;
		if (style < 0.34) {
			if (house) {
				win = step(0.3, f.x) * step(f.x, 0.7) * step(0.3, f.y) * step(f.y, 0.8);
			} else {
				win = step(0.2, f.x) * step(f.x, 0.8) * step(0.3, f.y) * step(f.y, 0.85);
			}
		} else if (style < 0.67) {
			win = step(0.28, f.y) * step(f.y, 0.82);
		} else if (office) {
			win = step(0.2, f.x) * step(f.x, 0.8) * step(0.03, f.y) * step(f.y, 0.97);
		} else {
			win = step(0.06, f.y) * step(f.y, 0.94) * step(0.04, f.x) * step(f.x, 0.96);
		}
		float ground = 0.0;
		if (shop && uv.y < 4.4) {
			// storefront: big dark glazing with mullions, a coloured sign band above it
			float sx = fract(uv.x / 3.4);
			float glaze = step(0.3, uv.y) * step(uv.y, 3.0) * step(0.05, sx) * step(sx, 0.95);
			float sign_band = step(3.25, uv.y) * step(uv.y, 4.15);
			float sh = hash(vec2(floor(uv.x / 3.4), seed));
			vec3 sign_col = mix(vec3(0.7, 0.12, 0.1), vec3(0.1, 0.3, 0.6), step(0.33, sh));
			sign_col = mix(sign_col, vec3(0.85, 0.7, 0.15), step(0.66, sh));
			col = base;
			col = mix(col, vec3(0.04, 0.07, 0.09), glaze);
			col = mix(col, sign_col, sign_band);
			rough = mix(0.9, 0.15, glaze);
			met = glaze * 0.4;
			emit = sign_col * sign_band * 0.18;
			win = 0.0;
			ground = 1.0;
		} else {
				win = mix(win, 0.4, far);
				win *= step(0.9, uv.y);
				float h = hash(id + seed * 0.1);
				vec3 glass = mix(vec3(0.03, 0.06, 0.1), vec3(0.14, 0.24, 0.32), h * 0.8);
				if (glassy) {
					glass = mix(vec3(0.06, 0.14, 0.22), vec3(0.3, 0.5, 0.62), 0.25 + h * 0.5);
				}
				float brk = mix(broken_at(id, dmg, seed), dmg * 0.4, far) * win;
				glass = mix(glass, vec3(0.008, 0.008, 0.009), brk);
				col = mix(base, glass, win);
				rough = mix(0.9, 0.12, win * (1.0 - brk));
				met = win * 0.5 * (1.0 - brk);
				if (glassy && !office && topk > 0.965) {
					emit = vec3(0.1, 0.65, 0.9) * (1.0 - step(0.5, dmg));
				}
				// fire glowing behind the broken windows of the burnt-out floors of a burning building
				float fire_cell = floor_burnt_at(id.y, dmg, seed) * win * step(0.5, burning) * step(0.5, hash(id * 1.7 + seed + 5.0)) * (1.0 - far);
				float flick = 0.75 + 0.35 * sin(TIME * 8.0 + hash(id) * 30.0) + 0.2 * sin(TIME * 17.0 + hash(id + 3.0) * 50.0);
				emit += fire_cell * vec3(1.0, 0.42, 0.09) * flick * 1.5;
			}
			// soot: above broken windows (up to two storeys) and creeping up from the street
			float s1 = broken_at(id - vec2(0.0, 1.0), dmg, seed);
			float s2 = broken_at(id - vec2(0.0, 2.0), dmg, seed);
			float soot = s1 * 0.42 * (1.0 - f.y * 0.6) + s2 * 0.16;
			soot = mix(soot, dmg * 0.22, far) * clamp(dmg * 1.6, 0.0, 1.0);
			float street = (1.0 - smoothstep(0.0, 2.0 + dmg * 6.0, wpos.y)) * dmg * 0.55;
			float burn_soot = burning * dmg * (1.0 - smoothstep(0.0, 18.0, wpos.y)) * 0.25;
			float total = clamp(soot + street + burn_soot, 0.0, 0.8) * (1.0 - ground * 0.5);
			col = mix(col, vec3(0.02, 0.019, 0.018), total);
			rough = mix(rough, 1.0, total);
	} else if (style < 0.97 && onrm.y > 0.5) {
		col = base * 0.55;
		col = mix(col, vec3(0.03), clamp(dmg * 0.5, 0.0, 0.6));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = met;
	EMISSION = emit;
}
"""
