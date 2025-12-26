import SwiftUI
import AppKit

// MARK: - Instant Tooltip Modifier

/// A custom tooltip that appears immediately on hover (no delay)
struct InstantTooltip: ViewModifier {
    let text: String
    @State private var isHovering = false
    @State private var hoverLocation: CGPoint = .zero
    
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
            }
            .overlay(alignment: .topLeading) {
                if isHovering && !text.isEmpty {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(white: 0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                        .fixedSize()
                        .offset(x: 0, y: -60)
                        .allowsHitTesting(false)
                        .zIndex(1000)
                }
            }
    }
}

extension View {
    /// Adds an instant tooltip that appears immediately on hover
    func instantTooltip(_ text: String) -> some View {
        modifier(InstantTooltip(text: text))
    }
    
    /// Adds a tap gesture that plays a tick sound
    func onTapWithSound(perform action: @escaping () -> Void) -> some View {
        self.onTapGesture {
            AudioManager.shared.playTick()
            action()
        }
    }
}

// MARK: - Tick Button Style

/// A button style that plays a tick sound when pressed
struct TickButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    AudioManager.shared.playTick()
                }
            }
    }
}

extension View {
    /// Apply tick sound button style
    func withTickSound() -> some View {
        self.buttonStyle(TickButtonStyle())
    }
}

/// Represents a notification (loot, heal, etc.)
struct LootNotification: Identifiable {
    let id = UUID()
    let gold: Int
    let itemName: String?
    let itemRarity: String?
    let title: String
    let icon: String
    var opacity: Double = 1.0
    
    init(gold: Int, itemName: String?, itemRarity: String?, title: String = "🎁 Treasure Found!", icon: String = "circle.fill") {
        self.gold = gold
        self.itemName = itemName
        self.itemRarity = itemRarity
        self.title = title
        self.icon = icon
    }
}

/// Represents a floating damage number on screen
struct DamageNumberDisplay: Identifiable {
    let id: UUID
    let amount: Int
    let isCritical: Bool
    let isHeal: Bool
    let isBlock: Bool
    var screenPosition: CGPoint
    var opacity: Double
    var scale: Double
}

/// Represents an enemy health bar displayed above their head
struct EnemyHealthBar: Identifiable {
    let id: UUID
    var screenPosition: CGPoint
    var hpPercentage: Float
    var opacity: Double
    var name: String
}

/// Represents an item slot in the inventory grid
struct InventorySlot: Identifiable {
    let id: Int
    var item: InventoryItemDisplay?
}

/// Represents a lootable item from a corpse
struct LootableItem: Identifiable {
    let id: UUID
    let item: Item
    let quantity: Int
    var isLooted: Bool = false
}

/// Represents loot from a corpse
struct CorpseLoot {
    let enemyName: String
    var gold: Int
    var items: [LootableItem]
    var xpReward: Int
}

/// Display info for an inventory item
struct InventoryItemDisplay: Identifiable {
    let id: UUID
    let name: String
    let rarity: String
    let quantity: Int
    let iconName: String
    let iconVariant: Int  // Which icon variant to use (e.g., shield_1 vs shield_6)
    let isEquippable: Bool
    let equipSlotName: String?
    let value: Int  // Gold value for selling
    
    // Stat bonuses for tooltips
    var damageBonus: Int = 0
    var dexterityBonus: Int = 0
    var strengthBonus: Int = 0
    var intelligenceBonus: Int = 0
    var armorBonus: Int = 0
    var healAmount: Int = 0
    var blockChance: Int = 0
    
    /// Build a tooltip string for this item
    var tooltipText: String {
        var lines: [String] = [name]
        
        // Add rarity
        if !rarity.isEmpty {
            lines.append("(\(rarity))")
        }
        
        // Add stat bonuses
        if damageBonus > 0 { lines.append("+\(damageBonus) Damage") }
        if dexterityBonus > 0 { lines.append("+\(dexterityBonus) Dexterity") }
        if strengthBonus > 0 { lines.append("+\(strengthBonus) Strength") }
        if intelligenceBonus > 0 { lines.append("+\(intelligenceBonus) Intelligence") }
        if armorBonus > 0 { lines.append("+\(armorBonus) Armor") }
        if blockChance > 0 { lines.append("\(blockChance)% Block Chance") }
        if healAmount > 0 { lines.append("Heals \(healAmount) HP") }
        
        // Add quantity if > 1
        if quantity > 1 {
            lines.append("Quantity: \(quantity)")
        }
        
        return lines.joined(separator: "\n")
    }
}

/// HUD overlay displaying player stats, health, and XP
struct GameHUD: View {
    @Bindable var viewModel: GameHUDViewModel
    
    var body: some View {
        ZStack {
            // Main HUD content
            mainHUDContent
            
            // Shop + Inventory side by side (when both open)
            if viewModel.isShopOpen && viewModel.isInventoryOpen {
                shopAndInventoryOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            // Inventory only (when shop is closed)
            else if viewModel.isInventoryOpen {
                inventoryOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            // Shop only (when inventory is closed)
            else if viewModel.isShopOpen {
                shopOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            
            // Loot panel overlay
            if viewModel.isLootPanelOpen {
                lootPanelOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            
            // Death screen overlay
            if viewModel.isPlayerDead {
                deathScreenOverlay
                    .transition(.opacity)
            }
            
            // Help menu overlay
            if viewModel.isHelpMenuOpen {
                helpMenuOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            
            // Level up menu overlay
            if viewModel.isLevelUpMenuOpen {
                levelUpMenuOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            
            // Pause menu overlay
            if viewModel.isPauseMenuOpen {
                pauseMenuOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            
            // Loot notification popup
            if let loot = viewModel.currentLoot {
                lootNotificationView(loot: loot)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            
            // Enemy health bars
            ForEach(viewModel.enemyHealthBars) { bar in
                enemyHealthBarView(bar)
            }
            
            // Floating damage numbers
            ForEach(viewModel.damageNumbers) { dmg in
                damageNumberView(dmg)
            }
            
            // Level up announcement (big text across screen)
            if viewModel.showLevelUpAnnouncement {
                levelUpAnnouncementView
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    private var levelUpAnnouncementView: some View {
        ZStack {
            // Radial gradient background flash
            RadialGradient(
                colors: [Color.yellow.opacity(0.3), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()
            .opacity(viewModel.announcementOpacity * 0.5)
            
            VStack(spacing: 16) {
                // Sparkle icons
                HStack(spacing: 30) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    Image(systemName: "star.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.orange)
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                }
                
                // Main text
                Text("LEVEL UP!")
                    .font(.system(size: 80, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange, .yellow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: .orange, radius: 20)
                    .shadow(color: .black, radius: 4, x: 2, y: 2)
                
                // Level number
                Text("Level \(viewModel.level)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 4)
                
                // Points gained hint
                Text("+3 Attribute Points!")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
                    .shadow(color: .black, radius: 3)
            }
            .scaleEffect(viewModel.announcementScale)
            .opacity(viewModel.announcementOpacity)
        }
    }
    
    private func damageNumberView(_ dmg: DamageNumberDisplay) -> some View {
        let text: String
        let color: Color
        let fontSize: CGFloat
        
        if dmg.isBlock {
            text = "Blocked!"
            color = .cyan
            fontSize = 26
        } else if dmg.isHeal {
            text = "+\(dmg.amount)"
            color = .green
            fontSize = 22
        } else {
            text = "-\(dmg.amount)"
            color = dmg.isCritical ? .yellow : .red
            fontSize = dmg.isCritical ? 28 : 22
        }
        
        return Text(text)
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .foregroundColor(color)
            .shadow(color: .black, radius: 2, x: 1, y: 1)
            .scaleEffect(dmg.scale)
            .opacity(dmg.opacity)
            .position(dmg.screenPosition)
    }
    
    private func enemyHealthBarView(_ bar: EnemyHealthBar) -> some View {
        VStack(spacing: 2) {
            // Enemy name
            Text(bar.name)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .black, radius: 1, x: 0, y: 1)
            
            // Health bar background
            ZStack(alignment: .leading) {
                // Background (dark)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 60, height: 8)
                
                // Health fill (red to green gradient based on health)
                RoundedRectangle(cornerRadius: 3)
                    .fill(healthBarColor(percentage: bar.hpPercentage))
                    .frame(width: CGFloat(bar.hpPercentage) * 60, height: 8)
                
                // Border
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    .frame(width: 60, height: 8)
            }
        }
        .opacity(bar.opacity)
        .position(bar.screenPosition)
    }
    
    /// Get health bar color based on percentage (green -> yellow -> red)
    private func healthBarColor(percentage: Float) -> Color {
        if percentage > 0.6 {
            return .green
        } else if percentage > 0.3 {
            return .yellow
        } else {
            return .red
        }
    }
    
    private var inventoryOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            // Inventory panel
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("🎒 Inventory")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Gold display
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 14))
                        Text("\(viewModel.gold)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                    }
                    
                    Spacer()
                    
                    // Close hint
                    Text("Press I to close")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal)
                
                HStack(alignment: .top, spacing: 20) {
                    // Equipment slots on the left
                    VStack(spacing: 8) {
                        Text("Equipped")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.gray)
                        
                        // Main Hand slot (Weapon)
                        equipmentSlotView(item: viewModel.equippedMainHand, slotName: "Weapon", slot: .mainHand)
                        
                        // Off Hand slot (Shield)
                        equipmentSlotView(item: viewModel.equippedOffHand, slotName: "Shield", slot: .offHand)
                        
                        // Chest slot (Armor)
                        equipmentSlotView(item: viewModel.equippedChest, slotName: "Armor", slot: .chest)
                    }
                    .frame(width: 90)
                    
                    // Inventory grid (4 columns x 5 rows = 20 slots)
                    VStack(spacing: 8) {
                        Text("Inventory")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.gray)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 8), count: 4), spacing: 8) {
                            ForEach(viewModel.inventorySlots) { slot in
                                inventorySlotView(slot: slot)
                            }
                        }
                    }
                }
                .padding()
            }
            .padding(20)
            .frame(width: 480)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.2), lineWidth: 2)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 20)
        }
    }
    
    private var helpMenuOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    AudioManager.shared.playTick()
                    viewModel.toggleHelpMenu()
                }
            
