import Metal
import simd

/// Generates static world geometry meshes
class GeometryGenerator {
    
    // MARK: - Grid Lines (Wireframe)
    
    static func makeGridLines(device: MTLDevice) -> (MTLBuffer, Int) {
        var vertices: [Vertex] = []
        let gridMin: Float = -100
        let gridMax: Float = 100
        
        let majorColor = simd_float4(0.5, 0.5, 0.5, 1.0)  // Gray for major lines
        let minorColor = simd_float4(0.35, 0.35, 0.35, 1.0)  // Darker gray for minor
        
        var i: Float = gridMin
        while i <= gridMax {
            let isMajor = Int(i) % 10 == 0
            let color = isMajor ? majorColor : minorColor
            let y: Float = 0.01  // Slightly above ground
            
            vertices.append(Vertex(position: simd_float3(gridMin, y, i), color: color))
            vertices.append(Vertex(position: simd_float3(gridMax, y, i), color: color))
            vertices.append(Vertex(position: simd_float3(i, y, gridMin), color: color))
            vertices.append(Vertex(position: simd_float3(i, y, gridMax), color: color))
            i += 5
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count)
    }
    
    // MARK: - Ground Mesh (Textured)
    
    static func makeGroundMesh(device: MTLDevice) -> (MTLBuffer, Int) {
        var vertices: [TexturedVertex] = []
        let size: Float = 100
        let normal = simd_float3(0, 1, 0)
        let texScale: Float = 20  // Repeat texture
        
        // Two triangles for ground quad
        let corners = [
            (simd_float3(-size, 0, -size), simd_float2(0, 0)),
            (simd_float3( size, 0, -size), simd_float2(texScale, 0)),
            (simd_float3( size, 0,  size), simd_float2(texScale, texScale)),
            (simd_float3(-size, 0,  size), simd_float2(0, texScale))
        ]
        
        // Triangle 1
        vertices.append(TexturedVertex(position: corners[0].0, normal: normal, texCoord: corners[0].1, materialIndex: MaterialIndex.ground.rawValue))
        vertices.append(TexturedVertex(position: corners[1].0, normal: normal, texCoord: corners[1].1, materialIndex: MaterialIndex.ground.rawValue))
        vertices.append(TexturedVertex(position: corners[2].0, normal: normal, texCoord: corners[2].1, materialIndex: MaterialIndex.ground.rawValue))
        // Triangle 2
        vertices.append(TexturedVertex(position: corners[0].0, normal: normal, texCoord: corners[0].1, materialIndex: MaterialIndex.ground.rawValue))
        vertices.append(TexturedVertex(position: corners[2].0, normal: normal, texCoord: corners[2].1, materialIndex: MaterialIndex.ground.rawValue))
        vertices.append(TexturedVertex(position: corners[3].0, normal: normal, texCoord: corners[3].1, materialIndex: MaterialIndex.ground.rawValue))
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count)
    }
    
    // MARK: - Tree Meshes
    
    static func makeTreeMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        var seed = 1
        for gridX in stride(from: -90, through: 90, by: 12) {
            for gridZ in stride(from: -90, through: 90, by: 12) {
                if abs(gridX) < 8 && abs(gridZ) < 8 { seed += 5; continue }
                
                let offsetX = (seededRandom(seed) - 0.5) * 10
                let offsetZ = (seededRandom(seed + 1) - 0.5) * 10
                let height = 3.5 + seededRandom(seed + 2) * 3.0
                let radius = 1.0 + seededRandom(seed + 3) * 1.0
                
                if seededRandom(seed + 4) < 0.7 {
                    let pos = simd_float3(Float(gridX) + offsetX, 0, Float(gridZ) + offsetZ)
                    addTree(at: pos, height: height, radius: radius, vertices: &vertices, colliders: &colliders)
                }
                seed += 5
            }
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count, colliders)
    }
    
    private static func addTree(at pos: simd_float3, height: Float, radius: Float, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let trunkHeight = height * 0.35
        let trunkRadius = radius * 0.12
        
        addCylinder(at: pos, radius: trunkRadius, height: trunkHeight, segments: 8, material: MaterialIndex.treeTrunk.rawValue, vertices: &vertices)
        
        // Three cone layers for foliage
        let layerHeights: [Float] = [trunkHeight * 0.8, trunkHeight + height * 0.2, trunkHeight + height * 0.4]
        let layerRadii: [Float] = [radius, radius * 0.7, radius * 0.4]
        let coneHeights: [Float] = [height * 0.35, height * 0.3, height * 0.3]
        
        for i in 0..<3 {
            addCone(at: pos + simd_float3(0, layerHeights[i], 0), radius: layerRadii[i], height: coneHeights[i], segments: 8, material: MaterialIndex.foliage.rawValue, vertices: &vertices)
        }
        
        // Collision for tree trunk
        colliders.append(Collider(position: simd_float2(pos.x, pos.z), radius: trunkRadius + 0.2))
    }
    
    // MARK: - Rock Meshes
    
    static func makeRockMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        var seed = 1000
        for gridX in stride(from: -85, through: 85, by: 18) {
            for gridZ in stride(from: -85, through: 85, by: 18) {
                if abs(gridX) < 10 && abs(gridZ) < 10 { seed += 4; continue }
                
                let offsetX = (seededRandom(seed) - 0.5) * 12
                let offsetZ = (seededRandom(seed + 1) - 0.5) * 12
                let size = 0.6 + seededRandom(seed + 2) * 0.8
                
                let chance = seededRandom(seed + 3)
                if chance < 0.5 {
                    let pos = simd_float3(Float(gridX) + offsetX, 0, Float(gridZ) + offsetZ)
                    addRock(at: pos, size: size, vertices: &vertices, colliders: &colliders)
                    // Add cluster
                    if chance < 0.25 {
                        addRock(at: simd_float3(pos.x + size * 1.2, 0, pos.z + size * 0.3), size: size * 0.7, vertices: &vertices, colliders: &colliders)
                        addRock(at: simd_float3(pos.x - size * 0.4, 0, pos.z + size * 1.0), size: size * 0.5, vertices: &vertices, colliders: &colliders)
                    }
                }
                seed += 4
            }
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count, colliders)
    }
    
    private static func addRock(at pos: simd_float3, size: Float, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let s = size
        let h = size * 1.2
        
        // Irregular rock vertices
        let corners: [simd_float3] = [
            pos + simd_float3(-s * 0.9, 0, -s * 0.8),
            pos + simd_float3(s * 0.85, 0, -s * 0.95),
            pos + simd_float3(s * 0.9, 0, s * 0.75),
            pos + simd_float3(-s * 0.75, 0, s * 0.9),
            pos + simd_float3(-s * 0.5, h * 0.9, -s * 0.4),
            pos + simd_float3(s * 0.45, h, -s * 0.5),
            pos + simd_float3(s * 0.5, h * 0.85, s * 0.35),
            pos + simd_float3(-s * 0.4, h * 0.8, s * 0.45)
        ]
        
        // Define faces (as triangles)
        let faces: [(Int, Int, Int)] = [
            // Bottom
            (0, 2, 1), (0, 3, 2),
            // Top
            (4, 5, 6), (4, 6, 7),
            // Sides
            (0, 1, 5), (0, 5, 4),
            (1, 2, 6), (1, 6, 5),
            (2, 3, 7), (2, 7, 6),
            (3, 0, 4), (3, 4, 7)
        ]
        
        for (a, b, c) in faces {
            let edge1 = corners[b] - corners[a]
            let edge2 = corners[c] - corners[a]
            let normal = simd_normalize(simd_cross(edge1, edge2))
            
            vertices.append(TexturedVertex(position: corners[a], normal: normal, texCoord: simd_float2(0, 0), materialIndex: MaterialIndex.rock.rawValue))
            vertices.append(TexturedVertex(position: corners[b], normal: normal, texCoord: simd_float2(1, 0), materialIndex: MaterialIndex.rock.rawValue))
            vertices.append(TexturedVertex(position: corners[c], normal: normal, texCoord: simd_float2(0.5, 1), materialIndex: MaterialIndex.rock.rawValue))
        }
        
        // Collision for rock
        colliders.append(Collider(position: simd_float2(pos.x, pos.z), radius: s))
    }
    
    // MARK: - Pole Meshes
    
    static func makePoleMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        // Corner posts
        addPole(at: simd_float3(0, 0, 0), height: 5.0, radius: 0.2, vertices: &vertices, colliders: &colliders)
        addPole(at: simd_float3(-95, 0, -95), height: 4.0, radius: 0.15, vertices: &vertices, colliders: &colliders)
        addPole(at: simd_float3(95, 0, -95), height: 4.0, radius: 0.15, vertices: &vertices, colliders: &colliders)
        addPole(at: simd_float3(-95, 0, 95), height: 4.0, radius: 0.15, vertices: &vertices, colliders: &colliders)
        addPole(at: simd_float3(95, 0, 95), height: 4.0, radius: 0.15, vertices: &vertices, colliders: &colliders)
        
        // Edge posts
        for i in stride(from: -50, through: 50, by: 50) {
            if i != 0 {
                addPole(at: simd_float3(Float(i), 0, -95), height: 3.0, radius: 0.15, vertices: &vertices, colliders: &colliders)
                addPole(at: simd_float3(Float(i), 0, 95), height: 3.0, radius: 0.15, vertices: &vertices, colliders: &colliders)
                addPole(at: simd_float3(-95, 0, Float(i)), height: 3.0, radius: 0.15, vertices: &vertices, colliders: &colliders)
                addPole(at: simd_float3(95, 0, Float(i)), height: 3.0, radius: 0.15, vertices: &vertices, colliders: &colliders)
            }
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count, colliders)
    }
    
    private static func addPole(at pos: simd_float3, height: Float, radius: Float, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let segments = 6
        
        // Sides
        for i in 0..<segments {
            let angle1 = Float(i) / Float(segments) * 2 * .pi
            let angle2 = Float(i + 1) / Float(segments) * 2 * .pi
            
            let x1 = cos(angle1) * radius
            let z1 = sin(angle1) * radius
            let x2 = cos(angle2) * radius
            let z2 = sin(angle2) * radius
            
            let n1 = simd_normalize(simd_float3(cos(angle1), 0, sin(angle1)))
            let n2 = simd_normalize(simd_float3(cos(angle2), 0, sin(angle2)))
            
            let bl = pos + simd_float3(x1, 0, z1)
            let br = pos + simd_float3(x2, 0, z2)
            let tl = pos + simd_float3(x1, height, z1)
            let tr = pos + simd_float3(x2, height, z2)
            
            vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(0, 1), materialIndex: MaterialIndex.pole.rawValue))
            vertices.append(TexturedVertex(position: br, normal: n2, texCoord: simd_float2(1, 1), materialIndex: MaterialIndex.pole.rawValue))
            vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(1, 0), materialIndex: MaterialIndex.pole.rawValue))
            
            vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(0, 1), materialIndex: MaterialIndex.pole.rawValue))
            vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(1, 0), materialIndex: MaterialIndex.pole.rawValue))
            vertices.append(TexturedVertex(position: tl, normal: n1, texCoord: simd_float2(0, 0), materialIndex: MaterialIndex.pole.rawValue))
        }
        
        // Top cap
        let topCenter = pos + simd_float3(0, height, 0)
        let topNormal = simd_float3(0, 1, 0)
        for i in 0..<segments {
            let angle1 = Float(i) / Float(segments) * 2 * .pi
            let angle2 = Float(i + 1) / Float(segments) * 2 * .pi
            
            let p1 = pos + simd_float3(cos(angle1) * radius, height, sin(angle1) * radius)
            let p2 = pos + simd_float3(cos(angle2) * radius, height, sin(angle2) * radius)
            
            vertices.append(TexturedVertex(position: topCenter, normal: topNormal, texCoord: simd_float2(0.5, 0.5), materialIndex: MaterialIndex.pole.rawValue))
            vertices.append(TexturedVertex(position: p1, normal: topNormal, texCoord: simd_float2(0, 0), materialIndex: MaterialIndex.pole.rawValue))
            vertices.append(TexturedVertex(position: p2, normal: topNormal, texCoord: simd_float2(1, 0), materialIndex: MaterialIndex.pole.rawValue))
        }
        
        // Collision for pole
        colliders.append(Collider(position: simd_float2(pos.x, pos.z), radius: radius + 0.1))
    }
    
    // MARK: - Primitive Helpers
    
    private static func addCylinder(at pos: simd_float3, radius: Float, height: Float, segments: Int, material: UInt32, vertices: inout [TexturedVertex]) {
        for i in 0..<segments {
            let angle1 = Float(i) / Float(segments) * 2 * .pi
            let angle2 = Float(i + 1) / Float(segments) * 2 * .pi
            
            let x1 = cos(angle1) * radius
            let z1 = sin(angle1) * radius
            let x2 = cos(angle2) * radius
            let z2 = sin(angle2) * radius
            
            let n1 = simd_normalize(simd_float3(cos(angle1), 0, sin(angle1)))
            let n2 = simd_normalize(simd_float3(cos(angle2), 0, sin(angle2)))
            
            let u1 = Float(i) / Float(segments)
            let u2 = Float(i + 1) / Float(segments)
            
            let bl = pos + simd_float3(x1, 0, z1)
            let br = pos + simd_float3(x2, 0, z2)
            let tl = pos + simd_float3(x1, height, z1)
            let tr = pos + simd_float3(x2, height, z2)
            
            vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(u1, 1), materialIndex: material))
            vertices.append(TexturedVertex(position: br, normal: n2, texCoord: simd_float2(u2, 1), materialIndex: material))
            vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(u2, 0), materialIndex: material))
            
            vertices.append(TexturedVertex(position: bl, normal: n1, texCoord: simd_float2(u1, 1), materialIndex: material))
            vertices.append(TexturedVertex(position: tr, normal: n2, texCoord: simd_float2(u2, 0), materialIndex: material))
            vertices.append(TexturedVertex(position: tl, normal: n1, texCoord: simd_float2(u1, 0), materialIndex: material))
        }
    }
    
    private static func addCone(at pos: simd_float3, radius: Float, height: Float, segments: Int, material: UInt32, vertices: inout [TexturedVertex]) {
        let apex = pos + simd_float3(0, height, 0)
        
        for i in 0..<segments {
            let angle1 = Float(i) / Float(segments) * 2 * .pi
            let angle2 = Float(i + 1) / Float(segments) * 2 * .pi
            
            let x1 = cos(angle1) * radius
            let z1 = sin(angle1) * radius
            let x2 = cos(angle2) * radius
            let z2 = sin(angle2) * radius
            
            let p1 = pos + simd_float3(x1, 0, z1)
            let p2 = pos + simd_float3(x2, 0, z2)
            
            // Calculate face normal
            let edge1 = p2 - p1
            let edge2 = apex - p1
            let normal = simd_normalize(simd_cross(edge1, edge2))
            
            let u1 = Float(i) / Float(segments)
            let u2 = Float(i + 1) / Float(segments)
            
            vertices.append(TexturedVertex(position: p1, normal: normal, texCoord: simd_float2(u1, 1), materialIndex: material))
            vertices.append(TexturedVertex(position: p2, normal: normal, texCoord: simd_float2(u2, 1), materialIndex: material))
            vertices.append(TexturedVertex(position: apex, normal: normal, texCoord: simd_float2((u1 + u2) / 2, 0), materialIndex: material))
        }
    }
}

