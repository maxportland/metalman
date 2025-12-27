//
//  EditModeView.swift
//  MetalMan
//
//  Debug edit mode for visual adjustments to game world
//

import SwiftUI

// MARK: - Edit Target

/// What object type is currently being edited
enum EditTarget: String, CaseIterable {
    case player = "Player"
    case enemy = "Enemy"
    case vendor = "Vendor"
    case terrain = "Terrain"
    
    var icon: String {
        switch self {
        case .player: return "person.fill"
        case .enemy: return "figure.fall"
        case .vendor: return "bag.fill"
        case .terrain: return "mountain.2.fill"
        }
    }
}

// MARK: - Edit Mode Settings

/// Stores all editable parameters
@Observable
final class EditModeSettings {
    // General
    var isEnabled: Bool = false
    var currentTarget: EditTarget = .player
    
    // Camera controls (temporary, reset on exit)
    var cameraOrbitAngle: Float = 0.0      // Angle around player (radians)
    var cameraZoom: Float = 1.0            // Zoom multiplier (0.5 = closer, 2.0 = farther)
    var cameraPitch: Float = 0.0           // Vertical angle offset (radians)
    
    // UV V-flip toggle (common fix for different 3D format conventions)
    var flipUVVertical: Bool = false
    
    // Player UV adjustments
    var playerUVOffsetX: Float = 0.0
    var playerUVOffsetY: Float = 0.0
    var playerUVScale: Float = 1.0
    
    // Enemy UV adjustments
    var enemyUVOffsetX: Float = 0.0
    var enemyUVOffsetY: Float = 0.0
    var enemyUVScale: Float = 1.0
    
    // Vendor UV adjustments  
    var vendorUVOffsetX: Float = 0.0
    var vendorUVOffsetY: Float = 0.0
    var vendorUVScale: Float = 1.0
    
    // Model transform adjustments
    var playerModelScale: Float = 1.0
    var playerModelOffsetY: Float = 0.0
    
    var enemyModelScale: Float = 1.0
    var enemyModelOffsetY: Float = 0.0
    
    var vendorModelScale: Float = 1.0
    var vendorModelOffsetY: Float = 0.0
    
    /// Toggle edit mode
    func toggle() {
        isEnabled.toggle()
        // Reset camera when exiting edit mode
        if !isEnabled {
            resetCamera()
        }
    }
    
    /// Reset camera to default
    func resetCamera() {
        cameraOrbitAngle = 0.0
        cameraZoom = 1.0
        cameraPitch = 0.0
    }
    
    /// Reset current target's settings to defaults
    func resetCurrentTarget() {
        switch currentTarget {
        case .player:
            playerUVOffsetX = 0.0
            playerUVOffsetY = 0.0
            playerUVScale = 1.0
            playerModelScale = 1.0
            playerModelOffsetY = 0.0
        case .enemy:
            enemyUVOffsetX = 0.0
            enemyUVOffsetY = 0.0
            enemyUVScale = 1.0
            enemyModelScale = 1.0
            enemyModelOffsetY = 0.0
        case .vendor:
            vendorUVOffsetX = 0.0
            vendorUVOffsetY = 0.0
            vendorUVScale = 1.0
            vendorModelScale = 1.0
            vendorModelOffsetY = 0.0
        case .terrain:
            break
        }
    }
    
    /// Get current UV settings for active target
    var currentUVOffset: (x: Float, y: Float) {
        switch currentTarget {
        case .player: return (playerUVOffsetX, playerUVOffsetY)
        case .enemy: return (enemyUVOffsetX, enemyUVOffsetY)
        case .vendor: return (vendorUVOffsetX, vendorUVOffsetY)
        case .terrain: return (0, 0)
        }
    }
    
    var currentUVScale: Float {
        switch currentTarget {
        case .player: return playerUVScale
        case .enemy: return enemyUVScale
        case .vendor: return vendorUVScale
        case .terrain: return 1.0
        }
    }
    
    /// Export settings as a string for copying
    func exportSettings() -> String {
        """
        // Edit Mode Settings Export
        // Player
        playerUVOffsetX = \(playerUVOffsetX)
        playerUVOffsetY = \(playerUVOffsetY)
        playerUVScale = \(playerUVScale)
        playerModelScale = \(playerModelScale)
        playerModelOffsetY = \(playerModelOffsetY)
        
        // Enemy
        enemyUVOffsetX = \(enemyUVOffsetX)
        enemyUVOffsetY = \(enemyUVOffsetY)
        enemyUVScale = \(enemyUVScale)
        enemyModelScale = \(enemyModelScale)
        enemyModelOffsetY = \(enemyModelOffsetY)
        
        // Vendor
        vendorUVOffsetX = \(vendorUVOffsetX)
        vendorUVOffsetY = \(vendorUVOffsetY)
        vendorUVScale = \(vendorUVScale)
        vendorModelScale = \(vendorModelScale)
        vendorModelOffsetY = \(vendorModelOffsetY)
        """
    }
}

// MARK: - Edit Mode View

