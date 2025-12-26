//
//  RealityKitAnimationLoader.swift
//  MetalMan
//
//  Extracts skeletal animation data from USDZ files using RealityKit
//

import Foundation
import RealityKit
import ModelIO
import Metal
import MetalKit
import simd

/// Represents extracted animation data from RealityKit
struct ExtractedAnimation {
    let name: String
    let duration: Float
    let jointNames: [String]
    let keyframes: [ExtractedKeyframe]
}

/// A single keyframe with transforms for all bones
struct ExtractedKeyframe {
    let time: Float
    let localTransforms: [simd_float4x4]  // Transform for each joint at this time
}

/// Loads and extracts skeletal animation data from USDZ files using RealityKit
@MainActor
class RealityKitAnimationLoader {
    
    /// Extract animations from a USDZ file
    /// - Parameter url: URL to the USDZ file
    /// - Returns: Array of extracted animations, or empty array if extraction fails
    static func loadAnimations(from url: URL) async -> [ExtractedAnimation] {
        print("[RealityKit] Loading animations from: \(url.lastPathComponent)")
        
        do {
            // Load the entity from USDZ using async initializer
            let entity = try await Entity(contentsOf: url)
            
            print("[RealityKit] Entity loaded successfully")
            printEntityHierarchy(entity, indent: "  ")
            
            // Find available animations
            let availableAnimations = entity.availableAnimations
            print("[RealityKit] Available animations: \(availableAnimations.count)")
            
            // Find skeletal info
            var jointNames: [String] = []
            var bindPoseTransforms: [simd_float4x4] = []
            
            // Search for ModelComponent which contains skeletal data
            findSkeletalData(in: entity, jointNames: &jointNames, bindPose: &bindPoseTransforms)
            
            if jointNames.isEmpty {
                print("[RealityKit] No skeletal data found, trying to extract from animation")
            }
            
            var extractedAnimations: [ExtractedAnimation] = []
            
            for animResource in availableAnimations {
                if let extracted = extractAnimation(from: animResource, entity: entity, jointNames: jointNames) {
                    extractedAnimations.append(extracted)
                    print("[RealityKit] ✅ Extracted animation: \(extracted.name)")
                    print("[RealityKit]    Duration: \(extracted.duration)s, Keyframes: \(extracted.keyframes.count)")
                    print("[RealityKit]    Joints: \(extracted.jointNames.count)")
                }
            }
            
            // If no animations found in availableAnimations, try to find AnimationComponent
            if extractedAnimations.isEmpty {
                print("[RealityKit] No availableAnimations, searching for animation data in hierarchy...")
                if let extracted = extractAnimationFromHierarchy(entity: entity, jointNames: jointNames) {
                    extractedAnimations.append(extracted)
                }
            }
            
            return extractedAnimations
            
        } catch {
            print("[RealityKit] Failed to load entity: \(error)")
            return []
        }
    }
    
    /// Print entity hierarchy for debugging
    private static func printEntityHierarchy(_ entity: Entity, indent: String) {
        let components = entity.components.map { type(of: $0).self }
        print("[RealityKit] \(indent)\(entity.name): \(components)")
        
        for child in entity.children {
            printEntityHierarchy(child, indent: indent + "  ")
        }
    }
    
    /// Find skeletal data (joint names and bind poses) from entity hierarchy
    private static func findSkeletalData(in entity: Entity, jointNames: inout [String], bindPose: inout [simd_float4x4]) {
        // Check for ModelComponent (contains mesh and potentially skeletal info)
        if let modelComponent = entity.components[ModelComponent.self] {
            print("[RealityKit] Found ModelComponent in '\(entity.name)'")
            
            // Try to get mesh resource details
            let mesh = modelComponent.mesh
            print("[RealityKit]   Mesh bounds: \(mesh.bounds)")
        }
        
        // Recursively search children
        for child in entity.children {
            // Joint entities typically represent bones
            if child.name.contains("mixamorig") || 
               child.name.contains("Hips") ||
               child.name.contains("Spine") ||
               child.name.contains("Arm") ||
               child.name.contains("Leg") {
                jointNames.append(child.name)
                bindPose.append(child.transform.matrix)
            }
            
            findSkeletalData(in: child, jointNames: &jointNames, bindPose: &bindPose)
        }
    }
    
