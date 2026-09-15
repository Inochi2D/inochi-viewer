/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
#version 420
uniform vec4 color;

layout(location = 0) out vec4 outAlbedo;

void main() {
    outAlbedo = color;
}
