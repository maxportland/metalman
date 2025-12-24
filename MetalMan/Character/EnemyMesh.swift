import Metal
import simd

/// Generates and animates enemy meshes (bandits with red shirts)
class EnemyMesh {
    private let maxVerticesPerEnemy = 1000
    private let maxEnemies = 50
    private let maxTotalVertices: Int
    let vertexBuffer: MTLBuffer
    private(set) var vertexCount: Int = 0
    private(set) var enemyVertexRanges: [(start: Int, count: Int)] = []
    
    init(device: MTLDevice) {
        maxTotalVertices = maxVerticesPerEnemy * maxEnemies
        vertexBuffer = device.makeBuffer(
            length: MemoryLayout<TexturedVertex>.stride * maxTotalVertices,
            options: .storageModeShared
        )!
    }
    
    /// Update all enemy meshes
    func update(enemies: [Enemy]) {
        var vertices: [TexturedVertex] = []
        vertices.reserveCapacity(min(enemies.count * 600, maxTotalVertices))
        enemyVertexRanges = []
        
        for enemy in enemies where enemy.isAlive || enemy.stateTimer < 60.0 {
            // Stop if we're approaching buffer limit
            if vertices.count > maxTotalVertices - maxVerticesPerEnemy {
                print("[EnemyMesh] Warning: Too many enemies, some not rendered")
                break
            }
            
            let startVertex = vertices.count
            
            addEnemyMesh(
                enemy: enemy,
                vertices: &vertices
            )
            
            let count = vertices.count - startVertex
            enemyVertexRanges.append((start: startVertex, count: count))
        }
        
        vertexCount = min(vertices.count, maxTotalVertices)
        
        if vertexCount > 0 {
            let bytesToCopy = min(vertices.count, maxTotalVertices) * MemoryLayout<TexturedVertex>.stride
            _ = vertices.withUnsafeBytes { ptr in
                memcpy(vertexBuffer.contents(), ptr.baseAddress!, bytesToCopy)
            }
        }
    }
    
