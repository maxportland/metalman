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

// Textured lit vertex with tangent for normal mapping
struct TexturedVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float3 tangent [[attribute(2)]];
    float2 texCoord [[attribute(3)]];
    uint materialIndex [[attribute(4)]];
};

struct LitVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float3 tangent;
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
    
    // Sky colors for day/night cycle
    float3 skyColorTop;
    float3 skyColorHorizon;
    float3 sunColor;
    float timeOfDay;          // 0-24 hours
    
    // Point lights (lanterns on poles) - xyz = position, w = intensity
    float4 pointLight0;
    float4 pointLight1;
    float4 pointLight2;
    float4 pointLight3;
    float4 pointLight4;
    float4 pointLight5;
    float4 pointLight6;
    float4 pointLight7;
    int pointLightCount;
    float3 padding2;          // Alignment padding
    
    // Screen-space occlusion mask (for trees/occluders)
    float2 playerScreenPos;    // Player's screen-space position (0-1, with (0,0) at top-left)
    float2 viewportSize;       // Viewport size in pixels (width, height)
    float occlusionRadius;    // Radius of the circular mask in screen pixels
    float occlusionSoftness;  // Softness of the gradient edge (0-1, higher = softer)
};

vertex LitVertexOut vertex_lit(TexturedVertexIn in [[stage_in]],
                               constant LitUniforms &uniforms [[buffer(1)]]) {
    LitVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPos.xyz;
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.normal = normalize((uniforms.modelMatrix * float4(in.normal, 0.0)).xyz);
    out.tangent = normalize((uniforms.modelMatrix * float4(in.tangent, 0.0)).xyz);
    out.texCoord = in.texCoord;
    out.lightSpacePosition = uniforms.lightViewProjectionMatrix * worldPos;
    out.materialIndex = in.materialIndex;
    return out;
}

