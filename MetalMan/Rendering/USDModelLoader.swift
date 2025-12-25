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
            
            // Process triangles
            for i in Swift.stride(from: 0, to: indexCount, by: 3) {
                var indices: [Int] = []
                
                switch submesh.indexType {
                case .invalid:
                    continue
                case .uInt16:
                    let ptr = indexData.bytes.bindMemory(to: UInt16.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+1]), Int(ptr[i+2])]
                case .uInt32:
                    let ptr = indexData.bytes.bindMemory(to: UInt32.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+1]), Int(ptr[i+2])]
                case .uInt8:
                    let ptr = indexData.bytes.bindMemory(to: UInt8.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+1]), Int(ptr[i+2])]
                @unknown default:
                    continue
                }
                
                for idx in indices {
                    let basePtr = vertexData.bytes.advanced(by: idx * stride)
                    
                    // Read position
                    let posPtr = basePtr.advanced(by: positionOffset).bindMemory(to: Float.self, capacity: 3)
                    let position = simd_float3(posPtr[0], posPtr[1], posPtr[2])
                    
                    // Update bounds
                    minBound = simd_min(minBound, position)
                    maxBound = simd_max(maxBound, position)
                    
                    // Read normal (with fallback)
                    var normal = simd_float3(0, 1, 0)
                    if normalOffset < stride - 8 {
                        let normPtr = basePtr.advanced(by: normalOffset).bindMemory(to: Float.self, capacity: 3)
                        normal = simd_float3(normPtr[0], normPtr[1], normPtr[2])
                    }
                    
                    // Read tangent (with fallback)
                    var tangent = simd_float3(1, 0, 0)
                    if tangentOffset < stride - 8 {
                        let tanPtr = basePtr.advanced(by: tangentOffset).bindMemory(to: Float.self, capacity: 3)
                        tangent = simd_float3(tanPtr[0], tanPtr[1], tanPtr[2])
                    }
                    
                    // Read texCoord (with fallback)
                    var texCoord = simd_float2(0, 0)
                    if texCoordOffset < stride - 4 {
                        let texPtr = basePtr.advanced(by: texCoordOffset).bindMemory(to: Float.self, capacity: 2)
                        texCoord = simd_float2(texPtr[0], texPtr[1])
                    }
                    
                    let vertex = TexturedVertex(
                        position: position,
                        normal: normal,
                        tangent: tangent,
                        texCoord: texCoord,
                        materialIndex: materialIndex
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

