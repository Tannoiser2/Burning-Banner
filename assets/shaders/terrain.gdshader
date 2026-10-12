// Terreno: la mappa stampata come texture, con la griglia esagonale e gli esagoni evidenziati
// calcolati nello shader (così seguono il rilievo).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D hl_tex : filter_nearest, repeat_disable;   // 32x32: colore e intensità per esagono
uniform float grid_alpha = 0.22;
uniform float dx = 1.3992431864335458;
uniform float dy = 1.614;
uniform vec2 org = vec2(0.06, 0.23);
uniform vec2 hover = vec2(-99.0, -99.0);
uniform float dim = 0.0;
uniform float time_s = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb;
	base = pow(base, vec3(1.35)) * 0.96;
	vec2 p = wpos.xz;
	float c0 = floor((p.x - org.x) / dx + 0.5);
	float best = 1e9;
	vec2 bh = vec2(0.0);
	vec2 bc = vec2(0.0);
	for (int i = -1; i <= 1; i++) {
		float c = c0 + float(i);
		float off = mod(c, 2.0) > 0.5 ? dy * 0.5 : 0.0;
		float r = floor((p.y - org.y - off) / dy + 0.5);
		for (int j = -1; j <= 1; j++) {
			float rr = r + float(j);
			vec2 ctr = vec2(org.x + c * dx, org.y + rr * dy + off);
			float d = distance(p, ctr);
			if (d < best) {
				best = d;
				bh = vec2(c, rr);
				bc = ctr;
			}
		}
	}
	vec2 q = abs(p - bc);
	float edge = dy * 0.5 - max(q.y, dot(q, vec2(0.8660254, 0.5)));
	vec4 hl = vec4(0.0);
	if (bh.x >= 0.0 && bh.y >= 0.0 && bh.x < 32.0 && bh.y < 32.0) {
		hl = texelFetch(hl_tex, ivec2(int(bh.x), int(bh.y)), 0);
	}
	vec3 col = base * (1.0 - dim);
	float pulse = 0.75 + 0.25 * sin(time_s * 3.0);
	if (hl.a > 0.01) {
		col = mix(col, hl.rgb, hl.a * 0.42 * pulse);
	}
	float line = 1.0 - smoothstep(0.0, 0.025, edge);
	col = mix(col, vec3(0.08, 0.05, 0.02), line * grid_alpha);
	if (hl.a > 0.01) {
		float l2 = 1.0 - smoothstep(0.0, 0.06, edge);
		col = mix(col, hl.rgb * 1.3, l2 * 0.9 * hl.a);
	}
	if (bh == hover) {
		float l3 = 1.0 - smoothstep(0.0, 0.05, edge);
		col = mix(col, vec3(1.0, 0.95, 0.7), l3 * 0.95);
		col *= 1.06;
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
