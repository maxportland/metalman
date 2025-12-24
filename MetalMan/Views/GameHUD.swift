import SwiftUI

/// Represents loot found in a chest
struct LootNotification: Identifiable {
    let id = UUID()
    let gold: Int
    let itemName: String?
    let itemRarity: String?
    var opacity: Double = 1.0
}

/// Represents a floating damage number on screen
struct DamageNumberDisplay: Identifiable {
    let id: UUID
    let amount: Int
    let isCritical: Bool
    let isHeal: Bool
    var screenPosition: CGPoint
    var opacity: Double
    var scale: Double
}

/// Represents an item slot in the inventory grid
struct InventorySlot: Identifiable {
    let id: Int
    var item: InventoryItemDisplay?
}

/// Display info for an inventory item
struct InventoryItemDisplay: Identifiable {
    let id: UUID
    let name: String
    let rarity: String
    let quantity: Int
    let iconName: String
    let isEquippable: Bool
    let equipSlotName: String?
}

/// HUD overlay displaying player stats, health, and XP
struct GameHUD: View {
    var viewModel: GameHUDViewModel
    
    var body: some View {
        ZStack {
            // Main HUD content
            mainHUDContent
            
            // Inventory overlay
            if viewModel.isInventoryOpen {
                inventoryOverlay
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
            
            // Floating damage numbers
            ForEach(viewModel.damageNumbers) { dmg in
                damageNumberView(dmg)
            }
        }
    }
    
    private func damageNumberView(_ dmg: DamageNumberDisplay) -> some View {
        Text(dmg.isHeal ? "+\(dmg.amount)" : "-\(dmg.amount)")
            .font(.system(size: dmg.isCritical ? 28 : 22, weight: .bold, design: .rounded))
            .foregroundColor(dmg.isHeal ? .green : (dmg.isCritical ? .yellow : .red))
            .shadow(color: .black, radius: 2, x: 1, y: 1)
            .scaleEffect(dmg.scale)
            .opacity(dmg.opacity)
            .position(dmg.screenPosition)
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
                        
                        // Main Hand slot
                        equipmentSlotView(item: viewModel.equippedMainHand, slotName: "Main Hand")
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
    
    private func equipmentSlotView(item: InventoryItemDisplay?, slotName: String) -> some View {
        ZStack {
            // Slot background
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(item != nil ? Color.orange.opacity(0.8) : Color.gray.opacity(0.3), lineWidth: 2)
                )
            
            if let item = item {
                VStack(spacing: 2) {
                    // Item icon
                    Image(systemName: iconForItem(item.iconName))
                        .font(.system(size: 24))
                        .foregroundColor(rarityColor(item.rarity))
                    
                    // Item name (truncated)
                    Text(item.name)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    // Unequip hint
                    Text("2x to Unequip")
                        .font(.system(size: 6, weight: .medium))
                        .foregroundColor(.orange.opacity(0.8))
                }
                .padding(4)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "hand.raised.slash")
                        .font(.system(size: 20))
                        .foregroundColor(.gray.opacity(0.5))
                    Text(slotName)
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
        }
        .frame(width: 80, height: 80)
        .onTapGesture(count: 2) {
            if item != nil {
                viewModel.unequipMainHand()
            }
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
                    VStack(spacing: 2) {
                        // Item icon
                        Image(systemName: iconForItem(item.iconName))
                            .font(.system(size: 24))
                            .foregroundColor(rarityColor(item.rarity))
                        
                        // Item name (truncated)
                        Text(item.name)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        // Quantity (if > 1) or Equip hint
                        if item.quantity > 1 {
                            Text("x\(item.quantity)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                        } else if item.isEquippable {
                            Text("2x to Equip")
                                .font(.system(size: 7, weight: .medium))
                                .foregroundColor(.green.opacity(0.8))
                        }
                    }
                    .padding(4)
                }
            }
            .frame(width: 70, height: 70)
        }
        .onTapGesture(count: 2) {
            print("[UI] Double-clicked slot \(slot.id), hasItem: \(slot.item != nil)")
            if slot.item != nil {
                viewModel.equipItem(at: slot.id)
            }
        }
    }
    
    private func iconForItem(_ iconName: String) -> String {
        // Map item icon names to SF Symbols
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
        case "quest": return "star.fill"
        case "misc": return "archivebox.fill"
        default: return "questionmark.square.fill"
        }
    }
    
    private func rarityBorderColor(_ rarity: String?) -> Color {
        rarityColor(rarity).opacity(0.8)
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
    
    private func lootNotificationView(loot: LootNotification) -> some View {
        VStack(spacing: 8) {
            Text("🎁 Treasure Found!")
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
    var gold: Int = 0
    var strength: Int = 10
    var dexterity: Int = 10
    var intelligence: Int = 10
    var unspentPoints: Int = 0
    
    // Loot notification
    var currentLoot: LootNotification? = nil
    private var lootDismissTask: Task<Void, Never>?
    
    // Inventory state
    var isInventoryOpen: Bool = false
    var inventorySlots: [InventorySlot] = (0..<20).map { InventorySlot(id: $0, item: nil) }
    
    // Equipment slots display
    var equippedMainHand: InventoryItemDisplay? = nil
    
    // Damage numbers
    var damageNumbers: [DamageNumberDisplay] = []
    
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
    
    /// Show a loot notification for the given gold and item
    func showLoot(gold: Int, itemName: String?, itemRarity: String?) {
        // Cancel any existing dismiss task
        lootDismissTask?.cancel()
        
        // Show the new loot
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentLoot = LootNotification(gold: gold, itemName: itemName, itemRarity: itemRarity)
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
    func addDamageNumber(amount: Int, screenPosition: CGPoint, isCritical: Bool = false, isHeal: Bool = false) {
        let dmgNum = DamageNumberDisplay(
            id: UUID(),
            amount: amount,
            isCritical: isCritical,
            isHeal: isHeal,
            screenPosition: screenPosition,
            opacity: 1.0,
            scale: isCritical ? 1.3 : 1.0
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
    
    /// Update equipment display
    func updateEquipmentDisplay() {
        guard let player = player else { return }
        
        if let weapon = player.equipment.itemIn(.mainHand) {
            equippedMainHand = InventoryItemDisplay(
                id: weapon.id,
                name: weapon.name,
                rarity: weapon.rarity.name,
                quantity: 1,
                iconName: weapon.iconName,
                isEquippable: true,
                equipSlotName: EquipmentSlot.mainHand.displayName
            )
        } else {
            equippedMainHand = nil
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
                    isEquippable: item.equipSlot != nil,
                    equipSlotName: item.equipSlot?.displayName
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

