//
//  SkeletalMesh.swift
//  MetalMan
//
//  Skeletal mesh loading and animation for rigged 3D models (Mixamo compatible)
//

import Metal
import MetalKit
import ModelIO
import simd

// MARK: - Skinned Vertex

/// Vertex structure for skeletal meshes with bone weights
/// Packed layout to match Metal shader expectations (no SIMD alignment padding)
struct SkinnedVertex {
    var position: (Float, Float, Float)      // 12 bytes
    var normal: (Float, Float, Float)        // 12 bytes
    var texCoord: (Float, Float)             // 8 bytes
    var boneIndices: (UInt32, UInt32, UInt32, UInt32)  // 16 bytes
    var boneWeights: (Float, Float, Float, Float)      // 16 bytes
    var materialIndex: UInt32                // 4 bytes
    var padding: UInt32 = 0                  // 4 bytes for alignment
    // Total: 72 bytes
    
    static var stride: Int {
        return MemoryLayout<SkinnedVertex>.stride
    }
    
    init(position: simd_float3, normal: simd_float3, texCoord: simd_float2,
         boneIndices: simd_uint4, boneWeights: simd_float4, materialIndex: UInt32) {
        self.position = (position.x, position.y, position.z)
        self.normal = (normal.x, normal.y, normal.z)
        self.texCoord = (texCoord.x, texCoord.y)
        self.boneIndices = (boneIndices.x, boneIndices.y, boneIndices.z, boneIndices.w)
        self.boneWeights = (boneWeights.x, boneWeights.y, boneWeights.z, boneWeights.w)
        self.materialIndex = materialIndex
    }
}

// MARK: - Bone

/// Represents a single bone in the skeleton
struct Bone {
    let name: String
    let index: Int
    var parentIndex: Int  // -1 for root
    var bindPose: simd_float4x4          // Local bind pose transform
    var inverseBindMatrix: simd_float4x4  // World space inverse bind matrix
    
    init(name: String, index: Int, parentIndex: Int = -1) {
        self.name = name
        self.index = index
        self.parentIndex = parentIndex
        self.bindPose = matrix_identity_float4x4
        self.inverseBindMatrix = matrix_identity_float4x4
    }
}

// MARK: - Animation Keyframe

/// A single keyframe in an animation
struct AnimationKeyframe {
    let time: Float
    let boneTransforms: [simd_float4x4]  // Local transform for each bone at this time
}

// MARK: - Animation Clip

/// An animation clip containing keyframes
struct AnimationClip {
    let name: String
    let duration: Float
    let keyframes: [AnimationKeyframe]
    let isLooping: Bool
    
    init(name: String, duration: Float, keyframes: [AnimationKeyframe], isLooping: Bool = true) {
        self.name = name
        self.duration = duration
        self.keyframes = keyframes
        self.isLooping = isLooping
    }
    
    /// Get interpolated bone transforms at a given time
    func getBoneTransforms(at time: Float, boneCount: Int) -> [simd_float4x4] {
        guard !keyframes.isEmpty else {
            return Array(repeating: matrix_identity_float4x4, count: boneCount)
        }
        
        let clampedTime = isLooping ? time.truncatingRemainder(dividingBy: max(duration, 0.001)) : min(time, duration)
        
        // Find surrounding keyframes
        var prevIdx = 0
        var nextIdx = 0
        
        for i in 0..<keyframes.count {
            if keyframes[i].time <= clampedTime {
                prevIdx = i
                nextIdx = min(i + 1, keyframes.count - 1)
            }
        }
        
        let prevFrame = keyframes[prevIdx]
        let nextFrame = keyframes[nextIdx]
        
        // Calculate interpolation factor
        let frameDuration = nextFrame.time - prevFrame.time
        let t: Float = frameDuration > 0.001 ? (clampedTime - prevFrame.time) / frameDuration : 0
        
        // Interpolate transforms
        var result: [simd_float4x4] = []
        for i in 0..<boneCount {
            let prev = i < prevFrame.boneTransforms.count ? prevFrame.boneTransforms[i] : matrix_identity_float4x4
            let next = i < nextFrame.boneTransforms.count ? nextFrame.boneTransforms[i] : matrix_identity_float4x4
            result.append(lerpMatrix(prev, next, t: t))
        }
        
        return result
    }
}

/// Linear interpolation between two matrices
private func lerpMatrix(_ a: simd_float4x4, _ b: simd_float4x4, t: Float) -> simd_float4x4 {
    return simd_float4x4(
        simd_mix(a.columns.0, b.columns.0, simd_float4(repeating: t)),
        simd_mix(a.columns.1, b.columns.1, simd_float4(repeating: t)),
        simd_mix(a.columns.2, b.columns.2, simd_float4(repeating: t)),
        simd_mix(a.columns.3, b.columns.3, simd_float4(repeating: t))
    )
}

// MARK: - Skeletal Mesh

/// A loaded skeletal mesh with skeleton and optional animations
final class SkeletalMesh {
    let vertexBuffer: MTLBuffer
    let vertexCount: Int
    let bones: [Bone]
    let boneNameToIndex: [String: Int]
    let animations: [String: AnimationClip]
    let boundingBox: (min: simd_float3, max: simd_float3)
    
    /// Texture extracted from the USDZ file (if available)
    let texture: MTLTexture?
    
    /// Whether this mesh has valid joint weight data for skeletal animation
    let hasValidJointData: Bool
    
    /// Buffer containing bone transform matrices (updated each frame)
    let boneMatrixBuffer: MTLBuffer
    
    /// Maximum number of bones supported
    static let maxBones = 128
    
    private var currentBoneMatrices: [simd_float4x4]
    
    init(device: MTLDevice, vertices: [SkinnedVertex], bones: [Bone], 
         boneNameToIndex: [String: Int],
         animations: [String: AnimationClip] = [:], 
         boundingBox: (min: simd_float3, max: simd_float3),
         texture: MTLTexture? = nil,
         hasValidJointData: Bool = false) {
        
        self.texture = texture
        self.hasValidJointData = hasValidJointData
        
        // Use actual MemoryLayout stride to ensure buffer matches array layout
        let actualStride = MemoryLayout<SkinnedVertex>.stride
        print("[SkeletalMesh] Creating vertex buffer with \(vertices.count) vertices, stride=\(actualStride)")
        
        self.vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: actualStride * vertices.count,
            options: .storageModeShared
        )!
        self.vertexCount = vertices.count
        self.bones = bones
        self.boneNameToIndex = boneNameToIndex
        self.animations = animations
        self.boundingBox = boundingBox
        
        // Initialize bone matrices to identity
        self.currentBoneMatrices = Array(repeating: matrix_identity_float4x4, count: Self.maxBones)
        
        // Create bone matrix buffer
        self.boneMatrixBuffer = device.makeBuffer(
            length: MemoryLayout<simd_float4x4>.stride * Self.maxBones,
            options: .storageModeShared
        )!
        
