import simd

// MARK: - Vertex Types

/// Simple vertex for wireframe rendering (grid lines)
struct Vertex {
    var position: simd_float3
    var color: simd_float4
}

/// Textured vertex for solid geometry with lighting
struct TexturedVertex {
    var position: simd_float3
    var normal: simd_float3
    var texCoord: simd_float2
    var materialIndex: UInt32  // 0=ground, 1=tree trunk, 2=foliage, 3=rock, 4=pole, 5=character
    var padding: UInt32 = 0
}

// MARK: - Uniform Types

/// Uniforms for lit/textured rendering with shadows
struct LitUniforms {
    var modelMatrix: simd_float4x4
    var viewProjectionMatrix: simd_float4x4
    var lightViewProjectionMatrix: simd_float4x4
    var lightDirection: simd_float3
    var cameraPosition: simd_float3
    var ambientIntensity: Float
    var diffuseIntensity: Float
}

// MARK: - Collision Types

/// Collision circle for simple 2D collision detection (on XZ plane)
struct Collider {
    var position: simd_float2  // X, Z position
    var radius: Float
}

// MARK: - Material Indices

/// Material indices for texture lookup in shaders
enum MaterialIndex: UInt32 {
    case ground = 0
    case treeTrunk = 1
    case foliage = 2
    case rock = 3
    case pole = 4
    case character = 5
}

