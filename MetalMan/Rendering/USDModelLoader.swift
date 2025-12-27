import Metal
import MetalKit
import ModelIO
import simd

// Disable verbose logging for USD loading
private let usdDebugLogging = false
private func debugLog(_ message: @autoclosure () -> String) {
    if usdDebugLogging {
        print(message())
    }
}

/// Loads USD/USDC/USDZ models and converts them to Metal-compatible meshes
final class USDModelLoader {
    
    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader
    
    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }
    
    /// Loaded model data ready for rendering
    struct LoadedModel {
        let vertexBuffer: MTLBuffer
        let vertexCount: Int
        let indexBuffer: MTLBuffer?
        let indexCount: Int
        let texture: MTLTexture?
        let boundingBox: (min: simd_float3, max: simd_float3)
    }
    
    /// Loaded chest model with separate base and lid for animation
    struct LoadedChestModel {
        let baseVertexBuffer: MTLBuffer
        let baseVertexCount: Int
        let lidVertexBuffer: MTLBuffer
        let lidVertexCount: Int
        let boundingBox: (min: simd_float3, max: simd_float3)
        let lidBounds: (min: simd_float3, max: simd_float3)  // For calculating hinge position
        let hingeOffset: simd_float3  // Offset from model center to hinge pivot point
    }
    
    /// Load a USD model from a file path
    func loadModel(named name: String, withExtension ext: String = "usdc", materialIndex: UInt32) -> LoadedModel? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            debugLog("[USDLoader] Could not find \(name).\(ext) in bundle")
            return nil
        }
        
        return loadModel(from: url, materialIndex: materialIndex)
    }
    
    /// Print the full hierarchy of a USD asset for debugging
    func printAssetHierarchy(from url: URL) {
        guard usdDebugLogging else { return }
        
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: allocator)
        
        debugLog("\n[USDLoader] ========== ASSET HIERARCHY ==========")
        debugLog("[USDLoader] URL: \(url.lastPathComponent)")
        debugLog("[USDLoader] Object count: \(asset.count)")
        
        for i in 0..<asset.count {
            let object = asset.object(at: i)
            printObjectHierarchy(object, indent: 0)
        }
        debugLog("[USDLoader] ======================================\n")
    }
    
    private func printObjectHierarchy(_ object: MDLObject, indent: Int) {
        guard usdDebugLogging else { return }
        
        let indentStr = String(repeating: "  ", count: indent)
        let typeName = String(describing: type(of: object))
        
        var info = "\(indentStr)[\(typeName)] \(object.name)"
        
        // Check for transform
        if let transform = object.transform {
            let matrix = transform.matrix
            let pos = simd_float3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
            info += " pos=(\(String(format: "%.2f", pos.x)), \(String(format: "%.2f", pos.y)), \(String(format: "%.2f", pos.z)))"
        }
        
        // Check for mesh info
        if let mesh = object as? MDLMesh {
            info += " vertices=\(mesh.vertexCount)"
            if let submeshes = mesh.submeshes as? [MDLSubmesh] {
                info += " submeshes=\(submeshes.count)"
            }
        }
        
        // Check for skeleton
        if let skeleton = object as? MDLSkeleton {
            info += " SKELETON"
            debugLog(info)
            // Print joint paths
            let jointPaths = skeleton.jointPaths
            debugLog("\(indentStr)  Joint count: \(jointPaths.count)")
            for (i, path) in jointPaths.enumerated() {
                if i < 20 {  // Print first 20 joints
                    debugLog("\(indentStr)    [\(i)] \(path)")
                } else if i == 20 {
                    debugLog("\(indentStr)    ... and \(jointPaths.count - 20) more joints")
                }
            }
            
            // Print children and return
            for child in object.children.objects {
                printObjectHierarchy(child, indent: indent + 1)
            }
            return
        }
        
        // Check components
        if object.components.count > 0 {
            var componentNames: [String] = []
            for i in 0..<object.components.count {
                let comp = object.components[i]
                componentNames.append(String(describing: type(of: comp)))
                
                // Check for animation bind component
                if let animBind = comp as? MDLAnimationBindComponent {
                    info += " HAS_ANIMATION_BIND"
                    if let skeleton = animBind.skeleton {
                        info += " skeleton=\(skeleton.name)"
                    }
                }
            }
            info += " components=[\(componentNames.joined(separator: ", "))]"
        }
        
        debugLog(info)
        
        // Print children
        for child in object.children.objects {
            printObjectHierarchy(child, indent: indent + 1)
        }
    }
    
    /// Load a USD model from a URL
    func loadModel(from url: URL, materialIndex: UInt32) -> LoadedModel? {
        // Create a Metal vertex descriptor matching our TexturedVertex layout
        let metalDescriptor = MTLVertexDescriptor()
        metalDescriptor.attributes[0].format = .float3  // position
        metalDescriptor.attributes[0].offset = 0
        metalDescriptor.attributes[0].bufferIndex = 0
        metalDescriptor.attributes[1].format = .float3  // normal
        metalDescriptor.attributes[1].offset = 12
        metalDescriptor.attributes[1].bufferIndex = 0
        metalDescriptor.attributes[2].format = .float3  // tangent
        metalDescriptor.attributes[2].offset = 24
        metalDescriptor.attributes[2].bufferIndex = 0
        metalDescriptor.attributes[3].format = .float2  // texCoord
        metalDescriptor.attributes[3].offset = 36
        metalDescriptor.attributes[3].bufferIndex = 0
        metalDescriptor.layouts[0].stride = MemoryLayout<TexturedVertex>.stride
        
        // Convert to Model I/O descriptor
        let mdlDescriptor = MTKModelIOVertexDescriptorFromMetal(metalDescriptor)
        (mdlDescriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (mdlDescriptor.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        (mdlDescriptor.attributes[2] as! MDLVertexAttribute).name = MDLVertexAttributeTangent
        (mdlDescriptor.attributes[3] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        
        // Create allocator
        let allocator = MTKMeshBufferAllocator(device: device)
        
        // Load the USD asset
        let asset = MDLAsset(url: url, vertexDescriptor: mdlDescriptor, bufferAllocator: allocator)
        
        guard asset.count > 0 else { return nil }
        
        // Collect all vertices from all meshes
        var allVertices: [TexturedVertex] = []
        var minBound = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBound = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        
        // Iterate through all objects in the asset
        for i in 0..<asset.count {
            let object = asset.object(at: i)
            processObject(object, materialIndex: materialIndex, vertices: &allVertices, minBound: &minBound, maxBound: &maxBound)
        }
        
        guard !allVertices.isEmpty else { return nil }
        
        // Create vertex buffer
        guard let vertexBuffer = device.makeBuffer(bytes: allVertices, 
                                                    length: MemoryLayout<TexturedVertex>.stride * allVertices.count,
                                                    options: .storageModeShared) else {
            return nil
        }
        
        return LoadedModel(
            vertexBuffer: vertexBuffer,
            vertexCount: allVertices.count,
            indexBuffer: nil,
            indexCount: 0,
            texture: nil,
            boundingBox: (minBound, maxBound)
        )
    }
    
    /// Recursively process MDL objects to extract mesh data
    private func processObject(_ object: MDLObject, materialIndex: UInt32, vertices: inout [TexturedVertex], minBound: inout simd_float3, maxBound: inout simd_float3) {
        
        if let mesh = object as? MDLMesh {
            extractMeshVertices(mesh, materialIndex: materialIndex, vertices: &vertices, minBound: &minBound, maxBound: &maxBound)
        }
        
        // Process children
        for child in object.children.objects {
            processObject(child, materialIndex: materialIndex, vertices: &vertices, minBound: &minBound, maxBound: &maxBound)
        }
    }
    
    /// Extract vertices from an MDL mesh
    private func extractMeshVertices(_ mesh: MDLMesh, materialIndex: UInt32, vertices: inout [TexturedVertex], minBound: inout simd_float3, maxBound: inout simd_float3) {
        
        // Get vertex buffers
        let vertexBuffers = mesh.vertexBuffers
        guard !vertexBuffers.isEmpty else { return }
        
        let vertexBuffer = vertexBuffers[0]
        
        // Map the vertex data
        let vertexData = vertexBuffer.map()
        
        // Get stride from layout
        guard let layout = mesh.vertexDescriptor.layouts[0] as? MDLVertexBufferLayout else { return }
        let stride = layout.stride
        
        // Try to get attribute offsets
        var positionOffset = 0
        var normalOffset = 12
        var tangentOffset = 24
        var texCoordOffset = 36
        
        for attr in mesh.vertexDescriptor.attributes as! [MDLVertexAttribute] {
            switch attr.name {
            case MDLVertexAttributePosition:
                positionOffset = attr.offset
            case MDLVertexAttributeNormal:
                normalOffset = attr.offset
            case MDLVertexAttributeTangent:
                tangentOffset = attr.offset
            case MDLVertexAttributeTextureCoordinate:
                texCoordOffset = attr.offset
            default:
                break
            }
        }
        
        // Process each submesh
        guard let submeshes = mesh.submeshes as? [MDLSubmesh] else { return }
        
        for submesh in submeshes {
            let indexBuffer = submesh.indexBuffer
            let indexData = indexBuffer.map()
            let indexCount = submesh.indexCount
            
            // Detect material type from submesh/material name for trees
            // This allows bark/trunk parts to use trunk texture and leaves to use foliage
            var effectiveMaterialIndex = materialIndex
            let submeshName = submesh.name.lowercased()
            let materialName = submesh.material?.name.lowercased() ?? ""
            let combinedName = submeshName + " " + materialName
            
            // Detect material type from submesh/material names
            if combinedName.contains("bark") || combinedName.contains("trunk") || 
               combinedName.contains("stem") || combinedName.contains("branch") ||
               combinedName.contains("wood") {
                effectiveMaterialIndex = 1  // treeTrunk material index
            } else if combinedName.contains("leaf") || combinedName.contains("leaves") || 
                      combinedName.contains("foliage") || combinedName.contains("frond") ||
                      combinedName.contains("needle") || combinedName.contains("flower") ||
                      combinedName.contains("fruit") {
                effectiveMaterialIndex = 2  // foliage material index
            }
            
            // Process triangles
            for i in Swift.stride(from: 0, to: indexCount, by: 3) {
                var indices: [Int] = []
                
                // Reverse winding order (swap indices 1 and 2) to fix inverted faces
                switch submesh.indexType {
                case .invalid:
                    continue
                case .uInt16:
                    let ptr = indexData.bytes.bindMemory(to: UInt16.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+2]), Int(ptr[i+1])]  // Reversed winding
                case .uInt32:
                    let ptr = indexData.bytes.bindMemory(to: UInt32.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+2]), Int(ptr[i+1])]  // Reversed winding
                case .uInt8:
                    let ptr = indexData.bytes.bindMemory(to: UInt8.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+2]), Int(ptr[i+1])]  // Reversed winding
                @unknown default:
                    continue
                }
                
                // First pass: read positions for all 3 vertices
                var positions: [simd_float3] = []
                for idx in indices {
                    let basePtr = vertexData.bytes.advanced(by: idx * stride)
                    let posPtr = basePtr.advanced(by: positionOffset).bindMemory(to: Float.self, capacity: 3)
                    let position = simd_float3(posPtr[0], posPtr[1], posPtr[2])
                    positions.append(position)
                    
                    // Update bounds
                    minBound = simd_min(minBound, position)
                    maxBound = simd_max(maxBound, position)
                }
                
                // Calculate face normal from triangle vertices
                let edge1 = positions[1] - positions[0]
                let edge2 = positions[2] - positions[0]
                var faceNormal = simd_normalize(simd_cross(edge1, edge2))
                
                // Handle degenerate triangles
                if faceNormal.x.isNaN || faceNormal.y.isNaN || faceNormal.z.isNaN {
                    faceNormal = simd_float3(0, 1, 0)
                }
                
                // Calculate tangent from first edge
                var tangent = simd_normalize(edge1)
                if tangent.x.isNaN || tangent.y.isNaN || tangent.z.isNaN {
                    tangent = simd_float3(1, 0, 0)
                }
                
                // Second pass: create vertices with calculated normal
                for (vertIdx, idx) in indices.enumerated() {
                    let position = positions[vertIdx]
                    let basePtr = vertexData.bytes.advanced(by: idx * stride)
                    
                    // Read texCoord (with fallback to procedural UVs based on position)
                    var texCoord = simd_float2(0, 0)
                    var hasValidUV = false
                    if texCoordOffset < stride - 4 {
                        let texPtr = basePtr.advanced(by: texCoordOffset).bindMemory(to: Float.self, capacity: 2)
                        texCoord = simd_float2(texPtr[0], texPtr[1])
                        // Check if UV is valid (not all zeros or extreme values)
                        if abs(texPtr[0]) > 0.001 || abs(texPtr[1]) > 0.001 {
                            hasValidUV = true
                        }
                    }
                    
                    // Generate procedural UVs if model doesn't have valid ones
                    // Use triplanar-style mapping based on normal direction
                    if !hasValidUV {
                        let uvScale: Float = 0.08  // Smaller = more texture repetition
                        let absNormal = simd_abs(faceNormal)
                        if absNormal.y > absNormal.x && absNormal.y > absNormal.z {
                            // Top/bottom facing - use XZ
                            texCoord = simd_float2(position.x * uvScale, position.z * uvScale)
                        } else if absNormal.x > absNormal.z {
                            // Left/right facing - use YZ
                            texCoord = simd_float2(position.z * uvScale, position.y * uvScale)
                        } else {
                            // Front/back facing - use XY
                            texCoord = simd_float2(position.x * uvScale, position.y * uvScale)
                        }
                    }
                    
                    let vertex = TexturedVertex(
                        position: position,
                        normal: faceNormal,
                        tangent: tangent,
                        texCoord: texCoord,
                        materialIndex: effectiveMaterialIndex
                    )
                    vertices.append(vertex)
                }
            }
        }
    }
    
    // MARK: - Chest Model Loading (with separate lid for animation)
    
    /// Load a treasure chest model with separate base and lid meshes for animation
    /// - Parameters:
    ///   - url: URL to the USDZ file
    ///   - materialIndex: Material index for the chest
    ///   - lidSubmeshNames: Names of submeshes that make up the lid (e.g., ["topdetail_low", "topwood_low"])
    /// - Returns: LoadedChestModel with separate base and lid buffers
    func loadChestModel(from url: URL, materialIndex: UInt32, lidSubmeshNames: [String]) -> LoadedChestModel? {
        // Create a Metal vertex descriptor matching our TexturedVertex layout
        let metalDescriptor = MTLVertexDescriptor()
        metalDescriptor.attributes[0].format = .float3  // position
        metalDescriptor.attributes[0].offset = 0
        metalDescriptor.attributes[0].bufferIndex = 0
        metalDescriptor.attributes[1].format = .float3  // normal
        metalDescriptor.attributes[1].offset = 12
        metalDescriptor.attributes[1].bufferIndex = 0
        metalDescriptor.attributes[2].format = .float3  // tangent
        metalDescriptor.attributes[2].offset = 24
        metalDescriptor.attributes[2].bufferIndex = 0
        metalDescriptor.attributes[3].format = .float2  // texCoord
        metalDescriptor.attributes[3].offset = 36
        metalDescriptor.attributes[3].bufferIndex = 0
        metalDescriptor.layouts[0].stride = MemoryLayout<TexturedVertex>.stride
        
        // Convert to Model I/O descriptor
        let mdlDescriptor = MTKModelIOVertexDescriptorFromMetal(metalDescriptor)
        (mdlDescriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (mdlDescriptor.attributes[1] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        (mdlDescriptor.attributes[2] as! MDLVertexAttribute).name = MDLVertexAttributeTangent
        (mdlDescriptor.attributes[3] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        
        // Create allocator
        let allocator = MTKMeshBufferAllocator(device: device)
        
        // Load the USD asset
        let asset = MDLAsset(url: url, vertexDescriptor: mdlDescriptor, bufferAllocator: allocator)
        
        guard asset.count > 0 else {
            debugLog("[USDLoader] Chest: No objects in asset")
            return nil
        }
        
        // Collect vertices into separate arrays for base and lid
        var baseVertices: [TexturedVertex] = []
        var lidVertices: [TexturedVertex] = []
        var minBound = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBound = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var lidMinBound = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var lidMaxBound = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        
        // Convert lid names to lowercase set for comparison
        let lidNamesLower = Set(lidSubmeshNames.map { $0.lowercased() })
        
        // Iterate through all objects in the asset
        for i in 0..<asset.count {
            let object = asset.object(at: i)
            processChestObject(
                object,
                materialIndex: materialIndex,
                lidSubmeshNames: lidNamesLower,
                baseVertices: &baseVertices,
                lidVertices: &lidVertices,
                minBound: &minBound,
                maxBound: &maxBound,
                lidMinBound: &lidMinBound,
                lidMaxBound: &lidMaxBound
            )
        }
        
        guard !baseVertices.isEmpty else { return nil }
        
        // Create base vertex buffer
        guard let baseBuffer = device.makeBuffer(bytes: baseVertices,
                                                  length: MemoryLayout<TexturedVertex>.stride * baseVertices.count,
                                                  options: .storageModeShared) else {
            return nil
        }
        
        // Create lid vertex buffer (may be empty if no lid found)
        let lidBuffer: MTLBuffer
        if !lidVertices.isEmpty {
            guard let buffer = device.makeBuffer(bytes: lidVertices,
                                                  length: MemoryLayout<TexturedVertex>.stride * lidVertices.count,
                                                  options: .storageModeShared) else {
                return nil
            }
            lidBuffer = buffer
        } else {
            // Create empty buffer if no lid
            lidBuffer = device.makeBuffer(length: 16, options: .storageModeShared)!
        }
        
        // Calculate hinge position - back center of the lid at its lowest point
        // For a Y-up model: X = left-right, Y = up-down, Z = front-back
        // The hinge is at the back (min or max Z) and bottom (min Y) of the lid
        let hingeOffset: simd_float3
        if !lidVertices.isEmpty {
            // Hinge is at the back-bottom of the lid bounds
            // For Y-up: bottom = minY, back = maxZ (assuming +Z is back)
            hingeOffset = simd_float3(
                (lidMinBound.x + lidMaxBound.x) / 2,  // Center X (left-right)
                lidMinBound.y,                         // Bottom of lid (min Y)
                lidMaxBound.z                          // Back of lid (max Z)
            )
        } else {
            hingeOffset = simd_float3(0, 0, 0)
        }
        
        return LoadedChestModel(
            baseVertexBuffer: baseBuffer,
            baseVertexCount: baseVertices.count,
            lidVertexBuffer: lidBuffer,
            lidVertexCount: lidVertices.count,
            boundingBox: (minBound, maxBound),
            lidBounds: (lidMinBound, lidMaxBound),
            hingeOffset: hingeOffset
        )
    }
    
    /// Recursively process MDL objects for chest, separating lid and base
    private func processChestObject(
        _ object: MDLObject,
        materialIndex: UInt32,
        lidSubmeshNames: Set<String>,
        baseVertices: inout [TexturedVertex],
        lidVertices: inout [TexturedVertex],
        minBound: inout simd_float3,
        maxBound: inout simd_float3,
        lidMinBound: inout simd_float3,
        lidMaxBound: inout simd_float3
    ) {
        if let mesh = object as? MDLMesh {
            extractChestMeshVertices(
                mesh,
                materialIndex: materialIndex,
                lidSubmeshNames: lidSubmeshNames,
                baseVertices: &baseVertices,
                lidVertices: &lidVertices,
                minBound: &minBound,
                maxBound: &maxBound,
                lidMinBound: &lidMinBound,
                lidMaxBound: &lidMaxBound
            )
        }
        
        // Also check the object name - some models have submesh names in the object
        let objectName = object.name.lowercased()
        let isLidObject = lidSubmeshNames.contains { objectName.contains($0) }
        
        // Process children
        for child in object.children.objects {
            if isLidObject {
                // If parent is a lid object, all children go to lid
                processChestObjectAsLid(child, materialIndex: materialIndex, lidVertices: &lidVertices, lidMinBound: &lidMinBound, lidMaxBound: &lidMaxBound, overallMin: &minBound, overallMax: &maxBound)
            } else {
                processChestObject(child, materialIndex: materialIndex, lidSubmeshNames: lidSubmeshNames, baseVertices: &baseVertices, lidVertices: &lidVertices, minBound: &minBound, maxBound: &maxBound, lidMinBound: &lidMinBound, lidMaxBound: &lidMaxBound)
            }
        }
    }
    
    /// Process an object that is known to be part of the lid
    private func processChestObjectAsLid(
        _ object: MDLObject,
        materialIndex: UInt32,
        lidVertices: inout [TexturedVertex],
        lidMinBound: inout simd_float3,
        lidMaxBound: inout simd_float3,
        overallMin: inout simd_float3,
        overallMax: inout simd_float3
    ) {
        if let mesh = object as? MDLMesh {
            extractMeshVertices(mesh, materialIndex: materialIndex, vertices: &lidVertices, minBound: &lidMinBound, maxBound: &lidMaxBound)
            // Also update overall bounds
            overallMin = simd_min(overallMin, lidMinBound)
            overallMax = simd_max(overallMax, lidMaxBound)
        }
        
        for child in object.children.objects {
            processChestObjectAsLid(child, materialIndex: materialIndex, lidVertices: &lidVertices, lidMinBound: &lidMinBound, lidMaxBound: &lidMaxBound, overallMin: &overallMin, overallMax: &overallMax)
        }
    }
    
    /// Extract vertices from a chest mesh, separating lid and base based on submesh names
    private func extractChestMeshVertices(
        _ mesh: MDLMesh,
        materialIndex: UInt32,
        lidSubmeshNames: Set<String>,
        baseVertices: inout [TexturedVertex],
        lidVertices: inout [TexturedVertex],
        minBound: inout simd_float3,
        maxBound: inout simd_float3,
        lidMinBound: inout simd_float3,
        lidMaxBound: inout simd_float3
    ) {
        // Get vertex buffers
        let vertexBuffers = mesh.vertexBuffers
        guard !vertexBuffers.isEmpty else { return }
        
        let vertexBuffer = vertexBuffers[0]
        let vertexData = vertexBuffer.map()
        
        guard let layout = mesh.vertexDescriptor.layouts[0] as? MDLVertexBufferLayout else { return }
        let stride = layout.stride
        
        // Get attribute offsets
        var positionOffset = 0
        var normalOffset = 12
        var texCoordOffset = 36
        
        for attr in mesh.vertexDescriptor.attributes as! [MDLVertexAttribute] {
            switch attr.name {
            case MDLVertexAttributePosition:
                positionOffset = attr.offset
            case MDLVertexAttributeNormal:
                normalOffset = attr.offset
            case MDLVertexAttributeTextureCoordinate:
                texCoordOffset = attr.offset
            default:
                break
            }
        }
        
        guard let submeshes = mesh.submeshes as? [MDLSubmesh] else { return }
        
        for submesh in submeshes {
            let submeshNameLower = submesh.name.lowercased()
            let isLid = lidSubmeshNames.contains { submeshNameLower.contains($0) }
            
            let indexBuffer = submesh.indexBuffer
            let indexData = indexBuffer.map()
            let indexCount = submesh.indexCount
            
            // Process triangles - reverse winding order to match Metal's coordinate system
            // This matches the standard extractMeshVertices method used for cabin/trees
            for i in Swift.stride(from: 0, to: indexCount, by: 3) {
                var indices: [Int] = []
                
                switch submesh.indexType {
                case .uInt16:
                    let ptr = indexData.bytes.bindMemory(to: UInt16.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+2]), Int(ptr[i+1])]  // Reversed winding
                case .uInt32:
                    let ptr = indexData.bytes.bindMemory(to: UInt32.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+2]), Int(ptr[i+1])]  // Reversed winding
                case .uInt8:
                    let ptr = indexData.bytes.bindMemory(to: UInt8.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+2]), Int(ptr[i+1])]  // Reversed winding
                default:
                    continue
                }
                
                // First pass: read positions for all 3 vertices
                var positions: [simd_float3] = []
                for idx in indices {
                    let basePtr = vertexData.bytes.advanced(by: idx * stride)
                    let posPtr = basePtr.advanced(by: positionOffset).bindMemory(to: Float.self, capacity: 3)
                    let position = simd_float3(posPtr[0], posPtr[1], posPtr[2])
                    positions.append(position)
                }
                
                // Calculate face normal from triangle vertices (as fallback)
                let edge1 = positions[1] - positions[0]
                let edge2 = positions[2] - positions[0]
                var faceNormal = simd_normalize(simd_cross(edge1, edge2))
                if faceNormal.x.isNaN || faceNormal.y.isNaN || faceNormal.z.isNaN {
                    faceNormal = simd_float3(0, 1, 0)
                }
                
                // Calculate tangent from first edge
                var tangent = simd_normalize(edge1)
                if tangent.x.isNaN || tangent.y.isNaN || tangent.z.isNaN {
                    tangent = simd_float3(1, 0, 0)
                }
                
                // Second pass: create vertices - read normals from model when available (like skeletal loader)
                for (vertIdx, idx) in indices.enumerated() {
                    let position = positions[vertIdx]
                    let basePtr = vertexData.bytes.advanced(by: idx * stride)
                    
                    // Read normal from model data if available, otherwise use face normal
                    var normal = faceNormal
                    if normalOffset >= 0 && normalOffset < stride - 8 {
                        let normPtr = basePtr.advanced(by: normalOffset).bindMemory(to: Float.self, capacity: 3)
                        let modelNormal = simd_float3(normPtr[0], normPtr[1], normPtr[2])
                        // Only use model normal if it's valid (non-zero length)
                        if simd_length(modelNormal) > 0.001 {
                            normal = simd_normalize(modelNormal)
                        }
                    }
                    
                    // Read texCoord
                    var texCoord = simd_float2(0, 0)
                    var hasValidUV = false
                    if texCoordOffset < stride - 4 {
                        let texPtr = basePtr.advanced(by: texCoordOffset).bindMemory(to: Float.self, capacity: 2)
                        texCoord = simd_float2(texPtr[0], texPtr[1])
                        if abs(texPtr[0]) > 0.001 || abs(texPtr[1]) > 0.001 {
                            hasValidUV = true
                        }
                    }
                    
                    // Generate procedural UVs if model doesn't have valid ones
                    if !hasValidUV {
                        let uvScale: Float = 0.08
                        let absNormal = simd_abs(faceNormal)
                        if absNormal.y > absNormal.x && absNormal.y > absNormal.z {
                            texCoord = simd_float2(position.x * uvScale, position.z * uvScale)
                        } else if absNormal.x > absNormal.z {
                            texCoord = simd_float2(position.z * uvScale, position.y * uvScale)
                        } else {
                            texCoord = simd_float2(position.x * uvScale, position.y * uvScale)
                        }
                    }
                    
                    let vertex = TexturedVertex(
                        position: position,
                        normal: normal,
                        tangent: tangent,
                        texCoord: texCoord,
                        materialIndex: materialIndex
                    )
                    
                    // Add to appropriate array and update bounds
                    if isLid {
                        lidVertices.append(vertex)
                        lidMinBound = simd_min(lidMinBound, position)
                        lidMaxBound = simd_max(lidMaxBound, position)
                    } else {
                        baseVertices.append(vertex)
                    }
                    
                    // Always update overall bounds
                    minBound = simd_min(minBound, position)
                    maxBound = simd_max(maxBound, position)
                }
            }
        }
    }
    
    /// Load a texture from a file (supports PNG, JPG, EXR via conversion)
    func loadTexture(named name: String, withExtension ext: String = "png") -> MTLTexture? {
        // Try bundle first
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return loadTexture(from: url)
        }
        
        // Try in textures subdirectory
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "textures") {
            return loadTexture(from: url)
        }
        
        debugLog("[USDLoader] Could not find texture: \(name).\(ext)")
        return nil
    }
    
    /// Load a texture from a URL
    func loadTexture(from url: URL) -> MTLTexture? {
        do {
            let options: [MTKTextureLoader.Option: Any] = [
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue,
                .generateMipmaps: true,
                .SRGB: false
            ]
            
            let texture = try textureLoader.newTexture(URL: url, options: options)
            debugLog("[USDLoader] Loaded texture: \(url.lastPathComponent)")
            return texture
        } catch {
            debugLog("[USDLoader] Failed to load texture: \(error)")
            return nil
        }
    }
}

