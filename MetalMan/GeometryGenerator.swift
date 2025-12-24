import Metal
import simd

/// Generates static world geometry meshes
class GeometryGenerator {
    
    // MARK: - Tangent Calculation Helper
    
    /// Compute tangent vector for a surface given its normal
    /// For flat or mostly-flat surfaces, tangent points along the texture U axis
    static func computeTangent(normal: simd_float3) -> simd_float3 {
        // Start with world X axis as initial tangent direction
        var tangent = simd_float3(1, 0, 0)
        
        // If normal is too close to X axis, use Z axis instead
        if abs(simd_dot(normal, tangent)) > 0.9 {
            tangent = simd_float3(0, 0, 1)
        }
        
        // Make tangent perpendicular to normal using Gram-Schmidt
        tangent = simd_normalize(tangent - simd_dot(tangent, normal) * normal)
        return tangent
    }
    
    /// Compute tangent for a triangle given its vertices and UVs
    static func computeTriangleTangent(
        p0: simd_float3, p1: simd_float3, p2: simd_float3,
        uv0: simd_float2, uv1: simd_float2, uv2: simd_float2
    ) -> simd_float3 {
        let edge1 = p1 - p0
        let edge2 = p2 - p0
        let deltaUV1 = uv1 - uv0
        let deltaUV2 = uv2 - uv0
        
        let denom = deltaUV1.x * deltaUV2.y - deltaUV2.x * deltaUV1.y
        if abs(denom) < 0.0001 {
            return simd_float3(1, 0, 0) // Fallback
        }
        
        let f = 1.0 / denom
        let tangent = simd_float3(
            f * (deltaUV2.y * edge1.x - deltaUV1.y * edge2.x),
            f * (deltaUV2.y * edge1.y - deltaUV1.y * edge2.y),
            f * (deltaUV2.y * edge1.z - deltaUV1.y * edge2.z)
        )
        
        return simd_normalize(tangent)
    }
    
    // MARK: - Grid Lines (Wireframe)
    
    static func makeGridLines(device: MTLDevice) -> (MTLBuffer, Int) {
        var vertices: [Vertex] = []
        let gridMin: Float = -100
        let gridMax: Float = 100
        
        let majorColor = simd_float4(0.4, 0.45, 0.35, 0.5)
        let minorColor = simd_float4(0.3, 0.35, 0.25, 0.3)
        
        var i: Float = gridMin
        while i <= gridMax {
            let isMajor = Int(i) % 10 == 0
            let color = isMajor ? majorColor : minorColor
            
            // Create line segments that follow terrain
            for j in stride(from: gridMin, to: gridMax, by: 5) {
                let y1 = Terrain.heightAt(x: j, z: i) + 0.02
                let y2 = Terrain.heightAt(x: j + 5, z: i) + 0.02
                vertices.append(Vertex(position: simd_float3(j, y1, i), color: color))
                vertices.append(Vertex(position: simd_float3(j + 5, y2, i), color: color))
                
                let y3 = Terrain.heightAt(x: i, z: j) + 0.02
                let y4 = Terrain.heightAt(x: i, z: j + 5) + 0.02
                vertices.append(Vertex(position: simd_float3(i, y3, j), color: color))
                vertices.append(Vertex(position: simd_float3(i, y4, j + 5), color: color))
            }
            i += 5
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<Vertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count)
    }
    
    // MARK: - Ground Mesh with Terrain Height
    
