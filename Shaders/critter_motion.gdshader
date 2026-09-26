// critter_motion.gdshader — brings the unrigged critters to life (user, test 41: "can you animate the static enemies as
// well"). The rat, snake, bat, spiders, scarab and slime are single Meshy meshes with no bones, so the shader moves their
// vertices on the graphics card instead, by body type (mode):
//   0 RAT     scurries: a quick bob, the body swaying, the feet paddling, the tail swishing in a travelling wave
//   1 LEGS    spiders and the scarab: legs lift and step in two alternating sets (every other leg around the body)
//   2 SNAKE   slithers: an S-wave running down the body, the head steadier; a strike thrusts the head forward
//   3 BAT     flaps: the wings beat (always, it flies), the body rising and falling between beats
//   4 SLIME   squashes and stretches, and jiggles
// Driven per monster (monster3d.gd, instance uniforms): anim_time (runs faster when it moves), move (0 still .. 1 at a
// run), attack (1 at a blow, fading). The mesh's own box (box_center / box_half, its local axes: Z is up) tells the shader
// where head, tail, legs and wings are; body_axis / tail_sign say which way the body lies.
// The fragment is the same PBR as the critters' old StandardMaterial3D (albedo, normal, roughness, metallic maps).
shader_type spatial;

uniform int mode = 0;
uniform vec3 box_center = vec3(0.0);
uniform vec3 box_half = vec3(1.0);
uniform int body_axis = 0;            // 0: the body lies along x, 1: along y
uniform float tail_sign = 1.0;        // +1: the tail is at the + end of that axis
uniform float amount = 1.0;           // overall strength (per creature)

instance uniform float anim_time = 0.0;
instance uniform float move = 0.0;
instance uniform float attack = 0.0;

uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap;
uniform sampler2D metallic_tex : hint_default_black, filter_linear_mipmap;
uniform bool use_normal = false;
uniform bool use_metallic = false;


void vertex() {
	vec3 p = (VERTEX - box_center) / box_half;          // -1..1 inside the box
	float along = (body_axis == 0 ? p.x : p.y) * tail_sign;   // +1 at the tail, -1 at the head
	float side = body_axis == 0 ? p.y : p.x;
	float h = p.z;                                      // -1 the ground, +1 the top
	float t = anim_time;
	float mv = clamp(move, 0.0, 1.5);
	vec3 d = vec3(0.0);                                 // displacement, in -1..1 box units: (along, side, up)

	if (mode == 0) {           // RAT
		d.z += 0.08 * abs(sin(TAU * t * 2.0)) * mv;
		d.y += 0.05 * sin(TAU * t) * (0.3 + mv) * (1.0 - abs(along));
		float feet = smoothstep(-0.45, -0.8, h);
		float leg_phase = (side > 0.0 ? 0.0 : 0.5) + (along < 0.0 ? 0.0 : 0.5);
		d.x += 0.14 * sin(TAU * (t * 2.0 + leg_phase)) * mv * feet;
		d.z += 0.06 * max(0.0, sin(TAU * (t * 2.0 + leg_phase))) * mv * feet;
		float tail = smoothstep(0.35, 1.0, along);
		d.y += 0.45 * tail * tail * sin(TAU * t * 1.3 - along * 3.0) * (0.4 + mv);
		d.z += 0.12 * tail * tail * sin(TAU * t * 0.9) * (0.5 + 0.5 * mv);
		d.x -= 0.18 * attack * smoothstep(0.3, -1.0, along);        // lunges with its head
	} else if (mode == 1) {    // LEGS (spiders, scarab)
		float r = length(p.xy);
		float leg = smoothstep(0.4, 0.75, r) * smoothstep(0.2, -0.4, h + 0.2);   // far from the body, low
		float ang = atan(p.y, p.x);
		float group = mod(floor((ang + 3.14159) / (TAU / 8.0)), 2.0);          // every other leg around the body
		float step_t = TAU * (t * 2.2 + group * 0.5);
		d.z += 0.35 * max(0.0, sin(step_t)) * leg * (0.15 + mv);
		d.x += 0.12 * cos(step_t) * leg * (0.1 + mv);
		d.z += 0.04 * sin(TAU * t * 4.4) * mv * (1.0 - leg);                   // the body bobs as it scuttles
		d.z += 0.02 * sin(TAU * t * 0.5) * (1.0 - leg);                        // and breathes when still
		d.z += 0.35 * attack * smoothstep(0.2, -1.0, along);                   // rears up at the front to strike
	} else if (mode == 2) {    // SNAKE
		float body = smoothstep(-0.7, 0.2, along);                             // the head end holds steadier
		d.y += 0.55 * sin(TAU * t * 1.1 - along * 5.5) * body * (0.35 + mv);
		d.z += 0.03 * sin(TAU * t * 0.6) * (1.0 - body);                       // the raised head sways gently
		d.x -= 0.45 * attack * smoothstep(0.0, -1.0, along);                   // the strike
	} else if (mode == 3) {    // BAT
		float wing = smoothstep(0.18, 1.0, abs(p.x));
		d.z += 0.7 * sin(TAU * t * 3.0) * wing * wing;
		d.z += 0.08 * sin(TAU * t * 3.0 + 1.6) * (1.0 - wing);
		d.z -= 0.25 * attack;                                                   // swoops
	} else {                   // SLIME
		float squash = sin(TAU * t * 1.2) * (0.08 + 0.08 * mv) + 0.25 * attack;
		float up = h * 0.5 + 0.5;
		d.z += squash * up;
		d.x -= squash * 0.4 * p.x;
		d.y -= squash * 0.4 * side;
		d.x += 0.04 * sin(TAU * t * 3.0 + p.z * 4.0) * up;
		d.y += 0.04 * cos(TAU * t * 2.6 + p.z * 3.0) * up;
	}
	d *= amount;
	// (along, side, up) back to the mesh's own axes
	vec3 local = body_axis == 0 ? vec3(d.x * tail_sign, d.y, d.z) : vec3(d.y, d.x * tail_sign, d.z);
	VERTEX += local * box_half;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * tint;
	ALBEDO = c.rgb;
	ROUGHNESS = texture(roughness_tex, UV).r;
	METALLIC = use_metallic ? texture(metallic_tex, UV).r : 0.0;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
