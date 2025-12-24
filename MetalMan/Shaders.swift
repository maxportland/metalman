import Foundation

/// Metal shader source code for the game
let metalShaderSource = """
#include <metal_stdlib>
using namespace metal;

// Simple wireframe vertex
struct VertexIn {
    float3 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct Uniforms {
    float4x4 mvpMatrix;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]],
                             constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    out.position = uniforms.mvpMatrix * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}

// Textured lit vertex
struct TexturedVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
    uint materialIndex [[attribute(3)]];
};

struct LitVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 texCoord;
    float4 lightSpacePosition;
    uint materialIndex [[flat]];  // flat interpolation prevents integer interpolation artifacts
};

struct LitUniforms {
    float4x4 modelMatrix;
    float4x4 viewProjectionMatrix;
    float4x4 lightViewProjectionMatrix;
    float3 lightDirection;
    float3 cameraPosition;
    float ambientIntensity;
    float diffuseIntensity;
};

vertex LitVertexOut vertex_lit(TexturedVertexIn in [[stage_in]],
                               constant LitUniforms &uniforms [[buffer(1)]]) {
    LitVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPos.xyz;
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.normal = normalize((uniforms.modelMatrix * float4(in.normal, 0.0)).xyz);
    out.texCoord = in.texCoord;
    out.lightSpacePosition = uniforms.lightViewProjectionMatrix * worldPos;
    out.materialIndex = in.materialIndex;
    return out;
}

float calculateShadow(float4 lightSpacePos, depth2d<float> shadowMap, sampler shadowSampler) {
    float3 projCoords = lightSpacePos.xyz / lightSpacePos.w;
    projCoords.xy = projCoords.xy * 0.5 + 0.5;
    projCoords.y = 1.0 - projCoords.y;
    
    if (projCoords.x < 0 || projCoords.x > 1 || projCoords.y < 0 || projCoords.y > 1 || projCoords.z > 1) {
        return 1.0;
    }
    
    float currentDepth = projCoords.z;
    float bias = 0.005;
    
    // PCF soft shadows
    float shadow = 0.0;
    float2 texelSize = 1.0 / float2(shadowMap.get_width(), shadowMap.get_height());
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            float pcfDepth = shadowMap.sample(shadowSampler, projCoords.xy + float2(x, y) * texelSize);
            shadow += currentDepth - bias > pcfDepth ? 0.4 : 1.0;
        }
    }
    return shadow / 9.0;
}

fragment float4 fragment_lit(LitVertexOut in [[stage_in]],
                             texture2d<float> groundTex [[texture(0)]],
                             texture2d<float> trunkTex [[texture(1)]],
                             texture2d<float> foliageTex [[texture(2)]],
                             texture2d<float> rockTex [[texture(3)]],
                             texture2d<float> poleTex [[texture(4)]],
                             depth2d<float> shadowMap [[texture(5)]],
                             texture2d<float> characterTex [[texture(6)]],
                             texture2d<float> pathTex [[texture(7)]],
                             texture2d<float> stoneWallTex [[texture(8)]],
                             texture2d<float> roofTex [[texture(9)]],
                             texture2d<float> woodPlankTex [[texture(10)]],
                             texture2d<float> skyTex [[texture(11)]],
                             sampler texSampler [[sampler(0)]],
                             sampler shadowSampler [[sampler(1)]],
                             constant LitUniforms &uniforms [[buffer(1)]]) {
    // Sample texture based on material
    float4 texColor;
    switch (in.materialIndex) {
        case 0: texColor = groundTex.sample(texSampler, in.texCoord); break;
        case 1: texColor = trunkTex.sample(texSampler, in.texCoord); break;
        case 2: texColor = foliageTex.sample(texSampler, in.texCoord); break;
        case 3: texColor = rockTex.sample(texSampler, in.texCoord); break;
        case 4: texColor = poleTex.sample(texSampler, in.texCoord); break;
        case 5: texColor = characterTex.sample(texSampler, in.texCoord); break;
        case 6: texColor = pathTex.sample(texSampler, in.texCoord); break;
        case 7: texColor = stoneWallTex.sample(texSampler, in.texCoord); break;
        case 8: texColor = roofTex.sample(texSampler, in.texCoord); break;
        case 9: texColor = woodPlankTex.sample(texSampler, in.texCoord); break;
        case 10: texColor = skyTex.sample(texSampler, in.texCoord); break;
        default: texColor = float4(1, 0, 1, 1); break;
    }
    
    // Skybox doesn't receive lighting or shadows
    if (in.materialIndex == 10) {
        return texColor;
    }
    
    // Lighting
    float3 normal = normalize(in.normal);
    float3 lightDir = normalize(-uniforms.lightDirection);
    float NdotL = max(dot(normal, lightDir), 0.0);
    
    // Shadow
    float shadow = calculateShadow(in.lightSpacePosition, shadowMap, shadowSampler);
    
    // Final color
    float lighting = uniforms.ambientIntensity + uniforms.diffuseIntensity * NdotL * shadow;
    float3 finalColor = texColor.rgb * lighting;
    
    return float4(finalColor, texColor.a);
}

// Shadow pass vertex shader
vertex float4 vertex_shadow(TexturedVertexIn in [[stage_in]],
                            constant LitUniforms &uniforms [[buffer(1)]]) {
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    return uniforms.lightViewProjectionMatrix * worldPos;
}

fragment void fragment_shadow() {
    // Depth-only pass, no color output
}
"""
