import simd

// MARK: - Vertex Types

/// Simple vertex for wireframe rendering (grid lines)
struct Vertex {
    var position: simd_float3
    var color: simd_float4
}

/// Textured vertex for solid geometry with lighting and normal mapping
struct TexturedVertex {
    var position: simd_float3
    var normal: simd_float3
    var tangent: simd_float3      // For normal mapping (tangent space)
    var texCoord: simd_float2
    var materialIndex: UInt32     // 0=ground, 1=tree trunk, 2=foliage, 3=rock, 4=pole, 5=character
    var padding: UInt32 = 0
    
    /// Initialize with automatic tangent computation from normal
    init(position: simd_float3, normal: simd_float3, texCoord: simd_float2, materialIndex: UInt32) {
        self.position = position
        self.normal = normal
        self.texCoord = texCoord
        self.materialIndex = materialIndex
        self.padding = 0
        
        // Compute tangent perpendicular to normal, pointing along texture U axis
        var t = simd_float3(1, 0, 0)
        if abs(simd_dot(normal, t)) > 0.9 {
            t = simd_float3(0, 0, 1)
        }
        self.tangent = simd_normalize(t - simd_dot(t, normal) * normal)
    }
    
    /// Initialize with explicit tangent
    init(position: simd_float3, normal: simd_float3, tangent: simd_float3, texCoord: simd_float2, materialIndex: UInt32) {
        self.position = position
        self.normal = normal
        self.tangent = tangent
        self.texCoord = texCoord
        self.materialIndex = materialIndex
        self.padding = 0
    }
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
    case path = 6
    case stoneWall = 7
    case roof = 8
    case woodPlank = 9
    case sky = 10
}

// MARK: - Terrain

/// Terrain height generation using layered noise
struct Terrain {
    /// Get terrain height at world position (x, z)
    static func heightAt(x: Float, z: Float) -> Float {
        // Layered noise for natural-looking hills
        var height: Float = 0
        
        // Large rolling hills
        height += sin(x * 0.02) * cos(z * 0.025) * 3.0
        height += sin(x * 0.015 + 1.0) * sin(z * 0.018 + 0.5) * 2.0
        
        // Medium undulations
        height += sin(x * 0.05 + 2.0) * cos(z * 0.06) * 1.0
        height += cos(x * 0.07) * sin(z * 0.055 + 1.5) * 0.8
        
        // Small bumps
        height += sin(x * 0.15) * cos(z * 0.12) * 0.3
        
        // Flatten center area for player spawn
        let distFromCenter = sqrt(x * x + z * z)
        let flattenFactor = max(0, 1 - distFromCenter / 15.0)
        height *= (1 - flattenFactor * 0.8)
        
        return height
    }
    
    /// Get terrain normal at world position
    static func normalAt(x: Float, z: Float) -> simd_float3 {
        let eps: Float = 0.5
        let hL = heightAt(x: x - eps, z: z)
        let hR = heightAt(x: x + eps, z: z)
        let hD = heightAt(x: x, z: z - eps)
        let hU = heightAt(x: x, z: z + eps)
        
        let normal = simd_float3(hL - hR, 2.0 * eps, hD - hU)
        return simd_normalize(normal)
    }
}

