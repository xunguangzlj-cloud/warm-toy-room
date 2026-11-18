shader_type spatial;
render_mode cull_disabled, unshaded;
// 远树与矮篱分别采用预烘的叶簇明暗，避免微小的直射高光在远景连成亮线。
void fragment(){
	float lightness=smoothstep(0.08,0.94,UV.x);
	vec3 hedge=mix(vec3(0.155,0.204,0.150),vec3(0.284,0.344,0.237),lightness);
	vec3 crown=mix(vec3(0.183,0.244,0.169),vec3(0.410,0.460,0.301),lightness);
	ALBEDO=mix(hedge,crown,UV.y);
}
