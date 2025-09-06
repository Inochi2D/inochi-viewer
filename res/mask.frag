/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
#version 420
in vec2 texUVs;

layout(location = 0) out float outMask;
layout(binding = 0) uniform sampler2D mask;

uniform int maskMode;

layout(std140, binding = 0)
uniform iUniforms {
    vec3 tint;
    vec3 screenTint;
    float opacity;
};

void main() {
    outMask = maskMode == 1 ? texture(mask, texUVs).a : 1-texture(mask, texUVs).a;
}