// Acqua animata: piano trasparente sopra le zone di mare della mappa, con onde e riflessi.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec4 deep : source_color = vec4(0.16, 0.30, 0.38, 1.0);
uniform vec4 shallow : source_color = vec4(0.45, 0.62, 0.66, 1.0);
uniform float alpha = 0.55;
uniform float time_s = 0.0;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += 0.012 * sin(wpos.x * 3.0 + time_s * 1.3) * cos(wpos.z * 2.6 + time_s * 1.1);
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = noise(p * 3.0 + vec2(time_s * 0.25, time_s * 0.18));
	float n2 = noise(p * 7.0 - vec2(time_s * 0.35, -time_s * 0.22));
	float n = n1 * 0.6 + n2 * 0.4;
	vec3 nrm = normalize(vec3((n1 - 0.5) * 0.35, 1.0, (n2 - 0.5) * 0.35));
	NORMAL = (VIEW_MATRIX * vec4(nrm, 0.0)).xyz;
	ALBEDO = mix(deep.rgb, shallow.rgb, n);
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = alpha + 0.12 * n;
}
