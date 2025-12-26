//
//  AnimatedEnemy.swift
//  MetalMan
//
//  Skeletal animation for enemy characters using the mutant/castle guard model
//

import Metal
import MetalKit
import simd

// MARK: - Enemy Animation State

/// Represents the current animation state of an enemy
enum EnemyAnimationState {
    case idle
    case walking
    case running
    case attacking
    case hurt
    case dying
    case dead
    case roaring      // Spotting player / aggro
    
    /// The animation file name (without extension) for this state
    var animationName: String {
        switch self {
        case .idle: return "mutant-idle"
        case .walking: return "mutant-walking"
        case .running: return "mutant-run"
        case .attacking: return "mutant-punch"
        case .hurt: return "mutant-idle"  // No hurt animation, use idle
        case .dying: return "mutant-dying"
        case .dead: return "mutant-dying"
        case .roaring: return "mutant-roaring"
        }
    }
    
    /// Fallback animation names if primary isn't found
    var fallbackNames: [String] {
        switch self {
        case .idle: return ["mutant-idle-2", "mutant-breathing-idle"]
        case .walking: return ["mutant-run"]
        case .running: return ["mutant-walking"]
        case .attacking: return ["mutant-swiping", "mutant-jump-attack"]
        case .hurt: return ["mutant-idle-2"]
        case .dying: return ["mutant-idle"]
        case .dead: return ["mutant-idle"]
        case .roaring: return ["mutant-flexing-muscles", "mutant-idle"]
        }
    }
    
    /// Whether this animation should loop
    var isLooping: Bool {
        switch self {
        case .idle, .walking, .running: return true
        case .attacking, .hurt, .dying, .dead, .roaring: return false
        }
    }
}

// MARK: - Animated Enemy

/// Manages skeletal animation for a single enemy instance
final class AnimatedEnemy {
    let mesh: SkeletalMesh
    
    /// Current animation state
    private(set) var animationState: EnemyAnimationState = .idle
    
    /// Current animation time
    private var animationTime: Float = 0
    
    /// Speed multiplier for animations
    var animationSpeed: Float = 1.0
    
    /// Blend factor for transitioning between animations (0-1)
    private var blendFactor: Float = 1.0
    private var previousBoneTransforms: [simd_float4x4] = []
    
    /// Uniform buffer for GPU
    let uniformBuffer: MTLBuffer
    
    /// This enemy's own bone matrix buffer (separate from shared mesh)
    let boneMatrixBuffer: MTLBuffer
    
    /// Current bone matrices for this enemy
    private var currentBoneMatrices: [simd_float4x4]
    
    init(device: MTLDevice, mesh: SkeletalMesh) {
        self.mesh = mesh
        
        // Create uniform buffer
        self.uniformBuffer = device.makeBuffer(
            length: MemoryLayout<SkinnedUniforms>.stride,
            options: .storageModeShared
        )!
        
        // Create this enemy's own bone matrix buffer
        let boneCount = max(mesh.bones.count, 1)
        self.boneMatrixBuffer = device.makeBuffer(
            length: MemoryLayout<simd_float4x4>.stride * boneCount,
            options: .storageModeShared
        )!
        
        // Initialize bone matrices with identity
        self.currentBoneMatrices = Array(repeating: matrix_identity_float4x4, count: boneCount)
    }
    
    // MARK: - Animation Control
    
    /// Change to a new animation state
    func setAnimationState(_ newState: EnemyAnimationState, resetTime: Bool = true) {
        if newState != animationState {
            // Check if the new state uses the same animation file
            // (e.g., both .dying and .dead use "mutant-dying")
            let sameAnimation = newState.animationName == animationState.animationName
            
            // Store previous transforms for blending (unless same animation)
            if !sameAnimation, let currentTransforms = getCurrentBoneTransforms() {
                previousBoneTransforms = currentTransforms
                blendFactor = 0  // Start blend
            }
            
            animationState = newState
            
            // Only reset time if it's a different animation and resetTime is requested
            if resetTime && !sameAnimation {
                animationTime = 0
            }
        }
    }
    