        // Initialize with bind pose
        resetToBindPose()
    }
    
    /// Reset all bones to bind pose (identity - no deformation)
    func resetToBindPose() {
        for i in 0..<Self.maxBones {
            currentBoneMatrices[i] = matrix_identity_float4x4
        }
        updateGPUBuffer()
    }
    
    /// Update bone matrices for the current animation frame
    /// Animation transforms are ABSOLUTE local transforms from the animation clip
    /// Identity transform = use bind pose, non-identity = use animation's transform directly
    func updateBoneMatrices(_ animationTransforms: [simd_float4x4]) {
        if hasValidJointData {
            // Calculate world transforms by traversing the bone hierarchy
            var worldTransforms = Array(repeating: matrix_identity_float4x4, count: bones.count)
            
            for i in 0..<bones.count {
                let bone = bones[i]
                
                // Get animation transform
                let animTransform = i < animationTransforms.count ? animationTransforms[i] : matrix_identity_float4x4
                
                // Check if animation provides a transform for this bone
                // If animTransform is identity, use bind pose; otherwise use animation's absolute transform
                let isIdentity = isIdentityMatrix(animTransform)
                let localTransform = isIdentity ? bone.bindPose : animTransform
                
                if bone.parentIndex >= 0 && bone.parentIndex < worldTransforms.count {
                    worldTransforms[i] = worldTransforms[bone.parentIndex] * localTransform
                } else {
                    worldTransforms[i] = localTransform
                }
            }
            
            // Calculate final bone matrices (world * inverseBindMatrix)
            for i in 0..<bones.count {
                currentBoneMatrices[i] = worldTransforms[i] * bones[i].inverseBindMatrix
            }
        } else {
            // No valid joint data - keep identity matrices (bind pose)
            for i in 0..<Self.maxBones {
                currentBoneMatrices[i] = matrix_identity_float4x4
            }
        }
        
        updateGPUBuffer()
    }
    
    /// Check if a matrix is approximately identity
    private func isIdentityMatrix(_ m: simd_float4x4) -> Bool {
        let identity = matrix_identity_float4x4
        let epsilon: Float = 0.0001
        
        for col in 0..<4 {
            for row in 0..<4 {
                if abs(m[col][row] - identity[col][row]) > epsilon {
                    return false
                }
            }
        }
        return true
    }
    
    private func updateGPUBuffer() {
        memcpy(boneMatrixBuffer.contents(), &currentBoneMatrices, 
               MemoryLayout<simd_float4x4>.stride * min(bones.count, Self.maxBones))
    }
}

// MARK: - Skeletal Mesh Loader

/// Loads USDZ models with skeletal animation data (Mixamo compatible)
final class SkeletalMeshLoader {
    
    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader
    
