import Metal
import simd

/// Generates and animates NPC meshes (vendors with yellow shirts)
class NPCMesh {
    private let maxVerticesPerNPC = 800
    private let maxNPCs = 10
    private let maxTotalVertices: Int
    let vertexBuffer: MTLBuffer
    private(set) var vertexCount: Int = 0
    private(set) var npcVertexRanges: [(start: Int, count: Int)] = []
    
    init(device: MTLDevice) {
        maxTotalVertices = maxVerticesPerNPC * maxNPCs
        vertexBuffer = device.makeBuffer(
            length: MemoryLayout<TexturedVertex>.stride * maxTotalVertices,
            options: .storageModeShared
        )!
    }
    
    /// Update all NPC meshes
    func update(npcs: [NPC]) {
        var vertices: [TexturedVertex] = []
        vertices.reserveCapacity(min(npcs.count * 600, maxTotalVertices))
        npcVertexRanges = []
        
        for npc in npcs {
            if vertices.count > maxTotalVertices - maxVerticesPerNPC {
                break
            }
            
            let startVertex = vertices.count
            addNPCMesh(npc: npc, vertices: &vertices)
            let count = vertices.count - startVertex
            npcVertexRanges.append((start: startVertex, count: count))
        }
        
        vertexCount = min(vertices.count, maxTotalVertices)
        
        if vertexCount > 0 {
            let bytesToCopy = min(vertices.count, maxTotalVertices) * MemoryLayout<TexturedVertex>.stride
            _ = vertices.withUnsafeBytes { ptr in
                memcpy(vertexBuffer.contents(), ptr.baseAddress!, bytesToCopy)
            }
        }
    }
    
    private func addNPCMesh(npc: NPC, vertices: inout [TexturedVertex]) {
        let idlePhase = npc.idlePhase
        
        // Material indices
        let matChar: UInt32 = MaterialIndex.character.rawValue
        let matVendor: UInt32 = MaterialIndex.vendor.rawValue  // Yellow shirt
        
        // Character dimensions with idle animation
        let bodyBob = abs(sin(npc.idleTimer * 2)) * 0.01
        let hipY: Float = 0.85 + bodyBob
        let shoulderY: Float = 1.45 + bodyBob
        let neckY: Float = 1.55 + bodyBob
        let headY: Float = 1.75 + bodyBob
        
        // HEAD
        addSphere(center: simd_float3(0, headY, 0), radius: 0.22, latSegments: 6, lonSegments: 8,
                  uvYStart: 0.0, uvYEnd: 0.25, material: matChar, vertices: &vertices)
        
        // NECK
        addLimb(from: simd_float3(0, shoulderY, 0), to: simd_float3(0, neckY, 0),
                radius: 0.08, segments: 6, uvYStart: 0.0, uvYEnd: 0.25, material: matChar, vertices: &vertices)
        
        // TORSO (YELLOW for vendor)
        let torsoTop = simd_float3(0, shoulderY, 0)
        let torsoBottom = simd_float3(0, hipY, 0)
        let torsoCenter = (torsoTop + torsoBottom) / 2
        addBox(center: torsoCenter, size: simd_float3(0.4, shoulderY - hipY, 0.22),
               uvYStart: 0.0, uvYEnd: 1.0, material: matVendor, vertices: &vertices)
        
        // ARMS (idle animation - slight sway, or waving)
        let shoulderWidth: Float = 0.25
        let armSway = idlePhase * 0.3
        
        // Left arm (always idle sway)
        let leftShoulderPos = simd_float3(-shoulderWidth, shoulderY - 0.05, 0)
        let leftElbowPos = simd_float3(-shoulderWidth - 0.08, shoulderY - 0.35, armSway)
        let leftHandPos = simd_float3(-shoulderWidth - 0.05, shoulderY - 0.65, armSway * 0.8)
        
        addLimb(from: leftShoulderPos, to: leftElbowPos, radius: 0.07, segments: 6,
                uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
        addLimb(from: leftElbowPos, to: leftHandPos, radius: 0.06, segments: 6,
                uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
        addSphere(center: leftHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                  uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
        
        // Right arm (waves when player is nearby)
        let rightShoulderPos = simd_float3(shoulderWidth, shoulderY - 0.05, 0)
        
        let rightElbowPos: simd_float3
        let rightHandPos: simd_float3
        
        if npc.isWaving {
            // Waving animation - arm raised up and swaying side to side
            let waveSwing = npc.wavePhase * 0.4  // Side to side motion
            
            // Upper arm raised up and slightly forward
            rightElbowPos = simd_float3(
                shoulderWidth + 0.15 + waveSwing * 0.1,
                shoulderY + 0.25,  // Raised up high
                -0.15  // Slightly forward
            )
            
            // Forearm and hand waving
            rightHandPos = simd_float3(
                shoulderWidth + 0.2 + waveSwing * 0.25,  // Wave side to side
                shoulderY + 0.55,  // Hand up high
                -0.1
            )
        } else if npc.isPlayerNearby {
            // Player nearby but not waving - arm slightly raised (friendly pose)
            rightElbowPos = simd_float3(shoulderWidth + 0.1, shoulderY - 0.15, -0.1)
            rightHandPos = simd_float3(shoulderWidth + 0.08, shoulderY - 0.35, -0.15)
        } else {
            // Normal idle
            rightElbowPos = simd_float3(shoulderWidth + 0.08, shoulderY - 0.35, -armSway)
            rightHandPos = simd_float3(shoulderWidth + 0.05, shoulderY - 0.65, -armSway * 0.8)
        }
        
        addLimb(from: rightShoulderPos, to: rightElbowPos, radius: 0.07, segments: 6,
                uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
        addLimb(from: rightElbowPos, to: rightHandPos, radius: 0.06, segments: 6,
                uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
        addSphere(center: rightHandPos, radius: 0.08, latSegments: 4, lonSegments: 6,
                  uvYStart: 0.25, uvYEnd: 0.5, material: matChar, vertices: &vertices)
        
        // LEGS (standing still)
        let legSeparation: Float = 0.12
        
        // Left leg
        let leftHipPos = simd_float3(-legSeparation, hipY, 0)
        let leftKneePos = simd_float3(-legSeparation, 0.45, 0)
        let leftFootPos = simd_float3(-legSeparation, 0.08, 0)
        
        addLimb(from: leftHipPos, to: leftKneePos, radius: 0.09, segments: 6,
                uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
        addLimb(from: leftKneePos, to: leftFootPos, radius: 0.07, segments: 6,
                uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
        addBox(center: leftFootPos + simd_float3(0, -0.03, -0.05), size: simd_float3(0.1, 0.06, 0.18),
               uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
        
        // Right leg
        let rightHipPos = simd_float3(legSeparation, hipY, 0)
        let rightKneePos = simd_float3(legSeparation, 0.45, 0)
        let rightFootPos = simd_float3(legSeparation, 0.08, 0)
        
        addLimb(from: rightHipPos, to: rightKneePos, radius: 0.09, segments: 6,
                uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
        addLimb(from: rightKneePos, to: rightFootPos, radius: 0.07, segments: 6,
                uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
        addBox(center: rightFootPos + simd_float3(0, -0.03, -0.05), size: simd_float3(0.1, 0.06, 0.18),
               uvYStart: 0.75, uvYEnd: 1.0, material: matChar, vertices: &vertices)
    }
    
    // MARK: - Primitive Helpers
    
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