    /// Extract animation from AnimationResource
    private static func extractAnimation(from animResource: AnimationResource, entity: Entity, jointNames: [String]) -> ExtractedAnimation? {
        // Get animation definition info
        let definition = animResource.definition
        print("[RealityKit] Animation definition: \(type(of: definition))")
        
        // Get duration from the animation
        // AnimationResource doesn't directly expose duration, so we sample it
        let sampleRate: Float = 30.0  // Sample at 30 FPS
        let maxDuration: Float = 10.0  // Maximum animation length to sample
        
        // Sample the animation by playing it and capturing joint transforms
        var keyframes: [ExtractedKeyframe] = []
        var detectedJoints: [String] = jointNames
        
        // If we don't have joint names yet, collect them from entity hierarchy
        if detectedJoints.isEmpty {
            collectJointNames(from: entity, into: &detectedJoints)
        }
        
        // For RealityKit, we need to sample the animation at different time points
        // Since we can't directly access keyframe data, we create a synthetic animation
        // based on sampling the played animation
        
        // Create keyframes by sampling time
        let numSamples = Int(maxDuration * sampleRate)
        var lastNonIdentityTime: Float = 0
        
        for i in 0..<min(numSamples, 300) {  // Cap at 300 samples (10 seconds at 30fps)
            let time = Float(i) / sampleRate
            
            // Sample joint transforms at this time
            var transforms: [simd_float4x4] = []
            
            for jointName in detectedJoints {
                if let jointEntity = findEntity(named: jointName, in: entity) {
                    transforms.append(jointEntity.transform.matrix)
                } else {
                    transforms.append(matrix_identity_float4x4)
                }
            }
            
            // Check if this keyframe has meaningful data
            let hasData = transforms.contains { !isIdentityMatrix($0) }
            if hasData {
                lastNonIdentityTime = time
            }
            
            keyframes.append(ExtractedKeyframe(time: time, localTransforms: transforms))
        }
        
        // Trim to actual animation duration
        let duration = max(lastNonIdentityTime, 1.0)
        let relevantKeyframes = keyframes.filter { $0.time <= duration + 0.1 }
        
        if relevantKeyframes.isEmpty || detectedJoints.isEmpty {
            print("[RealityKit] Could not extract meaningful animation data")
            return nil
        }
        
        return ExtractedAnimation(
            name: "animation",
            duration: duration,
            jointNames: detectedJoints,
            keyframes: relevantKeyframes
        )
    }
    
    /// Collect joint names from entity hierarchy
    private static func collectJointNames(from entity: Entity, into names: inout [String]) {
        // Common Mixamo joint name patterns
        let jointPatterns = ["mixamorig", "Hips", "Spine", "Neck", "Head", 
                            "Shoulder", "Arm", "Hand", "Finger",
                            "UpLeg", "Leg", "Foot", "Toe"]
        
        for pattern in jointPatterns {
            if entity.name.contains(pattern) {
                if !names.contains(entity.name) {
                    names.append(entity.name)
                }
            }
        }
        
        for child in entity.children {
            collectJointNames(from: child, into: &names)
        }
    }
    
    /// Find entity by name in hierarchy
    private static func findEntity(named name: String, in parent: Entity) -> Entity? {
        if parent.name == name {
            return parent
        }
        
        for child in parent.children {
            if let found = findEntity(named: name, in: child) {
                return found
            }
        }
        
        return nil
    }
    
    /// Check if matrix is identity
    private static func isIdentityMatrix(_ m: simd_float4x4) -> Bool {
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
    
    /// Extract animation data from entity hierarchy (fallback)
    private static func extractAnimationFromHierarchy(entity: Entity, jointNames: [String]) -> ExtractedAnimation? {
        print("[RealityKit] Attempting to extract animation from hierarchy transforms")
        
        var detectedJoints = jointNames
        if detectedJoints.isEmpty {
            collectJointNames(from: entity, into: &detectedJoints)
        }
        
        if detectedJoints.isEmpty {
            print("[RealityKit] No joints found in hierarchy")
            return nil
        }
        
        print("[RealityKit] Found \(detectedJoints.count) joints")
        
        // Get current transforms as a single keyframe (bind pose)
        var transforms: [simd_float4x4] = []
        for jointName in detectedJoints {
            if let jointEntity = findEntity(named: jointName, in: entity) {
                transforms.append(jointEntity.transform.matrix)
            } else {
                transforms.append(matrix_identity_float4x4)
            }
        }
        
        // Create a basic animation with just the bind pose
        let keyframe = ExtractedKeyframe(time: 0, localTransforms: transforms)
        
        return ExtractedAnimation(
            name: "bindPose",
            duration: 0,
            jointNames: detectedJoints,
            keyframes: [keyframe]
        )
    }
}

// MARK: - Alternative: Direct USD parsing using Apple's ModelIO with deeper inspection

/// Alternative loader that digs deeper into ModelIO's USD data
class ModelIOAnimationExtractor {
    
