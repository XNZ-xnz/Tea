#version 450
#extension GL_ARB_shader_viewport_layer_array : enable
void main() {
    vec2 pos[3] = vec2[](vec2(-1,-1), vec2(3,-1), vec2(-1,3));
    gl_Position = vec4(pos[gl_VertexIndex], 0, 1);
    gl_Layer = gl_InstanceIndex;
}