struct EditModeView: View {
    @Bindable var settings: EditModeSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            targetSelectorView
            Divider().background(Color.orange.opacity(0.5))
            controlsScrollView
            footerView
        }
        .frame(width: 320)
        .background(Color.black.opacity(0.85))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 10)
        .contentShape(Rectangle())
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundColor(.orange)
            Text("EDIT MODE")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)
            
            Spacer()
            
            Button(action: { settings.toggle() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
    
    private var targetSelectorView: some View {
        HStack(spacing: 4) {
            ForEach(EditTarget.allCases, id: \.self) { target in
                targetButton(for: target)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.7))
    }
    
    private func targetButton(for target: EditTarget) -> some View {
        Button(action: { settings.currentTarget = target }) {
            HStack(spacing: 4) {
                Image(systemName: target.icon)
                    .font(.system(size: 11))
                Text(target.rawValue)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(settings.currentTarget == target ? Color.orange : Color.gray.opacity(0.3))
            .foregroundColor(settings.currentTarget == target ? .black : .white)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private var controlsScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                cameraControlsSection
                Divider().background(Color.gray.opacity(0.3)).padding(.vertical, 4)
                
                if settings.currentTarget != .terrain {
                    uvControlsSection
                    Divider().background(Color.gray.opacity(0.3)).padding(.vertical, 4)
                    modelControlsSection
                } else {
                    Text("Terrain editing coming soon...")
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                        .padding()
                }
            }
            .padding(12)
        }
        .background(Color.black.opacity(0.6))
    }
    
    private var cameraControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Camera (Edit Mode Only)")
            
            SliderRow(label: "Orbit Angle", value: $settings.cameraOrbitAngle, range: -Float.pi...Float.pi, step: 0.05)
            SliderRow(label: "Zoom", value: $settings.cameraZoom, range: 0.3...3.0, step: 0.05)
            SliderRow(label: "Pitch", value: $settings.cameraPitch, range: -0.5...0.8, step: 0.02)
            
            HStack {
                Button {
                    settings.resetCamera()
                } label: {
                    Text("Reset Camera")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(4)
                }
                .buttonStyle(.borderless)
                Spacer()
            }
        }
    }
    
    private var uvControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "UV / Texture Mapping")
            
            // UV V-Flip toggle
            HStack {
                Text("Flip V (vertical)")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Toggle("", isOn: $settings.flipUVVertical)
                    .toggleStyle(.switch)
                    .scaleEffect(0.7)
            }
            .padding(.vertical, 2)
            
            SliderRow(label: "UV Offset X", value: uvOffsetXBinding, range: -2...2, step: 0.01)
            SliderRow(label: "UV Offset Y", value: uvOffsetYBinding, range: -2...2, step: 0.01)
            SliderRow(label: "UV Scale", value: uvScaleBinding, range: 0.1...3.0, step: 0.05)
        }
    }
    
    private var modelControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Model Transform")
            
            SliderRow(label: "Model Scale", value: modelScaleBinding, range: 0.5...2.0, step: 0.05)
            SliderRow(label: "Y Offset", value: modelOffsetYBinding, range: -1.0...1.0, step: 0.01)
        }
    }
    
    private var footerView: some View {
        HStack {
            Button(action: { settings.resetCurrentTarget() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(4)
            }
            .buttonStyle(.borderless)
            
            Spacer()
            
            Button(action: {
                let exportText = settings.exportSettings()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(exportText, forType: .string)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                    Text("Copy Settings")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(4)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
    
    // MARK: - Bindings for current target
    
    private var uvOffsetXBinding: Binding<Float> {
        switch settings.currentTarget {
        case .player: return $settings.playerUVOffsetX
        case .enemy: return $settings.enemyUVOffsetX
        case .vendor: return $settings.vendorUVOffsetX
        case .terrain: return .constant(0)
        }
    }
    
    private var uvOffsetYBinding: Binding<Float> {
        switch settings.currentTarget {
        case .player: return $settings.playerUVOffsetY
        case .enemy: return $settings.enemyUVOffsetY
        case .vendor: return $settings.vendorUVOffsetY
        case .terrain: return .constant(0)
        }
    }
    
    private var uvScaleBinding: Binding<Float> {
        switch settings.currentTarget {
        case .player: return $settings.playerUVScale
        case .enemy: return $settings.enemyUVScale
        case .vendor: return $settings.vendorUVScale
        case .terrain: return .constant(1)
        }
    }
    
    private var modelScaleBinding: Binding<Float> {
        switch settings.currentTarget {
        case .player: return $settings.playerModelScale
        case .enemy: return $settings.enemyModelScale
        case .vendor: return $settings.vendorModelScale
        case .terrain: return .constant(1)
        }
    }
    
    private var modelOffsetYBinding: Binding<Float> {
        switch settings.currentTarget {
        case .player: return $settings.playerModelOffsetY
        case .enemy: return $settings.enemyModelOffsetY
        case .vendor: return $settings.vendorModelOffsetY
        case .terrain: return .constant(0)
        }
    }
}

// MARK: - Helper Views

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.orange)
            .textCase(.uppercase)
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    
    @State private var localValue: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(String(format: "%.3f", value))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.orange)
            }
            
            HStack(spacing: 8) {
                // Decrease button
                Button {
                    value = max(range.lowerBound, value - step)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
                
                // Slider - using Double and syncing with Float
                Slider(value: $localValue, in: Double(range.lowerBound)...Double(range.upperBound))
                    .tint(.orange)
                    .onChange(of: localValue) { _, newValue in
                        value = Float(newValue)
                    }
                    .onAppear {
                        localValue = Double(value)
                    }
                    .onChange(of: value) { _, newValue in
                        if abs(localValue - Double(newValue)) > 0.001 {
                            localValue = Double(newValue)
                        }
                    }
                
                // Increase button
                Button {
                    value = min(range.upperBound, value + step)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.opacity(0.5)
        EditModeView(settings: EditModeSettings())
            .padding()
    }
    .frame(width: 400, height: 600)
}

