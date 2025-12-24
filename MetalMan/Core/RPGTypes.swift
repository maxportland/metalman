import Foundation

// MARK: - Character Stats

/// Core character attributes that affect gameplay
struct CharacterAttributes {
    var strength: Int      // Affects melee damage, carry capacity
    var dexterity: Int     // Affects speed, accuracy, dodge chance
    var intelligence: Int  // Affects magic power, XP gain, crafting
    
    init(strength: Int = 10, dexterity: Int = 10, intelligence: Int = 10) {
        self.strength = strength
        self.dexterity = dexterity
        self.intelligence = intelligence
    }
    
    /// Total attribute points
    var total: Int { strength + dexterity + intelligence }
}

/// Character health and experience
struct CharacterVitals {
    var currentHP: Int
    var maxHP: Int
    var currentXP: Int
    var xpToNextLevel: Int
    var level: Int
    
    init(maxHP: Int = 100, level: Int = 1) {
        self.currentHP = maxHP
        self.maxHP = maxHP
        self.currentXP = 0
        self.level = level
        self.xpToNextLevel = CharacterVitals.calculateXPForLevel(level + 1)
    }
    
    /// XP required to reach a given level (exponential scaling)
    static func calculateXPForLevel(_ level: Int) -> Int {
        return Int(100 * pow(1.5, Double(level - 1)))
    }
    
    /// HP percentage (0.0 to 1.0)
    var hpPercentage: Float {
        guard maxHP > 0 else { return 0 }
        return Float(currentHP) / Float(maxHP)
    }
    
    /// XP percentage toward next level (0.0 to 1.0)
    var xpPercentage: Float {
        guard xpToNextLevel > 0 else { return 0 }
        return Float(currentXP) / Float(xpToNextLevel)
    }
    
    var isAlive: Bool { currentHP > 0 }
}

// MARK: - Items

/// Item rarity affects stats and drop rates
enum ItemRarity: Int, Comparable, CaseIterable {
    case common = 0
    case uncommon = 1
    case rare = 2
    case epic = 3
    case legendary = 4
    
    var name: String {
        switch self {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .legendary: return "Legendary"
        }
    }
    
    var colorHex: UInt32 {
        switch self {
        case .common: return 0xAAAAAA
        case .uncommon: return 0x1EFF00
        case .rare: return 0x0070DD
        case .epic: return 0xA335EE
        case .legendary: return 0xFF8000
        }
    }
    
    static func < (lhs: ItemRarity, rhs: ItemRarity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Category of item for inventory organization
enum ItemCategory {
    case weapon
    case armor
    case consumable
    case material
    case quest
    case misc
}

/// Equipment slot for wearable items
enum EquipmentSlot: CaseIterable {
    case head
    case chest
    case legs
    case feet
    case hands
    case mainHand
    case offHand
    case accessory1
    case accessory2
    
    var displayName: String {
        switch self {
        case .head: return "Head"
        case .chest: return "Chest"
        case .legs: return "Legs"
        case .feet: return "Feet"
        case .hands: return "Hands"
        case .mainHand: return "Main Hand"
        case .offHand: return "Off Hand"
        case .accessory1: return "Accessory"
        case .accessory2: return "Accessory"
        }
    }
}

/// Base item definition
struct Item: Identifiable, Equatable {
    let id: UUID
    let name: String
    let description: String
    let category: ItemCategory
    let rarity: ItemRarity
    let stackable: Bool
    let maxStackSize: Int
    let value: Int  // Gold value
    
    // Optional stat modifiers
    var strengthBonus: Int = 0
    var dexterityBonus: Int = 0
    var intelligenceBonus: Int = 0
    var hpBonus: Int = 0
    var damageBonus: Int = 0
    var armorBonus: Int = 0
    
    // For equipment
    var equipSlot: EquipmentSlot? = nil
    
    // For consumables
    var healAmount: Int = 0
    var xpAmount: Int = 0
    
    init(id: UUID = UUID(),
         name: String,
         description: String,
         category: ItemCategory,
         rarity: ItemRarity = .common,
         stackable: Bool = false,
         maxStackSize: Int = 1,
         value: Int = 0) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.rarity = rarity
        self.stackable = stackable
        self.maxStackSize = stackable ? max(1, maxStackSize) : 1
        self.value = value
    }
    
    static func == (lhs: Item, rhs: Item) -> Bool {
        lhs.id == rhs.id
    }
    
    /// Icon name based on category for UI display
    var iconName: String {
        switch category {
        case .weapon:
            if name.lowercased().contains("staff") { return "staff" }
            if name.lowercased().contains("bow") { return "bow" }
            return "sword"
        case .armor:
            if equipSlot == .head { return "helmet" }
            if equipSlot == .feet { return "boots" }
            if equipSlot == .hands { return "ring" }
            return "armor"
        case .consumable:
            if name.lowercased().contains("scroll") { return "scroll" }
            return "potion"
        case .material:
            return "material"
        case .quest:
            return "quest"
        case .misc:
            return "misc"
        }
    }
}

/// Stack of items in inventory
struct ItemStack {
    let item: Item
    var quantity: Int
    
