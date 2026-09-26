// sky.gdshader — the zones' sky (test 39: "a more realistic looking day and night sky"). Driven every game minute by
// Scripts/day_night_cycle.gd: the sky and horizon colours, the sun and the moon (directions, how visible), the moon's
// phase (a new moon is the dark moon), how dark it is (stars), and the clouds (more and greyer in rain). No textures:
// the stars, the moon's face and the clouds are all made here from noise.
// The expensive parts (clouds, stars, the moon's face) are drawn only in the view pass; the lighting cubemap (ambient
// and reflections) gets the plain gradient, sun glow and a flat cloud tint, so the sky stays cheap.
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.23, 0.39, 0.92);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.65, 0.71);
uniform vec3 ground_color : source_color = vec3(0.30, 0.27, 0.22);

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);     // toward the sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.78);
uniform float sun_visible = 1.0;
uniform float sunset = 0.0;                      // 0 = midday, 1 = the sun on the horizon (warm glow)

uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_visible = 0.0;
uniform float moon_phase = 0.5;                  // 0 = new (the dark moon), 0.5 = full, back to 1
uniform vec3 moon_color : source_color = vec3(0.86, 0.88, 0.95);

uniform float night = 0.0;                       // 0 day .. 1 full night (stars)
uniform float cloud_coverage = 0.3;              // 0 clear .. 1 overcast
uniform float cloud_darkness = 0.0;              // rain greys them
uniform vec2 wind = vec2(0.006, 0.0025);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// A point on a disc of angular radius `r` around direction `c`: xy in -1..1 (inside when length < 1).
vec2 disc_uv(vec3 d, vec3 c, float r) {
	vec3 up = abs(c.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, c));
	vec3 upv = cross(c, right);
	return vec2(dot(d, right), dot(d, upv)) / r;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;

	// the dome: horizon to top, and the ground below the horizon
	vec3 col = h >= 0.0 ? mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), 0.45))
			: mix(horizon_color, ground_color, clamp(-h * 3.0, 0.0, 1.0));

	// the sun's glow, and a warm band along the horizon at sunrise and sunset (strongest toward the sun)
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	col += sun_color * (pow(sd, 6.0) * 0.25 + pow(sd, 48.0) * 0.5) * sun_visible * (1.0 - cloud_darkness * 0.8);
	float band = pow(1.0 - abs(h), 5.0) * sunset * (0.35 + 0.65 * pow(sd, 3.0));
	col = mix(col, vec3(1.0, 0.45, 0.18) * (0.6 + 0.8 * sd), clamp(band, 0.0, 0.85));

	// the moon's glow
	float md = max(dot(d, normalize(moon_dir)), 0.0);
	col += moon_color * (pow(md, 900.0) * 0.18 + pow(md, 60.0) * 0.025) * moon_visible * (0.3 + 0.7 * (1.0 - abs(moon_phase * 2.0 - 1.0)));

	if (AT_CUBEMAP_PASS) {
		// lighting only: a flat cloud tint instead of the real clouds
		col = mix(col, mix(vec3(0.75), vec3(0.2), cloud_darkness) * mix(1.0, 0.12, night), cloud_coverage * 0.35 * step(0.0, h));
		COLOR = col;
	} else {
		if (h > 0.0) {
			// stars: one chance per cell on a fine grid over the sphere; they twinkle, and fade out by day
			if (night > 0.02) {
				vec3 p = d * 260.0;
				vec3 cell = floor(p);
				float r = hash13(cell);
				if (r > 0.9965) {
					vec3 centre = cell + vec3(hash13(cell + 1.7), hash13(cell + 3.1), hash13(cell + 5.3));
					float dist = length(p - centre);
					float twinkle = 0.65 + 0.35 * sin(TIME * (1.5 + r * 4.0) + r * 60.0);
					float bright = (r - 0.9965) / 0.0035;
					vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.9, 0.75), hash13(cell + 9.9));
					col += tint * smoothstep(0.55, 0.0, dist) * (0.4 + 1.8 * bright) * twinkle * night * smoothstep(0.0, 0.12, h);
				}
			}
			// the sun's disc
			col += sun_color * 6.0 * smoothstep(0.99955, 0.99975, dot(d, normalize(sun_dir))) * sun_visible;
			// the moon: a lit face with its phase (the terminator sweeps across it), grey maria, faint earthshine
			vec2 m = disc_uv(d, normalize(moon_dir), 0.028);
			float mr = length(m);
			if (mr < 1.0 && dot(d, moon_dir) > 0.0 && moon_visible > 0.0) {
				float y = m.y;
				float k = cos(moon_phase * 6.2831853);
				float edge = k * sqrt(max(1.0 - y * y, 0.0));
				float lit = moon_phase < 0.5 ? smoothstep(edge - 0.04, edge + 0.04, m.x) : smoothstep(edge - 0.04, edge + 0.04, -m.x);
				float maria = fbm(m * 2.2 + vec2(3.0, 7.0));
				vec3 face = moon_color * mix(0.62, 1.05, smoothstep(0.35, 0.65, maria));
				float rim = smoothstep(1.0, 0.94, mr);
				col = mix(col, face * (lit * 1.6 + 0.035), rim * moon_visible);
			}
			// clouds: a noise layer on a flat plane overhead, drifting on the wind; lit by the sun by day, a silver edge
			// toward it, dark grey at night and in rain; they hide the stars and the moon behind them
			vec2 uv = d.xz / (h + 0.12) * 0.55 + TIME * wind;
			float n = fbm(uv * 1.6);
			float thin = 1.0 - cloud_coverage;
			float c = smoothstep(thin - 0.05, thin + 0.28, n) * smoothstep(0.0, 0.18, h);
			vec3 day_cloud = mix(vec3(1.0, 0.98, 0.95), vec3(0.16, 0.17, 0.19), cloud_darkness) * (0.75 + 0.25 * sun_color);
			vec3 dusk = mix(day_cloud, vec3(1.0, 0.55, 0.35), sunset * 0.6);
			vec3 night_cloud = mix(vec3(0.07, 0.08, 0.11), vec3(0.03, 0.035, 0.045), cloud_darkness) + moon_color * 0.05 * moon_visible;
			vec3 cloud = mix(dusk, night_cloud, night);
			cloud += sun_color * pow(sd, 12.0) * 0.45 * (1.0 - night) * (1.0 - cloud_darkness);
			cloud *= 1.0 - 0.25 * smoothstep(0.55, 0.95, n);   // thicker middles are darker underneath
			col = mix(col, cloud, clamp(c, 0.0, 0.95));
		}
		COLOR = col;
	}
}
