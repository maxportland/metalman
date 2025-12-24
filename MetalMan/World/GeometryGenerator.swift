import Metal
import simd

/// Generates static world geometry meshes
class GeometryGenerator {
    
    // MARK: - Placement Tracking
    
    /// Represents an occupied area in the world (XZ plane)
    struct OccupiedArea {
        let x: Float
        let z: Float
        let radius: Float
        
        func overlaps(with other: OccupiedArea) -> Bool {
            let dx = x - other.x
            let dz = z - other.z
            let dist = sqrt(dx * dx + dz * dz)
            return dist < (radius + other.radius)
        }
        
        func overlaps(x: Float, z: Float, radius: Float) -> Bool {
            let dx = self.x - x
            let dz = self.z - z
            let dist = sqrt(dx * dx + dz * dz)
            return dist < (self.radius + radius)
        }
    }
    
    /// Shared list of occupied areas - populated during world generation
    private static var occupiedAreas: [OccupiedArea] = []
    
    /// Character spawn exclusion radius
    private static let spawnExclusionRadius: Float = 8.0
    
    /// Check if a position is available for placement
    static func isPositionClear(x: Float, z: Float, radius: Float) -> Bool {
        // Check spawn point exclusion (character starts at origin)
        let distFromSpawn = sqrt(x * x + z * z)
        if distFromSpawn < spawnExclusionRadius + radius {
            return false
        }
        
        // Check against all occupied areas
        for area in occupiedAreas {
            if area.overlaps(x: x, z: z, radius: radius) {
                return false
            }
        }
        
        return true
    }
    
    /// Mark a position as occupied
    static func markOccupied(x: Float, z: Float, radius: Float) {
        occupiedAreas.append(OccupiedArea(x: x, z: z, radius: radius))
    }
    
    /// Clear all occupied areas (call before regenerating world)
    static func clearOccupiedAreas() {
        occupiedAreas.removeAll()
    }
    
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
    
    /// Tree types for variety
    enum TreeType: Int, CaseIterable {
        case oak = 0      // Round, full canopy
        case pine = 1     // Conical evergreen
        case birch = 2    // Slender with clusters
        case willow = 3   // Drooping branches
        case dead = 4     // Bare branches
    }
    
    static func makeTreeMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        var seed = 1
        for gridX in stride(from: -90, through: 90, by: 10) {
            for gridZ in stride(from: -90, through: 90, by: 10) {
                if abs(gridX) < 12 && abs(gridZ) < 12 { seed += 6; continue }
                
                let offsetX = (seededRandom(seed) - 0.5) * 8
                let offsetZ = (seededRandom(seed + 1) - 0.5) * 8
                let x = Float(gridX) + offsetX
                let z = Float(gridZ) + offsetZ
                
                // Skip if on a path
                if isOnPath(x: x, z: z) { seed += 6; continue }
                
                let height = 4.0 + seededRandom(seed + 2) * 4.0
                let radius = 1.2 + seededRandom(seed + 3) * 1.5
                
                // Calculate occupied radius (trunk + some buffer)
                let occupiedRadius = radius * 0.3 + 1.0
                
                // Check if position is clear
                if !isPositionClear(x: x, z: z, radius: occupiedRadius) {
                    seed += 6
                    continue
                }
                
                if seededRandom(seed + 4) < 0.75 {
                    let terrainY = Terrain.heightAt(x: x, z: z)
                    let pos = simd_float3(x, terrainY, z)
                    
                    // Select tree type based on location and randomness
                    let typeRand = seededRandom(seed + 5)
                    let treeType: TreeType
                    if typeRand < 0.35 {
                        treeType = .oak
                    } else if typeRand < 0.6 {
                        treeType = .pine
                    } else if typeRand < 0.8 {
                        treeType = .birch
                    } else if typeRand < 0.95 {
                        treeType = .willow
                    } else {
                        treeType = .dead
                    }
                    
                    // Mark position as occupied
                    markOccupied(x: x, z: z, radius: occupiedRadius)
                    
                    addTree(at: pos, height: height, radius: radius, type: treeType, seed: seed, vertices: &vertices, colliders: &colliders)
                }
                seed += 6
            }
        }
        
