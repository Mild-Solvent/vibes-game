shader_type spatial;
// The visible beam of someone else's torch: additive, soft along its length and at its edges,
// so from the side it reads as light in the fog instead of a solid grey cone.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 colour = vec3(1.0, 0.95, 0.8);
uniform float strength = 0.08;

void fragment() {
	// UV.y runs from the far end (0) to the torch (1).
	float along = UV.y;
	float fade = smoothstep(0.0, 0.7, along) * smoothstep(1.0, 0.92, along);
	// Faces seen edge-on (the silhouette) fade out; looking down the middle stays brightest.
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	ALBEDO = colour;
	ALPHA = strength * fade * edge;
}
