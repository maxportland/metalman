//
//  AnimatedCharacter.swift
//  MetalMan
//
//  Manages an animated skeletal character with state-based animation
//

import Metal
import MetalKit
import simd

// MARK: - Character Animation State

/// Represents the current animation state of a character
enum CharacterAnimationState {
    case idle
    case walking
    case running
    case attacking
    case blocking
    case jumping
    case dying
    case dead
    case impact  // Hit reaction
    
    /// The animation file name (without extension) for this state
    var animationName: String {
        switch self {
        case .idle: return "sword-and-shield-idle"
        case .walking: return "sword-and-shield-walk"
        case .running: return "sword-and-shield-run"
        case .attacking: return "sword-and-shield-slash"
        case .blocking: return "sword-and-shield-block"
        case .jumping: return "sword-and-shield-jump"
        case .dying: return "sword-and-shield-death"
        case .dead: return "sword-and-shield-death"
        case .impact: return "sword-and-shield-impact"
        }
    }
    
    /// Fallback animation names if primary isn't found
    var fallbackNames: [String] {
        switch self {
        case .idle: return ["sword-and-shield-idle-2", "sword-and-shield-idle-3", "idle", "walk"]
        case .walking: return ["sword-and-shield-walk-2", "walk", "sword-and-shield-run"]
        case .running: return ["sword-and-shield-run-2", "run", "sword-and-shield-walk"]
        case .attacking: return ["sword-and-shield-slash-2", "sword-and-shield-attack", "attack"]
        case .blocking: return ["sword-and-shield-block-2", "sword-and-shield-block-idle", "block"]
        case .jumping: return ["sword-and-shield-jump-2", "jump"]
        case .dying: return ["sword-and-shield-death-2", "die", "death"]
        case .dead: return ["sword-and-shield-death-2", "dead", "death"]
        case .impact: return ["sword-and-shield-impact-2", "sword-and-shield-impact-3", "hit"]
        }
    }
    
    var isLooping: Bool {
        switch self {
        case .idle, .walking, .running, .blocking: return true
        case .attacking, .jumping, .dying, .dead, .impact: return false
        }
    }
}

// MARK: - Animated Character

/// Represents an animated character that can be rendered and animated
final class AnimatedCharacter {
    
    // MARK: - Properties
    
    /// The skeletal mesh containing geometry and bones
    let mesh: SkeletalMesh
    
    /// Current animation state
    private(set) var animationState: CharacterAnimationState = .idle
    
    /// Current animation time
    private var animationTime: Float = 0
    
    /// Speed multiplier for animations
    var animationSpeed: Float = 1.0
    
    /// Blend factor for transitioning between animations (0-1)
    private var blendFactor: Float = 1.0
    private var previousBoneTransforms: [simd_float4x4] = []
    
    /// Whether this character has a shield equipped
    var hasShieldEquipped: Bool = false
    
    /// Device reference for creating buffers
    private let device: MTLDevice
    
    /// Uniform buffer for rendering
    let uniformBuffer: MTLBuffer
    
    /// The vertex descriptor for skinned vertices (packed layout - no SIMD padding)
    static var vertexDescriptor: MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        
        // Position (float3) - 12 bytes
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        
        // Normal (float3) - 12 bytes
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = 12
        descriptor.attributes[1].bufferIndex = 0
        
        // TexCoord (float2) - 8 bytes
        descriptor.attributes[2].format = .float2
        descriptor.attributes[2].offset = 24
        descriptor.attributes[2].bufferIndex = 0
        
        // Bone indices (uint4) - 16 bytes
        descriptor.attributes[3].format = .uint4
        descriptor.attributes[3].offset = 32
        descriptor.attributes[3].bufferIndex = 0
        
        // Bone weights (float4) - 16 bytes
        descriptor.attributes[4].format = .float4
        descriptor.attributes[4].offset = 48
        descriptor.attributes[4].bufferIndex = 0
        
        // Material index (uint) - 4 bytes
        descriptor.attributes[5].format = .uint
        descriptor.attributes[5].offset = 64
        descriptor.attributes[5].bufferIndex = 0
        
        // Layout - total stride should be 72 bytes (including 4 bytes padding)
        descriptor.layouts[0].stride = SkinnedVertex.stride
        descriptor.layouts[0].stepRate = 1
        descriptor.layouts[0].stepFunction = .perVertex
        
