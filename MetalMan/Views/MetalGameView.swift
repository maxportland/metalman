#if canImport(UIKit)
import SwiftUI
import UIKit
import MetalKit
import simd

struct MetalGameView: UIViewRepresentable {

    /// HUD view model to bind to the player
    var hudViewModel: GameHUDViewModel
    
    /// Initial save data to load (nil for new game)
    var initialSaveData: SaveGameData?
    
    /// Callback to return to main menu
    var onReturnToMainMenu: () -> Void

    // MARK: - Coordinator
    class Coordinator: NSObject, MTKViewDelegate {
        // Hold references here instead of in the struct
        let device: MTLDevice
        let mtkView: TouchForwardingMTKView
        let renderer: Renderer
        
        /// Reference to HUD view model for updates
        weak var hudViewModel: GameHUDViewModel?
        
        /// Callback to return to main menu
        var onReturnToMainMenu: () -> Void = {}

        // Input state
        var movementVector = SIMD2<Float>(0, 0)
        var lookDelta = SIMD2<Float>(0, 0)

        private var activeMovementTouch: UITouch?
        private var activeLookTouch: UITouch?
        private var lastLookTouchLocation: CGPoint?

        // Frame counter for HUD updates
        private var frameCount: Int = 0

        init(preferredFPS: Int, hudViewModel: GameHUDViewModel, initialSaveData: SaveGameData?, onReturnToMainMenu: @escaping () -> Void) {
            let device = MTLCreateSystemDefaultDevice()!
            self.device = device
            self.mtkView = TouchForwardingMTKView(frame: .zero, device: device)
            self.mtkView.colorPixelFormat = .bgra8Unorm
            self.mtkView.depthStencilPixelFormat = .depth32Float
            self.mtkView.preferredFramesPerSecond = preferredFPS
            self.mtkView.isPaused = false
            self.mtkView.enableSetNeedsDisplay = false
            self.hudViewModel = hudViewModel
            self.onReturnToMainMenu = onReturnToMainMenu

            // Create renderer with both device and view
            let renderer = Renderer(device: device, view: self.mtkView)
            self.renderer = renderer

            super.init()

            self.mtkView.delegate = self
            self.mtkView.touchDelegate = self
            
            // Load save data if provided
            if let saveData = initialSaveData {
                renderer.loadGame(from: saveData)
            }
            
            // Bind HUD to player and renderer (on main actor)
            let player = renderer.player
            let rendererRef = renderer
            let returnToMenu = onReturnToMainMenu
            Task { @MainActor in
                hudViewModel.bind(to: player)
                
                // Set up death screen callbacks
                hudViewModel.onRestartGame = {
                    rendererRef.restartGame()
                }
                hudViewModel.onLoadSaveGame = {
                    rendererRef.loadGame()
                }
                // Set up chest looting callback
                hudViewModel.onChestLooted = { chestIndex, goldTaken, itemsTaken in
                    rendererRef.finalizeChestLoot(chestIndex: chestIndex, goldTaken: goldTaken, itemsTaken: itemsTaken)
                }
                // Set up main menu callback
                hudViewModel.onReturnToMainMenu = returnToMenu
                // Set up save game callbacks
                hudViewModel.onQuickSave = {
                    return rendererRef.quickSave()
                }
                hudViewModel.onSaveGame = { name in
                    return rendererRef.saveGame(name: name)
                }
            }
            renderer.hudViewModel = hudViewModel
        }

        // MARK: - Touch handling
        func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            let halfWidth = mtkView.bounds.width / 2
            for touch in touches {
                let location = touch.location(in: mtkView)
                if location.x < halfWidth, activeMovementTouch == nil {
                    activeMovementTouch = touch
                    updateMovement(for: location, in: mtkView.bounds)
                } else if location.x >= halfWidth, activeLookTouch == nil {
                    activeLookTouch = touch
                    lastLookTouchLocation = location
                }
            }
        }