    var isFull: Bool { quantity >= item.maxStackSize }
    var canAdd: Bool { item.stackable && !isFull }
    
    mutating func add(_ amount: Int = 1) -> Int {
        let space = item.maxStackSize - quantity
        let toAdd = min(amount, space)
        quantity += toAdd
        return amount - toAdd  // Return remainder
    }
    
    mutating func remove(_ amount: Int = 1) -> Int {
        let toRemove = min(amount, quantity)
        quantity -= toRemove
        return toRemove
    }
}

// MARK: - Inventory

/// Player inventory with slots and weight limits
final class Inventory: @unchecked Sendable {
    private(set) var slots: [ItemStack?]
    private(set) var gold: Int
    let capacity: Int
    
    init(capacity: Int = 20, gold: Int = 0) {
        self.capacity = capacity
        self.slots = Array(repeating: nil, count: capacity)
        self.gold = gold
    }
    
    /// Number of occupied slots
    var usedSlots: Int {
        slots.compactMap { $0 }.count
    }
    
    /// Number of empty slots
    var freeSlots: Int {
        capacity - usedSlots
    }
    
    /// Check if inventory is full
    var isFull: Bool { freeSlots == 0 }
    
    /// Add an item to inventory
    /// - Returns: true if item was added, false if no room
    @discardableResult
    func addItem(_ item: Item, quantity: Int = 1) -> Bool {
        var remaining = quantity
        
        // First, try to stack with existing items
        if item.stackable {
            for i in 0..<slots.count {
                guard var stack = slots[i], stack.item.name == item.name && stack.canAdd else { continue }
                remaining = stack.add(remaining)
                slots[i] = stack
                if remaining == 0 { return true }
            }
        }
        
        // Then, try to add to empty slots
        while remaining > 0 {
            guard let emptyIndex = slots.firstIndex(where: { $0 == nil }) else {
                return false  // No room
            }
            
            let stackSize = min(remaining, item.maxStackSize)
            slots[emptyIndex] = ItemStack(item: item, quantity: stackSize)
            remaining -= stackSize
        }
        
        return true
    }
    
    /// Remove an item from inventory
    /// - Returns: Number of items actually removed
    @discardableResult
    func removeItem(_ item: Item, quantity: Int = 1) -> Int {
        var remaining = quantity
        
        for i in 0..<slots.count {
            guard var stack = slots[i], stack.item.name == item.name else { continue }
            
            let removed = stack.remove(remaining)
            remaining -= removed
            
            if stack.quantity == 0 {
                slots[i] = nil
            } else {
                slots[i] = stack
            }
            
            if remaining == 0 { break }
        }
        
        return quantity - remaining
    }
    
    /// Check if inventory contains an item
    func contains(_ item: Item) -> Bool {
        slots.contains { $0?.item.name == item.name }
    }
    
    /// Count total quantity of an item
    func count(of item: Item) -> Int {
        slots.compactMap { $0 }
            .filter { $0.item.name == item.name }
            .reduce(0) { $0 + $1.quantity }
    }
    
