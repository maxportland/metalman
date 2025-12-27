//
//  RealityKitCharacter.swift
//  MetalMan
//
//  Renders the player character using RealityKit for proper USDZ animation support
//

import Foundation
import RealityKit
import SwiftUI
import Combine

// Disable verbose logging
private let realityKitCharDebugLogging = false
private func debugLog(_ message: @autoclosure () -> String) {
    if realityKitCharDebugLogging {
        print(message())
    }
}

/// Manages a RealityKit entity for the player character with proper animation
@MainActor
class RealityKitCharacter: ObservableObject {
    
    /// The RealityKit entity for the character
    private(set) var entity: Entity?
    
    /// The anchor entity that positions the character
    private(set) var anchor: AnchorEntity?
    
    /// Available animation resources
    private var animations: [String: AnimationResource] = [:]
    
    /// Currently playing animation
    private var currentAnimation: String?
    
    /// Animation controller for the current animation
    private var animationController: AnimationPlaybackController?
    
    /// Whether the character is loaded
    @Published var isLoaded = false
    
    /// Load the character from a USDZ file
    func loadCharacter(from url: URL) async {
        debugLog("[RealityKitChar] Loading character from: \(url.lastPathComponent)")
        
        do {
            // Load the entity
            let loadedEntity = try await Entity(contentsOf: url)
            
            debugLog("[RealityKitChar] Entity loaded successfully")
            
            // Create anchor at origin
            let anchorEntity = AnchorEntity(world: .zero)
            anchorEntity.addChild(loadedEntity)
            
            self.entity = loadedEntity
            self.anchor = anchorEntity
            
            // Get available animations
            let availableAnims = loadedEntity.availableAnimations
            debugLog("[RealityKitChar] Available animations: \(availableAnims.count)")
            
            for (index, animResource) in availableAnims.enumerated() {
                let name = "animation_\(index)"
                animations[name] = animResource
                debugLog("[RealityKitChar]   [\(index)] \(name)")
            }
            
            // If there's at least one animation, store it as "walk"
            if let firstAnim = availableAnims.first {
                animations["walk"] = firstAnim
            }
            
            isLoaded = true
            debugLog("[RealityKitChar] ✅ Character ready with \(animations.count) animations")
            
        } catch {
            debugLog("[RealityKitChar] Failed to load character: \(error)")
        }
    }
    
    /// Update the character's position in the world
    func setPosition(_ position: SIMD3<Float>) {
        anchor?.position = position
    }
    
    /// Update the character's rotation (yaw only)
    func setRotation(yaw: Float) {
        anchor?.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    }
    
    /// Set both position and rotation
    func setTransform(position: SIMD3<Float>, yaw: Float) {
        anchor?.position = position
        anchor?.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
    }
    
    /// Set uniform scale
    func setScale(_ scale: Float) {
        entity?.scale = SIMD3<Float>(repeating: scale)
    }
    
    /// Play the walk animation
    func playWalkAnimation() {
        guard currentAnimation != "walk" else { return }
        playAnimation(named: "walk", loop: true)
    }
    
    /// Play idle (stop animation or play idle if available)
    func playIdleAnimation() {
        // Stop current animation
        animationController?.stop()
        currentAnimation = nil
    }
    
    /// Play a specific animation
    func playAnimation(named name: String, loop: Bool = true) {
        guard let entity = entity,
              let animResource = animations[name] else {
            debugLog("[RealityKitChar] Animation '\(name)' not found")
            return
        }
        
        // Stop current animation
        animationController?.stop()
        
        // Play new animation
        if loop {
            animationController = entity.playAnimation(animResource.repeat())
        } else {
            animationController = entity.playAnimation(animResource)
        }
        
        currentAnimation = name
        debugLog("[RealityKitChar] Playing animation: \(name)")
    }
    
    /// Stop all animations
    func stopAnimation() {
        animationController?.stop()
        currentAnimation = nil
    }
}

/// SwiftUI view that embeds a RealityKit ARView for the character
struct RealityKitCharacterView: View {
    @ObservedObject var character: RealityKitCharacter
    
    /// Camera position from the main Metal renderer
    var cameraPosition: SIMD3<Float>
    var cameraTarget: SIMD3<Float>
    
    var body: some View {
        RealityKitContainerView(character: character,
                                 cameraPosition: cameraPosition,
                                 cameraTarget: cameraTarget)
            .allowsHitTesting(false)  // Let touches pass through to Metal view
    }
}

/// UIViewRepresentable wrapper for ARView
struct RealityKitContainerView: NSViewRepresentable {
    let character: RealityKitCharacter
    var cameraPosition: SIMD3<Float>
    var cameraTarget: SIMD3<Float>
    
    func makeNSView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Configure for non-AR rendering
        arView.environment.background = .color(.clear)
        
        // Add the character's anchor if available
        if let anchor = character.anchor {
            arView.scene.addAnchor(anchor)
        }
        
        return arView
    }
    
    func updateNSView(_ arView: ARView, context: Context) {
        // Add anchor if it wasn't added before
        if let anchor = character.anchor, 
           !arView.scene.anchors.contains(where: { $0 === anchor }) {
            arView.scene.addAnchor(anchor)
        }
        
        // Update camera to match Metal view's camera
        // Note: This synchronizes the RealityKit camera with our Metal camera
        updateCamera(arView: arView)
    }
    
    private func updateCamera(arView: ARView) {
        // RealityKit's camera is controlled differently in non-AR mode
        // We need to position it to match our Metal camera
        
        // Create a transform that looks from cameraPosition toward cameraTarget
        let forward = simd_normalize(cameraTarget - cameraPosition)
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), forward))
        let up = simd_cross(forward, right)
        
        var cameraTransform = simd_float4x4(1)
        cameraTransform.columns.0 = SIMD4<Float>(right.x, right.y, right.z, 0)
        cameraTransform.columns.1 = SIMD4<Float>(up.x, up.y, up.z, 0)
        cameraTransform.columns.2 = SIMD4<Float>(-forward.x, -forward.y, -forward.z, 0)
        cameraTransform.columns.3 = SIMD4<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z, 1)
        
        // Apply to ARView's camera (if possible)
        // Note: In non-AR mode, we may need to use a different approach
    }
}