    /// Update the animation based on elapsed time
    func update(deltaTime: Float) {
        // For non-looping animations that are complete, don't advance time
        // (stay on last frame, especially for death animation)
        if !animationState.isLooping && isAnimationComplete {
            // Don't update time, keep showing final frame
        } else {
            animationTime += deltaTime * animationSpeed
        }
        
        // Update blend factor
        if blendFactor < 1.0 {
            blendFactor = min(1.0, blendFactor + deltaTime * 5.0)  // Blend over ~0.2 seconds
        }
        
        // Get current bone transforms from animation
        if let currentTransforms = getCurrentBoneTransforms() {
            var finalTransforms: [simd_float4x4]
            
            // Blend with previous if transitioning
            if blendFactor < 1.0 && !previousBoneTransforms.isEmpty {
                finalTransforms = []
                for i in 0..<min(currentTransforms.count, previousBoneTransforms.count) {
                    finalTransforms.append(lerpMatrix(previousBoneTransforms[i], currentTransforms[i], t: blendFactor))
                }
            } else {
                finalTransforms = currentTransforms
            }
            
            // Update this enemy's bone matrices (not the shared mesh's)
            updateOwnBoneMatrices(animationTransforms: finalTransforms)
        }
    }
    
    /// Update this enemy's bone matrices based on animation transforms
    private func updateOwnBoneMatrices(animationTransforms: [simd_float4x4]) {
        let bones = mesh.bones
        
        // Calculate world transforms from local animation transforms
        var worldTransforms = Array(repeating: matrix_identity_float4x4, count: bones.count)
        
        for i in 0..<bones.count {
            let bone = bones[i]
            
            // Get animation transform (or bind pose if not available)
            let localTransform: simd_float4x4
            if i < animationTransforms.count {
                localTransform = animationTransforms[i]
            } else {
                localTransform = bone.bindPose
            }
            
            // Calculate world transform
            if bone.parentIndex >= 0 && bone.parentIndex < worldTransforms.count {
                worldTransforms[i] = worldTransforms[bone.parentIndex] * localTransform
            } else {
                worldTransforms[i] = localTransform
            }
        }
        
        // Calculate final bone matrices
        for i in 0..<bones.count {
            currentBoneMatrices[i] = worldTransforms[i] * bones[i].inverseBindMatrix
        }
        
        // Copy to GPU buffer
        boneMatrixBuffer.contents().copyMemory(
            from: &currentBoneMatrices,
            byteCount: currentBoneMatrices.count * MemoryLayout<simd_float4x4>.stride
        )
    }
    
    /// Get bone transforms for the current animation state and time
    private func getCurrentBoneTransforms() -> [simd_float4x4]? {
        let boneCount = mesh.bones.count
        
        // Determine the effective time based on whether this state should loop
        func getEffectiveTime(for animation: AnimationClip) -> Float {
            if animationState.isLooping {
                // Loop the animation
                return animationTime.truncatingRemainder(dividingBy: max(animation.duration, 0.001))
            } else {
                // Clamp to end (stay on last frame)
                return min(animationTime, animation.duration - 0.001)
            }
        }
        
        // Try primary animation name
        if let animation = mesh.animations[animationState.animationName] {
            let effectiveTime = getEffectiveTime(for: animation)
            return animation.getBoneTransforms(at: effectiveTime, boneCount: boneCount)
        }
        
        // Try fallback names
        for fallbackName in animationState.fallbackNames {
            if let animation = mesh.animations[fallbackName] {
                let effectiveTime = getEffectiveTime(for: animation)
                return animation.getBoneTransforms(at: effectiveTime, boneCount: boneCount)
            }
        }
        
        // Last resort: use any available animation
        if let firstAnim = mesh.animations.values.first {
            let effectiveTime = getEffectiveTime(for: firstAnim)
            return firstAnim.getBoneTransforms(at: effectiveTime, boneCount: boneCount)
        }
        
        return nil
    }
    
    /// Check if current non-looping animation has completed
    var isAnimationComplete: Bool {
        guard !animationState.isLooping else { return false }
        
        let animName = animationState.animationName
        if let animation = mesh.animations[animName] {
            return animationTime >= animation.duration
        }
        return true
    }
    
    // MARK: - Rendering
    