// Instanced vertex shader for trees and other repeated objects
// Uses per-instance model matrices from buffer(2)
vertex LitVertexOut vertex_lit_instanced(TexturedVertexIn in [[stage_in]],
                                         constant LitUniforms &uniforms [[buffer(1)]],
                                         constant float4x4 *instanceMatrices [[buffer(2)]],
                                         uint instanceId [[instance_id]]) {
    LitVertexOut out;
    float4x4 modelMatrix = instanceMatrices[instanceId];
    float4 worldPos = modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPos.xyz;
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.normal = normalize((modelMatrix * float4(in.normal, 0.0)).xyz);
    out.tangent = normalize((modelMatrix * float4(in.tangent, 0.0)).xyz);
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
                             texture2d<float> groundNormalMap [[texture(12)]],
                             texture2d<float> trunkNormalMap [[texture(13)]],
                             texture2d<float> rockNormalMap [[texture(14)]],
                             texture2d<float> pathNormalMap [[texture(15)]],
                             texture2d<float> treasureChestTex [[texture(16)]],
                             texture2d<float> enemyTex [[texture(17)]],
                             texture2d<float> vendorTex [[texture(18)]],
                             texture2d<float> cabinTex [[texture(19)]],
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
        case 11: texColor = treasureChestTex.sample(texSampler, in.texCoord); break;
        case 12: texColor = enemyTex.sample(texSampler, in.texCoord); break;
        case 13: texColor = vendorTex.sample(texSampler, in.texCoord); break;
        case 14: texColor = cabinTex.sample(texSampler, in.texCoord); break;
        default: texColor = float4(1, 0, 1, 1); break;
    }
    
    // Skybox - dynamic sky colors with stars at night
    if (in.materialIndex == 10) {
        // Calculate sky gradient based on vertical position
        float3 viewDir = normalize(in.worldPosition - uniforms.cameraPosition);
        float heightFactor = viewDir.y * 0.5 + 0.5; // 0 at horizon, 1 at zenith
        heightFactor = clamp(heightFactor, 0.0, 1.0);
        
        // Interpolate between horizon and top colors
        float3 skyColor = mix(uniforms.skyColorHorizon, uniforms.skyColorTop, heightFactor);
        
        // Add sun/moon glow near light direction
        float3 lightDir = normalize(-uniforms.lightDirection);
        float sunAlignment = dot(viewDir, lightDir);
        if (sunAlignment > 0.0) {
            // Sun disc
            float sunDisc = smoothstep(0.995, 0.999, sunAlignment);
            skyColor = mix(skyColor, uniforms.sunColor, sunDisc);
            
            // Sun glow/halo
            float sunGlow = pow(max(0.0, sunAlignment), 8.0) * 0.3;
            skyColor += uniforms.sunColor * sunGlow;
        }
        
        // Add stars at night (when sun intensity is low)
        float nightFactor = 1.0 - smoothstep(5.0, 7.0, uniforms.timeOfDay) + smoothstep(18.0, 20.0, uniforms.timeOfDay);
        nightFactor = clamp(nightFactor, 0.0, 1.0);
        
        if (nightFactor > 0.1) {
            // Procedural stars using noise
            float2 starUV = in.texCoord * 200.0;
            float starNoise = fract(sin(dot(floor(starUV), float2(12.9898, 78.233))) * 43758.5453);
            
            // Only show some as stars (threshold)
            if (starNoise > 0.98) {
                // Twinkle effect based on time
                float twinkle = sin(uniforms.timeOfDay * 50.0 + starNoise * 100.0) * 0.5 + 0.5;
                float starBrightness = (starNoise - 0.98) * 50.0 * (0.5 + twinkle * 0.5);
                starBrightness *= nightFactor * heightFactor; // Fade near horizon
                skyColor += float3(starBrightness);
            }
            
            // Add moon (opposite side from sun at night)
            if (uniforms.timeOfDay < 6.0 || uniforms.timeOfDay > 18.0) {
                float3 moonDir = normalize(float3(-lightDir.x, abs(lightDir.y), -lightDir.z));
                float moonAlignment = dot(viewDir, moonDir);
                if (moonAlignment > 0.99) {
                    float moonDisc = smoothstep(0.99, 0.995, moonAlignment);
                    skyColor = mix(skyColor, float3(0.9, 0.92, 1.0), moonDisc * nightFactor);
                }
                // Moon glow
                float moonGlow = pow(max(0.0, moonAlignment), 16.0) * 0.15 * nightFactor;
                skyColor += float3(0.6, 0.65, 0.8) * moonGlow;
            }
        }
        
        // Add some clouds (from procedural texture, modulated)
        float4 cloudTex = skyTex.sample(texSampler, in.texCoord);
        float cloudAmount = cloudTex.r * 0.3 * (1.0 - nightFactor * 0.7); // Less visible at night
        skyColor = mix(skyColor, float3(1.0), cloudAmount * heightFactor);
        
        return float4(skyColor, 1.0);
    }
    
    // Build TBN (Tangent-Bitangent-Normal) matrix for normal mapping
    float3 N = normalize(in.normal);
    float3 T = normalize(in.tangent);
    // Re-orthogonalize T with respect to N
    T = normalize(T - dot(T, N) * N);
    float3 B = cross(N, T);
    float3x3 TBN = float3x3(T, B, N);
    
    // Sample normal map based on material
    float3 sampledNormal = float3(0.0, 0.0, 1.0); // Default: straight up in tangent space
    switch (in.materialIndex) {
        case 0: // Ground
            sampledNormal = groundNormalMap.sample(texSampler, in.texCoord).rgb;
            break;
        case 1: // Tree trunk
            sampledNormal = trunkNormalMap.sample(texSampler, in.texCoord).rgb;
            break;
        case 3: // Rock
            sampledNormal = rockNormalMap.sample(texSampler, in.texCoord).rgb;
            break;
        case 6: // Path
            sampledNormal = pathNormalMap.sample(texSampler, in.texCoord).rgb;
            break;
        default:
            // Use flat normal for materials without normal maps
            sampledNormal = float3(0.5, 0.5, 1.0);
            break;
    }
    
    // Convert from [0,1] to [-1,1] range
    sampledNormal = sampledNormal * 2.0 - 1.0;
    
    // Transform normal from tangent space to world space
    float3 normal = normalize(TBN * sampledNormal);
    
    // Lighting
    float3 lightDir = normalize(-uniforms.lightDirection);
    float NdotL = max(dot(normal, lightDir), 0.0);
    
    // Shadow
    float shadow = calculateShadow(in.lightSpacePosition, shadowMap, shadowSampler);
    
    // Base lighting from sun/moon
    float lighting = uniforms.ambientIntensity + uniforms.diffuseIntensity * NdotL * shadow;
    
    // Character-specific lighting boost (material 5 = player, 12 = enemy, 13 = vendor)
    bool isCharacter = (in.materialIndex == 5 || in.materialIndex == 12 || in.materialIndex == 13);
    if (isCharacter) {
        // Boost ambient for characters to make them more visible
        float characterAmbientBoost = 0.50;
        lighting += characterAmbientBoost;
        
        // Add rim lighting (Fresnel effect) for character pop
        float3 viewDir = normalize(uniforms.cameraPosition - in.worldPosition);
        float fresnel = 1.0 - max(dot(normal, viewDir), 0.0);
        fresnel = pow(fresnel, 3.0);  // Sharpen the rim
        float rimIntensity = 0.45;
        lighting += fresnel * rimIntensity;
    }
    
    // Point lights contribution (lanterns)
    float3 pointLightContrib = float3(0.0);
    float3 worldPos = in.worldPosition;
    // Reuse 'normal' calculated above from TBN matrix
    
    // Warm lantern color (orange/yellow glow)
    float3 lanternColor = float3(1.0, 0.7, 0.3);
    
    // Calculate contribution from each active point light
    float4 pointLights[8] = {
        uniforms.pointLight0, uniforms.pointLight1, uniforms.pointLight2, uniforms.pointLight3,
        uniforms.pointLight4, uniforms.pointLight5, uniforms.pointLight6, uniforms.pointLight7
    };
    
    for (int i = 0; i < uniforms.pointLightCount && i < 8; i++) {
        float3 lightPos = pointLights[i].xyz;
        float intensity = pointLights[i].w;
        
        float3 toLight = lightPos - worldPos;
        float dist = length(toLight);
        float3 lightDir = toLight / dist;
        
        // Attenuation (inverse square with cutoff)
        float radius = 15.0;  // Light radius
        float attenuation = saturate(1.0 - dist / radius);
        attenuation *= attenuation;  // Quadratic falloff
        
        // Diffuse contribution
        float NdotL_point = max(dot(normal, lightDir), 0.0);
        
        pointLightContrib += lanternColor * intensity * attenuation * NdotL_point;
    }
    
    // Darken cabin (material 14) by 50%
    if (in.materialIndex == 14) {
        lighting *= 0.5;
    }
    
    float3 finalColor = texColor.rgb * lighting + texColor.rgb * pointLightContrib;
    float finalAlpha = texColor.a;
    
    // Screen-space circular occlusion mask for trees (materials 1 = trunk, 2 = foliage)
    // This creates a soft circular gradient that fades out occluders near the player's screen position
    bool isOccluder = (in.materialIndex == 1 || in.materialIndex == 2);
    if (isOccluder && uniforms.occlusionRadius > 0.0) {
        // Get current fragment's screen-space position
        // in.position.xy is already in screen space (pixels), with (0,0) at top-left
        float2 fragScreenPos = in.position.xy;
        
        // Calculate distance from player's screen position to current fragment (in pixels)
        float2 playerScreenPosPixels = uniforms.playerScreenPos * uniforms.viewportSize;
        float distToPlayer = length(fragScreenPos - playerScreenPosPixels);
        
        // Calculate mask alpha using smoothstep for soft circular gradient
        // occlusionSoftness controls the gradient width (0 = hard edge, 1 = very soft)
        float softEdgeWidth = uniforms.occlusionRadius * uniforms.occlusionSoftness;
        float maskAlpha = smoothstep(uniforms.occlusionRadius, uniforms.occlusionRadius - softEdgeWidth, distToPlayer);
        
        // Apply mask to alpha (higher maskAlpha = more transparent)
        finalAlpha *= (1.0 - maskAlpha);
        
        // Ordered dithering for alpha clipping (Bayer 4x4 matrix)
        // This avoids depth-sorting artifacts by using alpha-to-coverage style dithering
        int2 screenCoord = int2(fmod(fragScreenPos, 4.0));
        // Bayer 4x4 matrix as 1D array (row-major order)
        const float bayerMatrix[16] = {
            0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
            12.0/16.0, 4.0/16.0, 14.0/16.0,  6.0/16.0,
            3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
            15.0/16.0, 7.0/16.0, 13.0/16.0,  5.0/16.0
        };
        int bayerIndex = screenCoord.y * 4 + screenCoord.x;
        float ditherThreshold = bayerMatrix[bayerIndex];
        
        // Alpha clip: if alpha is below dither threshold, discard the fragment
        // This creates a dithered transparency effect
        if (finalAlpha < ditherThreshold) {
            discard_fragment();
        }
    }
    
    return float4(finalColor, finalAlpha);
}