        func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                if touch == activeMovementTouch {
                    let location = touch.location(in: mtkView)
                    updateMovement(for: location, in: mtkView.bounds)
                } else if touch == activeLookTouch {
                    let location = touch.location(in: mtkView)
                    if let last = lastLookTouchLocation {
                        let delta = CGPoint(x: location.x - last.x, y: location.y - last.y)
                        lookDelta = SIMD2<Float>(Float(delta.x), Float(delta.y))
                        renderer.lookDelta = lookDelta
                    }
                    lastLookTouchLocation = location
                }
            }
        }

        func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                if touch == activeMovementTouch {
                    activeMovementTouch = nil
                    movementVector = SIMD2<Float>(0, 0)
                    renderer.movementVector = movementVector
                }
                if touch == activeLookTouch {
                    activeLookTouch = nil
                    lookDelta = SIMD2<Float>(0, 0)
                    renderer.lookDelta = lookDelta
                    lastLookTouchLocation = nil
                }
            }
        }

        func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            touchesEnded(touches, with: event)
        }

        private func updateMovement(for location: CGPoint, in bounds: CGRect) {
            let halfWidth = bounds.width / 2
            let halfHeight = bounds.height / 2

            var x = Float((location.x / halfWidth) - 1)
            var y = Float((location.y / halfHeight) - 1)
            y = -y // invert y so up is positive

            x = max(-1, min(1, x))
            y = max(-1, min(1, y))

            movementVector = SIMD2<Float>(x, y)
            renderer.movementVector = movementVector
        }

        // MARK: - MTKViewDelegate
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer.mtkView(view, drawableSizeWillChange: size)
        }

        func draw(in view: MTKView) {
            // Update renderer with input state before drawing
            renderer.movementVector = movementVector
            renderer.lookDelta = lookDelta
            renderer.draw(in: view)
            // Reset look each frame
            lookDelta = SIMD2<Float>(0, 0)
            
            // Update HUD every 10 frames
            frameCount += 1
            if frameCount >= 10 {
                frameCount = 0
                DispatchQueue.main.async { [weak self] in
                    self?.hudViewModel?.update()
                }
            }
        }
    }

    // MARK: - Touch-forwarding MTKView
    class TouchForwardingMTKView: MTKView {
        weak var touchDelegate: Coordinator?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            touchDelegate?.touchesBegan(touches, with: event)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            touchDelegate?.touchesMoved(touches, with: event)
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            touchDelegate?.touchesEnded(touches, with: event)
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            touchDelegate?.touchesCancelled(touches, with: event)
        }
    }

    // MARK: - UIViewRepresentable
    func makeCoordinator() -> Coordinator {
        return Coordinator(preferredFPS: 60, hudViewModel: hudViewModel, initialSaveData: initialSaveData, onReturnToMainMenu: onReturnToMainMenu)
    }

    func makeUIView(context: UIViewRepresentableContext<MetalGameView>) -> MTKView {
        return context.coordinator.mtkView
    }

    func updateUIView(_ uiView: MTKView, context: UIViewRepresentableContext<MetalGameView>) {
        // No-op: view updates handled by MTKViewDelegate
    }
}
#elseif canImport(AppKit)
import SwiftUI
import AppKit
import MetalKit
import simd

struct MetalGameView: NSViewRepresentable {
    
    /// HUD view model to bind to the player
    var hudViewModel: GameHUDViewModel
    
    /// Initial save data to load (nil for new game)
    var initialSaveData: SaveGameData?
    
    /// Callback to return to main menu
    var onReturnToMainMenu: () -> Void

    // MARK: - Keyboard-handling MTKView
    class KeyboardMTKView: MTKView {
        weak var keyboardDelegate: Coordinator?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            keyboardDelegate?.keyDown(event)
        }
        
