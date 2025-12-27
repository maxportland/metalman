import SwiftUI
import MetalKit

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct MetalGameContainer: View {
    let initialSaveData: SaveGameData?
    let onReturnToMainMenu: () -> Void
    
    @State private var hudViewModel = GameHUDViewModel()
    
    init(initialSaveData: SaveGameData? = nil, onReturnToMainMenu: @escaping () -> Void = {}) {
        self.initialSaveData = initialSaveData
        self.onReturnToMainMenu = onReturnToMainMenu
    }
    
    var body: some View {
        ZStack {
        #if canImport(UIKit)
            MetalGameView(hudViewModel: hudViewModel, initialSaveData: initialSaveData, onReturnToMainMenu: onReturnToMainMenu)
        #elseif canImport(AppKit)
            MetalGameView(hudViewModel: hudViewModel, initialSaveData: initialSaveData, onReturnToMainMenu: onReturnToMainMenu)
        #else
        Text("Metal not supported on this platform")
        #endif
            
            // HUD overlay
            GameHUD(viewModel: hudViewModel)
                .allowsHitTesting(hudViewModel.isInventoryOpen || hudViewModel.isLootPanelOpen || hudViewModel.isPlayerDead || hudViewModel.isHelpMenuOpen || hudViewModel.isShopOpen || hudViewModel.isLevelUpMenuOpen || hudViewModel.isPauseMenuOpen || hudViewModel.editModeSettings.isEnabled)  // Allow hit testing for UI overlays
        }
    }
}

#if canImport(UIKit)
// iOS/tvOS
struct UIKitMetalView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView(frame: .zero)
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 60
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        uiView.setNeedsDisplay()
    }
}
#endif
#if canImport(AppKit)
// macOS
struct AppKitMetalView: NSViewRepresentable {
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView(frame: .zero)
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 60
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.setNeedsDisplay(nsView.bounds)
    }
}
#endif