// Shadow pass vertex shader
vertex float4 vertex_shadow(TexturedVertexIn in [[stage_in]],
                            constant LitUniforms &uniforms [[buffer(1)]]) {
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    return uniforms.lightViewProjectionMatrix * worldPos;
}

// Instanced shadow pass vertex shader for trees
vertex float4 vertex_shadow_instanced(TexturedVertexIn in [[stage_in]],
                                      constant LitUniforms &uniforms [[buffer(1)]],
                                      constant float4x4 *instanceMatrices [[buffer(2)]],
                                      uint instanceId [[instance_id]]) {
    float4x4 modelMatrix = instanceMatrices[instanceId];
    float4 worldPos = modelMatrix * float4(in.position, 1.0);
    return uniforms.lightViewProjectionMatrix * worldPos;
}

fragment void fragment_shadow() {
    // Depth-only pass, no color output
}

// ====================================================================
// SKELETAL ANIMATION SHADERS
// ====================================================================

// Maximum bones per skeletal mesh
constant int MAX_BONES = 128;

// Skinned vertex input with bone weights
struct SkinnedVertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
    uint4 boneIndices [[attribute(3)]];
    float4 boneWeights [[attribute(4)]];
    uint materialIndex [[attribute(5)]];
};

// Uniforms for skeletal animation
struct SkinnedUniforms {
    float4x4 modelMatrix;
    float4x4 viewProjectionMatrix;
    float4x4 lightViewProjectionMatrix;
    float3 lightDirection;
    float padding1;
    float3 cameraPosition;
    float padding2;
    float ambientIntensity;
    float diffuseIntensity;
    float2 padding3;
    
