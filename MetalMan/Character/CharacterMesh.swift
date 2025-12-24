import Metal
import simd

/// Generates and animates the 3D character mesh
class CharacterMesh {
    private let maxVertices = 2000
    let vertexBuffer: MTLBuffer
    private(set) var vertexCount: Int = 0
    
    init(device: MTLDevice) {
        vertexBuffer = device.makeBuffer(
            length: MemoryLayout<TexturedVertex>.stride * maxVertices,
            options: .storageModeShared
        )!
    }
    
    /// Updates the character mesh with walking/jumping animation
    /// - Parameters:
    ///   - walkPhase: Current phase of the walking animation cycle
    ///   - isJumping: Whether the character is currently jumping
    ///   - hasSwordEquipped: Whether a sword is equipped in the right hand
    func update(walkPhase: Float, isJumping: Bool, hasSwordEquipped: Bool = false) {
        var vertices: [TexturedVertex] = []
        
        // Animation parameters
        let legSwingAmount: Float = 0.5
        let armSwingAmount: Float = 0.35
        
        // Body bob during walking
        let bodyBob = isJumping ? 0.0 : abs(sin(walkPhase * 2)) * 0.03
        
        // Material index for character (5)
        let matChar: UInt32 = MaterialIndex.character.rawValue
        
        // Character dimensions
        let hipY: Float = 0.85 + bodyBob
        let shoulderY: Float = 1.45 + bodyBob
        let neckY: Float = 1.55 + bodyBob
        let headY: Float = 1.75 + bodyBob
        
        // HEAD
        addSphere(center: simd_float3(0, headY, 0), radius: 0.22, latSegments: 8, lonSegments: 12,
                  uvYStart: 0.0, uvYEnd: 0.25, material: matChar, vertices: &vertices)
        
        // NECK
        addLimb(from: simd_float3(0, shoulderY, 0), to: simd_float3(0, neckY, 0),
                radius: 0.08, segments: 6, uvYStart: 0.0, uvYEnd: 0.25, material: matChar, vertices: &vertices)
        
        // TORSO
        addBox(center: simd_float3(0, (hipY + shoulderY) / 2, 0), size: simd_float3(0.4, shoulderY - hipY, 0.22),
               uvYStart: 0.5, uvYEnd: 0.75, material: matChar, vertices: &vertices)
        
        // ARMS
        let shoulderWidth: Float = 0.25
        let upperArmLength: Float = 0.30
        let forearmLength: Float = 0.28
        
        if isJumping {
            // Jumping arm pose: arms raised up and slightly bent
            // Left arm - raised up
            let leftShoulderPos = simd_float3(-shoulderWidth, shoulderY - 0.05, 0)
            let leftElbowPos = leftShoulderPos + simd_float3(-0.1, upperArmLength * 0.7, -0.05)
            let leftHandPos = leftElbowPos + simd_float3(-0.05, forearmLength * 0.5, 0.1)
            
            addLimb(from: leftShoulderPos, to: leftElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: leftElbowPos, to: leftHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: leftHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Right arm - raised up
            let rightShoulderPos = simd_float3(shoulderWidth, shoulderY - 0.05, 0)
            let rightElbowPos = rightShoulderPos + simd_float3(0.1, upperArmLength * 0.7, -0.05)
            let rightHandPos = rightElbowPos + simd_float3(0.05, forearmLength * 0.5, 0.1)
            
            addLimb(from: rightShoulderPos, to: rightElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: rightElbowPos, to: rightHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: rightHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Sword in right hand (if equipped) - held up during jump
            if hasSwordEquipped {
                addSword(at: rightHandPos, swingAngle: 0.5, vertices: &vertices)
            }
        } else {
            // Walking arm animation
            let leftArmSwing = sin(walkPhase) * armSwingAmount
            let rightArmSwing = -sin(walkPhase) * armSwingAmount
            
            // Left arm
            let leftShoulderPos = simd_float3(-shoulderWidth, shoulderY - 0.05, 0)
            let leftElbowPos = simd_float3(-shoulderWidth - 0.08, shoulderY - 0.35, leftArmSwing * 0.3)
            let leftHandPos = simd_float3(-shoulderWidth - 0.05, shoulderY - 0.65, leftArmSwing * 0.5)
            
            addLimb(from: leftShoulderPos, to: leftElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: leftElbowPos, to: leftHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: leftHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Right arm
            let rightShoulderPos = simd_float3(shoulderWidth, shoulderY - 0.05, 0)
            let rightElbowPos = simd_float3(shoulderWidth + 0.08, shoulderY - 0.35, rightArmSwing * 0.3)
            let rightHandPos = simd_float3(shoulderWidth + 0.05, shoulderY - 0.65, rightArmSwing * 0.5)
            
            addLimb(from: rightShoulderPos, to: rightElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: rightElbowPos, to: rightHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: rightHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Sword in right hand (if equipped)
            if hasSwordEquipped {
                addSword(at: rightHandPos, swingAngle: rightArmSwing, vertices: &vertices)
            }
        }
        
        // LEGS
        let legSeparation: Float = 0.12
        let thighLength: Float = 0.40
        let shinLength: Float = 0.38
        
        if isJumping {
            // Jumping leg pose: knees tucked up toward chest
            // Hip flexion angle (thigh rotates up toward chest) - about 70-80 degrees
            let hipFlexion: Float = 1.2  // radians (~70 degrees)
            // Knee flexion angle (shin folds back) - about 90-100 degrees
            let kneeFlexion: Float = 1.7  // radians (~100 degrees)
            
            // Left leg - tucked
            let leftHipPos = simd_float3(-legSeparation, hipY, 0)
            // Thigh goes forward and up (hip flexion)
            let leftThighDir = simd_float3(0, -cos(hipFlexion), -sin(hipFlexion))
            let leftKneePos = leftHipPos + leftThighDir * thighLength
            // Shin goes down and back from knee (knee flexion)
            // The shin direction is relative to thigh - it bends back
            let shinAngle = hipFlexion - (.pi - kneeFlexion)  // Combined angle from vertical
            let leftShinDir = simd_float3(0, -cos(shinAngle), -sin(shinAngle))
            let leftAnklePos = leftKneePos + leftShinDir * shinLength
            
            addLimb(from: leftHipPos, to: leftKneePos, radius: 0.09, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addLimb(from: leftKneePos, to: leftAnklePos, radius: 0.07, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            // Foot points down/back when tucked
            let leftFootCenter = leftAnklePos + simd_float3(0, -0.05, 0.02)
            addBox(center: leftFootCenter, size: simd_float3(0.1, 0.06, 0.16),
                   uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            
            // Right leg - tucked (same pose)
            let rightHipPos = simd_float3(legSeparation, hipY, 0)
            let rightThighDir = simd_float3(0, -cos(hipFlexion), -sin(hipFlexion))
            let rightKneePos = rightHipPos + rightThighDir * thighLength
            let rightShinDir = simd_float3(0, -cos(shinAngle), -sin(shinAngle))
            let rightAnklePos = rightKneePos + rightShinDir * shinLength
            
            addLimb(from: rightHipPos, to: rightKneePos, radius: 0.09, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addLimb(from: rightKneePos, to: rightAnklePos, radius: 0.07, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            let rightFootCenter = rightAnklePos + simd_float3(0, -0.05, 0.02)
            addBox(center: rightFootCenter, size: simd_float3(0.1, 0.06, 0.16),
                   uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
        } else {
            // Walking leg animation
            let leftLegSwing = -sin(walkPhase) * legSwingAmount
            let rightLegSwing = sin(walkPhase) * legSwingAmount
            
            // Left leg
            let leftHipPos = simd_float3(-legSeparation, hipY, 0)
            let leftLegForward = max(0, -leftLegSwing / legSwingAmount)
            let leftKneeHeight = 0.45 + leftLegForward * 0.08
            let leftKneePos = simd_float3(-legSeparation, leftKneeHeight, leftLegSwing * 0.4)
            let leftFootHeight: Float = 0.08 + leftLegForward * 0.12
            let leftFootPos = simd_float3(-legSeparation, leftFootHeight, leftLegSwing * 0.6)
            
            addLimb(from: leftHipPos, to: leftKneePos, radius: 0.09, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addLimb(from: leftKneePos, to: leftFootPos, radius: 0.07, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addBox(center: leftFootPos + simd_float3(0, -0.03, -0.05), size: simd_float3(0.1, 0.06, 0.18),
                   uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            
            // Right leg
            let rightHipPos = simd_float3(legSeparation, hipY, 0)
            let rightLegForward = max(0, -rightLegSwing / legSwingAmount)
            let rightKneeHeight = 0.45 + rightLegForward * 0.08
            let rightKneePos = simd_float3(legSeparation, rightKneeHeight, rightLegSwing * 0.4)
            let rightFootHeight: Float = 0.08 + rightLegForward * 0.12
            let rightFootPos = simd_float3(legSeparation, rightFootHeight, rightLegSwing * 0.6)
            
            addLimb(from: rightHipPos, to: rightKneePos, radius: 0.09, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addLimb(from: rightKneePos, to: rightFootPos, radius: 0.07, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addBox(center: rightFootPos + simd_float3(0, -0.03, -0.05), size: simd_float3(0.1, 0.06, 0.18),
                   uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
        }
        
        // Copy to buffer
        vertexCount = vertices.count
        _ = vertices.withUnsafeBytes { ptr in
            memcpy(vertexBuffer.contents(), ptr.baseAddress!, ptr.count)
        }
    }
    
    // MARK: - Primitive Generation Helpers
    
    private func addLimb(from start: simd_float3, to end: simd_float3, radius: Float, segments: Int,
                         uvYStart: Float, uvYEnd: Float, material: UInt32, vertices: inout [TexturedVertex]) {
        let direction = end - start
        let length = simd_length(direction)
        guard length > 0.001 else { return }
        
        let forward = simd_normalize(direction)
        
        var up = simd_float3(0, 1, 0)
        if abs(simd_dot(forward, up)) > 0.99 {
            up = simd_float3(1, 0, 0)
        }
        let right = simd_normalize(simd_cross(forward, up))
        let actualUp = simd_normalize(simd_cross(right, forward))
        
        for i in 0..<segments {
            let angle1 = Float(i) / Float(segments) * 2 * .pi
            let angle2 = Float((i + 1) % segments) / Float(segments) * 2 * .pi
            
            let offset1 = (cos(angle1) * right + sin(angle1) * actualUp) * radius
            let offset2 = (cos(angle2) * right + sin(angle2) * actualUp) * radius
            
            let n1 = simd_normalize(cos(angle1) * right + sin(angle1) * actualUp)
            let n2 = simd_normalize(cos(angle2) * right + sin(angle2) * actualUp)
            
            let bl = start + offset1
            let br = start + offset2
            let tl = end + offset1
            let tr = end + offset2
            
            let u1 = Float(i) / Float(segments)
            let u2 = Float(i + 1) / Float(segments)
            
            vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(u1, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: br, normal: n2, texCoord: simd_float2(u2, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(u2, uvYStart), materialIndex: material))
            
            vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(u1, uvYEnd), materialIndex: material))
            vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(u2, uvYStart), materialIndex: material))
            vertices.append(TexturedVertex(position: tl, normal: n1, texCoord: simd_float2(u1, uvYStart), materialIndex: material))
        }
    }
    
    private func addSphere(center: simd_float3, radius: Float, latSegments: Int, lonSegments: Int,
                           uvYStart: Float, uvYEnd: Float, material: UInt32, vertices: inout [TexturedVertex]) {
        for lat in 0..<latSegments {
            let theta1 = Float(lat) / Float(latSegments) * .pi
            let theta2 = Float(lat + 1) / Float(latSegments) * .pi
            
            for lon in 0..<lonSegments {
                let phi1 = Float(lon) / Float(lonSegments) * 2 * .pi
                let phi2 = Float(lon + 1) / Float(lonSegments) * 2 * .pi
                
                let p1 = center + radius * simd_float3(sin(theta1) * cos(phi1), cos(theta1), sin(theta1) * sin(phi1))
                let p2 = center + radius * simd_float3(sin(theta1) * cos(phi2), cos(theta1), sin(theta1) * sin(phi2))
                let p3 = center + radius * simd_float3(sin(theta2) * cos(phi2), cos(theta2), sin(theta2) * sin(phi2))
                let p4 = center + radius * simd_float3(sin(theta2) * cos(phi1), cos(theta2), sin(theta2) * sin(phi1))
                
                let n1 = simd_normalize(p1 - center)
                let n2 = simd_normalize(p2 - center)
                let n3 = simd_normalize(p3 - center)
                let n4 = simd_normalize(p4 - center)
                
                let u1 = Float(lon) / Float(lonSegments)
                let u2 = Float(lon + 1) / Float(lonSegments)
                let v1 = uvYStart + (uvYEnd - uvYStart) * Float(lat) / Float(latSegments)
                let v2 = uvYStart + (uvYEnd - uvYStart) * Float(lat + 1) / Float(latSegments)
                
                vertices.append(TexturedVertex(position: p1, normal: n1, texCoord: simd_float2(u1, v1), materialIndex: material))
                vertices.append(TexturedVertex(position: p2, normal: n2, texCoord: simd_float2(u2, v1), materialIndex: material))
                vertices.append(TexturedVertex(position: p3, normal: n3, texCoord: simd_float2(u2, v2), materialIndex: material))
                
                vertices.append(TexturedVertex(position: p1, normal: n1, texCoord: simd_float2(u1, v1), materialIndex: material))
                vertices.append(TexturedVertex(position: p3, normal: n3, texCoord: simd_float2(u2, v2), materialIndex: material))
                vertices.append(TexturedVertex(position: p4, normal: n4, texCoord: simd_float2(u1, v2), materialIndex: material))
            }
        }
    }
    
    private func addBox(center: simd_float3, size: simd_float3, uvYStart: Float, uvYEnd: Float,
                        material: UInt32, vertices: inout [TexturedVertex]) {
        let hw = size.x / 2
        let hh = size.y / 2
        let hd = size.z / 2
        
        // Front face
        addQuad(
            bl: center + simd_float3(-hw, -hh, hd),
            br: center + simd_float3(hw, -hh, hd),
            tl: center + simd_float3(-hw, hh, hd),
            tr: center + simd_float3(hw, hh, hd),
            normal: simd_float3(0, 0, 1),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
        
        // Back face
        addQuad(
            bl: center + simd_float3(hw, -hh, -hd),
            br: center + simd_float3(-hw, -hh, -hd),
            tl: center + simd_float3(hw, hh, -hd),
            tr: center + simd_float3(-hw, hh, -hd),
            normal: simd_float3(0, 0, -1),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
        
        // Left face
        addQuad(
            bl: center + simd_float3(-hw, -hh, -hd),
            br: center + simd_float3(-hw, -hh, hd),
            tl: center + simd_float3(-hw, hh, -hd),
            tr: center + simd_float3(-hw, hh, hd),
            normal: simd_float3(-1, 0, 0),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
        
        // Right face
        addQuad(
            bl: center + simd_float3(hw, -hh, hd),
            br: center + simd_float3(hw, -hh, -hd),
            tl: center + simd_float3(hw, hh, hd),
            tr: center + simd_float3(hw, hh, -hd),
            normal: simd_float3(1, 0, 0),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
        
        // Top face
        addQuad(
            bl: center + simd_float3(-hw, hh, hd),
            br: center + simd_float3(hw, hh, hd),
            tl: center + simd_float3(-hw, hh, -hd),
            tr: center + simd_float3(hw, hh, -hd),
            normal: simd_float3(0, 1, 0),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
        
        // Bottom face
        addQuad(
            bl: center + simd_float3(-hw, -hh, -hd),
            br: center + simd_float3(hw, -hh, -hd),
            tl: center + simd_float3(-hw, -hh, hd),
            tr: center + simd_float3(hw, -hh, hd),
            normal: simd_float3(0, -1, 0),
            uvYStart: uvYStart, uvYEnd: uvYEnd, material: material, vertices: &vertices
        )
    }
    
    private func addQuad(bl: simd_float3, br: simd_float3, tl: simd_float3, tr: simd_float3,
                         normal: simd_float3, uvYStart: Float, uvYEnd: Float, material: UInt32,
                         vertices: inout [TexturedVertex]) {
        vertices.append(TexturedVertex(position: bl, normal: normal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
        vertices.append(TexturedVertex(position: br, normal: normal, texCoord: simd_float2(1, uvYEnd), materialIndex: material))
        vertices.append(TexturedVertex(position: tr, normal: normal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
        vertices.append(TexturedVertex(position: bl, normal: normal, texCoord: simd_float2(0, uvYEnd), materialIndex: material))
        vertices.append(TexturedVertex(position: tr, normal: normal, texCoord: simd_float2(1, uvYStart), materialIndex: material))
        vertices.append(TexturedVertex(position: tl, normal: normal, texCoord: simd_float2(0, uvYStart), materialIndex: material))
    }
    
    /// Add a sword mesh at the given hand position
    private func addSword(at handPos: simd_float3, swingAngle: Float, vertices: inout [TexturedVertex]) {
        // Sword dimensions
        let handleLength: Float = 0.12
        let handleRadius: Float = 0.025
        let bladeLength: Float = 0.55
        let bladeWidth: Float = 0.06
        let bladeThickness: Float = 0.015
        let guardWidth: Float = 0.15
        let guardHeight: Float = 0.03
        
        // Sword material (using pole material for metallic look)
        let matSword: UInt32 = MaterialIndex.pole.rawValue
        
        // Sword points forward (negative Z in character local space) with slight downward angle
        // The blade extends forward from the hand, like holding a sword ready to strike
        let forwardTilt: Float = 0.15  // Slight downward angle
        let swordDir = simd_normalize(simd_float3(0, -forwardTilt, -1.0))
        
        // Add some swing based on arm movement
        let swingOffset = swingAngle * 0.3
        let adjustedDir = simd_normalize(simd_float3(swingOffset * 0.2, swordDir.y, swordDir.z))
        
        // Calculate basis vectors for sword orientation
        // "Up" for the sword is the character's up direction
        let swordUp = simd_float3(0, 1, 0)
        let swordRight = simd_normalize(simd_cross(adjustedDir, swordUp))
        let swordForward = simd_normalize(simd_cross(swordRight, adjustedDir))
        
        // Handle extends back from hand (opposite of blade direction)
        let handleStart = handPos
        let handleEnd = handleStart - adjustedDir * handleLength  // Handle goes backward
        addLimb(from: handleEnd, to: handleStart, radius: handleRadius, segments: 6,
                uvYStart: 0.0, uvYEnd: 0.2, material: matSword, vertices: &vertices)
        
        // Guard (cross-piece at the hand position)
        let guardCenter = handPos
        // Guard is horizontal (along swordRight axis)
        addBox(center: guardCenter,
               size: simd_float3(guardWidth, guardHeight, guardHeight),
               uvYStart: 0.2, uvYEnd: 0.4, material: matSword, vertices: &vertices)
        
        // Blade extends forward from guard
        let bladeStart = guardCenter + adjustedDir * (guardHeight / 2)
        let bladeCenter = bladeStart + adjustedDir * (bladeLength / 2)
        
        // Create blade as a flat box aligned with sword direction
        addSwordBlade(center: bladeCenter,
                      direction: adjustedDir,
                      right: swordRight,
                      forward: swordForward,
                      length: bladeLength,
                      width: bladeWidth,
                      thickness: bladeThickness,
                      material: matSword,
                      vertices: &vertices)
    }
    
    /// Add a sword blade oriented along a direction
    private func addSwordBlade(center: simd_float3, direction: simd_float3, right: simd_float3, forward: simd_float3,
                               length: Float, width: Float, thickness: Float, material: UInt32,
                               vertices: inout [TexturedVertex]) {
        let hl = length / 2   // half length (along sword direction)
        let hw = width / 2    // half width (perpendicular to flat side)
        let ht = thickness / 2 // half thickness (thin side)
        
        // Blade corners relative to center
        // The blade is flat (thin in 'forward' direction, wide in 'right' direction)
        // Break up into separate variables to help compiler
        let dirHL = direction * hl
        let rightHW = right * hw
        let forwardHT = forward * ht
        
        let c0 = center - dirHL - rightHW - forwardHT // back-left-bottom
        let c1 = center - dirHL + rightHW - forwardHT // back-right-bottom
        let c2 = center - dirHL + rightHW + forwardHT // back-right-top
        let c3 = center - dirHL - rightHW + forwardHT // back-left-top
        let c4 = center + dirHL - rightHW - forwardHT // front-left-bottom
        let c5 = center + dirHL + rightHW - forwardHT // front-right-bottom
        let c6 = center + dirHL + rightHW + forwardHT // front-right-top
        let c7 = center + dirHL - rightHW + forwardHT // front-left-top
        
        // Front face (tip)
        addQuadVerts(c4, c5, c7, c6, normal: direction, material: material, vertices: &vertices)
        // Back face (near guard)
        addQuadVerts(c1, c0, c2, c3, normal: -direction, material: material, vertices: &vertices)
        // Right face
        addQuadVerts(c5, c1, c6, c2, normal: right, material: material, vertices: &vertices)
        // Left face
        addQuadVerts(c0, c4, c3, c7, normal: -right, material: material, vertices: &vertices)
        // Top face
        addQuadVerts(c3, c2, c7, c6, normal: forward, material: material, vertices: &vertices)
        // Bottom face
        addQuadVerts(c4, c5, c0, c1, normal: -forward, material: material, vertices: &vertices)
    }
    
    /// Helper to add a quad with just corners and normal
    private func addQuadVerts(_ bl: simd_float3, _ br: simd_float3, _ tl: simd_float3, _ tr: simd_float3,
                              normal: simd_float3, material: UInt32, vertices: inout [TexturedVertex]) {
        vertices.append(TexturedVertex(position: bl, normal: normal, texCoord: simd_float2(0, 1), materialIndex: material))
        vertices.append(TexturedVertex(position: br, normal: normal, texCoord: simd_float2(1, 1), materialIndex: material))
        vertices.append(TexturedVertex(position: tr, normal: normal, texCoord: simd_float2(1, 0), materialIndex: material))
        vertices.append(TexturedVertex(position: bl, normal: normal, texCoord: simd_float2(0, 1), materialIndex: material))
        vertices.append(TexturedVertex(position: tr, normal: normal, texCoord: simd_float2(1, 0), materialIndex: material))
        vertices.append(TexturedVertex(position: tl, normal: normal, texCoord: simd_float2(0, 0), materialIndex: material))
    }
}

