// Billboarded rings that grow outward and fade, marking an object that is emitting sound.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(1.0);
uniform float inner = 0.33; // ring start radius, as a fraction of the quad's half-size
uniform float speed = 0.6;  // ring cycles per second
uniform float width = 0.035;

void vertex() {
	// Face the viewer, keeping the object's position.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float alpha = 0.0;
	for (int i = 0; i < 3; i++) {
		float t = fract(TIME * speed + float(i) / 3.0);
		float radius = mix(inner, 1.0, t);
		float ring = 1.0 - smoothstep(0.0, width, abs(r - radius));
		alpha = max(alpha, ring * (1.0 - t));
	}
	ALBEDO = color.rgb;
	ALPHA = alpha * color.a;
}