    /// Extract animation by deeply inspecting MDLAsset
    static func extractFromMDLAsset(_ asset: MDLAsset, device: MTLDevice) -> [ExtractedAnimation] {
        print("[ModelIO-Deep] Inspecting asset for animation data...")
        
        var animations: [ExtractedAnimation] = []
        
        // Get time range of asset
        let startTime = asset.startTime
        let endTime = asset.endTime
        let duration = endTime - startTime
        
        print("[ModelIO-Deep] Asset time range: \(startTime) to \(endTime) (duration: \(duration)s)")
        
        if duration <= 0 {
            print("[ModelIO-Deep] No time-based animation found")
            return animations
        }
        
        // Find skeleton and its joint names
        var skeleton: MDLSkeleton?
        var jointNames: [String] = []
        
        for i in 0..<asset.count {
            findSkeleton(in: asset.object(at: i), skeleton: &skeleton)
            if skeleton != nil { break }
        }
        
        guard let foundSkeleton = skeleton else {
            print("[ModelIO-Deep] No skeleton found")
            return animations
        }
        
        // Get joint names from skeleton paths (these are full paths like "mixamorig_Hips/mixamorig_Spine")
        jointNames = foundSkeleton.jointPaths.map { path in
            // Extract just the joint name from the path
            let components = path.components(separatedBy: "/")
            return components.last ?? path
        }
        
        print("[ModelIO-Deep] Found skeleton with \(jointNames.count) joints")
        
        // Look for MDLPackedJointAnimation in the asset
        var packedAnimation: MDLPackedJointAnimation?
        for i in 0..<asset.count {
            findPackedAnimation(in: asset.object(at: i), animation: &packedAnimation)
            if packedAnimation != nil { break }
        }
        
        if let animation = packedAnimation {
            print("[ModelIO-Deep] Found MDLPackedJointAnimation!")
            if let extracted = extractFromPackedAnimation(animation, jointNames: jointNames, duration: duration) {
                animations.append(extracted)
                return animations
            }
        }
        
        // Look for meshes with MDLAnimationBindComponent
        var animationBindMesh: MDLMesh?
        for i in 0..<asset.count {
            findMeshWithAnimationBind(in: asset.object(at: i), mesh: &animationBindMesh)
            if animationBindMesh != nil { break }
        }
        
        if let mesh = animationBindMesh {
            print("[ModelIO-Deep] Found mesh with animation bind: \(mesh.name)")
            
            // Get the animation bind component by iterating through components
            for component in mesh.components {
                if let animBind = component as? MDLAnimationBindComponent {
                    print("[ModelIO-Deep] Animation bind component found")
                    print("[ModelIO-Deep]   Skeleton: \(animBind.skeleton?.name ?? "nil")")
                    print("[ModelIO-Deep]   Joint animation: \(animBind.jointAnimation != nil ? "YES" : "NO")")
                    print("[ModelIO-Deep]   Joint paths: \(animBind.jointPaths?.count ?? 0)")
                    
                    // Try to get animation from jointAnimation
                    if let jointAnim = animBind.jointAnimation as? MDLPackedJointAnimation {
                        print("[ModelIO-Deep] Found packed joint animation in bind component!")
                        if let extracted = extractFromPackedAnimation(jointAnim, jointNames: jointNames, duration: duration) {
                            animations.append(extracted)
                            return animations
                        }
                    }
                    break
                }
            }
        }
        
        // Fallback: Sample skeleton transforms at different times
        print("[ModelIO-Deep] Trying to sample skeleton transforms over time...")
        
        let sampleRate = 30.0
        let numSamples = Int(duration * sampleRate)
        var keyframes: [ExtractedKeyframe] = []
        var hasVariation = false
        var firstFrameTransforms: [simd_float4x4]?
        
        for sampleIdx in 0...numSamples {
            let time = startTime + (Double(sampleIdx) / sampleRate)
            var transforms: [simd_float4x4] = []
            
            // Sample each joint's transform at this time
            for (jointIdx, jointPath) in foundSkeleton.jointPaths.enumerated() {
                // Try to find the joint object and sample its transform
                if let jointTransform = sampleJointTransform(jointPath: jointPath, at: time, in: asset) {
                    transforms.append(jointTransform)
                } else {
                    // Fallback to bind pose for this joint
                    let bindPose = foundSkeleton.jointBindTransforms.float4x4Array
                    if jointIdx < bindPose.count {
                        transforms.append(bindPose[jointIdx])
                    } else {
                        transforms.append(matrix_identity_float4x4)
                    }
                }
            }
            
            // Check if this frame differs from the first
            if firstFrameTransforms == nil {
                firstFrameTransforms = transforms
            } else if !hasVariation {
                for i in 0..<min(transforms.count, firstFrameTransforms!.count) {
                    if !matricesEqual(transforms[i], firstFrameTransforms![i]) {
                        hasVariation = true
                        break
                    }
                }
            }
            
            keyframes.append(ExtractedKeyframe(
                time: Float(time - startTime),
                localTransforms: transforms
            ))
        }
        
        if hasVariation {
            print("[ModelIO-Deep] ✅ Found animated transforms with \(keyframes.count) samples")
            animations.append(ExtractedAnimation(
                name: "sampled",
                duration: Float(duration),
                jointNames: jointNames,
                keyframes: keyframes
            ))
        } else {
            print("[ModelIO-Deep] ⚠️ No variation in transforms - animation data not accessible via ModelIO")
            print("[ModelIO-Deep] The animation may be stored in a format ModelIO can't sample")
        }
        
        return animations
    }
    
