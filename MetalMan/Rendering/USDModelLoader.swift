import Metal
import MetalKit
import ModelIO
import simd

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
    
    /// Load a USD model from a file path
    func loadModel(named name: String, withExtension ext: String = "usdc", materialIndex: UInt32) -> LoadedModel? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("[USDLoader] Could not find \(name).\(ext) in bundle")
            return nil
        }
        
        return loadModel(from: url, materialIndex: materialIndex)
    }
    
    /// Print the full hierarchy of a USD asset for debugging
    func printAssetHierarchy(from url: URL) {
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: allocator)
        
        print("\n[USDLoader] ========== ASSET HIERARCHY ==========")
        print("[USDLoader] URL: \(url.lastPathComponent)")
        print("[USDLoader] Object count: \(asset.count)")
        
        for i in 0..<asset.count {
            let object = asset.object(at: i)
            printObjectHierarchy(object, indent: 0)
        }
        print("[USDLoader] ======================================\n")
    }
    
    private func printObjectHierarchy(_ object: MDLObject, indent: Int) {
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
            print(info)
            // Print joint paths
            let jointPaths = skeleton.jointPaths
            print("\(indentStr)  Joint count: \(jointPaths.count)")
            for (i, path) in jointPaths.enumerated() {
                if i < 20 {  // Print first 20 joints
                    print("\(indentStr)    [\(i)] \(path)")
                } else if i == 20 {
                    print("\(indentStr)    ... and \(jointPaths.count - 20) more joints")
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
        
        print(info)
        
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
        
        guard asset.count > 0 else {
            print("[USDLoader] No objects in asset")
            return nil
        }
        
        // Collect all vertices from all meshes
        var allVertices: [TexturedVertex] = []
        var minBound = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBound = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        
        // Iterate through all objects in the asset
        for i in 0..<asset.count {
            let object = asset.object(at: i)
            processObject(object, materialIndex: materialIndex, vertices: &allVertices, minBound: &minBound, maxBound: &maxBound)
        }
        
        guard !allVertices.isEmpty else {
            print("[USDLoader] No vertices extracted from model")
            return nil
        }
        
        // Create vertex buffer
        guard let vertexBuffer = device.makeBuffer(bytes: allVertices, 
                                                    length: MemoryLayout<TexturedVertex>.stride * allVertices.count,
                                                    options: .storageModeShared) else {
            print("[USDLoader] Failed to create vertex buffer")
            return nil
        }
        
        print("[USDLoader] Loaded model with \(allVertices.count) vertices")
        print("[USDLoader] Bounds: min=\(minBound), max=\(maxBound)")
        
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
            
            // Log submesh info for debugging (first few only)
            if vertices.count < 1000 {
                print("[USDLoader] Submesh: '\(submesh.name)' material: '\(submesh.material?.name ?? "none")'")
            }
            
            // Check for bark/trunk keywords
            if combinedName.contains("bark") || combinedName.contains("trunk") || 
               combinedName.contains("stem") || combinedName.contains("branch") ||
               combinedName.contains("wood") {
                effectiveMaterialIndex = 1  // treeTrunk material index
                if vertices.count < 1000 {
                    print("[USDLoader]   -> Detected as TRUNK (material index 1)")
                }
            }
            // Check for leaves/foliage keywords
            else if combinedName.contains("leaf") || combinedName.contains("leaves") || 
                    combinedName.contains("foliage") || combinedName.contains("frond") ||
                    combinedName.contains("needle") || combinedName.contains("flower") ||
                    combinedName.contains("fruit") {
                effectiveMaterialIndex = 2  // foliage material index
                if vertices.count < 1000 {
                    print("[USDLoader]   -> Detected as FOLIAGE (material index 2)")
                }
            } else if vertices.count < 1000 {
                print("[USDLoader]   -> Using default material index \(materialIndex)")
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
        
        print("[USDLoader] Could not find texture: \(name).\(ext)")
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
            print("[USDLoader] Loaded texture: \(url.lastPathComponent)")
            return texture
        } catch {
            print("[USDLoader] Failed to load texture: \(error)")
            return nil
        }
    }
}