    private func addEnemyMesh(enemy: Enemy, vertices: inout [TexturedVertex]) {
        let walkPhase = enemy.walkPhase
        let isAttacking = enemy.isAttacking
        let attackPhase = enemy.attackPhase
        let isDead = enemy.state == .dead
        let hurtFlash = enemy.hurtTimer > 0
        
        // Animation parameters
        let legSwingAmount: Float = enemy.state == .chasing ? 0.6 : 0.4
        let armSwingAmount: Float = 0.35
        
        // Death animation - fall backwards with pivot at feet
        let deathProgress = isDead ? min(enemy.stateTimer / 1.0, 1.0) : 0
        let fallAngle = deathProgress * (.pi / 2)  // Fall backwards (positive angle rotates head to +Z)
        
        // Body bob during walking
        let isMoving = enemy.state == .patrolling || enemy.state == .chasing
        let bodyBob = isMoving ? abs(sin(walkPhase * 2)) * 0.03 : 0
        
        // Material indices - use enemy material (will be red-tinted in shader or use different texture region)
        // For now, we use the same character material but the torso will use a different UV region
        let matChar: UInt32 = MaterialIndex.character.rawValue
        let matEnemy: UInt32 = MaterialIndex.enemy.rawValue  // Red shirt material
        
        // Character dimensions
        let hipY: Float = 0.85 + bodyBob
        let shoulderY: Float = 1.45 + bodyBob
        let neckY: Float = 1.55 + bodyBob
        let headY: Float = 1.75 + bodyBob
        
        // Apply death rotation transform to all positions
        func applyDeathTransform(_ pos: simd_float3) -> simd_float3 {
            if !isDead { return pos }
            // Rotate around feet (ground level), falling backwards
            let pivotY: Float = 0.0  // Pivot at feet/ground level
            let relY = pos.y - pivotY
            let relZ = pos.z
            var newY = pivotY + relY * cos(fallAngle) - relZ * sin(fallAngle)
            let newZ = relZ * cos(fallAngle) + relY * sin(fallAngle)
            
            // Add offset so body rests ON the ground, not in it
            // When fully fallen (deathProgress = 1), add ~0.15 units to lift body above ground
            let groundOffset: Float = 0.15 * deathProgress
            newY += groundOffset
            
            return simd_float3(pos.x, max(groundOffset, newY), newZ)
        }
        
        // HEAD
        let headPos = applyDeathTransform(simd_float3(0, headY, 0))
        addSphere(center: headPos, radius: 0.22, latSegments: 6, lonSegments: 8,
                  uvYStart: 0.0, uvYEnd: 0.25, material: matChar, vertices: &vertices)
        
        // NECK
        let neckTop = applyDeathTransform(simd_float3(0, neckY, 0))
        let neckBottom = applyDeathTransform(simd_float3(0, shoulderY, 0))
        addLimb(from: neckBottom, to: neckTop,
                radius: 0.08, segments: 6, uvYStart: 0.0, uvYEnd: 0.25, material: matChar, vertices: &vertices)
        
        // TORSO (RED SHIRT for bandits)
        let torsoTop = applyDeathTransform(simd_float3(0, shoulderY, 0))
        let torsoBottom = applyDeathTransform(simd_float3(0, hipY, 0))
        let torsoCenter = (torsoTop + torsoBottom) / 2
        addBox(center: torsoCenter, size: simd_float3(0.4, shoulderY - hipY, 0.22),
               uvYStart: 0.0, uvYEnd: 1.0, material: matEnemy, vertices: &vertices)  // Red material!
        
        // ARMS
        let shoulderWidth: Float = 0.25
        
        if isAttacking {
            // Attack animation - swing sword (similar to player)
            let windUpT = min(attackPhase / 0.3, 1.0)
            let swingT = max(0, (attackPhase - 0.3) / 0.7)
            
            // Left arm - guard position
            let leftShoulderPos = applyDeathTransform(simd_float3(-shoulderWidth, shoulderY - 0.05, 0))
            let leftElbowPos = applyDeathTransform(simd_float3(-shoulderWidth - 0.1, shoulderY - 0.30, -0.15))
            let leftHandPos = applyDeathTransform(simd_float3(-shoulderWidth - 0.08, shoulderY - 0.55, -0.2))
            
            addLimb(from: leftShoulderPos, to: leftElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: leftElbowPos, to: leftHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: leftHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Right arm - swinging sword
            let rightShoulderPos = applyDeathTransform(simd_float3(shoulderWidth, shoulderY - 0.05, 0))
            var rightElbowPos: simd_float3
            var rightHandPos: simd_float3
            
            if attackPhase < 0.3 {
                // Wind up
                rightElbowPos = simd_float3(shoulderWidth + 0.15, shoulderY - 0.1 + windUpT * 0.25, 0.1 + windUpT * 0.15)
                rightHandPos = simd_float3(shoulderWidth + 0.1, shoulderY + windUpT * 0.2, 0.15 + windUpT * 0.1)
            } else {
                // Swing
                rightElbowPos = simd_float3(shoulderWidth + 0.1, shoulderY + 0.15 - swingT * 0.5, 0.25 - swingT * 0.5)
                rightHandPos = simd_float3(shoulderWidth + 0.05, shoulderY + 0.2 - swingT * 0.7, 0.25 - swingT * 0.6)
            }
            
            rightElbowPos = applyDeathTransform(rightElbowPos)
            rightHandPos = applyDeathTransform(rightHandPos)
            
            addLimb(from: rightShoulderPos, to: rightElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: rightElbowPos, to: rightHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: rightHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Add sword in hand
            addEnemySword(at: rightHandPos, attackPhase: attackPhase, vertices: &vertices)
        } else {
            // Normal walking/idle arm animation
            let leftArmSwing = isMoving ? sin(walkPhase) * armSwingAmount : 0
            let rightArmSwing = isMoving ? -sin(walkPhase) * armSwingAmount : 0
            
            // Left arm
            let leftShoulderPos = applyDeathTransform(simd_float3(-shoulderWidth, shoulderY - 0.05, 0))
            let leftElbowPos = applyDeathTransform(simd_float3(-shoulderWidth - 0.08, shoulderY - 0.35, leftArmSwing * 0.3))
            let leftHandPos = applyDeathTransform(simd_float3(-shoulderWidth - 0.05, shoulderY - 0.65, leftArmSwing * 0.5))
            
            addLimb(from: leftShoulderPos, to: leftElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: leftElbowPos, to: leftHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: leftHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Right arm (holding sword at side)
            let rightShoulderPos = applyDeathTransform(simd_float3(shoulderWidth, shoulderY - 0.05, 0))
            let rightElbowPos = applyDeathTransform(simd_float3(shoulderWidth + 0.08, shoulderY - 0.35, rightArmSwing * 0.3))
            let rightHandPos = applyDeathTransform(simd_float3(shoulderWidth + 0.05, shoulderY - 0.55, rightArmSwing * 0.4 - 0.1))
            
            addLimb(from: rightShoulderPos, to: rightElbowPos, radius: 0.07, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addLimb(from: rightElbowPos, to: rightHandPos, radius: 0.06, segments: 6,
                    uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            addSphere(center: rightHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                      uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
            
            // Sword at side
            addEnemySword(at: rightHandPos, attackPhase: nil, vertices: &vertices)
        }
        
        // LEGS
        let legSeparation: Float = 0.12
        
        if isDead {
            // Dead pose - legs straight
            let leftHipPos = applyDeathTransform(simd_float3(-legSeparation, hipY, 0))
            let leftKneePos = applyDeathTransform(simd_float3(-legSeparation, 0.45, 0))
            let leftFootPos = applyDeathTransform(simd_float3(-legSeparation, 0.08, 0))
            
            addLimb(from: leftHipPos, to: leftKneePos, radius: 0.09, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addLimb(from: leftKneePos, to: leftFootPos, radius: 0.07, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            
            let rightHipPos = applyDeathTransform(simd_float3(legSeparation, hipY, 0))
            let rightKneePos = applyDeathTransform(simd_float3(legSeparation, 0.45, 0))
            let rightFootPos = applyDeathTransform(simd_float3(legSeparation, 0.08, 0))
            
            addLimb(from: rightHipPos, to: rightKneePos, radius: 0.09, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
            addLimb(from: rightKneePos, to: rightFootPos, radius: 0.07, segments: 6,
                    uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
        } else {
            // Walking leg animation
            let leftLegSwing = isMoving ? -sin(walkPhase) * legSwingAmount : 0
            let rightLegSwing = isMoving ? sin(walkPhase) * legSwingAmount : 0
            
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
    }
    
    private func addEnemySword(at handPos: simd_float3, attackPhase: Float?, vertices: inout [TexturedVertex]) {
        let matMetal: UInt32 = MaterialIndex.pole.rawValue
        
        // Sword direction
        var swordDir: simd_float3
        if let phase = attackPhase {
            // Attack animation
            if phase < 0.3 {
                let t = phase / 0.3
                swordDir = simd_normalize(simd_float3(0, 0.3 + t * 0.5, -0.8 + t * 0.3))
            } else {
                let t = (phase - 0.3) / 0.7
                swordDir = simd_normalize(simd_float3(0, 0.8 - t * 1.0, -0.5 - t * 0.3))
            }
        } else {
            // Held at side
            swordDir = simd_normalize(simd_float3(0.1, -0.3, -0.8))
        }
        
        // Simple sword
        let bladeStart = handPos
        let bladeEnd = handPos + swordDir * 0.6
        
        addLimb(from: bladeStart, to: bladeEnd, radius: 0.02, segments: 4,
                uvYStart: 0.0, uvYEnd: 1.0, material: matMetal, vertices: &vertices)
    }
    
    // MARK: - Primitive Helpers (same as CharacterMesh)
    
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
}

