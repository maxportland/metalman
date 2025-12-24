import simd
import Foundation

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
    
    // Sky colors for day/night cycle
    var skyColorTop: simd_float3
    var skyColorHorizon: simd_float3
    var sunColor: simd_float3
    var timeOfDay: Float          // 0-24 hours
    var padding2: simd_float3 = .zero  // Alignment padding
}

// MARK: - Collision Types

/// Type of collision shape
enum ColliderType {
    case circle              // Simple 2D circle (trees, poles)
    case box                 // 2D box for walls (ruins)
    case climbable           // 3D object that can be walked on top of (rocks)
}

/// Collision shape for physics detection
struct Collider {
    var type: ColliderType
    var position: simd_float2  // X, Z position (center)
    var radius: Float          // For circle colliders
    var halfExtents: simd_float2 = .zero  // For box colliders (half width, half depth)
    var rotation: Float = 0    // Y-axis rotation in radians (for boxes)
    var height: Float = 0      // Height of the object (for climbable)
    var baseY: Float = 0       // Base terrain Y position (for climbable)
    
    /// Create a simple circle collider
    static func circle(x: Float, z: Float, radius: Float) -> Collider {
        return Collider(type: .circle, position: simd_float2(x, z), radius: radius)
    }
    
    /// Create a box collider for walls
    static func box(x: Float, z: Float, halfWidth: Float, halfDepth: Float, rotation: Float = 0) -> Collider {
        return Collider(type: .box, position: simd_float2(x, z), radius: 0, 
                       halfExtents: simd_float2(halfWidth, halfDepth), rotation: rotation)
    }
    
    /// Create a climbable collider (can walk on top)
    static func climbable(x: Float, z: Float, radius: Float, height: Float, baseY: Float) -> Collider {
        return Collider(type: .climbable, position: simd_float2(x, z), radius: radius,
                       height: height, baseY: baseY)
    }
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
    case treasureChest = 11
    case enemy = 12  // Red shirt for bandits
}

// MARK: - Interactables

/// Type of interactable object in the world
enum InteractableType {
    case treasureChest
}

/// An interactable object in the world that the player can interact with
struct Interactable: Identifiable {
    let id: UUID
    let type: InteractableType
    var position: simd_float3
    var isOpen: Bool = false
    var interactionRadius: Float = 1.5
    
    // Treasure chest specific
    var goldAmount: Int = 0
    var containedItem: Item? = nil
    
    init(type: InteractableType, position: simd_float3) {
        self.id = UUID()
        self.type = type
        self.position = position
    }
    
    /// Check if player is close enough to interact
    func canInteract(playerPosition: simd_float3) -> Bool {
        guard !isOpen else { return false }
        let dx = playerPosition.x - position.x
        let dz = playerPosition.z - position.z
        let distance = sqrt(dx * dx + dz * dz)
        return distance <= interactionRadius
    }
}

// MARK: - Terrain

/// Terrain height generation using layered noise
struct Terrain {
    /// Shared instance for use by enemy AI
    static let shared = Terrain()
    
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
    
    /// Instance method for enemy AI
    func heightAt(x: Float, z: Float) -> Float {
        Terrain.heightAt(x: x, z: z)
    }
}