    /// Get item at a specific slot
    func itemAt(slot: Int) -> ItemStack? {
        guard slot >= 0 && slot < capacity else { return nil }
        return slots[slot]
    }
    
    /// Remove item at a specific slot index (used when equipping)
    @discardableResult
    func removeItem(at slotIndex: Int, quantity: Int = 1) -> Item? {
        guard slotIndex >= 0 && slotIndex < slots.count else { return nil }
        guard var stack = slots[slotIndex] else { return nil }
        
        let item = stack.item
        
        if stack.quantity <= quantity {
            // Remove entire stack
            slots[slotIndex] = nil
        } else {
            // Reduce quantity
            stack.quantity -= quantity
            slots[slotIndex] = stack
        }
        
        return item
    }
    
    /// Add gold
    func addGold(_ amount: Int) {
        gold += max(0, amount)
    }
    
    /// Spend gold
    /// - Returns: true if had enough gold, false otherwise
    @discardableResult
    func spendGold(_ amount: Int) -> Bool {
        guard gold >= amount else { return false }
        gold -= amount
        return true
    }
    
    /// Get all items as a flat list
    func allItems() -> [ItemStack] {
        slots.compactMap { $0 }
    }
}

// MARK: - Equipment

/// Currently equipped items
final class Equipment: @unchecked Sendable {
    private var slots: [EquipmentSlot: Item] = [:]
    
    /// Equip an item
    /// - Returns: Previously equipped item if any
    @discardableResult
    func equip(_ item: Item) -> Item? {
        guard let slot = item.equipSlot else { return nil }
        let previous = slots[slot]
        slots[slot] = item
        return previous
    }
    
    /// Unequip from a slot
    /// - Returns: The unequipped item if any
    @discardableResult
    func unequip(_ slot: EquipmentSlot) -> Item? {
        let item = slots[slot]
        slots[slot] = nil
        return item
    }
    
    /// Get equipped item in slot
    func itemIn(_ slot: EquipmentSlot) -> Item? {
        slots[slot]
    }
    
    /// Total stat bonuses from all equipment
    var totalStrengthBonus: Int { slots.values.reduce(0) { $0 + $1.strengthBonus } }
    var totalDexterityBonus: Int { slots.values.reduce(0) { $0 + $1.dexterityBonus } }
    var totalIntelligenceBonus: Int { slots.values.reduce(0) { $0 + $1.intelligenceBonus } }
    var totalHPBonus: Int { slots.values.reduce(0) { $0 + $1.hpBonus } }
    var totalDamageBonus: Int { slots.values.reduce(0) { $0 + $1.damageBonus } }
    var totalArmorBonus: Int { slots.values.reduce(0) { $0 + $1.armorBonus } }
    
    /// Check if a weapon (sword) is equipped in main hand
    var hasSwordEquipped: Bool {
        guard let weapon = slots[.mainHand] else { return false }
        return weapon.category == .weapon && weapon.name.lowercased().contains("sword")
    }
    
    /// Check if any weapon is equipped in main hand
    var hasWeaponEquipped: Bool {
        guard let weapon = slots[.mainHand] else { return false }
        return weapon.category == .weapon
    }
}

// MARK: - Player Character

/// The main player character with all RPG systems
/// Note: @unchecked Sendable allows cross-thread access. The HUD reads on main thread,
/// Renderer writes on render thread. This is safe because updates are infrequent.
final class PlayerCharacter: @unchecked Sendable {
    let name: String
    var attributes: CharacterAttributes
    var vitals: CharacterVitals
    let inventory: Inventory
    let equipment: Equipment
    
    /// Attribute points available to spend
    var unspentAttributePoints: Int = 0
    
    init(name: String,
         attributes: CharacterAttributes = CharacterAttributes(),
         maxHP: Int = 100,
         inventoryCapacity: Int = 20) {
        self.name = name
        self.attributes = attributes
        self.vitals = CharacterVitals(maxHP: maxHP, level: 1)
        self.inventory = Inventory(capacity: inventoryCapacity)
        self.equipment = Equipment()
        
        // Set current HP to effective max HP (includes strength bonus)
        // This ensures the character starts at 100% health
        self.vitals.currentHP = effectiveMaxHP
    }
    