        let buffer = device.makeBuffer(bytes: vertices, length: MemoryLayout<TexturedVertex>.stride * vertices.count, options: [])!
        return (buffer, vertices.count, colliders)
    }
    
    private static func addTree(at pos: simd_float3, height: Float, radius: Float, type: TreeType, seed: Int, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        switch type {
        case .oak:
            addOakTree(at: pos, height: height, radius: radius, seed: seed, vertices: &vertices, colliders: &colliders)
        case .pine:
            addPineTree(at: pos, height: height, radius: radius, seed: seed, vertices: &vertices, colliders: &colliders)
        case .birch:
            addBirchTree(at: pos, height: height, radius: radius, seed: seed, vertices: &vertices, colliders: &colliders)
        case .willow:
            addWillowTree(at: pos, height: height, radius: radius, seed: seed, vertices: &vertices, colliders: &colliders)
        case .dead:
            addDeadTree(at: pos, height: height, seed: seed, vertices: &vertices, colliders: &colliders)
        }
    }
    
    // MARK: - Oak Tree (Round, full canopy)
    
    private static func addOakTree(at pos: simd_float3, height: Float, radius: Float, seed: Int, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let trunkHeight = height * 0.4
        let trunkRadius = radius * 0.15
        
        // Main trunk with slight taper
        addTaperedCylinder(at: pos, radiusBottom: trunkRadius, radiusTop: trunkRadius * 0.7, height: trunkHeight, segments: 8, material: MaterialIndex.treeTrunk.rawValue, vertices: &vertices)
        
        // Add main branches from trunk
        let branchCount = 3 + Int(seededRandom(seed + 10) * 3)
        for i in 0..<branchCount {
            let angle = Float(i) / Float(branchCount) * .pi * 2 + seededRandom(seed + 20 + i) * 0.5
            let branchY = trunkHeight * (0.6 + seededRandom(seed + 30 + i) * 0.3)
            let branchLen = radius * (0.4 + seededRandom(seed + 40 + i) * 0.3)
            let branchDir = simd_float3(cos(angle), 0.4, sin(angle))
            
            addBranch(from: pos + simd_float3(0, branchY, 0), direction: branchDir, length: branchLen, radius: trunkRadius * 0.4, vertices: &vertices)
        }
        
        // Foliage - multiple overlapping spheres for full canopy
        let canopyCenter = pos + simd_float3(0, trunkHeight + radius * 0.5, 0)
        
        // Main central foliage mass
        addFoliageSphere(at: canopyCenter, radius: radius * 0.9, segments: 10, vertices: &vertices)
        
        // Surrounding foliage clusters
        let clusterCount = 5 + Int(seededRandom(seed + 50) * 4)
        for i in 0..<clusterCount {
            let angle = Float(i) / Float(clusterCount) * .pi * 2 + seededRandom(seed + 60 + i) * 0.8
            let dist = radius * (0.5 + seededRandom(seed + 70 + i) * 0.4)
            let yOff = (seededRandom(seed + 80 + i) - 0.5) * radius * 0.6
            let clusterRadius = radius * (0.4 + seededRandom(seed + 90 + i) * 0.3)
            
            let clusterPos = canopyCenter + simd_float3(cos(angle) * dist, yOff, sin(angle) * dist)
            addFoliageSphere(at: clusterPos, radius: clusterRadius, segments: 8, vertices: &vertices)
        }
        
        colliders.append(Collider.circle(x: pos.x, z: pos.z, radius: trunkRadius + 0.3))
    }
    
    // MARK: - Pine Tree (Conical evergreen)
    
    private static func addPineTree(at pos: simd_float3, height: Float, radius: Float, seed: Int, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let trunkHeight = height * 0.85
        let trunkRadius = radius * 0.1
        
        // Tall straight trunk
        addTaperedCylinder(at: pos, radiusBottom: trunkRadius * 1.2, radiusTop: trunkRadius * 0.3, height: trunkHeight, segments: 6, material: MaterialIndex.treeTrunk.rawValue, vertices: &vertices)
        
        // Multiple cone layers for pine needle effect
        let layerCount = 5 + Int(seededRandom(seed + 10) * 3)
        for i in 0..<layerCount {
            let t = Float(i) / Float(layerCount - 1)
            let layerY = height * (0.15 + t * 0.8)
            let layerRadius = radius * (1.0 - t * 0.7) * (0.9 + seededRandom(seed + 20 + i) * 0.2)
            let layerHeight = height * 0.25 * (1.0 - t * 0.5)
            
            // Slightly offset each layer for natural look
            let offsetX = (seededRandom(seed + 30 + i) - 0.5) * radius * 0.1
            let offsetZ = (seededRandom(seed + 40 + i) - 0.5) * radius * 0.1
            
            addCone(at: pos + simd_float3(offsetX, layerY, offsetZ), radius: layerRadius, height: layerHeight, segments: 8, material: MaterialIndex.foliage.rawValue, vertices: &vertices)
        }
        
        // Top spire
        addCone(at: pos + simd_float3(0, height * 0.9, 0), radius: radius * 0.15, height: height * 0.15, segments: 6, material: MaterialIndex.foliage.rawValue, vertices: &vertices)
        
        colliders.append(Collider.circle(x: pos.x, z: pos.z, radius: trunkRadius + 0.2))
    }
    
    // MARK: - Birch Tree (Slender with clusters)
    
    private static func addBirchTree(at pos: simd_float3, height: Float, radius: Float, seed: Int, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let trunkHeight = height * 0.7
        let trunkRadius = radius * 0.08
        
        // Slender white trunk (slightly curved)
        addTaperedCylinder(at: pos, radiusBottom: trunkRadius * 1.1, radiusTop: trunkRadius * 0.6, height: trunkHeight, segments: 6, material: MaterialIndex.treeTrunk.rawValue, vertices: &vertices)
        
        // Small branches near top
        let branchCount = 4 + Int(seededRandom(seed + 10) * 4)
        for i in 0..<branchCount {
            let angle = Float(i) / Float(branchCount) * .pi * 2 + seededRandom(seed + 15 + i)
            let branchY = trunkHeight * (0.5 + seededRandom(seed + 20 + i) * 0.4)
            let branchLen = radius * (0.3 + seededRandom(seed + 25 + i) * 0.4)
            let upAngle: Float = 0.3 + seededRandom(seed + 30 + i) * 0.4
            let branchDir = simd_float3(cos(angle), upAngle, sin(angle))
            
            addBranch(from: pos + simd_float3(0, branchY, 0), direction: branchDir, length: branchLen, radius: trunkRadius * 0.3, vertices: &vertices)
            
            // Add foliage cluster at end of branch
            let branchEnd = pos + simd_float3(0, branchY, 0) + simd_normalize(branchDir) * branchLen
            let clusterRadius = radius * (0.3 + seededRandom(seed + 35 + i) * 0.2)
            addFoliageSphere(at: branchEnd, radius: clusterRadius, segments: 6, vertices: &vertices)
        }
        
        // Top foliage cluster
        addFoliageSphere(at: pos + simd_float3(0, trunkHeight, 0), radius: radius * 0.5, segments: 8, vertices: &vertices)
        
        colliders.append(Collider.circle(x: pos.x, z: pos.z, radius: trunkRadius + 0.2))
    }
    
    // MARK: - Willow Tree (Drooping branches)
    
    private static func addWillowTree(at pos: simd_float3, height: Float, radius: Float, seed: Int, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let trunkHeight = height * 0.45
        let trunkRadius = radius * 0.12
        
        // Thick trunk that splits
        addTaperedCylinder(at: pos, radiusBottom: trunkRadius * 1.3, radiusTop: trunkRadius * 0.8, height: trunkHeight, segments: 8, material: MaterialIndex.treeTrunk.rawValue, vertices: &vertices)
        
        // Main canopy sphere
        let canopyCenter = pos + simd_float3(0, trunkHeight + radius * 0.3, 0)
        addFoliageSphere(at: canopyCenter, radius: radius * 0.6, segments: 8, vertices: &vertices)
        
        // Drooping branch strands
        let strandCount = 12 + Int(seededRandom(seed + 10) * 8)
        for i in 0..<strandCount {
            let angle = Float(i) / Float(strandCount) * .pi * 2 + seededRandom(seed + 20 + i) * 0.3
            let startRadius = radius * (0.5 + seededRandom(seed + 30 + i) * 0.3)
            let startY = trunkHeight + radius * (0.2 + seededRandom(seed + 40 + i) * 0.3)
            
            let strandStart = pos + simd_float3(cos(angle) * startRadius, startY, sin(angle) * startRadius)
            let dropLength = radius * (0.8 + seededRandom(seed + 50 + i) * 0.6)
            
            // Create drooping strand as series of small foliage spheres
            let segments = 4 + Int(seededRandom(seed + 60 + i) * 3)
            for j in 0..<segments {
                let t = Float(j) / Float(segments)
                let dropY = -dropLength * t * t  // Parabolic droop
                let outward = radius * 0.1 * t
                let spherePos = strandStart + simd_float3(cos(angle) * outward, dropY, sin(angle) * outward)
                let sphereRadius = radius * 0.12 * (1.0 - t * 0.5)
                addFoliageSphere(at: spherePos, radius: sphereRadius, segments: 4, vertices: &vertices)
            }
        }
        
        colliders.append(Collider.circle(x: pos.x, z: pos.z, radius: trunkRadius + 0.3))
    }
    
    // MARK: - Dead Tree (Bare branches)
    
    private static func addDeadTree(at pos: simd_float3, height: Float, seed: Int, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let trunkHeight = height * 0.7
        let trunkRadius = height * 0.05
        
        // Gnarled main trunk
        addTaperedCylinder(at: pos, radiusBottom: trunkRadius * 1.5, radiusTop: trunkRadius * 0.4, height: trunkHeight, segments: 6, material: MaterialIndex.treeTrunk.rawValue, vertices: &vertices)
        
        // Bare branches at various heights
        let branchCount = 4 + Int(seededRandom(seed + 10) * 4)
        for i in 0..<branchCount {
            let angle = Float(i) / Float(branchCount) * .pi * 2 + seededRandom(seed + 20 + i) * 0.8
            let branchY = trunkHeight * (0.3 + seededRandom(seed + 30 + i) * 0.6)
            let branchLen = height * (0.15 + seededRandom(seed + 40 + i) * 0.2)
            let upAngle: Float = -0.1 + seededRandom(seed + 50 + i) * 0.5  // Some droop
            let branchDir = simd_float3(cos(angle), upAngle, sin(angle))
            
            addBranch(from: pos + simd_float3(0, branchY, 0), direction: branchDir, length: branchLen, radius: trunkRadius * 0.4, vertices: &vertices)
            
            // Sub-branches
            if seededRandom(seed + 60 + i) > 0.4 {
                let subAngle = angle + (seededRandom(seed + 70 + i) - 0.5) * 1.0
                let subLen = branchLen * 0.5
                let branchEnd = pos + simd_float3(0, branchY, 0) + simd_normalize(branchDir) * branchLen * 0.7
                let subDir = simd_float3(cos(subAngle), upAngle - 0.2, sin(subAngle))
                addBranch(from: branchEnd, direction: subDir, length: subLen, radius: trunkRadius * 0.2, vertices: &vertices)
            }
        }
        
        // Broken top
        if seededRandom(seed + 80) > 0.5 {
            let topPos = pos + simd_float3(0, trunkHeight, 0)
            let breakAngle = seededRandom(seed + 90) * .pi * 2
            let breakDir = simd_float3(cos(breakAngle), 0.3, sin(breakAngle))
            addBranch(from: topPos, direction: breakDir, length: height * 0.1, radius: trunkRadius * 0.5, vertices: &vertices)
        }
        
        colliders.append(Collider.circle(x: pos.x, z: pos.z, radius: trunkRadius + 0.2))
    }
    
    // MARK: - Tree Helper Functions
    
    private static func addTaperedCylinder(at pos: simd_float3, radiusBottom: Float, radiusTop: Float, height: Float, segments: Int, material: UInt32, vertices: inout [TexturedVertex]) {
        let angleStep = Float.pi * 2 / Float(segments)
        
        for i in 0..<segments {
            let angle1 = Float(i) * angleStep
            let angle2 = Float(i + 1) * angleStep
            
            let cos1 = cos(angle1), sin1 = sin(angle1)
            let cos2 = cos(angle2), sin2 = sin(angle2)
            
            let b1 = pos + simd_float3(cos1 * radiusBottom, 0, sin1 * radiusBottom)
            let b2 = pos + simd_float3(cos2 * radiusBottom, 0, sin2 * radiusBottom)
            let t1 = pos + simd_float3(cos1 * radiusTop, height, sin1 * radiusTop)
            let t2 = pos + simd_float3(cos2 * radiusTop, height, sin2 * radiusTop)
            
            let n1 = simd_normalize(simd_float3(cos1, (radiusBottom - radiusTop) / height, sin1))
            let n2 = simd_normalize(simd_float3(cos2, (radiusBottom - radiusTop) / height, sin2))
            
            let u1 = Float(i) / Float(segments)
            let u2 = Float(i + 1) / Float(segments)
            
            // Two triangles per segment
            vertices.append(TexturedVertex(position: b1, normal: n1, texCoord: simd_float2(u1, 0), materialIndex: material))
            vertices.append(TexturedVertex(position: t1, normal: n1, texCoord: simd_float2(u1, 1), materialIndex: material))
            vertices.append(TexturedVertex(position: t2, normal: n2, texCoord: simd_float2(u2, 1), materialIndex: material))
            
            vertices.append(TexturedVertex(position: b1, normal: n1, texCoord: simd_float2(u1, 0), materialIndex: material))
            vertices.append(TexturedVertex(position: t2, normal: n2, texCoord: simd_float2(u2, 1), materialIndex: material))
            vertices.append(TexturedVertex(position: b2, normal: n2, texCoord: simd_float2(u2, 0), materialIndex: material))
        }
    }
    
    private static func addBranch(from start: simd_float3, direction: simd_float3, length: Float, radius: Float, vertices: inout [TexturedVertex]) {
        let dir = simd_normalize(direction)
        let end = start + dir * length
        
        // Create a simple tapered cylinder along the direction
        let segments = 4
        let angleStep = Float.pi * 2 / Float(segments)
        
        // Find perpendicular vectors for the branch cross-section
        var up = simd_float3(0, 1, 0)
        if abs(simd_dot(dir, up)) > 0.9 {
            up = simd_float3(1, 0, 0)
        }
        let right = simd_normalize(simd_cross(dir, up))
        let forward = simd_normalize(simd_cross(right, dir))
        
        for i in 0..<segments {
            let angle1 = Float(i) * angleStep
            let angle2 = Float(i + 1) * angleStep
            
            let offset1 = right * cos(angle1) + forward * sin(angle1)
            let offset2 = right * cos(angle2) + forward * sin(angle2)
            
            let b1 = start + offset1 * radius
            let b2 = start + offset2 * radius
            let t1 = end + offset1 * radius * 0.3
            let t2 = end + offset2 * radius * 0.3
            
            let n1 = simd_normalize(offset1)
            let n2 = simd_normalize(offset2)
            
            vertices.append(TexturedVertex(position: b1, normal: n1, texCoord: simd_float2(0, 0), materialIndex: MaterialIndex.treeTrunk.rawValue))
            vertices.append(TexturedVertex(position: t1, normal: n1, texCoord: simd_float2(0, 1), materialIndex: MaterialIndex.treeTrunk.rawValue))
            vertices.append(TexturedVertex(position: t2, normal: n2, texCoord: simd_float2(1, 1), materialIndex: MaterialIndex.treeTrunk.rawValue))
            
            vertices.append(TexturedVertex(position: b1, normal: n1, texCoord: simd_float2(0, 0), materialIndex: MaterialIndex.treeTrunk.rawValue))
            vertices.append(TexturedVertex(position: t2, normal: n2, texCoord: simd_float2(1, 1), materialIndex: MaterialIndex.treeTrunk.rawValue))
            vertices.append(TexturedVertex(position: b2, normal: n2, texCoord: simd_float2(1, 0), materialIndex: MaterialIndex.treeTrunk.rawValue))
        }
    }
    
    private static func addFoliageSphere(at center: simd_float3, radius: Float, segments: Int, vertices: inout [TexturedVertex]) {
        // Create an icosphere-like shape for foliage
        let latSegments = segments
        let lonSegments = segments * 2
        
        for lat in 0..<latSegments {
            let theta1 = Float(lat) / Float(latSegments) * .pi
            let theta2 = Float(lat + 1) / Float(latSegments) * .pi
            
            for lon in 0..<lonSegments {
                let phi1 = Float(lon) / Float(lonSegments) * .pi * 2
                let phi2 = Float(lon + 1) / Float(lonSegments) * .pi * 2
                
                // Four corners of this quad
                let p1 = spherePoint(center: center, radius: radius, theta: theta1, phi: phi1)
                let p2 = spherePoint(center: center, radius: radius, theta: theta2, phi: phi1)
                let p3 = spherePoint(center: center, radius: radius, theta: theta2, phi: phi2)
                let p4 = spherePoint(center: center, radius: radius, theta: theta1, phi: phi2)
                
                let n1 = simd_normalize(p1 - center)
                let n2 = simd_normalize(p2 - center)
                let n3 = simd_normalize(p3 - center)
                let n4 = simd_normalize(p4 - center)
                
                let u1 = Float(lon) / Float(lonSegments)
                let u2 = Float(lon + 1) / Float(lonSegments)
                let v1 = Float(lat) / Float(latSegments)
                let v2 = Float(lat + 1) / Float(latSegments)
                
                // Two triangles
                vertices.append(TexturedVertex(position: p1, normal: n1, texCoord: simd_float2(u1, v1), materialIndex: MaterialIndex.foliage.rawValue))
                vertices.append(TexturedVertex(position: p2, normal: n2, texCoord: simd_float2(u1, v2), materialIndex: MaterialIndex.foliage.rawValue))
                vertices.append(TexturedVertex(position: p3, normal: n3, texCoord: simd_float2(u2, v2), materialIndex: MaterialIndex.foliage.rawValue))
                
                vertices.append(TexturedVertex(position: p1, normal: n1, texCoord: simd_float2(u1, v1), materialIndex: MaterialIndex.foliage.rawValue))
                vertices.append(TexturedVertex(position: p3, normal: n3, texCoord: simd_float2(u2, v2), materialIndex: MaterialIndex.foliage.rawValue))
                vertices.append(TexturedVertex(position: p4, normal: n4, texCoord: simd_float2(u2, v1), materialIndex: MaterialIndex.foliage.rawValue))
            }
        }
    }
    
    private static func spherePoint(center: simd_float3, radius: Float, theta: Float, phi: Float) -> simd_float3 {
        return center + simd_float3(
            radius * sin(theta) * cos(phi),
            radius * cos(theta),
            radius * sin(theta) * sin(phi)
        )
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
                let occupiedRadius = size * 1.2
                
                // Check if position is clear
                if !isPositionClear(x: x, z: z, radius: occupiedRadius) {
                    seed += 4
                    continue
                }
                
                let chance = seededRandom(seed + 3)
                
                if chance < 0.5 {
                    let terrainY = Terrain.heightAt(x: x, z: z)
                    let pos = simd_float3(x, terrainY, z)
                    
                    // Mark position as occupied
                    markOccupied(x: x, z: z, radius: occupiedRadius)
                    
                    addRock(at: pos, size: size, vertices: &vertices, colliders: &colliders)
                    
                    // Add cluster rock only if that position is also clear
                    if chance < 0.25 {
                        let x2 = pos.x + size * 1.2
                        let z2 = pos.z + size * 0.3
                        let clusterRadius = size * 0.7 * 1.2
                        
                        if isPositionClear(x: x2, z: z2, radius: clusterRadius) {
                            markOccupied(x: x2, z: z2, radius: clusterRadius)
                            addRock(at: simd_float3(x2, Terrain.heightAt(x: x2, z: z2), z2), size: size * 0.7, vertices: &vertices, colliders: &colliders)
                        }
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
        
        // Climbable collider - character can walk on top
        colliders.append(Collider.climbable(x: pos.x, z: pos.z, radius: s, height: h, baseY: pos.y))
    }
    
    // MARK: - Structure Meshes (Houses, Ruins, Bridges)
    
    static func makeStructureMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        // Structure definitions with positions and sizes
        let houses: [(pos: simd_float3, size: simd_float3, roofHeight: Float)] = [
            (simd_float3(25, 0, 30), simd_float3(6, 4, 5), 2.5),
            (simd_float3(-30, 0, 25), simd_float3(5, 3.5, 6), 2),
            (simd_float3(40, 0, -35), simd_float3(7, 4.5, 6), 3)
        ]
        
        for house in houses {
            let occupiedRadius = max(house.size.x, house.size.z) / 2 + 1.0
            if isPositionClear(x: house.pos.x, z: house.pos.z, radius: occupiedRadius) {
                markOccupied(x: house.pos.x, z: house.pos.z, radius: occupiedRadius)
                addHouse(at: house.pos, size: house.size, roofHeight: house.roofHeight, vertices: &vertices, colliders: &colliders)
            }
        }
        
        // Ruins
        let ruins: [(pos: simd_float3, size: simd_float3)] = [
            (simd_float3(-45, 0, -40), simd_float3(8, 3, 10)),
            (simd_float3(55, 0, 50), simd_float3(6, 2.5, 6))
        ]
        
        for ruin in ruins {
            let occupiedRadius = max(ruin.size.x, ruin.size.z) / 2 + 1.0
            if isPositionClear(x: ruin.pos.x, z: ruin.pos.z, radius: occupiedRadius) {
                markOccupied(x: ruin.pos.x, z: ruin.pos.z, radius: occupiedRadius)
                addRuin(at: ruin.pos, size: ruin.size, vertices: &vertices, colliders: &colliders)
            }
        }
        
        // Bridges over low terrain areas (bridges don't need spawn exclusion check as they're far from origin)
        let bridges: [(from: simd_float3, to: simd_float3, width: Float)] = [
            (simd_float3(-5, 0, 35), simd_float3(5, 0, 35), 3),
            (simd_float3(35, 0, -5), simd_float3(35, 0, 5), 2.5)
        ]
        
        for bridge in bridges {
            // Mark bridge endpoints as occupied
            let bridgeRadius = bridge.width / 2 + 0.5
            markOccupied(x: bridge.from.x, z: bridge.from.z, radius: bridgeRadius)
            markOccupied(x: bridge.to.x, z: bridge.to.z, radius: bridgeRadius)
            addBridge(from: bridge.from, to: bridge.to, width: bridge.width, vertices: &vertices, colliders: &colliders)
        }
        
        // Watchtower
        let watchtowerPos = simd_float3(-60, 0, 60)
        let watchtowerRadius: Float = 4.0
        if isPositionClear(x: watchtowerPos.x, z: watchtowerPos.z, radius: watchtowerRadius) {
            markOccupied(x: watchtowerPos.x, z: watchtowerPos.z, radius: watchtowerRadius)
            addWatchtower(at: watchtowerPos, vertices: &vertices, colliders: &colliders)
        }
        
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
        
        // Collision - houses are solid, can't walk inside
        colliders.append(Collider.circle(x: basePos.x, z: basePos.z, radius: max(hw, hd) + 0.5))
    }
    
    private static func addRuin(at pos: simd_float3, size: simd_float3, vertices: inout [TexturedVertex], colliders: inout [Collider]) {
        let terrainY = Terrain.heightAt(x: pos.x, z: pos.z)
        let basePos = simd_float3(pos.x, terrainY, pos.z)
        
        let hw = size.x / 2
        let hd = size.z / 2
        let wallThickness: Float = 0.4
        
        // Broken walls - varying heights
        var seed = Int(pos.x * 100 + pos.z * 10)
        
        // Back wall (mostly intact) - runs along X axis at +Z
        let backHeight = size.y * (0.7 + seededRandom(seed) * 0.3)
        let backWallPos = basePos + simd_float3(0, backHeight / 2, hd - wallThickness / 2)
        addBox(at: backWallPos, 
               size: simd_float3(size.x, backHeight, wallThickness), 
               material: MaterialIndex.stoneWall.rawValue, vertices: &vertices)
        // Box collider for back wall (half extents)
        colliders.append(Collider.box(x: backWallPos.x, z: backWallPos.z, 
                                      halfWidth: size.x / 2, halfDepth: wallThickness / 2))
        seed += 1
        
        // Left wall (broken) - runs along Z axis at -X
        let leftHeight = size.y * (0.3 + seededRandom(seed) * 0.4)
        let leftWallLength = size.z * 0.6
        let leftWallPos = basePos + simd_float3(-hw + wallThickness / 2, leftHeight / 2, 0)
        addBox(at: leftWallPos, 
               size: simd_float3(wallThickness, leftHeight, leftWallLength), 
               material: MaterialIndex.stoneWall.rawValue, vertices: &vertices)
        // Box collider for left wall
        colliders.append(Collider.box(x: leftWallPos.x, z: leftWallPos.z, 
                                      halfWidth: wallThickness / 2, halfDepth: leftWallLength / 2))
        seed += 1
        
        // Right wall (partial) - runs along Z axis at +X
        let rightHeight = size.y * (0.5 + seededRandom(seed) * 0.3)
        let rightWallLength = size.z * 0.5
        let rightWallPos = basePos + simd_float3(hw - wallThickness / 2, rightHeight / 2, hd * 0.3)
        addBox(at: rightWallPos, 
               size: simd_float3(wallThickness, rightHeight, rightWallLength), 
               material: MaterialIndex.stoneWall.rawValue, vertices: &vertices)
        // Box collider for right wall
        colliders.append(Collider.box(x: rightWallPos.x, z: rightWallPos.z, 
                                      halfWidth: wallThickness / 2, halfDepth: rightWallLength / 2))
        
        // Some rubble rocks (climbable)
        for i in 0..<4 {
            let rx = basePos.x + (seededRandom(seed + i * 2) - 0.5) * size.x * 0.8
            let rz = basePos.z + (seededRandom(seed + i * 2 + 1) - 0.5) * size.z * 0.8
            addRock(at: simd_float3(rx, terrainY, rz), size: 0.3 + seededRandom(seed + i) * 0.3, vertices: &vertices, colliders: &colliders)
        }
        
        // No big circular collider - walls have individual colliders so player can walk inside
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
        
        colliders.append(Collider.circle(x: basePos.x, z: basePos.z, radius: towerRadius + 0.5))
    }
    
    // MARK: - Pole Meshes
    
    static func makePoleMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
        var vertices: [TexturedVertex] = []
        var colliders: [Collider] = []
        
        // No center marker - keep spawn area clear
        
        // Boundary markers
        let positions: [(Float, Float)] = [(-95, -95), (95, -95), (-95, 95), (95, 95)]
        for (x, z) in positions {
            let poleRadius: Float = 0.15
            // Check if position is clear (boundary markers probably won't conflict, but check anyway)
            if isPositionClear(x: x, z: z, radius: poleRadius + 0.5) {
                markOccupied(x: x, z: z, radius: poleRadius + 0.5)
                let y = Terrain.heightAt(x: x, z: z)
                addPole(at: simd_float3(x, y, z), height: 4.0, radius: poleRadius, vertices: &vertices, colliders: &colliders)
            }
        }
        
        // Path markers along main paths
        for i in stride(from: -40, through: 40, by: 20) {
            if i != 0 {
                let x1 = Float(i)
                let z1: Float = 2.5
                let x2: Float = 2.5
                let z2 = Float(i)
                let poleRadius: Float = 0.1
                
                // Check first pole position
                if isPositionClear(x: x1, z: z1, radius: poleRadius + 0.5) {
                    markOccupied(x: x1, z: z1, radius: poleRadius + 0.5)
                    let y1 = Terrain.heightAt(x: x1, z: z1)
                    addPole(at: simd_float3(x1, y1, z1), height: 2.5, radius: poleRadius, vertices: &vertices, colliders: &colliders)
                }
                
                // Check second pole position
                if isPositionClear(x: x2, z: z2, radius: poleRadius + 0.5) {
                    markOccupied(x: x2, z: z2, radius: poleRadius + 0.5)
                    let y2 = Terrain.heightAt(x: x2, z: z2)
                    addPole(at: simd_float3(x2, y2, z2), height: 2.5, radius: poleRadius, vertices: &vertices, colliders: &colliders)
                }
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
        
        colliders.append(Collider.circle(x: pos.x, z: pos.z, radius: radius + 0.1))
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
