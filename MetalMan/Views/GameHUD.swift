import SwiftUI

/// HUD overlay displaying player stats, health, and XP
struct GameHUD: View {
    var viewModel: GameHUDViewModel
    
    var body: some View {
        VStack {
            // Top bar with HP and XP
            HStack(alignment: .top) {
                // Left side - Health and XP bars
                VStack(alignment: .leading, spacing: 8) {
                    // Health bar
                    StatBar(
                        label: "HP",
                        current: viewModel.currentHP,
                        max: viewModel.maxHP,
                        percentage: viewModel.hpPercentage,
                        color: hpColor
                    )
                    
                    // XP bar
                    StatBar(
                        label: "XP",
                        current: viewModel.currentXP,
                        max: viewModel.xpToNextLevel,
                        percentage: viewModel.xpPercentage,
                        color: .purple
                    )
                    
                    // Level indicator
                    Text("Level \(viewModel.level)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2)
                }
                .frame(width: 200)
                
                Spacer()
                
                // Right side - Gold and quick stats
                VStack(alignment: .trailing, spacing: 4) {
                    // Gold
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 12))
                        Text("\(viewModel.gold)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                    }
                    .shadow(color: .black, radius: 2)
                    
                    // Attribute points indicator
                    if viewModel.unspentPoints > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            Text("\(viewModel.unspentPoints) points")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        .shadow(color: .black, radius: 2)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            Spacer()
            
            // Bottom bar - Mini attribute display
            HStack(spacing: 20) {
                AttributeDisplay(name: "STR", value: viewModel.strength, color: .red)
                AttributeDisplay(name: "DEX", value: viewModel.dexterity, color: .green)
                AttributeDisplay(name: "INT", value: viewModel.intelligence, color: .blue)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    private var hpColor: Color {
        if viewModel.hpPercentage > 0.6 {
            return .green
        } else if viewModel.hpPercentage > 0.3 {
            return .yellow
        } else {
            return .red
        }
    }
}

/// A horizontal bar showing a stat with current/max values
struct StatBar: View {
    let label: String
    let current: Int
    let max: Int
    let percentage: Float
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Label and values
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Text("\(current)/\(max)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // Bar background
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.5))
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * CGFloat(percentage))
                    
                    // Border
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                }
            }
            .frame(height: 12)
        }
        .shadow(color: .black, radius: 2)
    }
}

/// Small attribute display with icon-like appearance
struct AttributeDisplay: View {
    let name: String
    let value: Int
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text("\(value)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.4))
        .cornerRadius(6)
        .shadow(color: .black, radius: 2)
    }
}

/// View model for the HUD that syncs with PlayerCharacter
@Observable
@MainActor
final class GameHUDViewModel {
    private var player: PlayerCharacter?
    
    var currentHP: Int = 100
    var maxHP: Int = 100
    var currentXP: Int = 0
    var xpToNextLevel: Int = 100
    var level: Int = 1
    var gold: Int = 0
    var strength: Int = 10
    var dexterity: Int = 10
    var intelligence: Int = 10
    var unspentPoints: Int = 0
    
    var hpPercentage: Float {
        guard maxHP > 0 else { return 0 }
        return Float(currentHP) / Float(maxHP)
    }
    
    var xpPercentage: Float {
        guard xpToNextLevel > 0 else { return 0 }
        return Float(currentXP) / Float(xpToNextLevel)
    }
    
    func bind(to player: PlayerCharacter) {
        self.player = player
        update()
    }
    
    func update() {
        guard let player = player else { return }
        
        currentHP = player.vitals.currentHP
        maxHP = player.effectiveMaxHP
        currentXP = player.vitals.currentXP
        xpToNextLevel = player.vitals.xpToNextLevel
        level = player.vitals.level
        gold = player.inventory.gold
        strength = player.effectiveStrength
        dexterity = player.effectiveDexterity
        intelligence = player.effectiveIntelligence
        unspentPoints = player.unspentAttributePoints
    }
}

#Preview {
    ZStack {
        Color.gray
        GameHUD(viewModel: {
            let vm = GameHUDViewModel()
            vm.currentHP = 75
            vm.maxHP = 100
            vm.currentXP = 80
            vm.xpToNextLevel = 150
            vm.level = 3
            vm.gold = 1250
            vm.strength = 12
            vm.dexterity = 15
            vm.intelligence = 8
            vm.unspentPoints = 2
            return vm
        }())
    }
}