        return descriptor
    }
    
    // MARK: - Initialization
    
    init(device: MTLDevice, mesh: SkeletalMesh) {
        self.device = device
        self.mesh = mesh
        
        // Create uniform buffer
        self.uniformBuffer = device.makeBuffer(
            length: MemoryLayout<SkinnedUniforms>.stride,
            options: .storageModeShared
        )!
        
        // Initialize bone transforms
        self.previousBoneTransforms = Array(repeating: matrix_identity_float4x4, count: mesh.bones.count)
        
        // Log bone information for combat debugging
        print("[AnimatedCharacter] Created with \(mesh.bones.count) bones")
        if let handBone = findRightHandBoneIndex() {
            let boneName = mesh.bones[handBone].name
            print("[AnimatedCharacter] Found right hand bone: '\(boneName)' at index \(handBone)")
        } else {
            print("[AnimatedCharacter] WARNING: No right hand bone found! Available bones:")
            for bone in mesh.bones.prefix(20) {
                print("[AnimatedCharacter]   - \(bone.name)")
            }
        }
    }
    
    // MARK: - Animation Control
    
    /// Change to a new animation state
    func setAnimationState(_ newState: CharacterAnimationState, resetTime: Bool = true) {
        if newState != animationState {
            // Store previous transforms for blending
            if let currentTransforms = getCurrentBoneTransforms() {
                previousBoneTransforms = currentTransforms
            }
            blendFactor = 0  // Start blend
            
            animationState = newState
            if resetTime {
                animationTime = 0
            }
        }
    }
    
    /// Update the animation based on elapsed time
    func update(deltaTime: Float) {
        animationTime += deltaTime * animationSpeed
        
        // Update blend factor
        if blendFactor < 1.0 {
            blendFactor = min(1.0, blendFactor + deltaTime * 5.0)  // Blend over ~0.2 seconds
        }
        
        // Get current animation transforms
        if let transforms = getCurrentBoneTransforms() {
            // Blend with previous transforms if transitioning
            let finalTransforms: [simd_float4x4]
            if blendFactor < 1.0 && previousBoneTransforms.count == transforms.count {
                finalTransforms = zip(previousBoneTransforms, transforms).map { prev, curr in
                    lerpMatrix(prev, curr, t: blendFactor)
                }
            } else {
                finalTransforms = transforms
            }
            
            mesh.updateBoneMatrices(finalTransforms)
        }
    }
    
    /// Get the current bone transforms from the active animation
    private func getCurrentBoneTransforms() -> [simd_float4x4]? {
        let boneCount = mesh.bones.count
        
        // Try primary animation name
        if let animation = mesh.animations[animationState.animationName] {
            return animation.getBoneTransforms(at: animationTime, boneCount: boneCount)
        }
        
        // Try fallback names
        for fallbackName in animationState.fallbackNames {
            if let animation = mesh.animations[fallbackName] {
                return animation.getBoneTransforms(at: animationTime, boneCount: boneCount)
            }
        }
        
        // Last resort: use any available animation (for debugging)
        if let firstAnim = mesh.animations.values.first {
            return firstAnim.getBoneTransforms(at: animationTime, boneCount: boneCount)
        }
        
        return nil
    }
    
    /// Check if the current animation has completed (for non-looping animations)
    var isAnimationComplete: Bool {
        guard !animationState.isLooping else { return false }
        
        let animName = animationState.animationName
        if let animation = mesh.animations[animName] {
            return animationTime >= animation.duration
        }
        return true
    }
    
    /// Get the current animation frame number (0-based)
    /// Returns nil if animation not found
    var currentAnimationFrame: Int? {
        let animName = animationState.animationName
        
        // Try primary animation
        if let animation = mesh.animations[animName], !animation.keyframes.isEmpty {
            let frameCount = animation.keyframes.count
            let normalizedTime = animationTime / max(animation.duration, 0.001)
            let frame = Int(normalizedTime * Float(frameCount))
            return min(frame, frameCount - 1)
        }
        
        // Try fallback names
        for fallbackName in animationState.fallbackNames {
            if let animation = mesh.animations[fallbackName], !animation.keyframes.isEmpty {
                let frameCount = animation.keyframes.count
                let normalizedTime = animationTime / max(animation.duration, 0.001)
                let frame = Int(normalizedTime * Float(frameCount))
                return min(frame, frameCount - 1)
            }
        }
        
        return nil
    }
    
    /// Check if we've reached or passed a specific frame in the current animation
    func hasReachedFrame(_ targetFrame: Int) -> Bool {
        guard let currentFrame = currentAnimationFrame else { return false }
        return currentFrame >= targetFrame
    }
    
    // MARK: - Sword Collision
    
    /// Names of bones that could be the right hand (sword hand)
    /// Listed in order of preference - will also try partial matching
    private static let rightHandBoneNames = [
        "RightHand", "mixamorig:RightHand", "mixamorig_RightHand",
        "Right_Hand", "hand.R", "Hand_R", "RightHandX",
        "RightForeArm", "mixamorig:RightForeArm", "RightArm"
    ]
    
    /// Find the right hand bone index, using partial matching if exact match fails
    private func findRightHandBoneIndex() -> Int? {
        // First try exact matches
        for boneName in Self.rightHandBoneNames {
            if let index = mesh.boneNameToIndex[boneName] {
                return index
            }
        }
        
        // Try partial matching (case insensitive)
        for (name, index) in mesh.boneNameToIndex {
            let lowered = name.lowercased()
            if lowered.contains("righthand") || lowered.contains("right_hand") ||
               (lowered.contains("right") && lowered.contains("hand")) {
                return index
            }
        }
        
        // Try any hand bone
        for (name, index) in mesh.boneNameToIndex {
            let lowered = name.lowercased()
            if lowered.contains("hand") && !lowered.contains("left") {
                return index
            }
        }
        
        // Last resort: try right arm/forearm
        for (name, index) in mesh.boneNameToIndex {
            let lowered = name.lowercased()
            if (lowered.contains("rightforearm") || lowered.contains("right_forearm") ||
                lowered.contains("rightarm")) {
                return index
            }
        }
        
        return nil
    }
    
    /// Get the world-space position of the sword tip for collision detection
    /// Returns nil if no sword bone can be found
    func getSwordTipWorldPosition(playerModelMatrix: simd_float4x4) -> simd_float3? {
        guard let boneIndex = findRightHandBoneIndex() else {
            return nil
        }
        
        // Get the bone's current transform from the bone matrix buffer
        let boneMatrixPtr = mesh.boneMatrixBuffer.contents().assumingMemoryBound(to: simd_float4x4.self)
        let boneMatrix = boneMatrixPtr[boneIndex]
        
        // The sword extends from the hand. Estimate sword tip offset (in local bone space)
        // Sword is roughly 1.0-1.2 meters long - try multiple directions
        let swordLength: Float = 1.2
        
        // Try different sword orientations (different models have different hand orientations)
        // Primary: sword extends in local Y (common for Mixamo)
        let swordTipLocal = simd_float4(0, swordLength, 0, 1)
        
        // Transform through bone matrix (in model space)
        let swordTipModel = boneMatrix * swordTipLocal
        
        // Transform through player model matrix (to world space)
        let swordTipWorld = playerModelMatrix * swordTipModel
        
        return simd_float3(swordTipWorld.x, swordTipWorld.y, swordTipWorld.z)
    }
    
    /// Get the world-space position of the sword base (hand position) for collision detection
    func getSwordBaseWorldPosition(playerModelMatrix: simd_float4x4) -> simd_float3? {
        guard let boneIndex = findRightHandBoneIndex() else {
            return nil
        }
        
        // Get the bone's current transform
        let boneMatrixPtr = mesh.boneMatrixBuffer.contents().assumingMemoryBound(to: simd_float4x4.self)
        let boneMatrix = boneMatrixPtr[boneIndex]
        
        // Hand position (origin of sword)
        let handLocal = simd_float4(0, 0, 0, 1)
        let handModel = boneMatrix * handLocal
        let handWorld = playerModelMatrix * handModel
        
        return simd_float3(handWorld.x, handWorld.y, handWorld.z)
    }
    
    // MARK: - Rendering
    
    /// Draw the animated character with optional equipment visibility control
    func draw(encoder: MTLRenderCommandEncoder,
              modelMatrix: simd_float4x4,
              viewProjectionMatrix: simd_float4x4,
              lightViewProjectionMatrix: simd_float4x4,
              lightDirection: simd_float3,
              cameraPosition: simd_float3,
              ambientIntensity: Float,
              diffuseIntensity: Float,
              timeOfDay: Float,
              pointLights: [PointLight],
              showShield: Bool = true,
              showWeapon: Bool = true,
              uvOffset: simd_float2 = .zero,
              uvScale: Float = 1.0,
              flipUVVertical: Bool = false) {
        
        // Update uniforms (matches SkinnedUniforms structure in shader)
        var uniforms = SkinnedUniforms()
        uniforms.modelMatrix = modelMatrix
        uniforms.viewProjectionMatrix = viewProjectionMatrix
        uniforms.lightViewProjectionMatrix = lightViewProjectionMatrix
        uniforms.lightDirection = lightDirection
        uniforms.cameraPosition = cameraPosition
        uniforms.ambientIntensity = ambientIntensity
        uniforms.uvOffset = uvOffset
        uniforms.uvScale = uvScale
        uniforms.flipUVVertical = flipUVVertical ? 1 : 0
        uniforms.diffuseIntensity = diffuseIntensity
        uniforms.timeOfDay = timeOfDay
        
        // Set point lights
        uniforms.pointLightCount = Int32(min(8, pointLights.count))
        for (i, light) in pointLights.prefix(8).enumerated() {
            let lightData = simd_float4(light.position.x, light.position.y, light.position.z, light.intensity)
            switch i {
            case 0: uniforms.pointLight0 = lightData
            case 1: uniforms.pointLight1 = lightData
            case 2: uniforms.pointLight2 = lightData
            case 3: uniforms.pointLight3 = lightData
            case 4: uniforms.pointLight4 = lightData
            case 5: uniforms.pointLight5 = lightData
            case 6: uniforms.pointLight6 = lightData
            case 7: uniforms.pointLight7 = lightData
            default: break
            }
        }
        
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<SkinnedUniforms>.stride)
        
        // Set buffers
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(mesh.boneMatrixBuffer, offset: 0, index: 2)
        
        // Draw using submesh ranges for selective equipment rendering
        let drawRanges = mesh.getDrawRanges(showShield: showShield, showWeapon: showWeapon)
        for range in drawRanges {
            encoder.drawPrimitives(type: .triangle, vertexStart: range.start, vertexCount: range.count)
        }
    }
}