    init(device: MTLDevice) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
    }
    
    /// Create a vertex descriptor that includes joint indices and weights
    private func createSkinnedVertexDescriptor() -> MDLVertexDescriptor {
        let descriptor = MDLVertexDescriptor()
        
        var offset = 0
        
        // Position (float3) - 12 bytes
        let positionAttr = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: offset,
            bufferIndex: 0
        )
        descriptor.attributes[0] = positionAttr
        offset += 12
        
        // Normal (float3) - 12 bytes
        let normalAttr = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: offset,
            bufferIndex: 0
        )
        descriptor.attributes[1] = normalAttr
        offset += 12
        
        // Texture coordinates (float2) - 8 bytes
        let texCoordAttr = MDLVertexAttribute(
            name: MDLVertexAttributeTextureCoordinate,
            format: .float2,
            offset: offset,
            bufferIndex: 0
        )
        descriptor.attributes[2] = texCoordAttr
        offset += 8
        
        // Joint indices (ushort4) - 8 bytes (USD typically uses ushort4)
        let jointIndicesAttr = MDLVertexAttribute(
            name: MDLVertexAttributeJointIndices,
            format: .uShort4,
            offset: offset,
            bufferIndex: 0
        )
        descriptor.attributes[3] = jointIndicesAttr
        offset += 8
        
        // Joint weights (float4) - 16 bytes
        let jointWeightsAttr = MDLVertexAttribute(
            name: MDLVertexAttributeJointWeights,
            format: .float4,
            offset: offset,
            bufferIndex: 0
        )
        descriptor.attributes[4] = jointWeightsAttr
        offset += 16
        
        // Set layout stride
        let layout = MDLVertexBufferLayout(stride: offset)
        descriptor.layouts[0] = layout
        
        print("[SkeletalLoader] Created vertex descriptor with stride \(offset), requesting joint data")
        
        return descriptor
    }
    
    /// Load a skeletal mesh from a USDZ file
    func loadSkeletalMesh(from url: URL, materialIndex: UInt32) -> SkeletalMesh? {
        print("[SkeletalLoader] Loading skeletal mesh from: \(url.lastPathComponent)")
        print("[SkeletalLoader] SkinnedVertex size: \(MemoryLayout<SkinnedVertex>.size), stride: \(MemoryLayout<SkinnedVertex>.stride), alignment: \(MemoryLayout<SkinnedVertex>.alignment)")
        
        // Create allocator
        let allocator = MTKMeshBufferAllocator(device: device)
        
        // Create a vertex descriptor that requests joint data
        let vertexDescriptor = createSkinnedVertexDescriptor()
        
        // Load the USD asset with our vertex descriptor
        let asset = MDLAsset(url: url, vertexDescriptor: vertexDescriptor, bufferAllocator: allocator)
        asset.loadTextures()
        
        guard asset.count > 0 else {
            print("[SkeletalLoader] No objects in asset")
            return nil
        }
        
        // Find MDLSkeleton and MDLMesh objects
        var mdlSkeleton: MDLSkeleton?
        var meshObjects: [MDLMesh] = []
        
        for i in 0..<asset.count {
            let object = asset.object(at: i)
            findSkeletonAndMeshes(object, skeleton: &mdlSkeleton, meshes: &meshObjects)
        }
        
        print("[SkeletalLoader] Found \(meshObjects.count) meshes")
        
        // Extract skeleton from MDLSkeleton
        var bones: [Bone] = []
        var boneNameToIndex: [String: Int] = [:]
        
        if let skeleton = mdlSkeleton {
            extractBonesFromMDLSkeleton(skeleton, bones: &bones, boneNameToIndex: &boneNameToIndex)
            print("[SkeletalLoader] Extracted \(bones.count) bones from MDLSkeleton")
        } else {
            print("[SkeletalLoader] No MDLSkeleton found - creating single root bone")
            bones.append(Bone(name: "root", index: 0, parentIndex: -1))
            boneNameToIndex["root"] = 0
        }
        
        // Extract vertices with bone weights
        var vertices: [SkinnedVertex] = []
        var minBound = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBound = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var hasValidJointData = false
        
        for mesh in meshObjects {
            extractSkinnedVertices(mesh, materialIndex: materialIndex, 
                                   boneNameToIndex: boneNameToIndex,
                                   vertices: &vertices, 
                                   minBound: &minBound, maxBound: &maxBound,
                                   hasValidJointData: &hasValidJointData)
        }
        
        if vertices.isEmpty {
            print("[SkeletalLoader] No vertices extracted")
            return nil
        }
        
        print("[SkeletalLoader] Loaded \(vertices.count) skinned vertices")
        print("[SkeletalLoader] Bounds: min=\(minBound), max=\(maxBound)")
        
        if hasValidJointData {
            print("[SkeletalLoader] ✅ Mesh has valid joint weights for animation!")
        }
        
        // Extract texture from materials
        let texture = extractTextureFromMeshes(meshObjects)
        if texture != nil {
            print("[SkeletalLoader] ✅ Extracted texture from USDZ materials")
        } else {
            print("[SkeletalLoader] No texture found in materials")
        }
        
        // Try loading animations using ModelIO deep inspection
        var animations: [String: AnimationClip] = [:]
        
        // Extract animations from the asset
        let extractedAnimations = ModelIOAnimationExtractor.extractFromMDLAsset(asset, device: device)
        
        if !extractedAnimations.isEmpty {
            print("[SkeletalLoader] ✅ Loaded \(extractedAnimations.count) animations from ModelIO")
            
            // Convert extracted animations to our AnimationClip format
            for extracted in extractedAnimations {
                // The extracted animations already have transforms in our skeleton's bone order
                var keyframes: [AnimationKeyframe] = []
                
                for extractedKF in extracted.keyframes {
                    keyframes.append(AnimationKeyframe(time: extractedKF.time, boneTransforms: extractedKF.localTransforms))
                }
                
                if !keyframes.isEmpty {
                    let clip = AnimationClip(name: extracted.name, duration: extracted.duration, keyframes: keyframes)
                    animations[extracted.name] = clip
                    
                    // Set as "walk" animation
                    if animations["walk"] == nil {
                        animations["walk"] = clip
                    }
                }
            }
        }
        
        // Fall back to identity animations if nothing loaded
        if animations.isEmpty {
            print("[SkeletalLoader] No ModelIO animations found, using identity animations")
            animations = createMixamoWalkAnimation(bones: bones, boneNameToIndex: boneNameToIndex)
        }
        
        print("[SkeletalLoader] Total animations: \(animations.count)")
        
        return SkeletalMesh(
            device: device,
            vertices: vertices,
            bones: bones,
            boneNameToIndex: boneNameToIndex,
            animations: animations,
            boundingBox: (minBound, maxBound),
            texture: texture,
            hasValidJointData: hasValidJointData
        )
    }
    
    /// Extract texture from mesh materials
    private func extractTextureFromMeshes(_ meshes: [MDLMesh]) -> MTLTexture? {
        // List of material properties to check for textures
        let semanticsToCheck: [MDLMaterialSemantic] = [
            .baseColor,
            .emission,
            .subsurface,
            .metallic,
            .specular,
            .specularExponent,
            .specularTint,
            .roughness,
            .anisotropic,
            .anisotropicRotation,
            .sheen,
            .sheenTint,
            .clearcoat,
            .clearcoatGloss
        ]
        
        for mesh in meshes {
            guard let submeshes = mesh.submeshes as? [MDLSubmesh] else { continue }
            
            for submesh in submeshes {
                guard let material = submesh.material else { continue }
                
                print("[SkeletalLoader] Checking material: \(material.name)")
                
                // Try each semantic that might have a texture
                for semantic in semanticsToCheck {
                    if let property = material.property(with: semantic) {
                        print("[SkeletalLoader]   Property \(semantic.rawValue): type=\(property.type.rawValue)")
                        
                        if property.type == .texture,
                           let textureValue = property.textureSamplerValue,
                           let mdlTexture = textureValue.texture {
                            
                            print("[SkeletalLoader] Found texture in \(semantic.rawValue)")
                            
                            // Try to load from the texture's URL/name
                            let textureName = mdlTexture.name
                            if !textureName.isEmpty {
                                print("[SkeletalLoader] Texture name: \(textureName)")
                                
                                // Try as URL
                                if let url = URL(string: textureName), let tex = loadTextureFromURL(url) {
                                    return tex
                                }
                                
                                // Try as file path
                                if let tex = loadTextureFromPath(textureName) {
                                    return tex
                                }
                            }
                            
                            // Try to create texture from MDLTexture data
                            if let tex = createTextureFromMDLTexture(mdlTexture) {
                                return tex
                            }
                        }
                        
                        // Check for string paths
                        if property.type == .string, let path = property.stringValue, !path.isEmpty {
                            print("[SkeletalLoader] Found texture path: \(path)")
                            if let tex = loadTextureFromPath(path) {
                                return tex
                            }
                        }
                    }
                }
                
                // Iterate through all properties as last resort
                for i in 0..<material.count {
                    if let prop = material[i] {
                        if prop.type == .texture {
                            print("[SkeletalLoader] Found texture property by index: \(prop.name)")
                            if let textureValue = prop.textureSamplerValue,
                               let mdlTexture = textureValue.texture,
                               let tex = createTextureFromMDLTexture(mdlTexture) {
                                return tex
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
    
    /// Load texture from a file URL
    private func loadTextureFromURL(_ url: URL) -> MTLTexture? {
        do {
            let options: [MTKTextureLoader.Option: Any] = [
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue,
                .generateMipmaps: true,
                .SRGB: false
            ]
            return try textureLoader.newTexture(URL: url, options: options)
        } catch {
            print("[SkeletalLoader] Failed to load texture from URL: \(error)")
            return nil
        }
    }
    
    /// Load texture from a path string
    private func loadTextureFromPath(_ path: String) -> MTLTexture? {
        // Try as bundle resource first
        let filename = (path as NSString).lastPathComponent
        let ext = (filename as NSString).pathExtension
        let name = (filename as NSString).deletingPathExtension
        
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return loadTextureFromURL(url)
        }
        
        // Try as file path
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            return loadTextureFromURL(url)
        }
        
        return nil
    }
    
    /// Create texture from MDLTexture data
    private func createTextureFromMDLTexture(_ mdlTexture: MDLTexture) -> MTLTexture? {
        // Get texture dimensions
        let width = Int(mdlTexture.dimensions.x)
        let height = Int(mdlTexture.dimensions.y)
        let channelCount = Int(mdlTexture.channelCount)
        
        guard width > 0 && height > 0 else { return nil }
        
        print("[SkeletalLoader] MDLTexture: \(width)x\(height), \(channelCount) channels")
        print("[SkeletalLoader] MDLTexture name: \(mdlTexture.name)")
        
        // Try to write to temporary file and load with MTKTextureLoader
        // This handles compressed texture formats (PNG, JPEG) better
        if let imageData = mdlTexture.texelDataWithTopLeftOrigin(atMipLevel: 0, create: true) {
            // Check if this is compressed image data (PNG/JPEG magic bytes)
            let isCompressed = imageData.count < width * height * 3 / 2 // Compressed would be much smaller
            print("[SkeletalLoader] Texture data size: \(imageData.count) bytes, expected raw: \(width * height * channelCount)")
            
            if isCompressed {
                // Try loading as CGImage
                if let dataProvider = CGDataProvider(data: imageData as CFData),
                   let cgImage = CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) ??
                                 CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
                    
                    do {
                        let options: [MTKTextureLoader.Option: Any] = [
                            .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                            .textureStorageMode: MTLStorageMode.private.rawValue,
                            .generateMipmaps: true,
                            .SRGB: true  // Handle sRGB properly
                        ]
                        let texture = try textureLoader.newTexture(cgImage: cgImage, options: options)
                        print("[SkeletalLoader] Created texture from compressed image data via CGImage")
                        return texture
                    } catch {
                        print("[SkeletalLoader] Failed to create texture from CGImage: \(error)")
                    }
                }
            }
        }
        
        // Get texture data for raw pixel approach
        guard let texData = mdlTexture.texelDataWithTopLeftOrigin(atMipLevel: 0, create: true) else {
            print("[SkeletalLoader] Could not get texture data from MDLTexture")
            return nil
        }
        
        // Try to create CGImage from raw data and use MTKTextureLoader
        // This properly handles sRGB color space
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 8
        var bitmapInfo: CGBitmapInfo
        var bytesPerPixelSrc: Int
        
        switch channelCount {
        case 3:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            bytesPerPixelSrc = 3
        case 4:
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            bytesPerPixelSrc = 4
        default:
            bytesPerPixelSrc = channelCount
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        }
        
        // For 3-channel, we need to convert to 4-channel for CGImage
        if channelCount == 3 {
            let pixelCount = width * height
            var rgbaData = Data(count: pixelCount * 4)
            
            texData.withUnsafeBytes { srcBuffer in
                rgbaData.withUnsafeMutableBytes { dstBuffer in
                    guard let srcPtr = srcBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let dstPtr = dstBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return
                    }
                    
                    for i in 0..<pixelCount {
                        dstPtr[i * 4 + 0] = srcPtr[i * 3 + 0]
                        dstPtr[i * 4 + 1] = srcPtr[i * 3 + 1]
                        dstPtr[i * 4 + 2] = srcPtr[i * 3 + 2]
                        dstPtr[i * 4 + 3] = 255
                    }
                }
            }
            
            // Create CGImage from RGBA data
            if let dataProvider = CGDataProvider(data: rgbaData as CFData),
               let cgImage = CGImage(
                   width: width,
                   height: height,
                   bitsPerComponent: 8,
                   bitsPerPixel: 32,
                   bytesPerRow: width * 4,
                   space: colorSpace,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: dataProvider,
                   decode: nil,
                   shouldInterpolate: true,
                   intent: .defaultIntent
               ) {
                do {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                        .textureStorageMode: MTLStorageMode.private.rawValue,
                        .generateMipmaps: true,
                        .SRGB: true
                    ]
                    let texture = try textureLoader.newTexture(cgImage: cgImage, options: options)
                    print("[SkeletalLoader] Created texture \(width)x\(height) via CGImage from RGB data")
                    return texture
                } catch {
                    print("[SkeletalLoader] Failed to create texture from CGImage: \(error)")
                }
            }
        } else if channelCount == 4 {
            // Create CGImage directly from RGBA data
            if let dataProvider = CGDataProvider(data: texData as CFData),
               let cgImage = CGImage(
                   width: width,
                   height: height,
                   bitsPerComponent: 8,
                   bitsPerPixel: 32,
                   bytesPerRow: width * 4,
                   space: colorSpace,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: dataProvider,
                   decode: nil,
                   shouldInterpolate: true,
                   intent: .defaultIntent
               ) {
                do {
                    let options: [MTKTextureLoader.Option: Any] = [
                        .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                        .textureStorageMode: MTLStorageMode.private.rawValue,
                        .generateMipmaps: true,
                        .SRGB: true
                    ]
                    let texture = try textureLoader.newTexture(cgImage: cgImage, options: options)
                    print("[SkeletalLoader] Created texture \(width)x\(height) via CGImage from RGBA data")
                    return texture
                } catch {
                    print("[SkeletalLoader] Failed to create texture from CGImage: \(error)")
                }
            }
        }
        
        // Fallback: manual texture creation
        print("[SkeletalLoader] Falling back to manual texture creation")
        
        let pixelFormat: MTLPixelFormat = .rgba8Unorm_srgb  // Use sRGB for correct color
        let bytesPerPixelOut = 4
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: true
        )
        descriptor.usage = .shaderRead
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        
        // Convert texture data to RGBA
        let pixelCount = width * height
        var rgbaData = Data(count: pixelCount * bytesPerPixelOut)
        
        texData.withUnsafeBytes { srcBuffer in
            rgbaData.withUnsafeMutableBytes { dstBuffer in
                guard let srcPtr = srcBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let dstPtr = dstBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }
                
                switch channelCount {
                case 1:
                    for i in 0..<pixelCount {
                        let gray = srcPtr[i]
                        dstPtr[i * 4 + 0] = gray
                        dstPtr[i * 4 + 1] = gray
                        dstPtr[i * 4 + 2] = gray
                        dstPtr[i * 4 + 3] = 255
                    }
                case 2:
                    for i in 0..<pixelCount {
                        dstPtr[i * 4 + 0] = srcPtr[i * 2 + 0]
                        dstPtr[i * 4 + 1] = srcPtr[i * 2 + 1]
                        dstPtr[i * 4 + 2] = 0
                        dstPtr[i * 4 + 3] = 255
                    }
                case 3:
                    for i in 0..<pixelCount {
                        dstPtr[i * 4 + 0] = srcPtr[i * 3 + 0]
                        dstPtr[i * 4 + 1] = srcPtr[i * 3 + 1]
                        dstPtr[i * 4 + 2] = srcPtr[i * 3 + 2]
                        dstPtr[i * 4 + 3] = 255
                    }
                case 4:
                    memcpy(dstPtr, srcPtr, pixelCount * 4)
                default:
                    for i in 0..<pixelCount {
                        dstPtr[i * 4 + 0] = 255
                        dstPtr[i * 4 + 1] = 0
                        dstPtr[i * 4 + 2] = 255
                        dstPtr[i * 4 + 3] = 255
                    }
                }
            }
        }
        
        let bytesPerRow = width * bytesPerPixelOut
        rgbaData.withUnsafeBytes { rawBufferPointer in
            if let baseAddress = rawBufferPointer.baseAddress {
                texture.replace(
                    region: MTLRegionMake2D(0, 0, width, height),
                    mipmapLevel: 0,
                    withBytes: baseAddress,
                    bytesPerRow: bytesPerRow
                )
            }
        }
        
        print("[SkeletalLoader] Created texture \(width)x\(height) manually (\(channelCount) -> 4 channels)")
        return texture
    }
    
    /// Find MDLSkeleton and MDLMesh objects in the hierarchy
    private func findSkeletonAndMeshes(_ object: MDLObject, skeleton: inout MDLSkeleton?, meshes: inout [MDLMesh]) {
        // Check if this is an MDLSkeleton
        if let skel = object as? MDLSkeleton {
            skeleton = skel
            print("[SkeletalLoader] Found MDLSkeleton: \(skel.name) with \(skel.jointPaths.count) joints")
        }
        
        // Check if this is a mesh
        if let mesh = object as? MDLMesh {
            meshes.append(mesh)
        }
        
        // Recurse into children
        for child in object.children.objects {
            findSkeletonAndMeshes(child, skeleton: &skeleton, meshes: &meshes)
        }
    }
    
    /// Extract bones from MDLSkeleton joint paths
    private func extractBonesFromMDLSkeleton(_ skeleton: MDLSkeleton, bones: inout [Bone], boneNameToIndex: inout [String: Int]) {
        let jointPaths = skeleton.jointPaths
        let jointBindTransforms = skeleton.jointBindTransforms
        let worldBindTransforms = jointBindTransforms.float4x4Array
        
        print("[SkeletalLoader] jointBindTransforms count: \(worldBindTransforms.count)")
        
        // MDLSkeleton.jointBindTransforms are typically in WORLD space
        // We need to:
        // 1. Store them as worldBindPose for computing inverseBindMatrix
        // 2. Compute localBindPose = inverse(parentWorld) * thisWorld
        
        // First pass: Create all bones and determine parent relationships
        for (index, path) in jointPaths.enumerated() {
            // Get bone name (last component of path)
            let components = path.split(separator: "/")
            let boneName = String(components.last ?? Substring(path))
            
            // Find parent index
            var parentIndex = -1
            if components.count > 1 {
                // Parent path is everything except the last component
                let parentPath = components.dropLast().joined(separator: "/")
                // Find parent by matching the end of existing bone paths
                for (i, existingPath) in jointPaths.enumerated() {
                    if existingPath == parentPath || existingPath.hasSuffix("/\(parentPath)") || 
                       String(existingPath.split(separator: "/").last ?? "") == String(components[components.count - 2]) {
                        if i < bones.count {
                            parentIndex = i
                            break
                        }
                    }
                }
                // If not found by path, try by name
                if parentIndex == -1 {
                    let parentName = String(components[components.count - 2])
                    parentIndex = boneNameToIndex[parentName] ?? -1
                }
            }
            
            let bone = Bone(name: boneName, index: index, parentIndex: parentIndex)
            bones.append(bone)
            boneNameToIndex[boneName] = index
            boneNameToIndex[path] = index  // Also map by full path
        }
        
        // Second pass: Compute local bind poses from world bind poses
        // localBindPose = inverse(parentWorldBind) * thisWorldBind
        for i in 0..<bones.count {
            let bone = bones[i]
            
            // Get this bone's world bind transform
            let thisWorld = i < worldBindTransforms.count ? worldBindTransforms[i] : matrix_identity_float4x4
            
            // Compute local bind pose
            if bone.parentIndex >= 0 && bone.parentIndex < worldBindTransforms.count {
                let parentWorld = worldBindTransforms[bone.parentIndex]
                let parentWorldInverse = simd_inverse(parentWorld)
                bones[i].bindPose = parentWorldInverse * thisWorld
            } else {
                // Root bone - local = world
                bones[i].bindPose = thisWorld
            }
            
            // Inverse bind matrix transforms from world space to bind pose bone space
            bones[i].inverseBindMatrix = simd_inverse(thisWorld)
        }
        
        // Print first few bones for debugging
        for bone in bones.prefix(5) {
            print("[SkeletalLoader]   Bone[\(bone.index)]: \(bone.name), parent=\(bone.parentIndex)")
        }
    }
    
    /// Extract skinned vertices from a mesh
    private func extractSkinnedVertices(_ mesh: MDLMesh, materialIndex: UInt32,
                                        boneNameToIndex: [String: Int],
                                        vertices: inout [SkinnedVertex],
                                        minBound: inout simd_float3, maxBound: inout simd_float3,
                                        hasValidJointData: inout Bool) {
        
        let vertexBuffers = mesh.vertexBuffers
        guard !vertexBuffers.isEmpty else { return }
        
        let vertexBuffer = vertexBuffers[0]
        let vertexData = vertexBuffer.map()
        
        guard let layout = mesh.vertexDescriptor.layouts[0] as? MDLVertexBufferLayout else { return }
        let stride = layout.stride
        
        // Find attribute offsets
        var positionOffset = 0
        var normalOffset = -1
        var texCoordOffset = -1
        var jointIndicesOffset = -1
        var jointWeightsOffset = -1
        var jointIndicesFormat: MDLVertexFormat = .invalid
        var jointWeightsFormat: MDLVertexFormat = .invalid
        
        print("[SkeletalLoader] Mesh vertex descriptor stride: \(stride)")
        print("[SkeletalLoader] Mesh vertex descriptor attributes:")
        
        for attr in mesh.vertexDescriptor.attributes as! [MDLVertexAttribute] {
            if attr.format != .invalid {
                print("[SkeletalLoader]   \(attr.name): offset=\(attr.offset), format=\(attr.format.rawValue)")
            }
            
            switch attr.name {
            case MDLVertexAttributePosition:
                positionOffset = attr.offset
            case MDLVertexAttributeNormal:
                normalOffset = attr.offset
            case MDLVertexAttributeTextureCoordinate:
                texCoordOffset = attr.offset
            case MDLVertexAttributeJointIndices:
                jointIndicesOffset = attr.offset
                jointIndicesFormat = attr.format
            case MDLVertexAttributeJointWeights:
                jointWeightsOffset = attr.offset
                jointWeightsFormat = attr.format
            default:
                break
            }
        }
        
        // Check if joint data is valid - must have distinct offsets from each other and from position
        let meshHasValidJointData = jointIndicesOffset >= 0 && jointWeightsOffset >= 0 &&
                                    jointIndicesOffset != jointWeightsOffset &&
                                    jointIndicesFormat != .invalid && jointWeightsFormat != .invalid
        
        if meshHasValidJointData {
            print("[SkeletalLoader] ✅ Valid joint data: indices at \(jointIndicesOffset) (format \(jointIndicesFormat.rawValue)), weights at \(jointWeightsOffset) (format \(jointWeightsFormat.rawValue))")
            hasValidJointData = true  // Set the output flag to indicate animation is possible
        } else {
            print("[SkeletalLoader] ⚠️ No valid joint data found - vertices will be bound to bone 0")
            print("[SkeletalLoader]   jointIndicesOffset=\(jointIndicesOffset), jointWeightsOffset=\(jointWeightsOffset)")
        }
        
        // Process submeshes
        guard let submeshes = mesh.submeshes as? [MDLSubmesh] else { return }
        
        for submesh in submeshes {
            let indexBuffer = submesh.indexBuffer
            let indexData = indexBuffer.map()
            let indexCount = submesh.indexCount
            
            for i in Swift.stride(from: 0, to: indexCount, by: 3) {
                var indices: [Int] = []
                
                switch submesh.indexType {
                case .invalid:
                    continue
                case .uInt16:
                    let ptr = indexData.bytes.bindMemory(to: UInt16.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+2]), Int(ptr[i+1])]  // Reversed winding
                case .uInt32:
                    let ptr = indexData.bytes.bindMemory(to: UInt32.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+2]), Int(ptr[i+1])]
                case .uInt8:
                    let ptr = indexData.bytes.bindMemory(to: UInt8.self, capacity: indexCount)
                    indices = [Int(ptr[i]), Int(ptr[i+2]), Int(ptr[i+1])]
                @unknown default:
                    continue
                }
                
                // Get positions for normal calculation
                var positions: [simd_float3] = []
                for idx in indices {
                    let basePtr = vertexData.bytes.advanced(by: idx * stride)
                    let posPtr = basePtr.advanced(by: positionOffset).bindMemory(to: Float.self, capacity: 3)
                    positions.append(simd_float3(posPtr[0], posPtr[1], posPtr[2]))
                }
                
                // Calculate face normal
                let edge1 = positions[1] - positions[0]
                let edge2 = positions[2] - positions[0]
                var faceNormal = simd_normalize(simd_cross(edge1, edge2))
                if faceNormal.x.isNaN { faceNormal = simd_float3(0, 1, 0) }
                
                // Create vertices
                for (vertIdx, idx) in indices.enumerated() {
                    let position = positions[vertIdx]
                    let basePtr = vertexData.bytes.advanced(by: idx * stride)
                    
                    minBound = simd_min(minBound, position)
                    maxBound = simd_max(maxBound, position)
                    
                    // Read normal (or use face normal)
                    var normal = faceNormal
                    if normalOffset >= 0 && normalOffset < stride - 8 {
                        let normPtr = basePtr.advanced(by: normalOffset).bindMemory(to: Float.self, capacity: 3)
                        normal = simd_float3(normPtr[0], normPtr[1], normPtr[2])
                        if simd_length(normal) < 0.001 { normal = faceNormal }
                    }
                    
                    // Read texCoord (or generate procedural)
                    var texCoord = simd_float2(position.x * 0.01, position.y * 0.01)
                    if texCoordOffset >= 0 && texCoordOffset < stride - 4 {
                        let texPtr = basePtr.advanced(by: texCoordOffset).bindMemory(to: Float.self, capacity: 2)
                        texCoord = simd_float2(texPtr[0], texPtr[1])
                    }
                    
                    // Read bone indices and weights
                    // Default: all vertices bound to bone 0 with weight 1 (static mesh fallback)
                    var boneIndices = simd_uint4(0, 0, 0, 0)
                    var boneWeights = simd_float4(1, 0, 0, 0)
                    
                    if meshHasValidJointData {
                        // Read joint indices based on format
                        switch jointIndicesFormat {
                        case .uShort4:
                            let jointPtr = basePtr.advanced(by: jointIndicesOffset).bindMemory(to: UInt16.self, capacity: 4)
                            boneIndices = simd_uint4(UInt32(jointPtr[0]), UInt32(jointPtr[1]), 
                                                      UInt32(jointPtr[2]), UInt32(jointPtr[3]))
                        case .uChar4:
                            let jointPtr = basePtr.advanced(by: jointIndicesOffset).bindMemory(to: UInt8.self, capacity: 4)
                            boneIndices = simd_uint4(UInt32(jointPtr[0]), UInt32(jointPtr[1]), 
                                                      UInt32(jointPtr[2]), UInt32(jointPtr[3]))
                        case .int4, .uInt4:
                            let jointPtr = basePtr.advanced(by: jointIndicesOffset).bindMemory(to: UInt32.self, capacity: 4)
                            boneIndices = simd_uint4(jointPtr[0], jointPtr[1], jointPtr[2], jointPtr[3])
                        default:
                            // Try as UInt16 by default
                            let jointPtr = basePtr.advanced(by: jointIndicesOffset).bindMemory(to: UInt16.self, capacity: 4)
                            boneIndices = simd_uint4(UInt32(jointPtr[0]), UInt32(jointPtr[1]), 
                                                      UInt32(jointPtr[2]), UInt32(jointPtr[3]))
                        }
                        
                        // Read joint weights
                        let weightPtr = basePtr.advanced(by: jointWeightsOffset).bindMemory(to: Float.self, capacity: 4)
                        boneWeights = simd_float4(weightPtr[0], weightPtr[1], weightPtr[2], weightPtr[3])
                        
                        // Normalize weights
                        let sum = boneWeights.x + boneWeights.y + boneWeights.z + boneWeights.w
                        if sum > 0.001 {
                            boneWeights /= sum
                        }
                        
                        // Debug: print first few vertices' joint data
                        if vertices.count < 3 {
                            print("[SkeletalLoader] Vertex \(vertices.count) joints: \(boneIndices), weights: \(boneWeights)")
                        }
                    }
                    
                    let vertex = SkinnedVertex(
                        position: position,
                        normal: normal,
                        texCoord: texCoord,
                        boneIndices: boneIndices,
                        boneWeights: boneWeights,
                        materialIndex: materialIndex
                    )
                    vertices.append(vertex)
                }
            }
        }
    }
    
    /// Try to extract animations from the USD asset
    private func extractAnimationsFromAsset(_ asset: MDLAsset, bones: [Bone], boneNameToIndex: [String: Int]) -> [String: AnimationClip] {
        var animations: [String: AnimationClip] = [:]
        
        print("[SkeletalLoader] Searching for animation data...")
        print("[SkeletalLoader] Asset time range: \(asset.startTime) to \(asset.endTime)")
        
        // Find animation bind components and packed joint animations
        var foundAnimation = false
        
        for i in 0..<asset.count {
            let object = asset.object(at: i)
            if let animClip = extractAnimationFromObject(object, bones: bones, boneNameToIndex: boneNameToIndex) {
                animations["walk"] = animClip
                foundAnimation = true
                print("[SkeletalLoader] ✅ Extracted animation '\(animClip.name)' with duration \(animClip.duration)s")
                break
            }
        }
        
        if !foundAnimation {
            // Try to extract from asset time range
            let startTime = asset.startTime
            let endTime = asset.endTime
            
            if endTime > startTime {
                print("[SkeletalLoader] Asset has animation time range, attempting to sample...")
                
                // Look for skeleton and try to sample transforms
                if let animClip = sampleAnimationFromAsset(asset, bones: bones, boneNameToIndex: boneNameToIndex) {
                    animations["walk"] = animClip
                    foundAnimation = true
                    print("[SkeletalLoader] ✅ Sampled animation with duration \(animClip.duration)s")
                }
            }
        }
        
        if !foundAnimation {
            print("[SkeletalLoader] No animation data found in asset")
        }
        
        return animations
    }
    
    /// Recursively search for animation data in object hierarchy
    private func extractAnimationFromObject(_ object: MDLObject, bones: [Bone], boneNameToIndex: [String: Int]) -> AnimationClip? {
        // Check for animation bind component on meshes via components property
        if let mesh = object as? MDLMesh {
            // Check all components on this object
            for component in object.components {
                if let animBind = component as? MDLAnimationBindComponent {
                    print("[SkeletalLoader] Found MDLAnimationBindComponent on mesh: \(mesh.name)")
                    
                    if let skeleton = animBind.skeleton {
                        print("[SkeletalLoader]   Bound to skeleton: \(skeleton.name)")
                        
                        // Check for joint animation (MDLPackedJointAnimation)
                        if let jointAnimation = animBind.jointAnimation {
                            print("[SkeletalLoader]   Found joint animation!")
                            return extractFromJointAnimation(jointAnimation, bones: bones, boneNameToIndex: boneNameToIndex)
                        } else {
                            print("[SkeletalLoader]   No jointAnimation property - trying transform sampling...")
                            // Try to extract animation from skeleton's joint transforms
                            if let anim = extractAnimationFromSkeletonTransforms(skeleton, bones: bones, boneNameToIndex: boneNameToIndex) {
                                return anim
                            }
                        }
                    }
                }
            }
        }
        
        // Check if this object has transform animation
        if let transform = object.transform {
            // MDLTransform can contain animation data
            if transform.minimumTime < transform.maximumTime {
                print("[SkeletalLoader] Object '\(object.name)' has transform animation: \(transform.minimumTime) to \(transform.maximumTime)")
            }
        }
        
        // Recurse into children
        for child in object.children.objects {
            if let anim = extractAnimationFromObject(child, bones: bones, boneNameToIndex: boneNameToIndex) {
                return anim
            }
        }
        
        return nil
    }
    
    /// Extract animation by sampling joint transforms from skeleton at different times
    private func extractAnimationFromSkeletonTransforms(_ skeleton: MDLSkeleton, bones: [Bone], boneNameToIndex: [String: Int]) -> AnimationClip? {
        // Check if skeleton transform has animation
        guard let skeletonTransform = skeleton.transform else {
            print("[SkeletalLoader]   Skeleton has no transform")
            return nil
        }
        
        let minTime = skeletonTransform.minimumTime
        let maxTime = skeletonTransform.maximumTime
        
        print("[SkeletalLoader]   Skeleton transform time range: \(minTime) to \(maxTime)")
        
        // Get the joint bind transforms
        let jointTransforms = skeleton.jointBindTransforms
        let bindTransformArray = jointTransforms.float4x4Array
        let jointCount = skeleton.jointPaths.count
        
        print("[SkeletalLoader]   Joint bind transforms count: \(bindTransformArray.count)")
        print("[SkeletalLoader]   Joint count: \(jointCount)")
        
        // Check if there are multiple time samples (animation)
        // If array size > joint count, there might be multiple frames
        let estimatedFrameCount = bindTransformArray.count / max(jointCount, 1)
        print("[SkeletalLoader]   Estimated frame count: \(estimatedFrameCount)")
        
        guard estimatedFrameCount > 1 else {
            print("[SkeletalLoader]   Only \(estimatedFrameCount) frame(s) - no animation data in jointBindTransforms")
            print("[SkeletalLoader]   Model I/O may not expose USDZ animation through this API")
            return nil
        }
        
        // If we have multiple frames, try to extract them
        let duration = Float(maxTime - minTime)
        guard duration > 0.001 else {
            print("[SkeletalLoader]   No valid time range for animation")
            return nil
        }
        
        print("[SkeletalLoader]   Extracting animation over \(duration)s with \(estimatedFrameCount) keyframes...")
        
        var keyframes: [AnimationKeyframe] = []
        
        // For each frame, extract transforms
        // Layout is: [joint0_time0, joint1_time0, ..., jointN_time0, joint0_time1, ...]
        for frameIdx in 0..<estimatedFrameCount {
            var transforms = Array(repeating: matrix_identity_float4x4, count: bones.count)
            let time = Float(frameIdx) / Float(max(estimatedFrameCount - 1, 1)) * duration
            
            for (jointIdx, jointPath) in skeleton.jointPaths.enumerated() {
                let boneName = (jointPath as NSString).lastPathComponent
                guard let boneIdx = boneNameToIndex[boneName] else { continue }
                
                // Index into the flat array: frameIdx * jointCount + jointIdx
                let arrayIndex = frameIdx * jointCount + jointIdx
                
                if arrayIndex < bindTransformArray.count {
                    let animTransform = bindTransformArray[arrayIndex]
                    let bindPose = bones[boneIdx].bindPose
                    
                    // Compute delta from bind pose
                    transforms[boneIdx] = simd_inverse(bindPose) * animTransform
                }
            }
            
            keyframes.append(AnimationKeyframe(time: time, boneTransforms: transforms))
        }
        
        if keyframes.count > 1 {
            print("[SkeletalLoader]   ✅ Created animation with \(keyframes.count) keyframes")
            return AnimationClip(name: "walk", duration: duration, keyframes: keyframes)
        }
        
        print("[SkeletalLoader]   Failed to create animation keyframes")
        return nil
    }
    
    /// Extract animation from MDLJointAnimation (packed or sampled)
    private func extractFromJointAnimation(_ jointAnimation: MDLJointAnimation, bones: [Bone], boneNameToIndex: [String: Int]) -> AnimationClip? {
        // Try as packed joint animation
        if let packed = jointAnimation as? MDLPackedJointAnimation {
            print("[SkeletalLoader] Processing MDLPackedJointAnimation...")
            print("[SkeletalLoader]   Joint paths: \(packed.jointPaths.count)")
            
            // Get animation data arrays
            let translations = packed.translations
            let rotations = packed.rotations
            _ = packed.scales  // scales available but often not used
            
            // Get times array to determine sample count
            let times = translations.times
            let sampleCount = times.count
            
            print("[SkeletalLoader]   Translations times: \(sampleCount)")
            print("[SkeletalLoader]   Rotations times: \(rotations.times.count)")
            
            guard sampleCount > 0 else {
                print("[SkeletalLoader]   No samples found")
                return nil
            }
            
            let duration = Float(times.last ?? 1.0)
            let jointCount = packed.jointPaths.count
            
            var keyframes: [AnimationKeyframe] = []
            
            // Sample at regular intervals (cap at 60 frames for performance)
            let frameCount = min(sampleCount, 60)
            for f in 0..<frameCount {
                let sampleIndex = f * sampleCount / max(frameCount, 1)
                let sampleTime = times.count > sampleIndex ? times[sampleIndex] : Double(f) / Double(max(frameCount - 1, 1)) * Double(duration)
                let time = Float(sampleTime)
                
                var transforms = Array(repeating: matrix_identity_float4x4, count: bones.count)
                
                // Sample translations and rotations at this time
                let transData = translations.float3Array(atTime: sampleTime)
                let rotData = rotations.floatQuaternionArray(atTime: sampleTime)
                
                // Build transforms for each joint
                for (jointIdx, jointPath) in packed.jointPaths.enumerated() {
                    let boneName = (jointPath as NSString).lastPathComponent
                    
                    guard let boneIdx = boneNameToIndex[boneName] ?? boneNameToIndex[jointPath] else {
                        continue
                    }
                    
                    // Get translation
                    var translation = simd_float3.zero
                    if jointIdx < transData.count {
                        translation = transData[jointIdx]
                    }
                    
                    // Get rotation (quaternion)
                    var rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                    if jointIdx < rotData.count {
                        rotation = rotData[jointIdx]
                    }
                    
                    // Build transform matrix: Translation * Rotation
                    let rotMatrix = simd_float4x4(rotation)
                    let transMatrix = simd_float4x4(
                        simd_float4(1, 0, 0, 0),
                        simd_float4(0, 1, 0, 0),
                        simd_float4(0, 0, 1, 0),
                        simd_float4(translation.x, translation.y, translation.z, 1)
                    )
                    
                    // Store as delta from bind pose (animation transform)
                    // The animation data IS the local transform, so we compute delta
                    let animTransform = transMatrix * rotMatrix
                    let bindPose = bones[boneIdx].bindPose
                    
                    // Delta = inverse(bindPose) * animTransform
                    transforms[boneIdx] = simd_inverse(bindPose) * animTransform
                }
                
                keyframes.append(AnimationKeyframe(time: time, boneTransforms: transforms))
            }
            
            if !keyframes.isEmpty {
                print("[SkeletalLoader] ✅ Created animation with \(keyframes.count) keyframes, \(jointCount) joints")
                return AnimationClip(name: "walk", duration: duration, keyframes: keyframes)
            }
        }
        
        print("[SkeletalLoader] Joint animation type not supported: \(type(of: jointAnimation))")
        return nil
    }
    
    /// Try to sample animation by querying object transforms at different times
    private func sampleAnimationFromAsset(_ asset: MDLAsset, bones: [Bone], boneNameToIndex: [String: Int]) -> AnimationClip? {
        let startTime = asset.startTime
        let endTime = asset.endTime
        let duration = Float(endTime - startTime)
        
        guard duration > 0.001 else { return nil }
        
        // Find skeleton object
        var skeletonObject: MDLSkeleton?
        for i in 0..<asset.count {
            findSkeleton(asset.object(at: i), skeleton: &skeletonObject)
        }
        
        guard let skeleton = skeletonObject else {
            print("[SkeletalLoader] No skeleton found for animation sampling")
            return nil
        }
        
        print("[SkeletalLoader] Sampling animation from skeleton '\(skeleton.name)'...")
        
        // Try the new extraction method first
        if let anim = extractAnimationFromSkeletonTransforms(skeleton, bones: bones, boneNameToIndex: boneNameToIndex) {
            return anim
        }
        
        print("[SkeletalLoader] Skeleton transform sampling failed, using identity animation")
        
        let frameCount = max(2, Int(duration * 30))  // 30 fps
        var keyframes: [AnimationKeyframe] = []
        
        for f in 0..<frameCount {
            let t = Double(f) / Double(frameCount - 1)
            
            // All identity transforms (bind pose)
            let transforms = Array(repeating: matrix_identity_float4x4, count: bones.count)
            keyframes.append(AnimationKeyframe(time: Float(t * Double(duration)), boneTransforms: transforms))
        }
        
        return AnimationClip(name: "walk", duration: duration, keyframes: keyframes)
    }
    
    private func findSkeleton(_ object: MDLObject, skeleton: inout MDLSkeleton?) {
        if let skel = object as? MDLSkeleton {
            skeleton = skel
            return
        }
        for child in object.children.objects {
            findSkeleton(child, skeleton: &skeleton)
        }
    }
    
    /// Create procedural walk animation for Mixamo rig
    private func createMixamoWalkAnimation(bones: [Bone], boneNameToIndex: [String: Int]) -> [String: AnimationClip] {
        var animations: [String: AnimationClip] = [:]
        
        print("[SkeletalLoader] Creating placeholder animations (identity transforms only)")
        
        // For now, create animations that keep the character in bind pose (identity transforms)
        // This prevents mesh mangling while we debug the animation system
        
        // Create walk cycle animation (all identity - no deformation)
        let walkDuration: Float = 1.0
        let walkTransforms = Array(repeating: matrix_identity_float4x4, count: bones.count)
        let walkKeyframes = [
            AnimationKeyframe(time: 0.0, boneTransforms: walkTransforms),
            AnimationKeyframe(time: walkDuration, boneTransforms: walkTransforms)
        ]
        
        animations["walk"] = AnimationClip(name: "walk", duration: walkDuration, keyframes: walkKeyframes)
        
        // Create idle animation (all identity - no deformation)
        let idleDuration: Float = 2.0
        let idleTransforms = Array(repeating: matrix_identity_float4x4, count: bones.count)
        let idleKeyframes = [
            AnimationKeyframe(time: 0.0, boneTransforms: idleTransforms),
            AnimationKeyframe(time: idleDuration, boneTransforms: idleTransforms)
        ]
        
        animations["idle"] = AnimationClip(name: "idle", duration: idleDuration, keyframes: idleKeyframes)
        
        return animations
    }
    
    // MARK: - JSON Animation Loading
    
    /// Load animation from a JSON file exported from Blender
    func loadAnimationFromJSON(named filename: String, bones: [Bone], boneNameToIndex: [String: Int]) -> AnimationClip? {
        // Try to find the JSON file in the bundle
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            print("[SkeletalLoader] Animation JSON not found: \(filename).json")
            return nil
        }
        
        return loadAnimationFromJSON(url: url, bones: bones, boneNameToIndex: boneNameToIndex)
    }
    
    /// Load animation from a JSON file URL
    func loadAnimationFromJSON(url: URL, bones: [Bone], boneNameToIndex: [String: Int]) -> AnimationClip? {
        print("[SkeletalLoader] Loading animation from JSON: \(url.lastPathComponent)")
        
        do {
            let data = try Data(contentsOf: url)
            return parseAnimationJSON(data: data, bones: bones, boneNameToIndex: boneNameToIndex)
        } catch {
            print("[SkeletalLoader] Failed to read JSON file: \(error)")
            return nil
        }
    }
    
    /// Parse animation JSON data
    private func parseAnimationJSON(data: Data, bones: [Bone], boneNameToIndex: [String: Int]) -> AnimationClip? {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[SkeletalLoader] Invalid JSON format")
                return nil
            }
            
            guard let name = json["name"] as? String,
                  let duration = json["duration"] as? Double,
                  let jsonKeyframes = json["keyframes"] as? [[String: Any]],
                  let jsonBones = json["bones"] as? [[String: Any]] else {
                print("[SkeletalLoader] Missing required fields in animation JSON")
                return nil
            }
            
            print("[SkeletalLoader] Parsing animation '\(name)' with \(jsonKeyframes.count) keyframes")
            
            // Build a mapping from JSON bone index to our bone index
            var jsonBoneToOurBone: [Int: Int] = [:]
            for jsonBone in jsonBones {
                guard let jsonName = jsonBone["name"] as? String,
                      let jsonIndex = jsonBone["index"] as? Int else {
                    continue
                }
                
                // Try to find this bone in our skeleton
                if let ourIndex = boneNameToIndex[jsonName] {
                    jsonBoneToOurBone[jsonIndex] = ourIndex
                } else {
                    // Try without mixamorig prefix
                    let simpleName = jsonName.replacingOccurrences(of: "mixamorig_", with: "")
                    if let ourIndex = boneNameToIndex[simpleName] {
                        jsonBoneToOurBone[jsonIndex] = ourIndex
                    }
                }
            }
            
            print("[SkeletalLoader] Mapped \(jsonBoneToOurBone.count)/\(jsonBones.count) bones from JSON to skeleton")
            
            // Parse keyframes
            var keyframes: [AnimationKeyframe] = []
            
            for jsonKeyframe in jsonKeyframes {
                guard let time = jsonKeyframe["time"] as? Double,
                      let jsonTransforms = jsonKeyframe["boneTransforms"] as? [[Double]] else {
                    continue
                }
                
                // Start with identity transforms for all bones
                var boneTransforms = Array(repeating: matrix_identity_float4x4, count: bones.count)
                
                // Fill in transforms from JSON
                for (jsonBoneIdx, matrixData) in jsonTransforms.enumerated() {
                    guard let ourBoneIdx = jsonBoneToOurBone[jsonBoneIdx],
                          matrixData.count == 16 else {
                        continue
                    }
                    
                    // Convert flat array to simd_float4x4 (column-major from Blender export)
                    let matrix = simd_float4x4(
                        simd_float4(Float(matrixData[0]), Float(matrixData[1]), Float(matrixData[2]), Float(matrixData[3])),
                        simd_float4(Float(matrixData[4]), Float(matrixData[5]), Float(matrixData[6]), Float(matrixData[7])),
                        simd_float4(Float(matrixData[8]), Float(matrixData[9]), Float(matrixData[10]), Float(matrixData[11])),
                        simd_float4(Float(matrixData[12]), Float(matrixData[13]), Float(matrixData[14]), Float(matrixData[15]))
                    )
                    
                    // Store the absolute local transform directly
                    // We'll handle it specially in updateBoneMatrices
                    boneTransforms[ourBoneIdx] = matrix
                }
                
                keyframes.append(AnimationKeyframe(time: Float(time), boneTransforms: boneTransforms))
            }
            
            guard !keyframes.isEmpty else {
                print("[SkeletalLoader] No valid keyframes parsed from JSON")
                return nil
            }
            
            print("[SkeletalLoader] ✅ Loaded animation '\(name)' with \(keyframes.count) keyframes, duration \(duration)s")
            
            // JSON animations use absolute local transforms, not deltas
            return AnimationClip(name: name, duration: Float(duration), keyframes: keyframes)
            
        } catch {
            print("[SkeletalLoader] Failed to parse JSON: \(error)")
            return nil
        }
    }
    
    // MARK: - Matrix Helpers
    
    /// Extract the rotation part of a 4x4 matrix (upper-left 3x3)
    private func extractRotation(from matrix: simd_float4x4) -> simd_float3x3 {
        return simd_float3x3(
            simd_float3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            simd_float3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            simd_float3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        )
    }
    
    /// Extract rotation from matrix and normalize to remove scale
    private func extractNormalizedRotation(from matrix: simd_float4x4) -> simd_float3x3 {
        // Get the rotation/scale matrix
        var col0 = simd_float3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z)
        var col1 = simd_float3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z)
        var col2 = simd_float3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        
        // Normalize each column to remove scale
        let len0 = simd_length(col0)
        let len1 = simd_length(col1)
        let len2 = simd_length(col2)
        
        if len0 > 0.0001 { col0 /= len0 }
        if len1 > 0.0001 { col1 /= len1 }
        if len2 > 0.0001 { col2 /= len2 }
        
        return simd_float3x3(col0, col1, col2)
    }
    
    /// Extract the translation part of a 4x4 matrix
    private func extractTranslation(from matrix: simd_float4x4) -> simd_float3 {
        return simd_float3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z)
    }
    
    /// Create a 4x4 transform matrix from rotation and translation
    private func makeTransform(rotation: simd_float3x3, translation: simd_float3) -> simd_float4x4 {
        return simd_float4x4(
            simd_float4(rotation.columns.0, 0),
            simd_float4(rotation.columns.1, 0),
            simd_float4(rotation.columns.2, 0),
            simd_float4(translation, 1)
        )
    }
}