    /// Find skeleton recursively
    private static func findSkeleton(in obj: MDLObject, skeleton: inout MDLSkeleton?) {
        if let skel = obj as? MDLSkeleton {
            skeleton = skel
            return
        }
        for child in obj.children.objects {
            findSkeleton(in: child, skeleton: &skeleton)
            if skeleton != nil { return }
        }
    }
    
    /// Find MDLPackedJointAnimation recursively
    private static func findPackedAnimation(in obj: MDLObject, animation: inout MDLPackedJointAnimation?) {
        // Check components
        for component in obj.components {
            if let anim = component as? MDLPackedJointAnimation {
                animation = anim
                return
            }
            if let animBind = component as? MDLAnimationBindComponent,
               let jointAnim = animBind.jointAnimation as? MDLPackedJointAnimation {
                animation = jointAnim
                return
            }
        }
        
        for child in obj.children.objects {
            findPackedAnimation(in: child, animation: &animation)
            if animation != nil { return }
        }
    }
    
    /// Find mesh with animation bind component
    private static func findMeshWithAnimationBind(in obj: MDLObject, mesh: inout MDLMesh?) {
        if let m = obj as? MDLMesh {
            // Check if mesh has animation bind component
            for component in m.components {
                if component is MDLAnimationBindComponent {
                    mesh = m
                    return
                }
            }
        }
        for child in obj.children.objects {
            findMeshWithAnimationBind(in: child, mesh: &mesh)
            if mesh != nil { return }
        }
    }
    
