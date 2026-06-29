/*
    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
#version 420
in vec2 texUVs;
in vec2 ndcTexCoords;

layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outEmission;
layout(location = 2) out vec4 outBumpmap;
layout(binding = 0) uniform sampler2D mask;
layout(binding = 1) uniform sampler2D albedo;
layout(binding = 2) uniform sampler2D emission;
layout(binding = 3) uniform sampler2D bumpmap;

void main() {
    vec4 inAlbedo = texture(albedo, texUVs) * texture(mask, ndcTexCoords).rrrr;
    vec4 inEmission = texture(emission, texUVs);
    vec4 inBumpmap = texture(bumpmap, texUVs);

    outAlbedo = inAlbedo;
    outEmission = inEmission * outAlbedo.aaaa;
    outBumpmap = inBumpmap * outAlbedo.aaaa;
}
