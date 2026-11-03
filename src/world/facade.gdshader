shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Fachada procedural. As janelas são desenhadas em espaço de mundo, então a
// mesma malha de caixa serve para as quatro faces sem precisar de UVs especiais
// nem de um modelo por prédio. Tudo é calculado no fragmento, sem textura.
//
// Otimização para Mobile: nenhuma amostragem de textura, nenhum laço, e o custo
// não depende do tamanho do prédio.

uniform vec3 wall_color : source_color = vec3(0.34, 0.35, 0.38);
uniform vec3 window_color : source_color = vec3(0.16, 0.20, 0.27);
uniform vec3 lit_window_color : source_color = vec3(0.95, 0.86, 0.62);
uniform float window_scale = 3.6;      // metros por célula de janela
uniform float window_width = 0.58;     // fração da célula ocupada pela janela
uniform float lit_fraction = 0.18;     // fração de janelas acesas
uniform float band_height = 3.2;       // altura da faixa horizontal entre andares
uniform float roughness_value = 0.75;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Hash barato: dá um valor estável por janela, para a luz não piscar.
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// Escolhe o plano da fachada: paredes verticais usam X/Z; telhado usa X/Z também,
	// então o telhado é tratado à parte pela normal.
	vec3 n = normalize(world_normal);
	float vertical = 1.0 - abs(n.y);
	vec2 plane = mix(vec2(world_position.x, world_position.z),
			vec2(world_position.x + world_position.z, world_position.y), vertical);

	vec2 cell = plane / window_scale;
	vec2 cell_id = floor(cell);
	vec2 local = fract(cell);

	// Máscara da janela: retângulo dentro da célula.
	vec2 half_size = vec2(window_width) * 0.5;
	vec2 distance_to_edge = abs(local - 0.5) - (vec2(0.5) - half_size);
	float window_mask = 1.0 - step(0.0, max(distance_to_edge.x, distance_to_edge.y));

	// Faixa de laje: parte de baixo de cada célula fica sem janela.
	float slab = step(local.y, 0.16);
	window_mask *= (1.0 - slab);

	// Janelas acesas: só em paredes verticais, com distribuição estável.
	float lit_roll = hash21(cell_id + vec2(0.5));
	float lit = step(1.0 - lit_fraction, lit_roll) * vertical * window_mask;

	vec3 base = mix(wall_color, window_color, window_mask * vertical);
	vec3 emissive = lit_window_color * lit;

	ALBEDO = base;
	EMISSION = emissive * 1.2;
	ROUGHNESS = mix(roughness_value, 0.15, window_mask * vertical);
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