    /// Extract animation from MDLPackedJointAnimation
    private static func extractFromPackedAnimation(_ animation: MDLPackedJointAnimation, jointNames: [String], duration: Double) -> ExtractedAnimation? {
        // Get animation joint paths
        let animJointPaths = animation.jointPaths
        let animJointCount = animJointPaths.count
        
        // Debug: Print unique identifier for this animation object
        let animPtr = Unmanaged.passUnretained(animation).toOpaque()
        print("[ModelIO-Deep] Packed animation object: \(animPtr)")
        print("[ModelIO-Deep] Packed animation has \(animJointCount) joints")
        print("[ModelIO-Deep] Animation joint paths (first 10):")
        for (i, path) in animJointPaths.prefix(10).enumerated() {
            print("[ModelIO-Deep]   [\(i)] \(path)")
        }
        
        print("[ModelIO-Deep] Skeleton joint names (first 10):")
        for (i, name) in jointNames.prefix(10).enumerated() {
            print("[ModelIO-Deep]   [\(i)] \(name)")
        }
        
        // Create mapping from animation joint index to skeleton bone index
        // Animation uses full paths like "Armature/mixamorig_Hips/mixamorig_Spine"
        // Skeleton uses just names like "mixamorig_Spine"
        var animToSkeletonMap: [Int: Int] = [:]
        
        for (animIdx, animPath) in animJointPaths.enumerated() {
            // Extract the last component of the path (the actual bone name)
            let pathComponents = animPath.components(separatedBy: "/")
            let boneName = pathComponents.last ?? animPath
            
            // Find matching skeleton bone
            if let skelIdx = jointNames.firstIndex(of: boneName) {
                animToSkeletonMap[animIdx] = skelIdx
            } else {
                // Try partial matching
                for (skelIdx, skelName) in jointNames.enumerated() {
                    if skelName == boneName || animPath.hasSuffix(skelName) {
                        animToSkeletonMap[animIdx] = skelIdx
                        break
                    }
                }
            }
        }
        
        print("[ModelIO-Deep] Mapped \(animToSkeletonMap.count) of \(animJointCount) animation joints to skeleton")
        
        // Sample at 30fps for the full animation duration
        let sampleRate: Float = 30.0
        let totalFrames = Int(Float(duration) * sampleRate)
        let animDuration = Float(duration)
        
        print("[ModelIO-Deep] Extracting animation: \(totalFrames) frames, duration: \(animDuration)s")
        
        var keyframes: [ExtractedKeyframe] = []
        
        // Log first frame data for debugging
        let firstTimeTranslations = animation.translations.float3Array(atTime: 0)
        let firstTimeRotations = animation.rotations.floatQuaternionArray(atTime: 0)
        let firstTimeScales = animation.scales.float3Array(atTime: 0)
        
        print("[ModelIO-Deep] First frame sample (t=0):")
        print("[ModelIO-Deep]   Translations count: \(firstTimeTranslations.count)")
        print("[ModelIO-Deep]   Rotations count: \(firstTimeRotations.count)")
        print("[ModelIO-Deep]   Scales count: \(firstTimeScales.count)")
        
        if !firstTimeTranslations.isEmpty {
            print("[ModelIO-Deep]   Joint 0 trans: \(firstTimeTranslations[0])")
        }
        if !firstTimeRotations.isEmpty {
            let q = firstTimeRotations[0]
            print("[ModelIO-Deep]   Joint 0 rot: (x:\(q.imag.x), y:\(q.imag.y), z:\(q.imag.z), w:\(q.real))")
        }
        
        // Sample mid-animation to verify data changes over time
        let midTime = duration / 2.0
        let midTranslations = animation.translations.float3Array(atTime: midTime)
        let midRotations = animation.rotations.floatQuaternionArray(atTime: midTime)
        
        print("[ModelIO-Deep] Mid frame sample (t=\(midTime)):")
        if !midTranslations.isEmpty {
            print("[ModelIO-Deep]   Joint 0 trans: \(midTranslations[0])")
            // Check if first and mid frames differ
            if !firstTimeTranslations.isEmpty {
                let diff = simd_distance(firstTimeTranslations[0], midTranslations[0])
                print("[ModelIO-Deep]   Trans difference from frame 0: \(diff)")
            }
        }
        if !midRotations.isEmpty {
            let q = midRotations[0]
            print("[ModelIO-Deep]   Joint 0 rot: (x:\(q.imag.x), y:\(q.imag.y), z:\(q.imag.z), w:\(q.real))")
        }
        
        // Find the root bone (Hips) index for stripping root motion
        var rootBoneAnimIdx: Int? = nil
        var rootBoneFirstTranslation: simd_float3? = nil
        
        for (animIdx, animPath) in animJointPaths.enumerated() {
            let pathComponents = animPath.components(separatedBy: "/")
            let boneName = pathComponents.last ?? animPath
            
            // Mixamo uses "mixamorig_Hips" as root bone
            if boneName.lowercased().contains("hips") {
                rootBoneAnimIdx = animIdx
                // Get the first frame translation for the root
                let firstTranslations = animation.translations.float3Array(atTime: 0)
                if animIdx < firstTranslations.count {
                    rootBoneFirstTranslation = firstTranslations[animIdx]
                    print("[ModelIO-Deep] Root bone (Hips) found at animation index \(animIdx)")
                    print("[ModelIO-Deep] Root bone first frame translation: \(rootBoneFirstTranslation!)")
                }
                break
            }
        }
        
        // Sample all frames of the animation
        for sampleIdx in 0..<totalFrames {
            let time = TimeInterval(Float(sampleIdx) / sampleRate)
            
            // Get translation, rotation, scale at this time
            let translations = animation.translations.float3Array(atTime: time)
            let rotations = animation.rotations.floatQuaternionArray(atTime: time)
            let scales = animation.scales.float3Array(atTime: time)
            
            // Initialize all transforms to identity
            var transforms = Array(repeating: matrix_identity_float4x4, count: jointNames.count)
            
            // Apply animation data to the mapped bones
            for (animIdx, skelIdx) in animToSkeletonMap {
                // Build TRS matrix: Translation * Rotation * Scale
                var scaleMatrix = matrix_identity_float4x4
                var rotMatrix = matrix_identity_float4x4
                var transMatrix = matrix_identity_float4x4
                
                // Scale
                if animIdx < scales.count {
                    let s = scales[animIdx]
                    scaleMatrix.columns.0.x = s.x
                    scaleMatrix.columns.1.y = s.y
                    scaleMatrix.columns.2.z = s.z
                }
                
                // Rotation
                if animIdx < rotations.count {
                    let quat = rotations[animIdx]
                    rotMatrix = simd_matrix4x4(quat)
                }
                
                // Translation
                if animIdx < translations.count {
                    var t = translations[animIdx]
                    
                    // Strip root motion from the Hips bone
                    // Keep only vertical (Y) movement, remove horizontal (X, Z) movement
                    if animIdx == rootBoneAnimIdx, let firstTrans = rootBoneFirstTranslation {
                        // Keep vertical bobbing but remove forward/sideways motion
                        // Use first frame as reference position for X and Z
                        t.x = firstTrans.x  // Lock X to first frame
                        t.z = firstTrans.z  // Lock Z to first frame
                        // Keep t.y as-is for natural up/down bobbing during walk
                    }
                    
                    transMatrix.columns.3 = simd_float4(t.x, t.y, t.z, 1.0)
                }
                
                // TRS order: T * R * S
                transforms[skelIdx] = transMatrix * rotMatrix * scaleMatrix
            }
            
            keyframes.append(ExtractedKeyframe(time: Float(time), localTransforms: transforms))
        }
        
        if keyframes.isEmpty {
            return nil
        }
        
        print("[ModelIO-Deep] ✅ Extracted \(keyframes.count) keyframes from packed animation")
        return ExtractedAnimation(
            name: "animation",
            duration: animDuration,
            jointNames: jointNames,
            keyframes: keyframes
        )
    }
    