            // Help panel
            VStack(spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.cyan)
                    Text("Controls & Help")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                Divider()
                    .background(Color.gray)
                
                // Controls grid
                VStack(alignment: .leading, spacing: 12) {
                    helpRow(key: "↑ / ↓", action: "Move Forward / Backward")
                    helpRow(key: "← / →", action: "Turn Left / Right")
                    helpRow(key: "Space", action: "Jump")
                    helpRow(key: "F", action: "Attack (with sword equipped)")
                    helpRow(key: "E", action: "Interact (chests, corpses)")
                    helpRow(key: "Enter", action: "Take All (when looting)")
                    helpRow(key: "I", action: "Open/Close Inventory")
                    helpRow(key: "L", action: "Open Level Up Menu (when points available)")
                    helpRow(key: "H", action: "Open/Close This Help Menu")
                    helpRow(key: "ESC", action: "Pause Menu / Close Menus")
                    helpRow(key: "Esc", action: "Close Current Panel")
                    helpRow(key: "F5", action: "Quick Save")
                }
                
                Divider()
                    .background(Color.gray)
                
                // Tips section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                    
                    tipRow("Double-click items in inventory to equip/use them")
                    tipRow("Potions restore 20 HP when consumed")
                    tipRow("Loot enemy corpses for gold and items")
                    tipRow("Click the '+X points' indicator to allocate stats")
                    tipRow("Save often with F5!")
                }
                
                Spacer()
                    .frame(height: 10)
                
                // Close hint
                Text("Press H or click outside to close")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
            }
            .padding(30)
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.cyan.opacity(0.4), lineWidth: 2)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 20)
        }
    }
    
    private func helpRow(key: String, action: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
                .frame(width: 80, alignment: .leading)
            
            Text(action)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
        }
    }
    
    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.yellow)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
    }
    
    private var shopOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    AudioManager.shared.playTick()
                    viewModel.closeShop()
                }
            
            // Shop panel
            VStack(spacing: 16) {
                // Header
                HStack {
                    Image(systemName: "bag.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.yellow)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.currentShopNPC?.name ?? "Shop")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Vendor")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.yellow.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Player gold
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .foregroundColor(.yellow)
                            .font(.system(size: 14))
                        Text("\(viewModel.gold)")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                    }
                }
                .padding(.horizontal)
                
                Divider()
                    .background(Color.gray)
                
                // Shop items grid
                if let npc = viewModel.currentShopNPC {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(Array(npc.shopItems.enumerated()), id: \.element.id) { index, shopItem in
                                shopItemRow(shopItem: shopItem, index: index)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxHeight: 300)
                } else {
                    Text("No items available")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .padding()
                }
                
                Divider()
                    .background(Color.gray)
                
                // Sell tip
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow.opacity(0.7))
                    Text("Open Inventory (I) and right-click items to sell")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 8)
                
                // Close button
                Button(action: {
                    AudioManager.shared.playTick()
                    viewModel.closeShop()
                }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Close")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.6))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .frame(width: 400)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.yellow.opacity(0.5), lineWidth: 2)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 20)
        }
    }
    
    /// Combined shop and inventory view shown side by side
    private var shopAndInventoryOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    AudioManager.shared.playTick()
                    viewModel.closeShop()
                    viewModel.toggleInventory()
                }
            
            // Side by side panels
            HStack(spacing: 20) {
                // Shop panel (left side)
                shopPanelContent
                
                // Inventory panel (right side)
                inventoryPanelContent
            }
            .padding(20)
        }
    }
    
    /// Shop panel content (extracted for reuse)
    private var shopPanelContent: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "bag.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.yellow)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentShopNPC?.name ?? "Shop")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Vendor - Buy")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.yellow.opacity(0.8))
                }
                
                Spacer()
                
                // Player gold
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 14))
                    Text("\(viewModel.gold)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                }
            }
            .padding(.horizontal)
            
            Divider()
                .background(Color.gray)
            
            // Shop items grid
            if let npc = viewModel.currentShopNPC {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(Array(npc.shopItems.enumerated()), id: \.element.id) { index, shopItem in
                            shopItemRow(shopItem: shopItem, index: index)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)
            } else {
                Text("No items available")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                    .padding()
            }
            
            Divider()
                .background(Color.gray)
            
            // Close button
            Button(action: {
                AudioManager.shared.playTick()
                viewModel.closeShop()
            }) {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("Close Shop")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.6))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.yellow.opacity(0.5), lineWidth: 2)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 20)
    }
    
    /// Inventory panel content for side-by-side view
    private var inventoryPanelContent: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "bag.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Inventory")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Right-click to sell")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green.opacity(0.8))
                }
                
                Spacer()
                
                // Gold display
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 14))
                    Text("\(viewModel.gold)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)
                }
            }
            .padding(.horizontal)
            
            Divider()
                .background(Color.gray)
            
            // Inventory grid (wider slots for sell view)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 12), count: 5), spacing: 12) {
                    ForEach(viewModel.inventorySlots) { slot in
                        inventorySlotView(slot: slot)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 350)
            
            Divider()
                .background(Color.gray)
            
            // Close inventory button
            Button(action: {
                AudioManager.shared.playTick()
                viewModel.toggleInventory()
            }) {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("Close Inventory")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.6))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 480)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.green.opacity(0.5), lineWidth: 2)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 20)
    }
    
    private func shopItemRow(shopItem: ShopItem, index: Int) -> some View {
        let canAfford = viewModel.gold >= shopItem.price
        let isAvailable = shopItem.isAvailable
        
        return HStack(spacing: 12) {
            // Item icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.2))
                    .frame(width: 50, height: 50)
                
                itemIcon(shopItem.item.iconName, size: 24, color: rarityColor(shopItem.item.rarity.name), variant: shopItem.item.iconVariant)
            }
            
            // Item info
            VStack(alignment: .leading, spacing: 4) {
                Text(shopItem.item.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(rarityColor(shopItem.item.rarity.name))
                
                Text(shopItem.item.description)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.gray)
                    .lineLimit(2)
                
                // Stats if any
                if shopItem.item.healAmount > 0 {
                    Text("Heals \(shopItem.item.healAmount) HP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            // Stock indicator (if limited)
            if shopItem.stock >= 0 {
                Text("×\(shopItem.available)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(shopItem.available > 0 ? .white.opacity(0.7) : .red)
            }
            
            // Price and buy button
            VStack(spacing: 6) {
                // Price
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 10))
                    Text("\(shopItem.price)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(canAfford ? .yellow : .red)
                }
                
                // Buy button
                Button(action: {
                    AudioManager.shared.playTick()
                    viewModel.purchaseItem(at: index)
                }) {
                    Text("Buy")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(canAfford && isAvailable ? Color.green : Color.gray)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(!canAfford || !isAvailable)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(rarityColor(shopItem.item.rarity.name).opacity(0.3), lineWidth: 1)
                )
        )
        .opacity(isAvailable ? 1.0 : 0.5)
        .instantTooltip(tooltipForShopItem(shopItem))
    }
    
    /// Build tooltip text for a shop item
    private func tooltipForShopItem(_ shopItem: ShopItem) -> String {
        let item = shopItem.item
        var lines: [String] = [item.name, "(\(item.rarity.name))"]
        
        // Add description if available
        if !item.description.isEmpty {
            lines.append(item.description)
        }
        
        // Add stat bonuses
        if item.damageBonus > 0 { lines.append("+\(item.damageBonus) Damage") }
        if item.dexterityBonus > 0 { lines.append("+\(item.dexterityBonus) Dexterity") }
        if item.strengthBonus > 0 { lines.append("+\(item.strengthBonus) Strength") }
        if item.intelligenceBonus > 0 { lines.append("+\(item.intelligenceBonus) Intelligence") }
        if item.armorBonus > 0 { lines.append("+\(item.armorBonus) Armor") }
        if item.healAmount > 0 { lines.append("Heals \(item.healAmount) HP") }
        
        // Add price
        lines.append("Price: \(shopItem.price) gold")
        
        return lines.joined(separator: "\n")
    }
    
    private var levelUpMenuOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    AudioManager.shared.playTick()
                    viewModel.closeLevelUpMenu()
                }
            
            // Level up panel
            VStack(spacing: 20) {
                // Header with sparkle effect
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    
                    Text("LEVEL UP!")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.yellow)
                        .shadow(color: .yellow.opacity(0.5), radius: 10)
                    
                    Text("Level \(viewModel.level)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
                
                // Unspent points indicator
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                    Text("\(viewModel.unspentPoints) points to allocate")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.green)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.2))
                )
                
                Divider()
                    .background(Color.gray)
                
                // Attribute allocation buttons
                VStack(spacing: 16) {
                    attributeAllocationRow(
                        name: "Strength",
                        shortName: "STR",
                        value: viewModel.strength,
                        color: .red,
                        description: "+5 Max HP, +1 Damage per point",
                        attributeType: .strength
                    )
                    
                    attributeAllocationRow(
                        name: "Dexterity",
                        shortName: "DEX",
                        value: viewModel.dexterity,
                        color: .green,
                        description: "+5% Move Speed, Faster Attacks",
                        attributeType: .dexterity
                    )
                    
                    attributeAllocationRow(
                        name: "Intelligence",
                        shortName: "INT",
                        value: viewModel.intelligence,
                        color: .blue,
                        description: "+2% XP Gain per point",
                        attributeType: .intelligence
                    )
                }
                .padding(.horizontal)
                
                Divider()
                    .background(Color.gray)
                
                // Close button
                Button(action: {
                    AudioManager.shared.playTick()
                    viewModel.closeLevelUpMenu()
                }) {
                    Text("Done")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.blue)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(30)
            .frame(width: 420)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(white: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                LinearGradient(
                                    colors: [.yellow, .orange, .yellow],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
            )
            .shadow(color: .yellow.opacity(0.3), radius: 20)
        }
    }
    
    private func attributeAllocationRow(
        name: String,
        shortName: String,
        value: Int,
        color: Color,
        description: String,
        attributeType: AttributeType
    ) -> some View {
        HStack(spacing: 16) {
            // Attribute info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(shortName)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                        .frame(width: 35)
                    
                    Text(name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(value)")
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundColor(color)
                }
                
                Text(description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            // Allocate button
            Button(action: {
                AudioManager.shared.playTick()
                viewModel.allocatePoint(to: attributeType)
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(viewModel.unspentPoints > 0 ? .green : .gray)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.unspentPoints <= 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Pause Menu
    
    private var pauseMenuOverlay: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    if !viewModel.showSaveDialog && !viewModel.showLoadMenu {
                        AudioManager.shared.playTick()
                        viewModel.closePauseMenu()
                    }
                }
            
            if viewModel.showSaveDialog {
                saveGameDialog
            } else if viewModel.showLoadMenu {
                loadGamePanel
            } else {
                pauseMenuPanel
            }
        }
    }
    
    private var pauseMenuPanel: some View {
        VStack(spacing: 20) {
            // Title
            Text("PAUSED")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .cyan.opacity(0.5), radius: 10)
            
            Spacer().frame(height: 20)
            
            // Menu buttons
            VStack(spacing: 12) {
                pauseMenuButton(title: "Resume", icon: "play.fill", color: .green) {
                    viewModel.closePauseMenu()
                }
                
                pauseMenuButton(title: "Quick Save", icon: "bolt.fill", color: .yellow) {
                    if viewModel.onQuickSave?() == true {
                        viewModel.closePauseMenu()
                    }
                }
                
                pauseMenuButton(title: "Save Game", icon: "square.and.arrow.down.fill", color: .blue) {
                    viewModel.saveGameName = SaveGameManager.shared.generateDefaultSaveName()
                    viewModel.showSaveDialog = true
                }
                
                pauseMenuButton(title: "Load Game", icon: "folder.fill", color: .cyan) {
                    viewModel.availableSaves = SaveGameManager.shared.getAllSaves()
                    viewModel.showLoadMenu = true
                }
                
                Divider()
                    .background(Color.white.opacity(0.3))
                    .padding(.vertical, 8)
                
                pauseMenuButton(title: "Main Menu", icon: "house.fill", color: .orange) {
                    viewModel.onReturnToMainMenu?()
                }
                
                pauseMenuButton(title: "Quit Game", icon: "xmark.circle.fill", color: .red) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .frame(width: 280)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(white: 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                )
        )
        .shadow(color: .cyan.opacity(0.3), radius: 20)
    }
    
    private func pauseMenuButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            AudioManager.shared.playTick()
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(color)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(color.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private var saveGameDialog: some View {
        VStack(spacing: 20) {
            Text("Save Game")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Save Name:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                
                TextField("Enter save name...", text: $viewModel.saveGameName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                            )
                    )
            }
            
            HStack(spacing: 16) {
                Button(action: {
                    AudioManager.shared.playTick()
                    viewModel.showSaveDialog = false
                }) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    AudioManager.shared.playTick()
                    let name = viewModel.saveGameName.isEmpty ? nil : viewModel.saveGameName
                    if viewModel.onSaveGame?(name) == true {
                        viewModel.showSaveDialog = false
                        viewModel.closePauseMenu()
                    }
                }) {
                    Text("Save")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.green)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(30)
        .frame(width: 350)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                )
        )
    }
    
    private var loadGamePanel: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Button(action: {
                    AudioManager.shared.playTick()
                    viewModel.showLoadMenu = false
                }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("Load Game")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Spacer for centering
                Text("Back")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.clear)
            }
            .padding(.horizontal)
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            // Save list
            if viewModel.availableSaves.isEmpty {
                Text("No saved games found")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.availableSaves) { save in
                            loadGameRow(save: save)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(20)
        .frame(width: 450)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.cyan.opacity(0.5), lineWidth: 2)
                )
        )
    }
    
    private func loadGameRow(save: SaveGameData) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(save.saveName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                
                Text(save.formattedTimestamp)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan.opacity(0.8))
                
                Text(save.displaySummary)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: {
                AudioManager.shared.playTick()
                viewModel.loadSaveGame(save)
            }) {
                Text("Load")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private var deathScreenOverlay: some View {
        ZStack {
            // Dark red/black gradient background
            LinearGradient(
                colors: [Color.black, Color.red.opacity(0.3), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Death icon
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                    .shadow(color: .red.opacity(0.5), radius: 20)
                
                // "You're Dead" text
                Text("YOU'RE DEAD")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundColor(.red)
                    .shadow(color: .black, radius: 4, x: 2, y: 2)
                
                Text("Your journey has come to an end...")
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundColor(.gray)
                    .italic()
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    // Load Save button (only if save exists)
                    if viewModel.hasSaveGame {
                        Button(action: {
                            AudioManager.shared.playTick()
                            viewModel.onLoadSaveGame?()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.system(size: 24))
                                Text("Load Last Save")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(width: 280)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue)
                                    .shadow(color: .blue.opacity(0.4), radius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Restart button
                    Button(action: {
                        AudioManager.shared.playTick()
                        viewModel.onRestartGame?()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 24))
                            Text("Start New Game")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 280)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.green.opacity(0.8))
                                .shadow(color: .green.opacity(0.4), radius: 8)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Hint text
                Text("Press F5 to quick save during gameplay")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray.opacity(0.6))
                    .padding(.bottom, 20)
            }
        }
    }
    
    private var lootPanelOverlay: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    AudioManager.shared.playTick()
                    viewModel.closeLootPanel()
                }
            
            // Loot panel
            VStack(spacing: 16) {
                // Header - different icon for chest vs enemy
                HStack {
                    if viewModel.currentLootingChestIndex != nil {
                        Text("🎁 \(viewModel.currentCorpseLoot?.enemyName ?? "Treasure")")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                    } else {
                        Text("💀 \(viewModel.currentCorpseLoot?.enemyName ?? "Corpse")")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // XP reward display (only for enemies)
                    if let loot = viewModel.currentCorpseLoot, loot.xpReward > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.purple)
                                .font(.system(size: 12))
                            Text("+\(loot.xpReward) XP")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.purple)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Gold section
                if let loot = viewModel.currentCorpseLoot, loot.gold > 0 {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 16))
                            Text("\(loot.gold) Gold")
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            AudioManager.shared.playTick()
                            viewModel.lootGold()
                        }) {
                            Text("Take")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.yellow)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.2))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                // Items grid
                if let loot = viewModel.currentCorpseLoot, !loot.items.isEmpty {
                    VStack(spacing: 8) {
                        Text("Items")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.gray)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(70), spacing: 8), count: 4), spacing: 8) {
                            ForEach(Array(loot.items.enumerated()), id: \.element.id) { index, lootItem in
                                lootItemSlotView(lootItem: lootItem, index: index)
                            }
                        }
                    }
                    .padding(.horizontal)
                } else if let loot = viewModel.currentCorpseLoot, loot.items.isEmpty && loot.gold == 0 {
                    Text("Nothing left to loot")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                        .padding()
                }
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: {
                        AudioManager.shared.playTick()
                        viewModel.lootAll()
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.to.line.circle.fill")
                            Text("Loot All")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        AudioManager.shared.playTick()
                        viewModel.closeLootPanel()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Close")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.gray)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            .padding(20)
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.red.opacity(0.4), lineWidth: 2)
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 20)
        }
    }
    
    private func lootItemSlotView(lootItem: LootableItem, index: Int) -> some View {
        ZStack {
            // Slot background
            RoundedRectangle(cornerRadius: 8)
                .fill(lootItem.isLooted ? Color(white: 0.1) : Color(white: 0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(lootItem.isLooted ? Color.gray.opacity(0.2) : rarityBorderColor(lootItem.item.rarity.name), lineWidth: 2)
                )
            
            if !lootItem.isLooted {
                ZStack {
                    // Item icon (larger now that name is removed)
                    itemIcon(lootItem.item.iconName, size: 32, color: rarityColor(lootItem.item.rarity.name), variant: lootItem.item.iconVariant)
                    
                    // Quantity badge (if > 1) in bottom-right corner
                    if lootItem.quantity > 1 {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("x\(lootItem.quantity)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4)
                            }
                        }
                        .padding(4)
                    }
                }
            } else {
                // Looted indicator
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green.opacity(0.5))
            }
        }
        .frame(width: 70, height: 70)
        .opacity(lootItem.isLooted ? 0.5 : 1.0)
        .instantTooltip(tooltipForLootItem(lootItem))
        .onTapGesture {
            AudioManager.shared.playTick()
            if !lootItem.isLooted {
                viewModel.lootItem(at: index)
            }
        }
    }
    
    private func equipmentSlotView(item: InventoryItemDisplay?, slotName: String, slot: EquipmentSlot) -> some View {
        ZStack {
            // Slot background
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(item != nil ? Color.orange.opacity(0.8) : Color.gray.opacity(0.3), lineWidth: 2)
                )
            
            if let item = item {
                // Item icon (larger now that name is removed)
                itemIcon(item.iconName, size: 36, color: rarityColor(item.rarity), variant: item.iconVariant)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: slotIconName(for: slot))
                        .font(.system(size: 24))
                        .foregroundColor(.gray.opacity(0.5))
                    Text(slotName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
        }
        .frame(width: 80, height: 80)
        .instantTooltip(item?.tooltipText ?? slotName)
        .onTapGesture(count: 2) {
            AudioManager.shared.playTick()
            if item != nil {
                viewModel.unequipSlot(slot)
            }
        }
    }
    
    /// Get the SF Symbol icon name for an empty equipment slot
    private func slotIconName(for slot: EquipmentSlot) -> String {
        switch slot {
        case .mainHand: return "hand.raised.fill"
        case .offHand: return "shield.fill"
        case .chest: return "tshirt.fill"
        case .head: return "crown.fill"
        case .feet: return "shoe.fill"
        default: return "hand.raised.slash"
        }
    }
    
    private func inventorySlotView(slot: InventorySlot) -> some View {
        ZStack {
            ZStack {
                // Slot background
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(slot.item != nil ? rarityBorderColor(slot.item?.rarity) : Color.gray.opacity(0.3), lineWidth: 2)
                    )
                
                if let item = slot.item {
                    ZStack {
                        // Item icon (larger now that name is removed)
                        itemIcon(item.iconName, size: 32, color: rarityColor(item.rarity), variant: item.iconVariant)
                        
                        // Quantity badge (if > 1) in bottom-right corner
                        if item.quantity > 1 {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text("x\(item.quantity)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.7))
                                        .cornerRadius(4)
                                }
                            }
                            .padding(4)
                        }
                    }
                }
            }
            .frame(width: 70, height: 70)
        }
        .instantTooltip(slot.item?.tooltipText ?? "")
        .onTapGesture(count: 2) {
            AudioManager.shared.playTick()
            print("[UI] Double-clicked slot \(slot.id), hasItem: \(slot.item != nil)")
            if slot.item != nil {
                viewModel.equipItem(at: slot.id)
            }
        }
        .contextMenu {
            if let item = slot.item {
                // Use item (for consumables like potions)
                if item.iconName == "potion" {
                    Button {
                        viewModel.consumeItem(at: slot.id)
                    } label: {
                        Label("Use", systemImage: "heart.fill")
                    }
                }
                
                // Equip item (for equippable items)
                if item.isEquippable {
                    Button {
                        viewModel.equipItem(at: slot.id)
                    } label: {
                        Label("Equip", systemImage: "hand.raised.fill")
                    }
                }
                
                // Sell item (when shop is open)
                if viewModel.isShopOpen {
                    Divider()
                    
                    let sellPrice = viewModel.sellPriceFor(item)
                    
                    Button {
                        viewModel.sellItem(at: slot.id, quantity: 1)
                    } label: {
                        Label("Sell 1 (\(sellPrice) gold)", systemImage: "dollarsign.circle")
                    }
                    
                    if item.quantity > 1 {
                        Button {
                            viewModel.sellItem(at: slot.id, quantity: item.quantity)
                        } label: {
                            Label("Sell All (\(sellPrice * item.quantity) gold)", systemImage: "dollarsign.circle.fill")
                        }
                    }
                }
                
                Divider()
                
                // Discard one
                Button(role: .destructive) {
                    AudioManager.shared.playTick()
                    viewModel.discardItem(at: slot.id, quantity: 1)
                } label: {
                    Label("Discard 1", systemImage: "trash")
                }
                
                // Discard all (if quantity > 1)
                if item.quantity > 1 {
                    Button(role: .destructive) {
                        AudioManager.shared.playTick()
                        viewModel.discardItem(at: slot.id, quantity: item.quantity)
                    } label: {
                        Label("Discard All (\(item.quantity))", systemImage: "trash.fill")
                    }
                }
            }
        }
    }
    
    /// Returns the SF Symbol name for an item (fallback when Font Awesome unavailable)
    private func sfSymbolForItem(_ iconName: String) -> String {
        switch iconName {
        case "sword": return "bolt.fill"
        case "shield": return "shield.fill"
        case "helmet": return "crown.fill"
        case "armor": return "person.crop.square.fill"
        case "boots": return "figure.walk"
        case "ring": return "circle.circle.fill"
        case "potion": return "drop.fill"
        case "staff": return "wand.and.stars"
        case "bow": return "arrow.up.right"
        case "scroll": return "scroll.fill"
        case "material": return "cube.fill"
        case "gem": return "diamond.fill"
        case "quest": return "star.fill"
        case "misc": return "archivebox.fill"
        default: return "questionmark.square.fill"
        }
    }
    
    /// Returns the Font Awesome unicode character for an item
    private func fontAwesomeForItem(_ iconName: String) -> String {
        switch iconName {
        case "sword": return "\u{f71c}"    // fa-sword (Pro) - will show if Pro font available
        case "shield": return "\u{f3ed}"   // fa-shield-alt
        case "helmet": return "\u{f521}"   // fa-crown
        case "armor": return "\u{f6de}"    // fa-fist-raised
        case "boots": return "\u{f70c}"    // fa-running
        case "ring": return "\u{f3a5}"     // fa-gem
        case "potion": return "\u{f0c3}"   // fa-flask
        case "staff": return "\u{f0d0}"    // fa-magic
        case "bow": return "\u{f05b}"      // fa-crosshairs
        case "scroll": return "\u{f70e}"   // fa-scroll (Pro)
        case "material": return "\u{f1b2}" // fa-cube
        case "quest": return "\u{f005}"    // fa-star
        case "misc": return "\u{f187}"     // fa-archive
        default: return "\u{f128}"         // fa-question
        }
    }
    
    /// Creates an icon view using PNG images from the Icons folder, with SF Symbols fallback
    @ViewBuilder
    private func itemIcon(_ iconName: String, size: CGFloat, color: Color, variant: Int = 1) -> some View {
        if let imagePath = pngIconPath(for: iconName, variant: variant),
           let nsImage = NSImage(contentsOfFile: imagePath) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            // Fallback to SF Symbols
            Image(systemName: sfSymbolForItem(iconName))
                .font(.system(size: size))
                .foregroundColor(color)
        }
    }
    
    /// Returns the path to the PNG icon for an item, if available
    private func pngIconPath(for iconName: String, variant: Int = 1) -> String? {
        // Map item types to their subdirectories and filename prefixes
        let iconMapping: [String: (prefix: String, subdir: String)] = [
            "sword": ("weapon", "weapons"),
            "potion": ("potion", "potions"),
            "shield": ("shield", "shields"),
            "armor": ("armor", "armor"),
            "gem": ("gem", "gems")
        ]
        
        guard let mapping = iconMapping[iconName] else { return nil }
        
        let fileName = "\(mapping.prefix)_\(variant)"
        
        // Try to find the file in the bundle (works with flattened structure)
        if let path = Bundle.main.path(forResource: fileName, ofType: "png") {
            return path
        }
        
        // Try in Icons subdirectories (folder reference structure)
        if let path = Bundle.main.path(forResource: fileName, ofType: "png", inDirectory: "Icons/\(mapping.subdir)") {
            return path
        }
        
        return nil
    }
    
    // Keep for backward compatibility
    private func iconForItem(_ iconName: String) -> String {
        sfSymbolForItem(iconName)
    }
    
    private func rarityBorderColor(_ rarity: String?) -> Color {
        rarityColor(rarity).opacity(0.8)
    }
    
    /// Build tooltip text for a lootable item
    private func tooltipForLootItem(_ lootItem: LootableItem) -> String {
        if lootItem.isLooted {
            return "Already looted"
        }
        
        let item = lootItem.item
        var lines: [String] = [item.name]
        
        // Add rarity
        lines.append("(\(item.rarity.name))")
        
        // Add stat bonuses
        if item.damageBonus > 0 { lines.append("+\(item.damageBonus) Damage") }
        if item.dexterityBonus > 0 { lines.append("+\(item.dexterityBonus) Dexterity") }
        if item.strengthBonus > 0 { lines.append("+\(item.strengthBonus) Strength") }
        if item.intelligenceBonus > 0 { lines.append("+\(item.intelligenceBonus) Intelligence") }
        if item.armorBonus > 0 { lines.append("+\(item.armorBonus) Armor") }
        if item.healAmount > 0 { lines.append("Heals \(item.healAmount) HP") }
        
        // Add quantity if > 1
        if lootItem.quantity > 1 {
            lines.append("Quantity: \(lootItem.quantity)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    private var mainHUDContent: some View {
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
                    
                    // Attribute points indicator (clickable to open level up menu)
                    if viewModel.unspentPoints > 0 {
                        Button(action: {
                            AudioManager.shared.playTick()
                            viewModel.openLevelUpMenu()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 12))
                                Text("\(viewModel.unspentPoints) points")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.green.opacity(0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.green.opacity(0.5), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .shadow(color: .black, radius: 2)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            Spacer()
            
            // Bottom bar - Mini attribute display, coordinates, and help hint
            HStack {
                HStack(spacing: 20) {
                    AttributeDisplay(name: "STR", value: viewModel.strength, color: .red)
                    AttributeDisplay(name: "DEX", value: viewModel.dexterity, color: .green)
                    AttributeDisplay(name: "INT", value: viewModel.intelligence, color: .blue)
                }
                
                Spacer()
                
                // Player coordinates (debug) - click to copy
                Button(action: {
                    AudioManager.shared.playTick()
                    let coords = String(format: "X: %.1f, Y: %.1f, Z: %.1f", viewModel.playerX, viewModel.playerY, viewModel.playerZ)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(coords, forType: .string)
                }) {
                    Text(String(format: "X: %.1f  Y: %.1f  Z: %.1f", viewModel.playerX, viewModel.playerY, viewModel.playerZ))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .help("Click to copy coordinates")
                
                // Help hint
                Text("Press H for Help")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.3))
                    )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    private func lootNotificationView(loot: LootNotification) -> some View {
        VStack(spacing: 8) {
            Text(loot.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.yellow)
            
            if loot.gold > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 14))
                    Text("+\(loot.gold) Gold")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.yellow)
                }
            }
            
            if let itemName = loot.itemName {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(rarityColor(loot.itemRarity))
                        .font(.system(size: 14))
                    Text(itemName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(rarityColor(loot.itemRarity))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.yellow.opacity(0.6), lineWidth: 2)
                )
        )
        .shadow(color: .yellow.opacity(0.3), radius: 10)
        .opacity(loot.opacity)
    }
    
    private func rarityColor(_ rarity: String?) -> Color {
        switch rarity?.lowercased() {
        case "common": return .white
        case "uncommon": return .green
        case "rare": return .blue
        case "epic": return .purple
        case "legendary": return .orange
        default: return .white
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
    var previousLevel: Int = 1  // Track for level up detection
    var gold: Int = 0
    var strength: Int = 10
    var dexterity: Int = 10
    var intelligence: Int = 10
    var unspentPoints: Int = 0
    
    // Debug: Player position
    var playerX: Float = 0
    var playerY: Float = 0
    var playerZ: Float = 0
    
    // Loot notification
    var currentLoot: LootNotification? = nil
    private var lootDismissTask: Task<Void, Never>?
    
    // Inventory state
    var isInventoryOpen: Bool = false
    var inventorySlots: [InventorySlot] = (0..<20).map { InventorySlot(id: $0, item: nil) }
    
    // Equipment slots display
    var equippedMainHand: InventoryItemDisplay? = nil
    var equippedChest: InventoryItemDisplay? = nil
    var equippedOffHand: InventoryItemDisplay? = nil
    
    // Loot panel state
    var isLootPanelOpen: Bool = false
    var currentCorpseLoot: CorpseLoot? = nil
    var currentLootingEnemy: Enemy? = nil
    var currentLootingChestIndex: Int? = nil
    var onChestLooted: ((Int, Int, [Item]) -> Void)?  // (chestIndex, goldTaken, itemsTaken)
    
    // Damage numbers
    var damageNumbers: [DamageNumberDisplay] = []
    
    // Enemy health bars (shown when enemies take damage)
    var enemyHealthBars: [EnemyHealthBar] = []
    
    // Death state
    var isPlayerDead: Bool = false
    var hasSaveGame: Bool = false
    var onRestartGame: (() -> Void)?
    var onLoadSaveGame: (() -> Void)?
    var onReturnToMainMenu: (() -> Void)?
    var onSaveGame: ((String?) -> Bool)?
    var onQuickSave: (() -> Bool)?
    
    // Pause menu state
    var isPauseMenuOpen: Bool = false
    var showSaveDialog: Bool = false
    var saveGameName: String = ""
    var showLoadMenu: Bool = false
    var availableSaves: [SaveGameData] = []
    
    // Help menu state
    var isHelpMenuOpen: Bool = false
    
    // Shop state
    var isShopOpen: Bool = false
    var currentShopNPC: NPC? = nil
    
    // Level up menu state
    var isLevelUpMenuOpen: Bool = false
    
    /// Returns true if the game should be paused (UI menus are open)
    var isGamePaused: Bool {
        isInventoryOpen || isLevelUpMenuOpen || isShopOpen || isPlayerDead || isPauseMenuOpen
    }
    
    // Level up announcement
    var showLevelUpAnnouncement: Bool = false
    var announcementOpacity: Double = 1.0
    var announcementScale: Double = 0.5
    private var levelUpAnnouncementTask: Task<Void, Never>?
    
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
        
        // Initialize level tracking to prevent false level-up on first bind
        level = player.vitals.level
        previousLevel = player.vitals.level
        
        update()
        updateInventorySlots()
        updateEquipmentDisplay()
    }
    
    func update() {
        guard let player = player else { return }
        
        currentHP = player.vitals.currentHP
        maxHP = player.effectiveMaxHP
        currentXP = player.vitals.currentXP
        xpToNextLevel = player.vitals.xpToNextLevel
        
        let newLevel = player.vitals.level
        
        // Check for level up
        if newLevel > level && level > 0 {
            // Player leveled up!
            showLevelUpAnnouncementEffect()
        }
        
        level = newLevel
        previousLevel = newLevel
        
        gold = player.inventory.gold
        strength = player.effectiveStrength
        dexterity = player.effectiveDexterity
        intelligence = player.effectiveIntelligence
        unspentPoints = player.unspentAttributePoints
        
        // Check for death
        if currentHP <= 0 && !isPlayerDead {
            showDeathScreen()
        }
    }
    
    /// Show the death screen
    func showDeathScreen() {
        isPlayerDead = true
        hasSaveGame = SaveGameManager.shared.hasSaveGame
        
        // Play death sounds
        AudioManager.shared.playPlayerDeath()
        
        // Close any open panels
        isInventoryOpen = false
        isLootPanelOpen = false
    }
    
    /// Hide the death screen (called when restarting/loading)
    func hideDeathScreen() {
        isPlayerDead = false
    }
    
    /// Show a loot notification for the given gold and item
    func showLoot(gold: Int, itemName: String?, itemRarity: String?, title: String = "🎁 Treasure Found!", icon: String = "circle.fill") {
        // Cancel any existing dismiss task
        lootDismissTask?.cancel()
        
        // Show the new loot
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentLoot = LootNotification(gold: gold, itemName: itemName, itemRarity: itemRarity, title: title, icon: icon)
        }
        
        // Auto-dismiss after 3 seconds
        lootDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.5)) {
                    currentLoot = nil
                }
            }
        }
    }
    
    /// Add a floating damage number at a screen position
    func addDamageNumber(amount: Int, screenPosition: CGPoint, isCritical: Bool = false, isHeal: Bool = false, isBlock: Bool = false) {
        let dmgNum = DamageNumberDisplay(
            id: UUID(),
            amount: amount,
            isCritical: isCritical,
            isHeal: isHeal,
            isBlock: isBlock,
            screenPosition: screenPosition,
            opacity: 1.0,
            scale: isCritical || isBlock ? 1.3 : 1.0
        )
        
        withAnimation(.easeOut(duration: 0.1)) {
            damageNumbers.append(dmgNum)
        }
        
        // Animate and remove after 1.5 seconds
        Task {
            // Float up animation
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
                if let idx = damageNumbers.firstIndex(where: { $0.id == dmgNum.id }) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        damageNumbers[idx].screenPosition.y -= 8
                        damageNumbers[idx].opacity -= 0.067
                    }
                }
            }
            
            // Remove
            damageNumbers.removeAll { $0.id == dmgNum.id }
        }
    }
    
    /// Update enemy health bars - called each frame by the renderer
    func updateEnemyHealthBars(_ bars: [EnemyHealthBar]) {
        enemyHealthBars = bars
    }
    
    /// Update player position - called each frame by the renderer
    func updatePlayerPosition(x: Float, y: Float, z: Float) {
        playerX = x
        playerY = y
        playerZ = z
    }
    
    /// Show a block notification (when shield blocks an attack)
    func showBlockNotification() {
        // Show block notification using the loot notification system
        showLoot(gold: 0, itemName: "Attack Blocked!", itemRarity: "common", title: "🛡️ Blocked", icon: "shield.fill")
    }
    
    /// Toggle inventory visibility
    func toggleInventory() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isInventoryOpen.toggle()
            if isInventoryOpen {
                updateInventorySlots()
                updateEquipmentDisplay()
            }
        }
    }
    
    func toggleHelpMenu() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isHelpMenuOpen.toggle()
        }
    }
    
    /// Open the shop for a vendor NPC
    func openShop(for npc: NPC) {
        currentShopNPC = npc
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isShopOpen = true
        }
    }
    
    /// Close the shop
    func closeShop() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isShopOpen = false
            currentShopNPC = nil
        }
    }
    
    /// Open the level up menu
    func openLevelUpMenu() {
        guard unspentPoints > 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isLevelUpMenuOpen = true
        }
    }
    
    /// Close the level up menu
    func closeLevelUpMenu() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isLevelUpMenuOpen = false
        }
    }
    
    // MARK: - Pause Menu
    
    /// Toggle the pause menu
    func togglePauseMenu() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if isPauseMenuOpen {
                closePauseMenu()
            } else {
                openPauseMenu()
            }
        }
    }
    
    /// Open the pause menu
    func openPauseMenu() {
        // Close other menus first
        isInventoryOpen = false
        isHelpMenuOpen = false
        isLevelUpMenuOpen = false
        isShopOpen = false
        isLootPanelOpen = false
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPauseMenuOpen = true
            showSaveDialog = false
            showLoadMenu = false
        }
    }
    
    /// Close the pause menu
    func closePauseMenu() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPauseMenuOpen = false
            showSaveDialog = false
            showLoadMenu = false
        }
    }
    
    /// Load a save game from the pause menu
    func loadSaveGame(_ save: SaveGameData) {
        closePauseMenu()
        // Return to main menu - the save will be loaded when starting a new game session
        // This ensures a clean state for loading
        onReturnToMainMenu?()
    }
    
    /// Allocate a point to an attribute
    func allocatePoint(to attribute: AttributeType) {
        guard let player = player else { return }
        
        if player.spendAttributePoint(on: attribute) {
            update()
            
            // Auto-close when no more points
            if unspentPoints == 0 {
                closeLevelUpMenu()
            }
        }
    }
    
    /// Show the dramatic level up announcement
    func showLevelUpAnnouncementEffect() {
        // Cancel any existing animation
        levelUpAnnouncementTask?.cancel()
        
        // Play level up sound
        AudioManager.shared.playLevelUp()
        
        // Reset and show
        announcementOpacity = 1.0
        announcementScale = 0.5
        showLevelUpAnnouncement = true
        
        // Animate in
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            announcementScale = 1.0
        }
        
        // Start fade out after delay
        levelUpAnnouncementTask = Task {
            // Hold for 2 seconds
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            
            // Fade out over 1 second
            withAnimation(.easeOut(duration: 1.0)) {
                announcementOpacity = 0.0
                announcementScale = 1.2
            }
            
            // Wait for animation to complete
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            
            // Hide completely
            showLevelUpAnnouncement = false
        }
    }
    
    /// Purchase an item from the shop
    func purchaseItem(at index: Int) {
        guard let player = player,
              let npc = currentShopNPC,
              index >= 0 && index < npc.shopItems.count else { return }
        
        let shopItem = npc.shopItems[index]
        
        // Check if available
        guard shopItem.isAvailable else {
            print("[Shop] Item '\(shopItem.item.name)' is out of stock")
            return
        }
        
        // Check if player has enough gold
        guard player.inventory.gold >= shopItem.price else {
            print("[Shop] Not enough gold! Need \(shopItem.price), have \(player.inventory.gold)")
            return
        }
        
        // Try to add item to inventory
        guard player.inventory.addItem(shopItem.item) else {
            print("[Shop] Inventory full!")
            return
        }
        
        // Deduct gold
        _ = player.inventory.spendGold(shopItem.price)
        
        // Mark item as sold
        _ = npc.purchaseItem(at: index)
        
        // Update displays
        update()
        updateInventorySlots()
        
        print("[Shop] Purchased '\(shopItem.item.name)' for \(shopItem.price) gold")
    }
    
    /// Equip an item from inventory slot
    func equipItem(at slotIndex: Int) {
        print("[Inventory] equipItem called for slot \(slotIndex)")
        
        guard let player = player else {
            print("[Inventory] ERROR: player is nil")
            return
        }
        guard slotIndex >= 0 && slotIndex < player.inventory.slots.count else {
            print("[Inventory] ERROR: slotIndex \(slotIndex) out of range (0..<\(player.inventory.slots.count))")
            return
        }
        guard let stack = player.inventory.slots[slotIndex] else {
            print("[Inventory] ERROR: no item in slot \(slotIndex)")
            return
        }
        
        let item = stack.item
        
        // Handle consumables (potions, etc.)
        if item.category == .consumable {
            consumeItem(at: slotIndex)
            return
        }
        
        // Only equip if it has an equipment slot
        guard item.equipSlot != nil else {
            print("[Inventory] Item '\(item.name)' is not equippable")
            return
        }
        
        // Try to equip the item
        if let previousItem = player.equipment.equip(item) {
            // Put the previously equipped item back in inventory
            player.inventory.addItem(previousItem)
            print("[Inventory] Swapped '\(previousItem.name)' for '\(item.name)'")
        } else {
            print("[Inventory] Equipped '\(item.name)'")
        }
        
        // Remove the equipped item from inventory
        player.inventory.removeItem(at: slotIndex)
        
        // Update display
        updateInventorySlots()
        updateEquipmentDisplay()
    }
    
    /// Consume an item (potions, etc.)
    func consumeItem(at slotIndex: Int) {
        print("[Inventory] consumeItem called for slot \(slotIndex)")
        
        guard let player = player else {
            print("[Inventory] ERROR: player is nil")
            return
        }
        guard slotIndex >= 0 && slotIndex < player.inventory.slots.count else {
            print("[Inventory] ERROR: slotIndex out of range")
            return
        }
        guard let stack = player.inventory.slots[slotIndex] else {
            print("[Inventory] ERROR: no item in slot")
            return
        }
        
        let item = stack.item
        
        // Apply the consumable's effect
        if item.healAmount > 0 {
            // Play drink potion sound
            AudioManager.shared.playDrinkPotion()
            
            let healed = player.heal(item.healAmount)
            print("[Inventory] Consumed '\(item.name)', healed \(healed) HP")
            // Show heal notification
            showLoot(gold: 0, itemName: "+\(healed) HP", itemRarity: "common", title: "💚 Healed!", icon: "heart.fill")
        }
        
        // Remove one from the stack
        player.inventory.removeItem(at: slotIndex, quantity: 1)
        
        // Update display
        updateInventorySlots()
        update()
    }
    
    /// Discard items from inventory (permanently remove)
    func discardItem(at slotIndex: Int, quantity: Int = 1) {
        print("[Inventory] discardItem called for slot \(slotIndex), quantity: \(quantity)")
        
        guard let player = player else {
            print("[Inventory] ERROR: player is nil")
            return
        }
        guard slotIndex >= 0 && slotIndex < player.inventory.slots.count else {
            print("[Inventory] ERROR: slotIndex out of range")
            return
        }
        guard let stack = player.inventory.slots[slotIndex] else {
            print("[Inventory] ERROR: no item in slot")
            return
        }
        
        let item = stack.item
        let actualQuantity = min(quantity, stack.quantity)
        
        // Remove from inventory
        player.inventory.removeItem(at: slotIndex, quantity: actualQuantity)
        
        print("[Inventory] Discarded \(actualQuantity)x '\(item.name)'")
        
        // Show discard notification
        let message = actualQuantity > 1 ? "Discarded \(actualQuantity)x \(item.name)" : "Discarded \(item.name)"
        showLoot(gold: 0, itemName: message, itemRarity: "common", title: "🗑️ Discarded", icon: "trash")
        
        // Update display
        updateInventorySlots()
        update()
    }
    
    /// Calculate sell price for an item (50% of item value, minimum 1 gold)
    func sellPriceFor(_ item: InventoryItemDisplay) -> Int {
        // Sell for 50% of value, minimum 1 gold
        return max(1, item.value / 2)
    }
    
    /// Sell items from inventory to vendor
    func sellItem(at slotIndex: Int, quantity: Int = 1) {
        print("[Shop] sellItem called for slot \(slotIndex), quantity: \(quantity)")
        
        guard isShopOpen else {
            print("[Shop] ERROR: shop is not open")
            return
        }
        guard let player = player else {
            print("[Shop] ERROR: player is nil")
            return
        }
        guard slotIndex >= 0 && slotIndex < player.inventory.slots.count else {
            print("[Shop] ERROR: slotIndex out of range")
            return
        }
        guard let stack = player.inventory.slots[slotIndex] else {
            print("[Shop] ERROR: no item in slot")
            return
        }
        
        let item = stack.item
        let actualQuantity = min(quantity, stack.quantity)
        let pricePerItem = max(1, item.value / 2)  // 50% of value, minimum 1
        let totalGold = pricePerItem * actualQuantity
        
        // Remove from inventory
        player.inventory.removeItem(at: slotIndex, quantity: actualQuantity)
        
        // Add gold
        player.inventory.addGold(totalGold)
        
        print("[Shop] Sold \(actualQuantity)x '\(item.name)' for \(totalGold) gold")
        
        // Show sell notification
        let message = actualQuantity > 1 ? "\(actualQuantity)x \(item.name)" : item.name
        showLoot(gold: totalGold, itemName: message, itemRarity: "common", title: "💰 Sold", icon: "dollarsign.circle.fill")
        
        // Update display
        updateInventorySlots()
        update()
    }
    
    /// Unequip item from main hand and return to inventory
    func unequipMainHand() {
        print("[Inventory] unequipMainHand called")
        guard let player = player else {
            print("[Inventory] ERROR: player is nil")
            return
        }
        
        guard let item = player.equipment.unequip(.mainHand) else {
            print("[Inventory] No item equipped in main hand")
            return
        }
        
        // Add back to inventory
        if player.inventory.addItem(item) {
            print("[Inventory] Unequipped '\(item.name)' and returned to inventory")
        } else {
            // Inventory full, re-equip
            player.equipment.equip(item)
            print("[Inventory] Inventory full! Cannot unequip '\(item.name)'")
        }
        
        updateInventorySlots()
        updateEquipmentDisplay()
    }
    
    /// Unequip item from any slot and return to inventory
    func unequipSlot(_ slot: EquipmentSlot) {
        print("[Inventory] unequipSlot called for \(slot.displayName)")
        guard let player = player else {
            print("[Inventory] ERROR: player is nil")
            return
        }
        
        guard let item = player.equipment.unequip(slot) else {
            print("[Inventory] No item equipped in \(slot.displayName)")
            return
        }
        
        // Add back to inventory
        if player.inventory.addItem(item) {
            print("[Inventory] Unequipped '\(item.name)' and returned to inventory")
        } else {
            // Inventory full, re-equip
            player.equipment.equip(item)
            print("[Inventory] Inventory full! Cannot unequip '\(item.name)'")
        }
        
        updateInventorySlots()
        updateEquipmentDisplay()
    }
    
    // MARK: - Loot Panel
    
    /// Open the loot panel for a corpse
    func openLootPanel(for enemy: Enemy) {
        guard !enemy.isLooted else { return }
        
        // Play loot menu sound
        AudioManager.shared.playLootMenu()
        
        currentLootingEnemy = enemy
        currentLootingChestIndex = nil
        
        // Create loot display
        var lootItems: [LootableItem] = []
        for item in enemy.lootItems {
            lootItems.append(LootableItem(id: UUID(), item: item, quantity: 1))
        }
        
        currentCorpseLoot = CorpseLoot(
            enemyName: enemy.displayName,
            gold: enemy.lootGold,
            items: lootItems,
            xpReward: enemy.xpReward
        )
        
        isLootPanelOpen = true
    }
    
    /// Open the loot panel for a treasure chest
    func openLootPanelForChest(index: Int, name: String, gold: Int, items: [Item]) {
        currentLootingEnemy = nil
        currentLootingChestIndex = index
        
        // Create loot display
        var lootItems: [LootableItem] = []
        for item in items {
            lootItems.append(LootableItem(id: UUID(), item: item, quantity: 1))
        }
        
        currentCorpseLoot = CorpseLoot(
            enemyName: name,
            gold: gold,
            items: lootItems,
            xpReward: 0  // Chests don't give XP
        )
        
        isLootPanelOpen = true
    }
    
    /// Loot gold from the corpse
    func lootGold() {
        guard let player = player,
              var loot = currentCorpseLoot else { return }
        
        if loot.gold > 0 {
            player.inventory.addGold(loot.gold)
            loot.gold = 0
            currentCorpseLoot = loot
            update()
        }
    }
    
    /// Loot a specific item from the corpse
    func lootItem(at index: Int) {
        guard let player = player,
              var loot = currentCorpseLoot,
              index >= 0 && index < loot.items.count else { return }
        
        let lootableItem = loot.items[index]
        guard !lootableItem.isLooted else { return }
        
        // Try to add to inventory
        if player.inventory.addItem(lootableItem.item, quantity: lootableItem.quantity) {
            loot.items[index].isLooted = true
            currentCorpseLoot = loot
            updateInventorySlots()
        }
    }
    
    /// Loot all items from the corpse
    func lootAll() {
        guard let player = player,
              var loot = currentCorpseLoot else { return }
        
        // Loot gold
        if loot.gold > 0 {
            player.inventory.addGold(loot.gold)
            loot.gold = 0
        }
        
        // Loot all items
        for i in 0..<loot.items.count {
            if !loot.items[i].isLooted {
                if player.inventory.addItem(loot.items[i].item, quantity: loot.items[i].quantity) {
                    loot.items[i].isLooted = true
                }
            }
        }
        
        currentCorpseLoot = loot
        updateInventorySlots()
        update()
        
        // Auto-close if everything is looted
        if loot.gold == 0 && loot.items.allSatisfy({ $0.isLooted }) {
            closeLootPanel()
        }
    }
    
    /// Close the loot panel and mark enemy as looted
    func closeLootPanel() {
        guard let loot = currentCorpseLoot else {
            isLootPanelOpen = false
            currentCorpseLoot = nil
            currentLootingEnemy = nil
            currentLootingChestIndex = nil
            return
        }
        
        // Check what was taken
        let tookItems = loot.items.contains { $0.isLooted }
        let originalGold = currentLootingEnemy?.lootGold ?? (currentLootingChestIndex != nil ? loot.gold : 0)
        let tookGold = originalGold != loot.gold || loot.gold == 0
        
        // Handle enemy looting
        if let enemy = currentLootingEnemy {
            if tookGold || tookItems {
                enemy.isLooted = true
                
                // Grant XP
                if let player = player, loot.xpReward > 0 {
                    player.gainXP(loot.xpReward)
                    update()
                }
                
                // If everything was looted, make enemy disappear immediately
                let allItemsLooted = loot.items.allSatisfy { $0.isLooted }
                let allGoldLooted = loot.gold == 0
                if allItemsLooted && allGoldLooted {
                    enemy.stateTimer = 1000  // High value triggers immediate removal
                }
            }
        }
        
        // Handle chest looting - notify the renderer
        if let chestIndex = currentLootingChestIndex {
            let itemsTaken = loot.items.filter { $0.isLooted }.map { $0.item }
            let goldTaken = max(0, originalGold - loot.gold)
            onChestLooted?(chestIndex, goldTaken, itemsTaken)
        }
        
        isLootPanelOpen = false
        currentCorpseLoot = nil
        currentLootingEnemy = nil
        currentLootingChestIndex = nil
    }
    
    /// Update equipment display
    func updateEquipmentDisplay() {
        guard let player = player else { return }
        
        // Main Hand (Weapon)
        if let weapon = player.equipment.itemIn(.mainHand) {
            equippedMainHand = InventoryItemDisplay(
                id: weapon.id,
                name: weapon.name,
                rarity: weapon.rarity.name,
                quantity: 1,
                iconName: weapon.iconName,
                iconVariant: weapon.iconVariant,
                isEquippable: true,
                equipSlotName: EquipmentSlot.mainHand.displayName,
                value: weapon.value,
                damageBonus: weapon.damageBonus,
                dexterityBonus: weapon.dexterityBonus,
                strengthBonus: weapon.strengthBonus,
                intelligenceBonus: weapon.intelligenceBonus,
                armorBonus: weapon.armorBonus,
                healAmount: weapon.healAmount
            )
        } else {
            equippedMainHand = nil
        }
        
        // Off Hand (Shield)
        if let shield = player.equipment.itemIn(.offHand) {
            equippedOffHand = InventoryItemDisplay(
                id: shield.id,
                name: shield.name,
                rarity: shield.rarity.name,
                quantity: 1,
                iconName: shield.iconName,
                iconVariant: shield.iconVariant,
                isEquippable: true,
                equipSlotName: EquipmentSlot.offHand.displayName,
                value: shield.value,
                damageBonus: shield.damageBonus,
                dexterityBonus: shield.dexterityBonus,
                strengthBonus: shield.strengthBonus,
                intelligenceBonus: shield.intelligenceBonus,
                armorBonus: shield.armorBonus,
                healAmount: shield.healAmount,
                blockChance: shield.blockChance
            )
        } else {
            equippedOffHand = nil
        }
        
        // Chest (Armor)
        if let armor = player.equipment.itemIn(.chest) {
            equippedChest = InventoryItemDisplay(
                id: armor.id,
                name: armor.name,
                rarity: armor.rarity.name,
                quantity: 1,
                iconName: armor.iconName,
                iconVariant: armor.iconVariant,
                isEquippable: true,
                equipSlotName: EquipmentSlot.chest.displayName,
                value: armor.value,
                damageBonus: armor.damageBonus,
                dexterityBonus: armor.dexterityBonus,
                strengthBonus: armor.strengthBonus,
                intelligenceBonus: armor.intelligenceBonus,
                armorBonus: armor.armorBonus,
                healAmount: armor.healAmount
            )
        } else {
            equippedChest = nil
        }
    }
    
    /// Update inventory slots from player data
    func updateInventorySlots() {
        guard let player = player else { return }
        
        var newSlots: [InventorySlot] = []
        let slots = player.inventory.slots
        
        for i in 0..<20 {
            if i < slots.count, let stack = slots[i] {
                let item = stack.item
                let display = InventoryItemDisplay(
                    id: item.id,
                    name: item.name,
                    rarity: item.rarity.name,
                    quantity: stack.quantity,
                    iconName: item.iconName,
                    iconVariant: item.iconVariant,
                    isEquippable: item.equipSlot != nil,
                    equipSlotName: item.equipSlot?.displayName,
                    value: item.value,
                    damageBonus: item.damageBonus,
                    dexterityBonus: item.dexterityBonus,
                    strengthBonus: item.strengthBonus,
                    intelligenceBonus: item.intelligenceBonus,
                    armorBonus: item.armorBonus,
                    healAmount: item.healAmount,
                    blockChance: item.blockChance
                )
                newSlots.append(InventorySlot(id: i, item: display))
            } else {
                newSlots.append(InventorySlot(id: i, item: nil))
            }
        }
        
        inventorySlots = newSlots
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