    // MARK: - Effective Stats (base + equipment)
    
    var effectiveStrength: Int {
        attributes.strength + equipment.totalStrengthBonus
    }
    
    var effectiveDexterity: Int {
        attributes.dexterity + equipment.totalDexterityBonus
    }
    
    var effectiveIntelligence: Int {
        attributes.intelligence + equipment.totalIntelligenceBonus
    }
    
    var effectiveMaxHP: Int {
        vitals.maxHP + equipment.totalHPBonus + (attributes.strength * 5)
    }
    
    var effectiveDamage: Int {
        let baseDamage = 5 + (effectiveStrength / 2)
        return baseDamage + equipment.totalDamageBonus
    }
    
    var effectiveArmor: Int {
        equipment.totalArmorBonus + (effectiveDexterity / 4)
    }
    
    /// Movement speed modifier based on dexterity
    var speedModifier: Float {
        1.0 + Float(effectiveDexterity - 10) * 0.02
    }
    
    // MARK: - Actions
    
    /// Take damage (reduced by armor)
    func takeDamage(_ rawDamage: Int) {
        let reduction = min(rawDamage - 1, effectiveArmor)
        let actualDamage = max(1, rawDamage - reduction)
        vitals.currentHP = max(0, vitals.currentHP - actualDamage)
    }
    
    /// Heal HP
    /// Heal the character by a specified amount
    /// - Returns: The actual amount healed
    @discardableResult
    func heal(_ amount: Int) -> Int {
        let previousHP = vitals.currentHP
        vitals.currentHP = min(effectiveMaxHP, vitals.currentHP + amount)
        return vitals.currentHP - previousHP
    }
    
    /// Gain XP and check for level up
    /// - Returns: true if leveled up
    @discardableResult
    func gainXP(_ amount: Int) -> Bool {
        // Intelligence bonus to XP gain
        let bonusMultiplier = 1.0 + Double(effectiveIntelligence - 10) * 0.02
        let actualXP = Int(Double(amount) * bonusMultiplier)
        
        vitals.currentXP += actualXP
        
        if vitals.currentXP >= vitals.xpToNextLevel {
            levelUp()
            return true
        }
        return false
    }
    
    /// Level up the character
    private func levelUp() {
        vitals.currentXP -= vitals.xpToNextLevel
        vitals.level += 1
        vitals.xpToNextLevel = CharacterVitals.calculateXPForLevel(vitals.level + 1)
        
        // Increase max HP on level up
        let hpGain = 10 + (attributes.strength / 2)
        vitals.maxHP += hpGain
        vitals.currentHP = min(vitals.currentHP + hpGain, effectiveMaxHP)
        
        // Grant attribute points
        unspentAttributePoints += 3
    }
    
    /// Spend an attribute point
    @discardableResult
    func spendAttributePoint(on attribute: AttributeType) -> Bool {
        guard unspentAttributePoints > 0 else { return false }
        
        switch attribute {
        case .strength:
            attributes.strength += 1
        case .dexterity:
            attributes.dexterity += 1
        case .intelligence:
            attributes.intelligence += 1
        }
        
        unspentAttributePoints -= 1
        return true
    }
    
    /// Use a consumable item from inventory
    @discardableResult
    func useConsumable(_ item: Item) -> Bool {
        guard item.category == .consumable else { return false }
        guard inventory.contains(item) else { return false }
        
        // Apply effects
        if item.healAmount > 0 {
            heal(item.healAmount)
        }
        if item.xpAmount > 0 {
            gainXP(item.xpAmount)
        }
        
        // Remove from inventory
        inventory.removeItem(item)
        return true
    }
    
    /// Equip an item from inventory
    @discardableResult
    func equipItem(_ item: Item) -> Bool {
        guard item.equipSlot != nil else { return false }
        guard inventory.contains(item) else { return false }
        
        inventory.removeItem(item)
        
        if let previous = equipment.equip(item) {
            inventory.addItem(previous)
        }
        
        return true
    }
    