    /// Sample a joint's transform at a specific time
    private static func sampleJointTransform(jointPath: String, at time: TimeInterval, in asset: MDLAsset) -> simd_float4x4? {
        // Try to find the joint object in the asset hierarchy
        for i in 0..<asset.count {
            if let transform = findAndSampleTransform(name: jointPath, at: time, in: asset.object(at: i)) {
                return transform
            }
        }
        return nil
    }
    
    /// Recursively find object and sample its transform
    private static func findAndSampleTransform(name: String, at time: TimeInterval, in obj: MDLObject) -> simd_float4x4? {
        // Check if this object matches (by path or last component)
        let objName = obj.name
        let pathLast = name.components(separatedBy: "/").last ?? name
        
        if objName == name || objName == pathLast {
            if let transform = obj.transform {
                return transform.localTransform?(atTime: time) ?? transform.matrix
            }
        }
        
        for child in obj.children.objects {
            if let result = findAndSampleTransform(name: name, at: time, in: child) {
                return result
            }
        }
        
        return nil
    }
    
    /// Check if two matrices are approximately equal
    private static func matricesEqual(_ a: simd_float4x4, _ b: simd_float4x4, epsilon: Float = 0.0001) -> Bool {
        for col in 0..<4 {
            for row in 0..<4 {
                if abs(a[col][row] - b[col][row]) > epsilon {
                    return false
                }
            }
        }
        return true
    }
}

