import Foundation
import simd

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
    var blockChance: Int = 0  // Percentage chance to block (0-100)
    
    // For equipment
    var equipSlot: EquipmentSlot? = nil
    var iconVariant: Int = 1  // Which icon variant to use (e.g., shield_1 vs shield_6)
    
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
            if equipSlot == .offHand { return "shield" }  // Shields go in off-hand
            return "armor"
        case .consumable:
            if name.lowercased().contains("scroll") { return "scroll" }
            return "potion"
        case .material:
            // Check if it's a gem by name
            let gemNames = ["Quartz", "Amethyst", "Topaz", "Emerald", "Sapphire", "Ruby", "Diamond", "Star Gem"]
            if gemNames.contains(where: { name.contains($0) }) {
                return "gem"
            }
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
    
    /// Clear all items and reset gold to zero
    func clear() {
        for i in 0..<slots.count {
            slots[i] = nil
        }
        gold = 0
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
    var totalBlockChance: Int { min(75, slots.values.reduce(0) { $0 + $1.blockChance }) }  // Capped at 75%
    
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
    
    /// Check if a shield is equipped in off hand
    var hasShieldEquipped: Bool {
        guard let shield = slots[.offHand] else { return false }
        return shield.equipSlot == .offHand
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
    
    /// Block chance from equipped shield (percentage 0-100)
    var effectiveBlockChance: Int {
        equipment.totalBlockChance
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
    /// Sword quality levels with exponentially decreasing drop rates
    enum SwordQuality: Int, CaseIterable {
        case dull = 0
        case common = 1
        case sharp = 2
        case excellentlyCrafted = 3
        case superblyCrafted = 4
        case ultimatelyCrafted = 5
        
        var name: String {
            switch self {
            case .dull: return "Dull"
            case .common: return "Common"
            case .sharp: return "Sharp"
            case .excellentlyCrafted: return "Excellently Crafted"
            case .superblyCrafted: return "Superbly Crafted"
            case .ultimatelyCrafted: return "Ultimately Crafted"
            }
        }
        
        var damageBonus: Int {
            switch self {
            case .dull: return 2
            case .common: return 5
            case .sharp: return 10
            case .excellentlyCrafted: return 18
            case .superblyCrafted: return 30
            case .ultimatelyCrafted: return 50
            }
        }
        
        var dexterityBonus: Int {
            switch self {
            case .dull, .common, .sharp: return 0
            case .excellentlyCrafted: return 3
            case .superblyCrafted: return 6
            case .ultimatelyCrafted: return 12
            }
        }
        
        var rarity: ItemRarity {
            switch self {
            case .dull: return .common
            case .common: return .common
            case .sharp: return .uncommon
            case .excellentlyCrafted: return .rare
            case .superblyCrafted: return .epic
            case .ultimatelyCrafted: return .legendary
            }
        }
        
        var value: Int {
            switch self {
            case .dull: return 10
            case .common: return 50
            case .sharp: return 150
            case .excellentlyCrafted: return 500
            case .superblyCrafted: return 1500
            case .ultimatelyCrafted: return 5000
            }
        }
        
        /// Get a random sword quality with exponentially decreasing chances
        /// Chances: Dull 40%, Common 30%, Sharp 18%, Excellent 8%, Superb 3%, Ultimate 1%
        static func randomQuality() -> SwordQuality {
            let roll = Float.random(in: 0...1)
            if roll < 0.40 { return .dull }
            if roll < 0.70 { return .common }
            if roll < 0.88 { return .sharp }
            if roll < 0.96 { return .excellentlyCrafted }
            if roll < 0.99 { return .superblyCrafted }
            return .ultimatelyCrafted
        }
    }
    
    static func sword(quality: SwordQuality = .common) -> Item {
        var item = Item(
            name: "\(quality.name) Sword",
            description: quality.dexterityBonus > 0 
                ? "A finely crafted sword that enhances agility."
                : "A sword for combat.",
            category: .weapon,
            rarity: quality.rarity,
            value: quality.value
        )
        item.equipSlot = .mainHand
        item.damageBonus = quality.damageBonus
        item.dexterityBonus = quality.dexterityBonus
        return item
    }
    
    /// Convenience for backward compatibility - random quality sword
    static func sword(rarity: ItemRarity = .common) -> Item {
        // Map old rarity to new quality
        let quality: SwordQuality
        switch rarity {
        case .common: quality = .common
        case .uncommon: quality = .sharp
        case .rare: quality = .excellentlyCrafted
        case .epic: quality = .superblyCrafted
        case .legendary: quality = .ultimatelyCrafted
        }
        return sword(quality: quality)
    }
    
    /// Get a random sword with exponentially decreasing quality chances
    static func randomSword() -> Item {
        return sword(quality: SwordQuality.randomQuality())
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
    
    /// Shield quality levels with different block chances
    enum ShieldQuality: Int, CaseIterable {
        case wooden = 0
        case iron = 1
        case steel = 2
        case reinforced = 3
        case masterwork = 4
        case legendary = 5
        
        var name: String {
            switch self {
            case .wooden: return "Wooden"
            case .iron: return "Iron"
            case .steel: return "Steel"
            case .reinforced: return "Reinforced"
            case .masterwork: return "Masterwork"
            case .legendary: return "Legendary"
            }
        }
        
        var blockChance: Int {
            switch self {
            case .wooden: return 10
            case .iron: return 15
            case .steel: return 20
            case .reinforced: return 28
            case .masterwork: return 38
            case .legendary: return 50
            }
        }
        
        var armorBonus: Int {
            switch self {
            case .wooden: return 1
            case .iron: return 2
            case .steel: return 3
            case .reinforced: return 5
            case .masterwork: return 8
            case .legendary: return 12
            }
        }
        
        var rarity: ItemRarity {
            switch self {
            case .wooden: return .common
            case .iron: return .common
            case .steel: return .uncommon
            case .reinforced: return .rare
            case .masterwork: return .epic
            case .legendary: return .legendary
            }
        }
        
        var value: Int {
            switch self {
            case .wooden: return 15
            case .iron: return 40
            case .steel: return 120
            case .reinforced: return 400
            case .masterwork: return 1200
            case .legendary: return 4000
            }
        }
        
        /// Icon variant number (which shield_X.png to use)
        var iconVariant: Int {
            switch self {
            case .wooden: return 2
            case .iron: return 6
            case .steel: return 31
            case .reinforced: return 15
            case .masterwork: return 25
            case .legendary: return 42
            }
        }
        
        /// Get a random shield quality with exponentially decreasing chances
        static func randomQuality() -> ShieldQuality {
            let roll = Float.random(in: 0...1)
            if roll < 0.35 { return .wooden }
            if roll < 0.60 { return .iron }
            if roll < 0.80 { return .steel }
            if roll < 0.92 { return .reinforced }
            if roll < 0.98 { return .masterwork }
            return .legendary
        }
    }
    
    static func shield(quality: ShieldQuality = .iron) -> Item {
        var item = Item(
            name: "\(quality.name) Shield",
            description: "\(quality.blockChance)% chance to block attacks.",
            category: .armor,
            rarity: quality.rarity,
            value: quality.value
        )
        item.equipSlot = .offHand
        item.armorBonus = quality.armorBonus
        item.blockChance = quality.blockChance
        item.iconVariant = quality.iconVariant
        return item
    }
    
    /// Get a random shield with exponentially decreasing quality chances
    static func randomShield() -> Item {
        return shield(quality: ShieldQuality.randomQuality())
    }
    
    /// Armor quality levels
    enum ArmorQuality: Int, CaseIterable {
        case tattered = 0
        case leather = 1
        case chainmail = 2
        case plate = 3
        case enchanted = 4
        case legendary = 5
        
        var name: String {
            switch self {
            case .tattered: return "Tattered"
            case .leather: return "Leather"
            case .chainmail: return "Chainmail"
            case .plate: return "Plate"
            case .enchanted: return "Enchanted"
            case .legendary: return "Legendary"
            }
        }
        
        var armorBonus: Int {
            switch self {
            case .tattered: return 2
            case .leather: return 5
            case .chainmail: return 10
            case .plate: return 16
            case .enchanted: return 25
            case .legendary: return 40
            }
        }
        
        var hpBonus: Int {
            switch self {
            case .tattered: return 0
            case .leather: return 5
            case .chainmail: return 10
            case .plate: return 20
            case .enchanted: return 35
            case .legendary: return 60
            }
        }
        
        var rarity: ItemRarity {
            switch self {
            case .tattered: return .common
            case .leather: return .common
            case .chainmail: return .uncommon
            case .plate: return .rare
            case .enchanted: return .epic
            case .legendary: return .legendary
            }
        }
        
        var value: Int {
            switch self {
            case .tattered: return 10
            case .leather: return 50
            case .chainmail: return 180
            case .plate: return 600
            case .enchanted: return 2000
            case .legendary: return 6000
            }
        }
        
        /// Icon variant number (which armor_X.png to use)
        var iconVariant: Int {
            switch self {
            case .tattered: return 1
            case .leather: return 8
            case .chainmail: return 15
            case .plate: return 25
            case .enchanted: return 35
            case .legendary: return 45
            }
        }
        
        /// Get a random armor quality with exponentially decreasing chances
        static func randomQuality() -> ArmorQuality {
            let roll = Float.random(in: 0...1)
            if roll < 0.35 { return .tattered }
            if roll < 0.60 { return .leather }
            if roll < 0.80 { return .chainmail }
            if roll < 0.92 { return .plate }
            if roll < 0.98 { return .enchanted }
            return .legendary
        }
    }
    
    static func armor(quality: ArmorQuality = .leather) -> Item {
        var item = Item(
            name: "\(quality.name) Armor",
            description: "Protects your body from attacks.",
            category: .armor,
            rarity: quality.rarity,
            value: quality.value
        )
        item.equipSlot = .chest
        item.armorBonus = quality.armorBonus
        item.hpBonus = quality.hpBonus
        item.iconVariant = quality.iconVariant
        return item
    }
    
    /// Get a random armor with exponentially decreasing quality chances
    static func randomArmor() -> Item {
        return armor(quality: ArmorQuality.randomQuality())
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
    
    // Gems - valuable items that can be sold
    enum GemType: Int, CaseIterable {
        case quartz = 0       // Common, low value
        case amethyst = 1     // Common-Uncommon
        case topaz = 2        // Uncommon
        case emerald = 3      // Uncommon-Rare
        case sapphire = 4     // Rare
        case ruby = 5         // Rare-Epic
        case diamond = 6      // Epic
        case starGem = 7      // Legendary
        
        var name: String {
            switch self {
            case .quartz: return "Quartz"
            case .amethyst: return "Amethyst"
            case .topaz: return "Topaz"
            case .emerald: return "Emerald"
            case .sapphire: return "Sapphire"
            case .ruby: return "Ruby"
            case .diamond: return "Diamond"
            case .starGem: return "Star Gem"
            }
        }
        
        var description: String {
            switch self {
            case .quartz: return "A cloudy white crystal."
            case .amethyst: return "A beautiful purple gemstone."
            case .topaz: return "A warm golden gem that glitters in light."
            case .emerald: return "A deep green gem prized by nobility."
            case .sapphire: return "A brilliant blue gem of great value."
            case .ruby: return "A fiery red gem, symbol of passion."
            case .diamond: return "The hardest and most precious of gems."
            case .starGem: return "A legendary gem that seems to contain a star within."
            }
        }
        
        var rarity: ItemRarity {
            switch self {
            case .quartz: return .common
            case .amethyst: return .common
            case .topaz: return .uncommon
            case .emerald: return .uncommon
            case .sapphire: return .rare
            case .ruby: return .rare
            case .diamond: return .epic
            case .starGem: return .legendary
            }
        }
        
        var value: Int {
            switch self {
            case .quartz: return 10
            case .amethyst: return 25
            case .topaz: return 50
            case .emerald: return 100
            case .sapphire: return 200
            case .ruby: return 350
            case .diamond: return 600
            case .starGem: return 1500
            }
        }
        
        /// Icon variant number (which gem_X.png to use)
        var iconVariant: Int {
            switch self {
            case .quartz: return 53      // White/clear crystal
            case .amethyst: return 17    // Purple gem
            case .topaz: return 3        // Golden/yellow gem
            case .emerald: return 7      // Green gem
            case .sapphire: return 1     // Blue gem
            case .ruby: return 10        // Red gem
            case .diamond: return 48     // Brilliant multi-faceted
            case .starGem: return 59     // Special/magical looking
            }
        }
        
        /// Get a random gem type with exponentially decreasing value chances
        static func randomType() -> GemType {
            let roll = Float.random(in: 0...1)
            if roll < 0.30 { return .quartz }
            if roll < 0.50 { return .amethyst }
            if roll < 0.65 { return .topaz }
            if roll < 0.78 { return .emerald }
            if roll < 0.88 { return .sapphire }
            if roll < 0.95 { return .ruby }
            if roll < 0.99 { return .diamond }
            return .starGem
        }
    }
    
    static func gem(type: GemType = .quartz) -> Item {
        var item = Item(
            name: type.name,
            description: type.description,
            category: .material,
            rarity: type.rarity,
            stackable: true,
            maxStackSize: 20,
            value: type.value
        )
        item.iconVariant = type.iconVariant
        return item
    }
    
    /// Get a random gem with weighted chances
    static func randomGem() -> Item {
        return gem(type: GemType.randomType())
    }
}

// MARK: - Save Game System

/// Represents a saved game state
struct SaveGameData: Codable {
    let timestamp: Date
    let playerName: String
    let level: Int
    let currentHP: Int
    let maxHP: Int
    let currentXP: Int
    let xpToNextLevel: Int
    let gold: Int
    let strength: Int
    let dexterity: Int
    let intelligence: Int
    let unspentPoints: Int
    let positionX: Float
    let positionY: Float
    let positionZ: Float
    let yaw: Float
    let inventoryItems: [SavedItemStack]
    let equippedItems: [String: SavedItem]  // slotName -> item
    
    struct SavedItem: Codable {
        let name: String
        let description: String
        let category: String
        let rarity: String
        let value: Int
        let strengthBonus: Int
        let dexterityBonus: Int
        let intelligenceBonus: Int
        let hpBonus: Int
        let damageBonus: Int
        let armorBonus: Int
        let equipSlot: String?
        let healAmount: Int
        let stackable: Bool
        let maxStackSize: Int
    }
    
    struct SavedItemStack: Codable {
        let item: SavedItem
        let quantity: Int
    }
}

/// Manages saving and loading game state
final class SaveGameManager {
    static let shared = SaveGameManager()
    
    private let saveFileName = "MetalMan_SaveGame.json"
    
    private var saveFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(saveFileName)
    }
    
    /// Check if a save game exists
    var hasSaveGame: Bool {
        FileManager.default.fileExists(atPath: saveFileURL.path)
    }
    
    /// Save the current game state
    func saveGame(player: PlayerCharacter, position: simd_float3, yaw: Float) -> Bool {
        // Convert inventory to saveable format
        var savedInventory: [SaveGameData.SavedItemStack] = []
        for slot in player.inventory.slots {
            if let stack = slot {
                savedInventory.append(SaveGameData.SavedItemStack(
                    item: convertItem(stack.item),
                    quantity: stack.quantity
                ))
            }
        }
        
        // Convert equipment to saveable format
        var savedEquipment: [String: SaveGameData.SavedItem] = [:]
        for slot in EquipmentSlot.allCases {
            if let item = player.equipment.itemIn(slot) {
                savedEquipment[slot.displayName] = convertItem(item)
            }
        }
        
        let saveData = SaveGameData(
            timestamp: Date(),
            playerName: player.name,
            level: player.vitals.level,
            currentHP: player.vitals.currentHP,
            maxHP: player.vitals.maxHP,
            currentXP: player.vitals.currentXP,
            xpToNextLevel: player.vitals.xpToNextLevel,
            gold: player.inventory.gold,
            strength: player.attributes.strength,
            dexterity: player.attributes.dexterity,
            intelligence: player.attributes.intelligence,
            unspentPoints: player.unspentAttributePoints,
            positionX: position.x,
            positionY: position.y,
            positionZ: position.z,
            yaw: yaw,
            inventoryItems: savedInventory,
            equippedItems: savedEquipment
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(saveData)
            try data.write(to: saveFileURL)
            print("[SaveGame] Game saved successfully to \(saveFileURL.path)")
            return true
        } catch {
            print("[SaveGame] Failed to save game: \(error)")
            return false
        }
    }
    
    /// Load the saved game state
    func loadGame() -> SaveGameData? {
        guard hasSaveGame else {
            print("[SaveGame] No save game found")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: saveFileURL)
            let decoder = JSONDecoder()
            let saveData = try decoder.decode(SaveGameData.self, from: data)
            print("[SaveGame] Game loaded successfully")
            return saveData
        } catch {
            print("[SaveGame] Failed to load game: \(error)")
            return nil
        }
    }
    
    /// Delete the save game
    func deleteSaveGame() {
        do {
            try FileManager.default.removeItem(at: saveFileURL)
            print("[SaveGame] Save game deleted")
        } catch {
            print("[SaveGame] Failed to delete save game: \(error)")
        }
    }
    
    /// Convert an Item to SavedItem format
    private func convertItem(_ item: Item) -> SaveGameData.SavedItem {
        SaveGameData.SavedItem(
            name: item.name,
            description: item.description,
            category: categoryString(item.category),
            rarity: item.rarity.name,
            value: item.value,
            strengthBonus: item.strengthBonus,
            dexterityBonus: item.dexterityBonus,
            intelligenceBonus: item.intelligenceBonus,
            hpBonus: item.hpBonus,
            damageBonus: item.damageBonus,
            armorBonus: item.armorBonus,
            equipSlot: item.equipSlot?.displayName,
            healAmount: item.healAmount,
            stackable: item.stackable,
            maxStackSize: item.maxStackSize
        )
    }
    
    /// Convert a SavedItem back to an Item
    func restoreItem(_ saved: SaveGameData.SavedItem) -> Item {
        var item = Item(
            name: saved.name,
            description: saved.description,
            category: categoryFromString(saved.category),
            rarity: rarityFromString(saved.rarity),
            stackable: saved.stackable,
            maxStackSize: saved.maxStackSize,
            value: saved.value
        )
        item.strengthBonus = saved.strengthBonus
        item.dexterityBonus = saved.dexterityBonus
        item.intelligenceBonus = saved.intelligenceBonus
        item.hpBonus = saved.hpBonus
        item.damageBonus = saved.damageBonus
        item.armorBonus = saved.armorBonus
        item.healAmount = saved.healAmount
        if let slotName = saved.equipSlot {
            item.equipSlot = equipSlotFromString(slotName)
        }
        return item
    }
    
    private func categoryString(_ cat: ItemCategory) -> String {
        switch cat {
        case .weapon: return "weapon"
        case .armor: return "armor"
        case .consumable: return "consumable"
        case .material: return "material"
        case .quest: return "quest"
        case .misc: return "misc"
        }
    }
    
    private func categoryFromString(_ str: String) -> ItemCategory {
        switch str {
        case "weapon": return .weapon
        case "armor": return .armor
        case "consumable": return .consumable
        case "material": return .material
        case "quest": return .quest
        default: return .misc
        }
    }
    
    private func rarityFromString(_ str: String) -> ItemRarity {
        switch str.lowercased() {
        case "common": return .common
        case "uncommon": return .uncommon
        case "rare": return .rare
        case "epic": return .epic
        case "legendary": return .legendary
        default: return .common
        }
    }
    
    private func equipSlotFromString(_ str: String) -> EquipmentSlot? {
        for slot in EquipmentSlot.allCases {
            if slot.displayName == str {
                return slot
            }
        }
        return nil
    }
}