    /// Unequip an item back to inventory
    @discardableResult
    func unequipSlot(_ slot: EquipmentSlot) -> Bool {
        guard let item = equipment.unequip(slot) else { return false }
        inventory.addItem(item)
        return true
    }
}

/// Attribute type for spending points
enum AttributeType {
    case strength
    case dexterity
    case intelligence
}

// MARK: - Item Templates

/// Pre-defined item templates for easy creation
enum ItemTemplates {
    // Consumables
    static func healthPotion(size: ItemRarity = .common) -> Item {
        var item = Item(
            name: "\(size.name) Health Potion",
            description: "Restores health when consumed.",
            category: .consumable,
            rarity: size,
            stackable: true,
            maxStackSize: 10,
            value: 20 * (size.rawValue + 1)
        )
        // Base heal: 20 HP, scales with rarity
        item.healAmount = 20 * (size.rawValue + 1)
        return item
    }
    
    // Weapons
    static func sword(rarity: ItemRarity = .common) -> Item {
        var item = Item(
            name: "\(rarity.name) Sword",
            description: "A standard sword for combat.",
            category: .weapon,
            rarity: rarity,
            value: 50 * (rarity.rawValue + 1)
        )
        item.equipSlot = .mainHand
        item.damageBonus = 5 + (rarity.rawValue * 3)
        item.strengthBonus = rarity.rawValue
        return item
    }
    
    static func staff(rarity: ItemRarity = .common) -> Item {
        var item = Item(
            name: "\(rarity.name) Staff",
            description: "A magical staff.",
            category: .weapon,
            rarity: rarity,
            value: 60 * (rarity.rawValue + 1)
        )
        item.equipSlot = .mainHand
        item.damageBonus = 3 + (rarity.rawValue * 2)
        item.intelligenceBonus = 2 + rarity.rawValue
        return item
    }
    
    // Armor
    static func helmet(rarity: ItemRarity = .common) -> Item {
        var item = Item(
            name: "\(rarity.name) Helmet",
            description: "Protects your head.",
            category: .armor,
            rarity: rarity,
            value: 40 * (rarity.rawValue + 1)
        )
        item.equipSlot = .head
        item.armorBonus = 2 + rarity.rawValue
        return item
    }
    
    static func chestplate(rarity: ItemRarity = .common) -> Item {
        var item = Item(
            name: "\(rarity.name) Chestplate",
            description: "Protects your torso.",
            category: .armor,
            rarity: rarity,
            value: 80 * (rarity.rawValue + 1)
        )
        item.equipSlot = .chest
        item.armorBonus = 5 + (rarity.rawValue * 2)
        item.hpBonus = 10 * rarity.rawValue
        return item
    }
    
    static func boots(rarity: ItemRarity = .common) -> Item {
        var item = Item(
            name: "\(rarity.name) Boots",
            description: "Protects your feet.",
            category: .armor,
            rarity: rarity,
            value: 35 * (rarity.rawValue + 1)
        )
        item.equipSlot = .feet
        item.armorBonus = 1 + rarity.rawValue
        item.dexterityBonus = rarity.rawValue
        return item
    }
    
    // Materials
    static func woodLog() -> Item {
        Item(
            name: "Wood Log",
            description: "A log of wood for crafting.",
            category: .material,
            rarity: .common,
            stackable: true,
            maxStackSize: 50,
            value: 2
        )
    }
    
    static func ironOre() -> Item {
        Item(
            name: "Iron Ore",
            description: "Raw iron ore for smelting.",
            category: .material,
            rarity: .common,
            stackable: true,
            maxStackSize: 50,
            value: 5
        )
    }
    
    static func gemstone(rarity: ItemRarity = .uncommon) -> Item {
        Item(
            name: "\(rarity.name) Gemstone",
            description: "A precious gemstone.",
            category: .material,
            rarity: rarity,
            stackable: true,
            maxStackSize: 20,
            value: 25 * (rarity.rawValue + 1)
        )
    }
}