    static func makeGroundMesh(device: MTLDevice) -> (MTLBuffer, Int) {
        var vertices: [TexturedVertex] = []
        let size: Float = 100
        let resolution: Int = 100  // Grid subdivisions
        let cellSize = size * 2 / Float(resolution)
        let texScale: Float = 0.5  // Texture repeat per cell
        
        for gz in 0..<resolution {
            for gx in 0..<resolution {
                let x0 = -size + Float(gx) * cellSize
                let z0 = -size + Float(gz) * cellSize
                let x1 = x0 + cellSize
                let z1 = z0 + cellSize
                
                // Get heights for corners
                let h00 = Terrain.heightAt(x: x0, z: z0)
                let h10 = Terrain.heightAt(x: x1, z: z0)
                let h01 = Terrain.heightAt(x: x0, z: z1)
                let h11 = Terrain.heightAt(x: x1, z: z1)
                
                // Get normals
                let n00 = Terrain.normalAt(x: x0, z: z0)
                let n10 = Terrain.normalAt(x: x1, z: z0)
                let n01 = Terrain.normalAt(x: x0, z: z1)
                let n11 = Terrain.normalAt(x: x1, z: z1)
                
                // Check if this cell is on a path
                let centerX = (x0 + x1) / 2
                let centerZ = (z0 + z1) / 2
                let isPath = isOnPath(x: centerX, z: centerZ)
                let material = isPath ? MaterialIndex.path.rawValue : MaterialIndex.ground.rawValue
                
                let u0 = Float(gx) * texScale
                let v0 = Float(gz) * texScale
                let u1 = u0 + texScale
                let v1 = v0 + texScale
                
                // Compute tangents from normals
                let t00 = computeTangent(normal: n00)
                let t10 = computeTangent(normal: n10)
                let t01 = computeTangent(normal: n01)
                let t11 = computeTangent(normal: n11)
                
                // Triangle 1
                vertices.append(TexturedVertex(position: simd_float3(x0, h00, z0), normal: n00, tangent: t00, texCoord: simd_float2(u0, v0), materialIndex: material))
                vertices.append(TexturedVertex(position: simd_float3(x1, h10, z0), normal: n10, tangent: t10, texCoord: simd_float2(u1, v0), materialIndex: material))
                vertices.append(TexturedVertex(position: simd_float3(x1, h11, z1), normal: n11, tangent: t11, texCoord: simd_float2(u1, v1), materialIndex: material))
                
                // Triangle 2
                vertices.append(TexturedVertex(position: simd_float3(x0, h00, z0), normal: n00, tangent: t00, texCoord: simd_float2(u0, v0), materialIndex: material))
                vertices.append(TexturedVertex(position: simd_float3(x1, h11, z1), normal: n11, tangent: t11, texCoord: simd_float2(u1, v1), materialIndex: material))
                vertices.append(TexturedVertex(position: simd_float3(x0, h01, z1), normal: n01, tangent: t01, texCoord: simd_float2(u0, v1), materialIndex: material))
            }
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count)
    }
    
    /// Check if a point is on a path
    private static func isOnPath(x: Float, z: Float) -> Bool {
        // Main paths from center
        let pathWidth: Float = 2.5
        
        // Cross paths through center
        if abs(x) < pathWidth && abs(z) < 60 { return true }
        if abs(z) < pathWidth && abs(x) < 60 { return true }
        
        // Diagonal path NE
        let diagDist1 = abs(x - z) / sqrt(2.0)
        if diagDist1 < pathWidth && x > -50 && x < 50 && z > -50 && z < 50 { return true }
        
        // Winding path to the east
        let windPath = sin(z * 0.08) * 15 + 40
        if abs(x - windPath) < pathWidth && z > -40 && z < 60 { return true }
        
        // Ring path around center
        let dist = sqrt(x * x + z * z)
        if abs(dist - 35) < pathWidth { return true }
        
        return false
    }
    
    // MARK: - Skybox
    