    /// Draw the animated enemy
    func draw(encoder: MTLRenderCommandEncoder,
              modelMatrix: simd_float4x4,
              viewProjectionMatrix: simd_float4x4,
              lightViewProjectionMatrix: simd_float4x4,
              lightDirection: simd_float3,
              cameraPosition: simd_float3,
              ambientIntensity: Float,
              diffuseIntensity: Float,
              timeOfDay: Float,
              pointLights: [PointLight]) {
        
        // Update uniforms
        var uniforms = SkinnedUniforms()
        uniforms.modelMatrix = modelMatrix
        uniforms.viewProjectionMatrix = viewProjectionMatrix
        uniforms.lightViewProjectionMatrix = lightViewProjectionMatrix
        uniforms.lightDirection = lightDirection
        uniforms.cameraPosition = cameraPosition
        uniforms.ambientIntensity = ambientIntensity
        uniforms.diffuseIntensity = diffuseIntensity
        uniforms.timeOfDay = timeOfDay
        
        // Copy point lights (position in xyz, intensity in w)
        if pointLights.count > 0 {
            uniforms.pointLight0 = simd_float4(pointLights[0].position, pointLights[0].intensity)
        }
        if pointLights.count > 1 {
            uniforms.pointLight1 = simd_float4(pointLights[1].position, pointLights[1].intensity)
        }
        if pointLights.count > 2 {
            uniforms.pointLight2 = simd_float4(pointLights[2].position, pointLights[2].intensity)
        }
        if pointLights.count > 3 {
            uniforms.pointLight3 = simd_float4(pointLights[3].position, pointLights[3].intensity)
        }
        if pointLights.count > 4 {
            uniforms.pointLight4 = simd_float4(pointLights[4].position, pointLights[4].intensity)
        }
        if pointLights.count > 5 {
            uniforms.pointLight5 = simd_float4(pointLights[5].position, pointLights[5].intensity)
        }
        if pointLights.count > 6 {
            uniforms.pointLight6 = simd_float4(pointLights[6].position, pointLights[6].intensity)
        }
        if pointLights.count > 7 {
            uniforms.pointLight7 = simd_float4(pointLights[7].position, pointLights[7].intensity)
        }
        uniforms.pointLightCount = Int32(min(pointLights.count, 8))
        
        uniformBuffer.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<SkinnedUniforms>.stride)
        
        // Bind buffers and draw
        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        encoder.setVertexBuffer(boneMatrixBuffer, offset: 0, index: 2)  // Use this enemy's own bone matrices
        
        // Draw all submeshes (enemies don't have equipment visibility)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
    }
    
    // MARK: - Vertex Descriptor
    
    /// Get the vertex descriptor for skinned enemy meshes
    static var vertexDescriptor: MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        
        // Position (float3)
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        
        // Normal (float3)
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = 12
        descriptor.attributes[1].bufferIndex = 0
        
        // TexCoord (float2)
        descriptor.attributes[2].format = .float2
        descriptor.attributes[2].offset = 24
        descriptor.attributes[2].bufferIndex = 0
        
        // Bone indices (uint4)
        descriptor.attributes[3].format = .uint4
        descriptor.attributes[3].offset = 32
        descriptor.attributes[3].bufferIndex = 0
        
        // Bone weights (float4)
        descriptor.attributes[4].format = .float4
        descriptor.attributes[4].offset = 48
        descriptor.attributes[4].bufferIndex = 0
        
        // Material index (uint)
        descriptor.attributes[5].format = .uint
        descriptor.attributes[5].offset = 64
        descriptor.attributes[5].bufferIndex = 0
        
        // Layout
        descriptor.layouts[0].stride = SkinnedVertex.stride
        descriptor.layouts[0].stepRate = 1
        descriptor.layouts[0].stepFunction = .perVertex
        
        return descriptor
    }
}

// Linear interpolation between two matrices
private func lerpMatrix(_ a: simd_float4x4, _ b: simd_float4x4, t: Float) -> simd_float4x4 {
    return simd_float4x4(
        simd_mix(a.columns.0, b.columns.0, simd_float4(repeating: t)),
        simd_mix(a.columns.1, b.columns.1, simd_float4(repeating: t)),
        simd_mix(a.columns.2, b.columns.2, simd_float4(repeating: t)),
        simd_mix(a.columns.3, b.columns.3, simd_float4(repeating: t))
    )
}

