shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
uniform vec4 olive : source_color = vec4(0.42,0.46,0.26,1.0);
void fragment(){
	ALBEDO=olive.rgb;
	ROUGHNESS=1.0;
	NORMAL=normalize((VIEW_MATRIX * vec4(0.0,1.0,0.0,0.0)).xyz);
}