    // Sky colors (for consistency with LitUniforms)
    float3 skyColorTop;
    float padding4;
    float3 skyColorHorizon;
    float padding5;
    float3 sunColor;
    float timeOfDay;
    
    // Point lights
    float4 pointLight0;
    float4 pointLight1;
    float4 pointLight2;
    float4 pointLight3;
    float4 pointLight4;
    float4 pointLight5;
    float4 pointLight6;
    float4 pointLight7;
    int pointLightCount;
    float3 padding6;
    
    // UV adjustments (edit mode)
    float2 uvOffset;
    float uvScale;
    int flipUVVertical;  // 0 = normal, 1 = flip V coordinate
};

// Skinned vertex shader - applies bone transforms to vertices
vertex LitVertexOut vertex_skinned(SkinnedVertexIn in [[stage_in]],
                                   constant SkinnedUniforms &uniforms [[buffer(1)]],
                                   constant float4x4 *boneMatrices [[buffer(2)]]) {
    LitVertexOut out;
    
    // Get bone transforms
    float4x4 bone0 = boneMatrices[in.boneIndices.x];
    float4x4 bone1 = boneMatrices[in.boneIndices.y];
    float4x4 bone2 = boneMatrices[in.boneIndices.z];
    float4x4 bone3 = boneMatrices[in.boneIndices.w];
    
    // Blend position using bone weights
    float4 pos = float4(in.position, 1.0);
    float4 skinnedPos = bone0 * pos * in.boneWeights.x +
                        bone1 * pos * in.boneWeights.y +
                        bone2 * pos * in.boneWeights.z +
                        bone3 * pos * in.boneWeights.w;
    
    // Blend normal using bone weights (no translation, just rotation)
    float3 norm = in.normal;
    float3 skinnedNorm = (bone0 * float4(norm, 0.0) * in.boneWeights.x +
                          bone1 * float4(norm, 0.0) * in.boneWeights.y +
                          bone2 * float4(norm, 0.0) * in.boneWeights.z +
                          bone3 * float4(norm, 0.0) * in.boneWeights.w).xyz;
    
    // Transform to world space
    float4 worldPos = uniforms.modelMatrix * skinnedPos;
    out.worldPosition = worldPos.xyz;
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.normal = normalize((uniforms.modelMatrix * float4(skinnedNorm, 0.0)).xyz);
    out.tangent = float3(1, 0, 0); // Generate tangent from normal
    
    // Apply UV adjustments from edit mode
    float2 baseTexCoord = in.texCoord;
    
    // Optionally flip V coordinate (common fix for format differences)
    if (uniforms.flipUVVertical != 0) {
        baseTexCoord.y = 1.0 - baseTexCoord.y;
    }
    
    float2 adjustedTexCoord = baseTexCoord * uniforms.uvScale + uniforms.uvOffset;
    out.texCoord = adjustedTexCoord;
    
    out.lightSpacePosition = uniforms.lightViewProjectionMatrix * worldPos;
    out.materialIndex = in.materialIndex;
    
    return out;
}

// Shadow pass for skinned meshes
vertex float4 vertex_skinned_shadow(SkinnedVertexIn in [[stage_in]],
                                    constant SkinnedUniforms &uniforms [[buffer(1)]],
                                    constant float4x4 *boneMatrices [[buffer(2)]]) {
    // Get bone transforms
    float4x4 bone0 = boneMatrices[in.boneIndices.x];
    float4x4 bone1 = boneMatrices[in.boneIndices.y];
    float4x4 bone2 = boneMatrices[in.boneIndices.z];
    float4x4 bone3 = boneMatrices[in.boneIndices.w];
    
    // Blend position using bone weights
    float4 pos = float4(in.position, 1.0);
    float4 skinnedPos = bone0 * pos * in.boneWeights.x +
                        bone1 * pos * in.boneWeights.y +
                        bone2 * pos * in.boneWeights.z +
                        bone3 * pos * in.boneWeights.w;
    
    float4 worldPos = uniforms.modelMatrix * skinnedPos;
    return uniforms.lightViewProjectionMatrix * worldPos;
}
"""