        override func keyUp(with event: NSEvent) {
            keyboardDelegate?.keyUp(event)
        }
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, MTKViewDelegate {
        // Hold references here instead of in the struct
        let device: MTLDevice
        let mtkView: KeyboardMTKView
        let renderer: Renderer
        
        /// Reference to HUD view model for updates
        weak var hudViewModel: GameHUDViewModel?
        
        /// Callback to return to main menu
        var onReturnToMainMenu: () -> Void = {}

        // Input state
        var movementVector = SIMD2<Float>(0, 0)
        var lookDelta = SIMD2<Float>(0, 0)
        
        // Track pressed keys
        private var pressedKeys: Set<UInt16> = []

        // Frame counter for HUD updates (don't update every frame)
        private var frameCount: Int = 0

        init(preferredFPS: Int, hudViewModel: GameHUDViewModel, initialSaveData: SaveGameData?, onReturnToMainMenu: @escaping () -> Void) {
            let device = MTLCreateSystemDefaultDevice()!
            self.device = device
            let mtkView = KeyboardMTKView(frame: .zero, device: device)
            mtkView.colorPixelFormat = .bgra8Unorm
            mtkView.depthStencilPixelFormat = .depth32Float
            mtkView.preferredFramesPerSecond = preferredFPS
            mtkView.isPaused = false
            mtkView.enableSetNeedsDisplay = false
            self.mtkView = mtkView
            self.hudViewModel = hudViewModel
            self.onReturnToMainMenu = onReturnToMainMenu

            // Create renderer with both device and view (before super.init)
            self.renderer = Renderer(device: device, view: mtkView)

            super.init()

            self.mtkView.delegate = self
            self.mtkView.keyboardDelegate = self
            
            // Load save data if provided
            if let saveData = initialSaveData {
                renderer.loadGame(from: saveData)
            }
            
            // Bind HUD to player and renderer (on main actor)
            let player = renderer.player
            let rendererRef = renderer
            let returnToMenu = onReturnToMainMenu
            Task { @MainActor in
                hudViewModel.bind(to: player)
                
                // Set up death screen callbacks
                hudViewModel.onRestartGame = {
                    rendererRef.restartGame()
                }
                hudViewModel.onLoadSaveGame = {
                    rendererRef.loadGame()
                }
                // Set up chest looting callback
                hudViewModel.onChestLooted = { chestIndex, goldTaken, itemsTaken in
                    rendererRef.finalizeChestLoot(chestIndex: chestIndex, goldTaken: goldTaken, itemsTaken: itemsTaken)
                }
                // Set up main menu callback
                hudViewModel.onReturnToMainMenu = returnToMenu
                // Set up save game callbacks
                hudViewModel.onQuickSave = {
                    return rendererRef.quickSave()
                }
                hudViewModel.onSaveGame = { name in
                    return rendererRef.saveGame(name: name)
                }
            }
            renderer.hudViewModel = hudViewModel
        }
        
        // MARK: - Keyboard handling
        func keyDown(_ event: NSEvent) {
            pressedKeys.insert(event.keyCode)
            updateMovementFromKeys()
        }
        
        func keyUp(_ event: NSEvent) {
            pressedKeys.remove(event.keyCode)
            updateMovementFromKeys()
        }
        
        private var inventoryKeyWasPressed = false
        private var helpKeyWasPressed = false
        private var escapeKeyWasPressed = false
        private var levelUpKeyWasPressed = false
        private var enterKeyWasPressed = false
        private var editModeKeyWasPressed = false
        
        private func updateMovementFromKeys() {
            var x: Float = 0
            var y: Float = 0
            
            // Arrow key codes:
            // Left: 123, Right: 124, Down: 125, Up: 126
            // Spacebar: 49, E: 14, I: 34, F: 3
            if pressedKeys.contains(123) { x -= 1 } // Left arrow - rotate left
            if pressedKeys.contains(124) { x += 1 } // Right arrow - rotate right
            if pressedKeys.contains(125) { y -= 1 } // Down arrow - walk backward
            if pressedKeys.contains(126) { y += 1 } // Up arrow - walk forward
            
            // Jump with spacebar
            renderer.jumpPressed = pressedKeys.contains(49)
            
            // Interact with E key (keyCode 14)
            renderer.interactPressed = pressedKeys.contains(14)
            
            // Attack with F key (keyCode 3)
            renderer.attackPressed = pressedKeys.contains(3)
            
            // Run with R key (keyCode 15)
            renderer.runPressed = pressedKeys.contains(15)
            
            // Toggle inventory with I key (keyCode 34)
            let inventoryKeyPressed = pressedKeys.contains(34)
            if inventoryKeyPressed && !inventoryKeyWasPressed {
                Task { @MainActor in
                    hudViewModel?.toggleInventory()
                }
            }
            inventoryKeyWasPressed = inventoryKeyPressed
            
            // Escape key (keyCode 53) closes open panels or opens pause menu
            let escapeKeyPressed = pressedKeys.contains(53)
            if escapeKeyPressed && !escapeKeyWasPressed {
                Task { @MainActor in
                    if hudViewModel?.isPauseMenuOpen == true {
                        hudViewModel?.closePauseMenu()
                    } else if hudViewModel?.isInventoryOpen == true {
                        hudViewModel?.toggleInventory()
                    } else if hudViewModel?.isHelpMenuOpen == true {
                        hudViewModel?.toggleHelpMenu()
                    } else if hudViewModel?.isLootPanelOpen == true {
                        hudViewModel?.closeLootPanel()
                    } else if hudViewModel?.isLevelUpMenuOpen == true {
                        hudViewModel?.closeLevelUpMenu()
                    } else if hudViewModel?.isShopOpen == true {
                        hudViewModel?.closeShop()
                    } else if hudViewModel?.isPlayerDead == false {
                        // Open pause menu if no other menu is open and player is alive
                        hudViewModel?.openPauseMenu()
                    }
                }
            }
            escapeKeyWasPressed = escapeKeyPressed
            
            // Toggle help menu with H key (keyCode 4)
            let helpKeyPressed = pressedKeys.contains(4)
            if helpKeyPressed && !helpKeyWasPressed {
                Task { @MainActor in
                    hudViewModel?.toggleHelpMenu()
                }
            }
            helpKeyWasPressed = helpKeyPressed
            
            // Open level up menu with L key (keyCode 37)
            let levelUpKeyPressed = pressedKeys.contains(37)
            if levelUpKeyPressed && !levelUpKeyWasPressed {
                Task { @MainActor in
                    hudViewModel?.openLevelUpMenu()
                }
            }
            levelUpKeyWasPressed = levelUpKeyPressed
            
            // Enter key (keyCode 36) - Take All and close loot panel
            let enterKeyPressed = pressedKeys.contains(36)
            if enterKeyPressed && !enterKeyWasPressed {
                Task { @MainActor in
                    if hudViewModel?.isLootPanelOpen == true {
                        hudViewModel?.lootAll()
                    }
                }
            }
            enterKeyWasPressed = enterKeyPressed
            
            // Quick save with F5 key (keyCode 96)
            renderer.savePressed = pressedKeys.contains(96)
            
            // Toggle edit mode with F12 key (keyCode 111)
            let editModeKeyPressed = pressedKeys.contains(111)
            if editModeKeyPressed && !editModeKeyWasPressed {
                Task { @MainActor in
                    hudViewModel?.editModeSettings.toggle()
                }
            }
            editModeKeyWasPressed = editModeKeyPressed
            
            // For tank controls, do NOT normalize - rotation (x) and movement (y) are independent
            movementVector = SIMD2<Float>(x, y)
        }

        // MARK: - MTKViewDelegate
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            renderer.mtkView(view, drawableSizeWillChange: size)
        }

        func draw(in view: MTKView) {
            // Update renderer with input state before drawing
            renderer.movementVector = movementVector
            renderer.lookDelta = lookDelta
            renderer.draw(in: view)
            // Reset look each frame
            lookDelta = SIMD2<Float>(0, 0)
            
            // Update HUD every 10 frames (6 times per second at 60fps)
            frameCount += 1
            if frameCount >= 10 {
                frameCount = 0
                DispatchQueue.main.async { [weak self] in
                    self?.hudViewModel?.update()
                }
            }
        }
    }

    // MARK: - NSViewRepresentable
    func makeCoordinator() -> Coordinator {
        return Coordinator(preferredFPS: 60, hudViewModel: hudViewModel, initialSaveData: initialSaveData, onReturnToMainMenu: onReturnToMainMenu)
    }

    func makeNSView(context: NSViewRepresentableContext<MetalGameView>) -> MTKView {
        let view = context.coordinator.mtkView
        // Make the view accept keyboard focus
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: MTKView, context: NSViewRepresentableContext<MetalGameView>) {
        // Ensure view can receive keyboard events
        if nsView.window?.firstResponder != nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}
#endif
