shader_type canvas_item;
// Árvores balançando no vento: só a copa anda (o pé fica no chão), em pixels inteiros.
// Cada árvore tem fase própria pela posição no mundo; "wind" vem do VilaFx (rajadas).

uniform float wind = 0.5;
uniform float height = 32.0;

void vertex() {
	float k = clamp(-VERTEX.y / height, 0.0, 1.0);
	float phase = MODEL_MATRIX[3].x * 0.071 + MODEL_MATRIX[3].y * 0.037;
	float s = sin(TIME * (1.3 + wind * 1.6) + phase) * (0.6 + wind * 1.6) + wind * 1.2;
	VERTEX.x += round(s * k * k);
}