// MARK: - Skinned Uniforms

/// Uniforms structure for skinned character rendering (matches shader)
struct SkinnedUniforms {
    var modelMatrix: simd_float4x4 = matrix_identity_float4x4
    var viewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4
    var lightViewProjectionMatrix: simd_float4x4 = matrix_identity_float4x4
    var lightDirection: simd_float3 = simd_float3(0, -1, 0)
    var padding1: Float = 0
    var cameraPosition: simd_float3 = .zero
    var padding2: Float = 0
    var ambientIntensity: Float = 0.3
    var diffuseIntensity: Float = 0.7
    var padding3: simd_float2 = .zero
    
    // Sky colors
    var skyColorTop: simd_float3 = simd_float3(0.3, 0.5, 0.9)
    var padding4: Float = 0
    var skyColorHorizon: simd_float3 = simd_float3(0.7, 0.8, 0.95)
    var padding5: Float = 0
    var sunColor: simd_float3 = simd_float3(1, 1, 0.8)
    var timeOfDay: Float = 12
    
    // Point lights
    var pointLight0: simd_float4 = .zero
    var pointLight1: simd_float4 = .zero
    var pointLight2: simd_float4 = .zero
    var pointLight3: simd_float4 = .zero
    var pointLight4: simd_float4 = .zero
    var pointLight5: simd_float4 = .zero
    var pointLight6: simd_float4 = .zero
    var pointLight7: simd_float4 = .zero
    var pointLightCount: Int32 = 0
    var padding6: simd_float3 = .zero
    
    // UV adjustments (edit mode)
    var uvOffset: simd_float2 = .zero
    var uvScale: Float = 1.0
    var flipUVVertical: Int32 = 0  // Bool as int for Metal
}

// MARK: - Helper

/// Linear interpolation between two matrices
private func lerpMatrix(_ a: simd_float4x4, _ b: simd_float4x4, t: Float) -> simd_float4x4 {
    return simd_float4x4(
        simd_mix(a.columns.0, b.columns.0, simd_float4(repeating: t)),
        simd_mix(a.columns.1, b.columns.1, simd_float4(repeating: t)),
        simd_mix(a.columns.2, b.columns.2, simd_float4(repeating: t)),
        simd_mix(a.columns.3, b.columns.3, simd_float4(repeating: t))
    )
}