    static func makeSkybox(device: MTLDevice) -> (MTLBuffer, Int) {
        var vertices: [TexturedVertex] = []
        let size: Float = 400
        
        // Create a large inverted box for the sky
        let positions: [(simd_float3, simd_float3, simd_float2)] = [
            // Front (looking at -Z)
            (simd_float3(-size, -size, -size), simd_float3(0, 0, 1), simd_float2(0, 1)),
            (simd_float3( size, -size, -size), simd_float3(0, 0, 1), simd_float2(1, 1)),
            (simd_float3( size,  size, -size), simd_float3(0, 0, 1), simd_float2(1, 0)),
            (simd_float3(-size,  size, -size), simd_float3(0, 0, 1), simd_float2(0, 0)),
            // Back
            (simd_float3( size, -size,  size), simd_float3(0, 0, -1), simd_float2(0, 1)),
            (simd_float3(-size, -size,  size), simd_float3(0, 0, -1), simd_float2(1, 1)),
            (simd_float3(-size,  size,  size), simd_float3(0, 0, -1), simd_float2(1, 0)),
            (simd_float3( size,  size,  size), simd_float3(0, 0, -1), simd_float2(0, 0)),
            // Left
            (simd_float3(-size, -size,  size), simd_float3(1, 0, 0), simd_float2(0, 1)),
            (simd_float3(-size, -size, -size), simd_float3(1, 0, 0), simd_float2(1, 1)),
            (simd_float3(-size,  size, -size), simd_float3(1, 0, 0), simd_float2(1, 0)),
            (simd_float3(-size,  size,  size), simd_float3(1, 0, 0), simd_float2(0, 0)),
            // Right
            (simd_float3( size, -size, -size), simd_float3(-1, 0, 0), simd_float2(0, 1)),
            (simd_float3( size, -size,  size), simd_float3(-1, 0, 0), simd_float2(1, 1)),
            (simd_float3( size,  size,  size), simd_float3(-1, 0, 0), simd_float2(1, 0)),
            (simd_float3( size,  size, -size), simd_float3(-1, 0, 0), simd_float2(0, 0)),
            // Top
            (simd_float3(-size,  size, -size), simd_float3(0, -1, 0), simd_float2(0, 0)),
            (simd_float3( size,  size, -size), simd_float3(0, -1, 0), simd_float2(1, 0)),
            (simd_float3( size,  size,  size), simd_float3(0, -1, 0), simd_float2(1, 1)),
            (simd_float3(-size,  size,  size), simd_float3(0, -1, 0), simd_float2(0, 1)),
        ]
        
        // Add each face (2 triangles per face)
        for faceIdx in 0..<5 {
            let base = faceIdx * 4
            let (p0, n0, t0) = positions[base]
            let (p1, n1, t1) = positions[base + 1]
            let (p2, n2, t2) = positions[base + 2]
            let (p3, n3, t3) = positions[base + 3]
            
            vertices.append(TexturedVertex(position: p0, normal: n0, texCoord: t0, materialIndex: MaterialIndex.sky.rawValue))
            vertices.append(TexturedVertex(position: p1, normal: n1, texCoord: t1, materialIndex: MaterialIndex.sky.rawValue))
            vertices.append(TexturedVertex(position: p2, normal: n2, texCoord: t2, materialIndex: MaterialIndex.sky.rawValue))
            
            vertices.append(TexturedVertex(position: p0, normal: n0, texCoord: t0, materialIndex: MaterialIndex.sky.rawValue))
            vertices.append(TexturedVertex(position: p2, normal: n2, texCoord: t2, materialIndex: MaterialIndex.sky.rawValue))
            vertices.append(TexturedVertex(position: p3, normal: n3, texCoord: t3, materialIndex: MaterialIndex.sky.rawValue))
        }
        
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
                if abs(gridX) < 12 && abs(gridZ) < 12 { seed += 5; continue }
                
                let offsetX = (seededRandom(seed) - 0.5) * 10
                let offsetZ = (seededRandom(seed + 1) - 0.5) * 10
                let x = Float(gridX) + offsetX
                let z = Float(gridZ) + offsetZ
                
                // Skip if on a path
                if isOnPath(x: x, z: z) { seed += 5; continue }
                
                let height = 3.5 + seededRandom(seed + 2) * 3.0
                let radius = 1.0 + seededRandom(seed + 3) * 1.0
                
                if seededRandom(seed + 4) < 0.7 {
                    let terrainY = Terrain.heightAt(x: x, z: z)
                    let pos = simd_float3(x, terrainY, z)
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
        
        let layerHeights: [Float] = [trunkHeight * 0.8, trunkHeight + height * 0.2, trunkHeight + height * 0.4]
        let layerRadii: [Float] = [radius, radius * 0.7, radius * 0.4]
        let coneHeights: [Float] = [height * 0.35, height * 0.3, height * 0.3]
        
        for i in 0..<3 {
            addCone(at: pos + simd_float3(0, layerHeights[i], 0), radius: layerRadii[i], height: coneHeights[i], segments: 8, material: MaterialIndex.foliage.rawValue, vertices: &vertices)
        }
        
        colliders.append(Collider(position: simd_float2(pos.x, pos.z), radius: trunkRadius + 0.3))
    }
    
    // MARK: - Rock Meshes
    
    static func makeRockMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        var seed = 1000
        for gridX in stride(from: -85, through: 85, by: 18) {
            for gridZ in stride(from: -85, through: 85, by: 18) {
                if abs(gridX) < 15 && abs(gridZ) < 15 { seed += 4; continue }
                
                let offsetX = (seededRandom(seed) - 0.5) * 12
                let offsetZ = (seededRandom(seed + 1) - 0.5) * 12
                let x = Float(gridX) + offsetX
                let z = Float(gridZ) + offsetZ
                
                if isOnPath(x: x, z: z) { seed += 4; continue }
                
                let size = 0.6 + seededRandom(seed + 2) * 0.8
                let chance = seededRandom(seed + 3)
                
                if chance < 0.5 {
                    let terrainY = Terrain.heightAt(x: x, z: z)
                    let pos = simd_float3(x, terrainY, z)
                    addRock(at: pos, size: size, vertices: &vertices, colliders: &colliders)
                    
                    if chance < 0.25 {
                        let x2 = pos.x + size * 1.2
                        let z2 = pos.z + size * 0.3
                        addRock(at: simd_float3(x2, Terrain.heightAt(x: x2, z: z2), z2), size: size * 0.7, vertices: &vertices, colliders: &colliders)
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
        
        let faces: [(Int, Int, Int)] = [
            (0, 2, 1), (0, 3, 2),
            (4, 5, 6), (4, 6, 7),
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
        
        colliders.append(Collider(position: simd_float2(pos.x, pos.z), radius: s))
    }
    
    // MARK: - Structure Meshes (Houses, Ruins, Bridges)
    
    static func makeStructureMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        // Small houses
        addHouse(at: simd_float3(25, 0, 30), size: simd_float3(6, 4, 5), roofHeight: 2.5, vertices: &vertices, colliders: &colliders)
        addHouse(at: simd_float3(-30, 0, 25), size: simd_float3(5, 3.5, 6), roofHeight: 2, vertices: &vertices, colliders: &colliders)
        addHouse(at: simd_float3(40, 0, -35), size: simd_float3(7, 4.5, 6), roofHeight: 3, vertices: &vertices, colliders: &colliders)
        
        // Ruins
        addRuin(at: simd_float3(-45, 0, -40), size: simd_float3(8, 3, 10), vertices: &vertices, colliders: &colliders)
        addRuin(at: simd_float3(55, 0, 50), size: simd_float3(6, 2.5, 6), vertices: &vertices, colliders: &colliders)
        
        // Bridges over low terrain areas
        addBridge(from: simd_float3(-5, 0, 35), to: simd_float3(5, 0, 35), width: 3, vertices: &vertices, colliders: &colliders)
        addBridge(from: simd_float3(35, 0, -5), to: simd_float3(35, 0, 5), width: 2.5, vertices: &vertices, colliders: &colliders)
        
        // Watchtower
        addWatchtower(at: simd_float3(-60, 0, 60), vertices: &vertices, colliders: &colliders)
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count, colliders)
    }
    
    private static func addHouse(at pos: simd_float3, size: simd_float3, roofHeight: Float, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let terrainY = Terrain.heightAt(x: pos.x, z: pos.z)
        let basePos = simd_float3(pos.x, terrainY, pos.z)
        
        let hw = size.x / 2
        let hd = size.z / 2
        let wallHeight = size.y
        
        // Walls
        addBox(at: basePos + simd_float3(0, wallHeight / 2, 0), size: size, material: MaterialIndex.stoneWall.rawValue, vertices: &vertices)
        
        // Roof (triangular prism)
        let roofBase = basePos.y + wallHeight
        let roofPeak = roofBase + roofHeight
        
        // Front and back triangles
        let frontLeft = basePos + simd_float3(-hw - 0.3, wallHeight, -hd - 0.3)
        let frontRight = basePos + simd_float3(hw + 0.3, wallHeight, -hd - 0.3)
        let frontPeak = basePos + simd_float3(0, roofPeak, -hd - 0.3)
        let backLeft = basePos + simd_float3(-hw - 0.3, wallHeight, hd + 0.3)
        let backRight = basePos + simd_float3(hw + 0.3, wallHeight, hd + 0.3)
        let backPeak = basePos + simd_float3(0, roofPeak, hd + 0.3)
        
        // Front gable
        addTriangle(frontLeft, frontRight, frontPeak, material: MaterialIndex.stoneWall.rawValue, vertices: &vertices)
        // Back gable
        addTriangle(backRight, backLeft, backPeak, material: MaterialIndex.stoneWall.rawValue, vertices: &vertices)
        
        // Roof slopes
        let roofNormalLeft = simd_normalize(simd_cross(frontPeak - frontLeft, backLeft - frontLeft))
        let roofNormalRight = simd_normalize(simd_cross(backRight - frontRight, frontPeak - frontRight))
        
        // Left slope
        vertices.append(TexturedVertex(position: frontLeft, normal: roofNormalLeft, texCoord: simd_float2(0, 1), materialIndex: MaterialIndex.roof.rawValue))
        vertices.append(TexturedVertex(position: frontPeak, normal: roofNormalLeft, texCoord: simd_float2(0.5, 0), materialIndex: MaterialIndex.roof.rawValue))
        vertices.append(TexturedVertex(position: backPeak, normal: roofNormalLeft, texCoord: simd_float2(0.5, 0), materialIndex: MaterialIndex.roof.rawValue))
        vertices.append(TexturedVertex(position: frontLeft, normal: roofNormalLeft, texCoord: simd_float2(0, 1), materialIndex: MaterialIndex.roof.rawValue))
        vertices.append(TexturedVertex(position: backPeak, normal: roofNormalLeft, texCoord: simd_float2(0.5, 0), materialIndex: MaterialIndex.roof.rawValue))
        vertices.append(TexturedVertex(position: backLeft, normal: roofNormalLeft, texCoord: simd_float2(0, 1), materialIndex: MaterialIndex.roof.rawValue))
        
        // Right slope
        vertices.append(TexturedVertex(position: frontRight, normal: roofNormalRight, texCoord: simd_float2(1, 1), materialIndex: MaterialIndex.roof.rawValue))
        vertices.append(TexturedVertex(position: backRight, normal: roofNormalRight, texCoord: simd_float2(1, 1), materialIndex: MaterialIndex.roof.rawValue))
        vertices.append(TexturedVertex(position: backPeak, normal: roofNormalRight, texCoord: simd_float2(0.5, 0), materialIndex: MaterialIndex.roof.rawValue))
        vertices.append(TexturedVertex(position: frontRight, normal: roofNormalRight, texCoord: simd_float2(1, 1), materialIndex: MaterialIndex.roof.rawValue))
        vertices.append(TexturedVertex(position: backPeak, normal: roofNormalRight, texCoord: simd_float2(0.5, 0), materialIndex: MaterialIndex.roof.rawValue))
        vertices.append(TexturedVertex(position: frontPeak, normal: roofNormalRight, texCoord: simd_float2(0.5, 0), materialIndex: MaterialIndex.roof.rawValue))
        
        // Collision
        colliders.append(Collider(position: simd_float2(basePos.x, basePos.z), radius: max(hw, hd) + 0.5))
    }
    
    private static func addRuin(at pos: simd_float3, size: simd_float3, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let terrainY = Terrain.heightAt(x: pos.x, z: pos.z)
        let basePos = simd_float3(pos.x, terrainY, pos.z)
        
        let hw = size.x / 2
        let hd = size.z / 2
        let wallThickness: Float = 0.4
        
        // Broken walls - varying heights
        var seed = Int(pos.x * 100 + pos.z * 10)
        
        // Back wall (mostly intact)
        let backHeight = size.y * (0.7 + seededRandom(seed) * 0.3)
        addBox(at: basePos + simd_float3(0, backHeight / 2, hd - wallThickness / 2), 
               size: simd_float3(size.x, backHeight, wallThickness), 
               material: MaterialIndex.stoneWall.rawValue, vertices: &vertices)
        seed += 1
        
        // Left wall (broken)
        let leftHeight = size.y * (0.3 + seededRandom(seed) * 0.4)
        addBox(at: basePos + simd_float3(-hw + wallThickness / 2, leftHeight / 2, 0), 
               size: simd_float3(wallThickness, leftHeight, size.z * 0.6), 
               material: MaterialIndex.stoneWall.rawValue, vertices: &vertices)
        seed += 1
        
        // Right wall (partial)
        let rightHeight = size.y * (0.5 + seededRandom(seed) * 0.3)
        addBox(at: basePos + simd_float3(hw - wallThickness / 2, rightHeight / 2, hd * 0.3), 
               size: simd_float3(wallThickness, rightHeight, size.z * 0.5), 
               material: MaterialIndex.stoneWall.rawValue, vertices: &vertices)
        
        // Some rubble rocks
        for i in 0..<4 {
            let rx = basePos.x + (seededRandom(seed + i * 2) - 0.5) * size.x * 0.8
            let rz = basePos.z + (seededRandom(seed + i * 2 + 1) - 0.5) * size.z * 0.8
            addRock(at: simd_float3(rx, terrainY, rz), size: 0.3 + seededRandom(seed + i) * 0.3, vertices: &vertices, colliders: &colliders)
        }
        
        colliders.append(Collider(position: simd_float2(basePos.x, basePos.z), radius: max(hw, hd)))
    }
    
    private static func addBridge(from start: simd_float3, to end: simd_float3, width: Float, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let startY = Terrain.heightAt(x: start.x, z: start.z) + 0.5
        let endY = Terrain.heightAt(x: end.x, z: end.z) + 0.5
        let bridgeY = max(startY, endY) + 1.0
        
        let direction = simd_normalize(simd_float3(end.x - start.x, 0, end.z - start.z))
        let perpendicular = simd_float3(-direction.z, 0, direction.x)
        let length = simd_length(simd_float3(end.x - start.x, 0, end.z - start.z))
        
        let center = (start + end) / 2
        let centerPos = simd_float3(center.x, bridgeY, center.z)
        
        // Bridge deck
        let hw = width / 2
        let hl = length / 2
        
        // Break up complex expressions for type checker
        let offset1 = perpendicular * hw + direction * hl
        let offset2 = perpendicular * hw - direction * hl
        let corner0 = centerPos + offset1
        let corner1 = centerPos - perpendicular * hw + direction * hl
        let corner2 = centerPos - perpendicular * hw - direction * hl
        let corner3 = centerPos + offset2
        let corners: [simd_float3] = [corner0, corner1, corner2, corner3]
        
        // Top surface
        let topNormal = simd_float3(0, 1, 0)
        vertices.append(TexturedVertex(position: corners[0], normal: topNormal, texCoord: simd_float2(0, 0), materialIndex: MaterialIndex.woodPlank.rawValue))
        vertices.append(TexturedVertex(position: corners[1], normal: topNormal, texCoord: simd_float2(1, 0), materialIndex: MaterialIndex.woodPlank.rawValue))
        vertices.append(TexturedVertex(position: corners[2], normal: topNormal, texCoord: simd_float2(1, 1), materialIndex: MaterialIndex.woodPlank.rawValue))
        vertices.append(TexturedVertex(position: corners[0], normal: topNormal, texCoord: simd_float2(0, 0), materialIndex: MaterialIndex.woodPlank.rawValue))
        vertices.append(TexturedVertex(position: corners[2], normal: topNormal, texCoord: simd_float2(1, 1), materialIndex: MaterialIndex.woodPlank.rawValue))
        vertices.append(TexturedVertex(position: corners[3], normal: topNormal, texCoord: simd_float2(0, 1), materialIndex: MaterialIndex.woodPlank.rawValue))
        
        // Support posts
        let postRadius: Float = 0.2
        let postHeight = bridgeY - min(startY, endY) + 1
        addCylinder(at: simd_float3(start.x, startY - 1, start.z), radius: postRadius, height: postHeight, segments: 6, material: MaterialIndex.pole.rawValue, vertices: &vertices)
        addCylinder(at: simd_float3(end.x, endY - 1, end.z), radius: postRadius, height: postHeight, segments: 6, material: MaterialIndex.pole.rawValue, vertices: &vertices)
        
        // Railings
        let railHeight: Float = 1.0
        let railRadius: Float = 0.08
        for side in [-1.0, 1.0] as [Float] {
            let offset = perpendicular * (hw - 0.1) * side
            addCylinder(at: corners[side > 0 ? 0 : 1] + simd_float3(0, 0, 0), radius: railRadius, height: railHeight, segments: 4, material: MaterialIndex.pole.rawValue, vertices: &vertices)
            addCylinder(at: corners[side > 0 ? 3 : 2] + simd_float3(0, 0, 0), radius: railRadius, height: railHeight, segments: 4, material: MaterialIndex.pole.rawValue, vertices: &vertices)
        }
    }
    
    private static func addWatchtower(at pos: simd_float3, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let terrainY = Terrain.heightAt(x: pos.x, z: pos.z)
        let basePos = simd_float3(pos.x, terrainY, pos.z)
        
        let towerRadius: Float = 2.5
        let towerHeight: Float = 8
        let platformHeight: Float = 6
        
        // Main tower (octagonal)
        addCylinder(at: basePos, radius: towerRadius, height: towerHeight, segments: 8, material: MaterialIndex.stoneWall.rawValue, vertices: &vertices)
        
        // Platform
        let platformY = basePos.y + platformHeight
        addCylinder(at: simd_float3(basePos.x, platformY, basePos.z), radius: towerRadius + 0.5, height: 0.3, segments: 8, material: MaterialIndex.woodPlank.rawValue, vertices: &vertices)
        
        // Roof cone
        addCone(at: simd_float3(basePos.x, basePos.y + towerHeight, basePos.z), radius: towerRadius + 0.3, height: 2.5, segments: 8, material: MaterialIndex.roof.rawValue, vertices: &vertices)
        
        colliders.append(Collider(position: simd_float2(basePos.x, basePos.z), radius: towerRadius + 0.5))
    }
    
    // MARK: - Pole Meshes
    
    static func makePoleMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        // Center marker
        let centerY = Terrain.heightAt(x: 0, z: 0)
        addPole(at: simd_float3(0, centerY, 0), height: 5.0, radius: 0.2, vertices: &vertices, colliders: &colliders)
        
        // Boundary markers
        let positions: [(Float, Float)] = [(-95, -95), (95, -95), (-95, 95), (95, 95)]
        for (x, z) in positions {
            let y = Terrain.heightAt(x: x, z: z)
            addPole(at: simd_float3(x, y, z), height: 4.0, radius: 0.15, vertices: &vertices, colliders: &colliders)
        }
        
        // Path markers along main paths
        for i in stride(from: -40, through: 40, by: 20) {
            if i != 0 {
                let y1 = Terrain.heightAt(x: Float(i), z: 0)
                let y2 = Terrain.heightAt(x: 0, z: Float(i))
                addPole(at: simd_float3(Float(i), y1, 2.5), height: 2.5, radius: 0.1, vertices: &vertices, colliders: &colliders)
                addPole(at: simd_float3(2.5, y2, Float(i)), height: 2.5, radius: 0.1, vertices: &vertices, colliders: &colliders)
            }
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count, colliders)
    }
    
    private static func addPole(at pos: simd_float3, height: Float, radius: Float, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        addCylinder(at: pos, radius: radius, height: height, segments: 6, material: MaterialIndex.pole.rawValue, vertices: &vertices)
        
        // Top cap
        let topCenter = pos + simd_float3(0, height, 0)
        let topNormal = simd_float3(0, 1, 0)
        for i in 0..<6 {
            let angle1 = Float(i) / 6.0 * 2 * .pi
            let angle2 = Float(i + 1) / 6.0 * 2 * .pi
            
            let p1 = pos + simd_float3(cos(angle1) * radius, height, sin(angle1) * radius)
            let p2 = pos + simd_float3(cos(angle2) * radius, height, sin(angle2) * radius)
            
            vertices.append(TexturedVertex(position: topCenter, normal: topNormal, texCoord: simd_float2(0.5, 0.5), materialIndex: MaterialIndex.pole.rawValue))
            vertices.append(TexturedVertex(position: p1, normal: topNormal, texCoord: simd_float2(0, 0), materialIndex: MaterialIndex.pole.rawValue))
            vertices.append(TexturedVertex(position: p2, normal: topNormal, texCoord: simd_float2(1, 0), materialIndex: MaterialIndex.pole.rawValue))
        }
        
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
            
            let p1 = pos + simd_float3(cos(angle1) * radius, 0, sin(angle1) * radius)
            let p2 = pos + simd_float3(cos(angle2) * radius, 0, sin(angle2) * radius)
            
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
    
    private static func addBox(at center: simd_float3, size: simd_float3, material: UInt32, vertices: inout [TexturedVertex]) {
        let hw = size.x / 2
        let hh = size.y / 2
        let hd = size.z / 2
        
        let faces: [(simd_float3, simd_float3, simd_float3, simd_float3, simd_float3)] = [
            // Front
            (center + simd_float3(-hw, -hh, hd), center + simd_float3(hw, -hh, hd), center + simd_float3(hw, hh, hd), center + simd_float3(-hw, hh, hd), simd_float3(0, 0, 1)),
            // Back
            (center + simd_float3(hw, -hh, -hd), center + simd_float3(-hw, -hh, -hd), center + simd_float3(-hw, hh, -hd), center + simd_float3(hw, hh, -hd), simd_float3(0, 0, -1)),
            // Left
            (center + simd_float3(-hw, -hh, -hd), center + simd_float3(-hw, -hh, hd), center + simd_float3(-hw, hh, hd), center + simd_float3(-hw, hh, -hd), simd_float3(-1, 0, 0)),
            // Right
            (center + simd_float3(hw, -hh, hd), center + simd_float3(hw, -hh, -hd), center + simd_float3(hw, hh, -hd), center + simd_float3(hw, hh, hd), simd_float3(1, 0, 0)),
            // Top
            (center + simd_float3(-hw, hh, hd), center + simd_float3(hw, hh, hd), center + simd_float3(hw, hh, -hd), center + simd_float3(-hw, hh, -hd), simd_float3(0, 1, 0)),
            // Bottom
            (center + simd_float3(-hw, -hh, -hd), center + simd_float3(hw, -hh, -hd), center + simd_float3(hw, -hh, hd), center + simd_float3(-hw, -hh, hd), simd_float3(0, -1, 0))
        ]
        
        for (bl, br, tr, tl, normal) in faces {
            vertices.append(TexturedVertex(position: bl, normal: normal, texCoord: simd_float2(0, 1), materialIndex: material))
            vertices.append(TexturedVertex(position: br, normal: normal, texCoord: simd_float2(1, 1), materialIndex: material))
            vertices.append(TexturedVertex(position: tr, normal: normal, texCoord: simd_float2(1, 0), materialIndex: material))
            
            vertices.append(TexturedVertex(position: bl, normal: normal, texCoord: simd_float2(0, 1), materialIndex: material))
            vertices.append(TexturedVertex(position: tr, normal: normal, texCoord: simd_float2(1, 0), materialIndex: material))
            vertices.append(TexturedVertex(position: tl, normal: normal, texCoord: simd_float2(0, 0), materialIndex: material))
        }
    }
    
    private static func addTriangle(_ p0: simd_float3, _ p1: simd_float3, _ p2: simd_float3, material: UInt32, vertices: inout [TexturedVertex]) {
        let edge1 = p1 - p0
        let edge2 = p2 - p0
        let normal = simd_normalize(simd_cross(edge1, edge2))
        
        vertices.append(TexturedVertex(position: p0, normal: normal, texCoord: simd_float2(0, 1), materialIndex: material))
        vertices.append(TexturedVertex(position: p1, normal: normal, texCoord: simd_float2(1, 1), materialIndex: material))
        vertices.append(TexturedVertex(position: p2, normal: normal, texCoord: simd_float2(0.5, 0), materialIndex: material))
    }
}
