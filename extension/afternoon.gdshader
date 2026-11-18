shader_type sky;

void sky() {
	float h = clamp(EYEDIR.y, 0.0, 1.0);
	vec3 horizon = vec3(0.67,0.68,0.57);
	vec3 zenith = vec3(0.21,0.42,0.54);
	vec3 color = mix(horizon, zenith, pow(h,0.48));
	if (LIGHT0_ENABLED) {
		float alignment = max(dot(EYEDIR,LIGHT0_DIRECTION),0.0);
		color += vec3(0.19,0.13,0.055)*pow(alignment,28.0);
		color += vec3(1.38,1.16,0.76)*smoothstep(0.99978,0.99992,alignment);
	}
	COLOR=color;
}
