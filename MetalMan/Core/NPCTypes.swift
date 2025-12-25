import Foundation
import simd

// MARK: - NPC Types

/// Types of NPCs in the game
enum NPCType: String, CaseIterable {
    case vendor = "Vendor"
    
    var interactionRange: Float {
        switch self {
        case .vendor: return 2.5
        }
    }
    
    /// Range at which NPC notices the player and starts waving
    var noticeRange: Float {
        switch self {
        case .vendor: return 8.0
        }
    }
}

// MARK: - Shop Item

/// An item for sale in a shop
struct ShopItem: Identifiable {
    let id: UUID
    let item: Item
    let price: Int
    let stock: Int  // -1 for unlimited
    var sold: Int = 0
    
    var available: Int {
        if stock < 0 { return 999 }
        return max(0, stock - sold)
    }
    
    var isAvailable: Bool { available > 0 }
    
    init(item: Item, price: Int, stock: Int = -1) {
        self.id = UUID()
        self.item = item
        self.price = price
        self.stock = stock
    }
}

// MARK: - NPC

/// A non-player character in the game world
final class NPC: Identifiable {
    let id: UUID
    let type: NPCType
    let name: String
    
    // Position and facing
    var position: simd_float3
    var yaw: Float
    
    // Shop inventory (for vendors)
    var shopItems: [ShopItem] = []
    
    // Animation
    var idleTimer: Float = 0
    var idlePhase: Float = 0
    
    // Player awareness
    var isPlayerNearby: Bool = false
    var isWaving: Bool = false
    var waveTimer: Float = 0
    var wavePhase: Float = 0
    var targetYaw: Float = 0
    private let turnSpeed: Float = 3.0  // Radians per second
    
    init(type: NPCType, name: String, position: simd_float3, yaw: Float = 0) {
        self.id = UUID()
        self.type = type
        self.name = name
        self.position = position
        self.yaw = yaw
        
        // Set up shop inventory based on type
        if type == .vendor {
            setupVendorShop()
        }
    }
    
    private func setupVendorShop() {
        shopItems = [
            // Potions
            ShopItem(item: ItemTemplates.healthPotion(size: .common), price: 25, stock: -1),
            ShopItem(item: ItemTemplates.healthPotion(size: .uncommon), price: 60, stock: 5),
            ShopItem(item: ItemTemplates.healthPotion(size: .rare), price: 150, stock: 2),
            
            // Weapons
            ShopItem(item: ItemTemplates.sword(quality: .common), price: 75, stock: 3),
            ShopItem(item: ItemTemplates.sword(quality: .sharp), price: 200, stock: 2),
            
            // Shields
            ShopItem(item: ItemTemplates.shield(quality: .iron), price: 60, stock: 3),
            ShopItem(item: ItemTemplates.shield(quality: .steel), price: 180, stock: 2),
            ShopItem(item: ItemTemplates.shield(quality: .reinforced), price: 500, stock: 1),
            
            // Armor
            ShopItem(item: ItemTemplates.armor(quality: .leather), price: 80, stock: 3),
            ShopItem(item: ItemTemplates.armor(quality: .chainmail), price: 250, stock: 2),
            ShopItem(item: ItemTemplates.armor(quality: .plate), price: 750, stock: 1),
        ]
    }
    
    /// Check if player can interact with this NPC
    func canInteract(playerPosition: simd_float3) -> Bool {
        let dist = simd_distance(
            simd_float2(position.x, position.z),
            simd_float2(playerPosition.x, playerPosition.z)
        )
        return dist <= type.interactionRange
    }
    
    /// Update NPC animation and player awareness
    func update(deltaTime dt: Float, playerPosition: simd_float3) {
        idleTimer += dt
        idlePhase = sin(idleTimer * 0.5) * 0.1  // Gentle idle sway
        
        // Calculate distance to player
        let toPlayer = simd_float2(playerPosition.x - position.x, playerPosition.z - position.z)
        let distanceToPlayer = simd_length(toPlayer)
        
        // Check if player is nearby
        let wasNearby = isPlayerNearby
        isPlayerNearby = distanceToPlayer <= type.noticeRange
        
        if isPlayerNearby {
            // Calculate target yaw to face player
            targetYaw = atan2(toPlayer.x, -toPlayer.y)
            
            // Smoothly rotate towards player
            var yawDiff = targetYaw - yaw
            
            // Normalize angle difference to [-π, π]
            while yawDiff > .pi { yawDiff -= 2 * .pi }
            while yawDiff < -.pi { yawDiff += 2 * .pi }
            
            // Turn towards player
            let maxTurn = turnSpeed * dt
            if abs(yawDiff) < maxTurn {
                yaw = targetYaw
            } else {
                yaw += (yawDiff > 0 ? 1 : -1) * maxTurn
            }
            
            // Normalize yaw
            while yaw > .pi { yaw -= 2 * .pi }
            while yaw < -.pi { yaw += 2 * .pi }
            
            // Start waving when player first enters range
            if !wasNearby {
                isWaving = true
                waveTimer = 0
            }
            
            // Update wave animation
            if isWaving {
                waveTimer += dt
                wavePhase = sin(waveTimer * 8.0)  // Fast wave motion
                
                // Stop waving after ~2 seconds
                if waveTimer > 2.0 {
                    isWaving = false
                    waveTimer = 0
                    wavePhase = 0
                }
            }
        } else {
            // Player left - stop waving
            isWaving = false
            waveTimer = 0
            wavePhase = 0
        }
    }
    
    /// Purchase an item from this vendor
    func purchaseItem(at index: Int) -> Bool {
        guard index >= 0 && index < shopItems.count else { return false }
        guard shopItems[index].isAvailable else { return false }
        
        shopItems[index].sold += 1
        return true
    }
}

// MARK: - NPC Manager

/// Manages all NPCs in the game world
final class NPCManager {
    private(set) var npcs: [NPC] = []
    
    /// Spawn an NPC at a position
    func spawnNPC(type: NPCType, name: String, at position: simd_float3, yaw: Float = 0) {
        let npc = NPC(type: type, name: name, position: position, yaw: yaw)
        npcs.append(npc)
    }
    
    /// Update all NPCs
    func update(deltaTime dt: Float, playerPosition: simd_float3) {
        for npc in npcs {
            npc.update(deltaTime: dt, playerPosition: playerPosition)
        }
    }
    
    /// Find an NPC the player can interact with
    func findInteractableNPC(near position: simd_float3) -> NPC? {
        for npc in npcs {
            if npc.canInteract(playerPosition: position) {
                return npc
            }
        }
        return nil
    }
    
    /// Get NPC count
    var count: Int { npcs.count }
}

