import Foundation
import simd

// MARK: - Enemy Types

/// Types of enemies in the game
enum EnemyType: String, CaseIterable {
    case bandit = "Bandit"
    
    var maxHP: Int {
        switch self {
        case .bandit: return 50
        }
    }
    
    var damage: Int {
        switch self {
        case .bandit: return 5
        }
    }
    
    var speed: Float {
        switch self {
        case .bandit: return 3.0
        }
    }
    
    var attackRange: Float {
        switch self {
        case .bandit: return 1.5
        }
    }
    
    var detectionRange: Float {
        switch self {
        case .bandit: return 12.0
        }
    }
    
    var attackCooldown: Float {
        switch self {
        case .bandit: return 1.2
        }
    }
    
    var xpReward: Int {
        switch self {
        case .bandit: return 25
        }
    }
    
    var goldDrop: ClosedRange<Int> {
        switch self {
        case .bandit: return 5...20
        }
    }
}

// MARK: - Enemy State

/// Current AI state of an enemy
enum EnemyState {
    case idle           // Standing still, not aware of player
    case patrolling     // Walking around patrol area
    case chasing        // Pursuing the player
    case attacking      // In attack animation
    case hurt           // Taking damage (brief stagger)
    case dead           // Dying/dead
}

// MARK: - Enemy

/// An enemy entity in the game world
final class Enemy: Identifiable {
    let id: UUID
    let type: EnemyType
    let level: Int  // Enemy level affects stats
    
    // Position and movement
    var position: simd_float3
    var yaw: Float  // Facing direction (radians)
    var velocity: simd_float3 = .zero
    
    // Stats (scaled by level)
    var currentHP: Int
    var maxHP: Int
    var damage: Int
    var xpReward: Int
    var goldDropRange: ClosedRange<Int>
    
    // AI State
    var state: EnemyState = .idle
    var stateTimer: Float = 0  // Time in current state
    var hasSpottedPlayer: Bool = false  // Track if this enemy has spotted the player (for audio)
    
    // Patrol
    var patrolCenter: simd_float3
    var patrolRadius: Float = 5.0
    var patrolTarget: simd_float3?
    var patrolWaitTime: Float = 0
    
    // Combat
    var attackCooldown: Float = 0
    var attackPhase: Float = 0  // 0 to 1 during attack animation
    var isAttacking: Bool { state == .attacking }
    var lastDamageTime: Float = 0
    
    // Animation
    var walkPhase: Float = 0
    var hurtTimer: Float = 0
    
    // Stun (hit reaction) - prevents attacking while animation plays
    var stunTimer: Float = 0
    var stunAnimationIndex: Int = 0  // 0 = reaction, 1 = taking-punch
    var isStunned: Bool { stunTimer > 0 }
    
    // Loot
    var isLooted: Bool = false
    var lootGold: Int = 0
    var lootItems: [Item] = []
    
    // Collider for collision detection
    var collider: Collider {
        Collider.circle(x: position.x, z: position.z, radius: 0.4)
    }
    
    /// Display name including level
    var displayName: String {
        "\(type.rawValue) Lv.\(level)"
    }
    
    init(type: EnemyType, position: simd_float3, level: Int = 1) {
        self.id = UUID()
        self.type = type
        self.level = max(1, level)
        self.position = position
        self.patrolCenter = position
        self.yaw = Float.random(in: 0...(2 * .pi))
        
        // Scale stats based on level
        // HP: +15% per level above 1
        let hpMultiplier = 1.0 + Double(level - 1) * 0.15
        self.maxHP = Int(Double(type.maxHP) * hpMultiplier)
        self.currentHP = self.maxHP
        
        // Damage: +10% per level above 1
        let damageMultiplier = 1.0 + Double(level - 1) * 0.10
        self.damage = Int(Double(type.damage) * damageMultiplier)
        
        // XP: +20% per level above 1
        let xpMultiplier = 1.0 + Double(level - 1) * 0.20
        self.xpReward = Int(Double(type.xpReward) * xpMultiplier)
        
        // Gold: +15% per level above 1
        let goldMultiplier = 1.0 + Double(level - 1) * 0.15
        let baseLow = type.goldDrop.lowerBound
        let baseHigh = type.goldDrop.upperBound
        self.goldDropRange = Int(Double(baseLow) * goldMultiplier)...Int(Double(baseHigh) * goldMultiplier)
    }
    
    /// Generate loot when killed
    func generateLoot() {
        guard !isLooted else { return }
        
        // Gold based on enemy level (scaled)
        lootGold = Int.random(in: goldDropRange)
        
        // Random chance for items (can get multiple items)
        let roll = Float.random(in: 0...1)
        
        if roll < 0.10 {
            // 10% chance for a sword with random quality (exponential distribution)
            lootItems.append(ItemTemplates.randomSword())
        } else if roll < 0.18 {
            // 8% chance for armor
            lootItems.append(ItemTemplates.randomArmor())
        } else if roll < 0.26 {
            // 8% chance for a shield
            lootItems.append(ItemTemplates.randomShield())
        } else if roll < 0.45 {
            // 19% chance for a potion
            lootItems.append(ItemTemplates.healthPotion(size: .common))
        } else if roll < 0.65 {
            // 20% chance for a gem
            lootItems.append(ItemTemplates.randomGem())
        }
        // 35% chance for just gold
    }
    
    var isAlive: Bool { currentHP > 0 }
    var hpPercentage: Float { Float(currentHP) / Float(maxHP) }
    
    /// Take damage and return the actual damage dealt
    @discardableResult
    func takeDamage(_ amount: Int) -> Int {
        let actualDamage = min(amount, currentHP)
        currentHP -= actualDamage
        
        if currentHP <= 0 {
            state = .dead
            stateTimer = 0
            generateLoot()  // Generate loot on death
        } else {
            // Set stun state with random hit reaction animation
            state = .hurt
            stateTimer = 0
            stunTimer = 1.2  // Duration of stun (animation length)
            stunAnimationIndex = Int.random(in: 0...1)  // 0 = reaction, 1 = taking-punch
            hurtTimer = 0.2
        }
        
        lastDamageTime = 0
        return actualDamage
    }
    
    /// Update enemy AI and animation
    func update(deltaTime dt: Float, playerPosition: simd_float3, terrain: Terrain) {
        stateTimer += dt
        lastDamageTime += dt
        
        // Update cooldowns
        if attackCooldown > 0 {
            attackCooldown -= dt
        }
        
        // Update hurt timer
        if hurtTimer > 0 {
            hurtTimer -= dt
        }
        
        // Update stun timer
        if stunTimer > 0 {
            stunTimer -= dt
        }
        
        // Update attack animation
        if state == .attacking {
            attackPhase += dt / 0.5  // 0.5 second attack animation
            if attackPhase >= 1.0 {
                attackPhase = 0
                state = .chasing  // Go back to chasing after attack
                stateTimer = 0
            }
        }
        
        // Calculate distance to player
        let toPlayer = playerPosition - position
        let distanceToPlayer = simd_length(simd_float2(toPlayer.x, toPlayer.z))
        
        // State machine
        switch state {
        case .idle:
            updateIdle(dt: dt, distanceToPlayer: distanceToPlayer)
            
        case .patrolling:
            updatePatrol(dt: dt, distanceToPlayer: distanceToPlayer, terrain: terrain)
            
        case .chasing:
            updateChase(dt: dt, playerPosition: playerPosition, distanceToPlayer: distanceToPlayer, terrain: terrain)
            
        case .attacking:
            // Already handled above
            break
            
        case .hurt:
            // Stay in hurt state until stun animation completes
            if stunTimer <= 0 {
                state = .chasing
                stateTimer = 0
            }
            
        case .dead:
            // Death animation/fade handled elsewhere
            break
        }
        
        // Update Y position based on terrain
        position.y = terrain.heightAt(x: position.x, z: position.z)
    }
    
    private func updateIdle(dt: Float, distanceToPlayer: Float) {
        // Check if player is in detection range
        if distanceToPlayer < type.detectionRange {
            // Play spotted sound if this is the first time spotting the player
            if !hasSpottedPlayer {
                hasSpottedPlayer = true
                AudioManager.shared.playSpotted()
            }
            state = .chasing
            stateTimer = 0
            return
        }
        
        // Randomly start patrolling
        if stateTimer > 2.0 && Float.random(in: 0...1) < 0.02 {
            state = .patrolling
            stateTimer = 0
            pickNewPatrolTarget()
        }
    }
    
    private func updatePatrol(dt: Float, distanceToPlayer: Float, terrain: Terrain) {
        // Check if player is in detection range
        if distanceToPlayer < type.detectionRange {
            // Play spotted sound if this is the first time spotting the player
            if !hasSpottedPlayer {
                hasSpottedPlayer = true
                AudioManager.shared.playSpotted()
            }
            state = .chasing
            stateTimer = 0
            return
        }
        
        // Handle patrol waiting
        if patrolWaitTime > 0 {
            patrolWaitTime -= dt
            return
        }
        
        // Move toward patrol target
        guard let target = patrolTarget else {
            pickNewPatrolTarget()
            return
        }
        
        let toTarget = target - position
        let distToTarget = simd_length(simd_float2(toTarget.x, toTarget.z))
        
        if distToTarget < 0.5 {
            // Reached patrol target, wait then pick new one
            patrolWaitTime = Float.random(in: 1.0...3.0)
            pickNewPatrolTarget()
        } else {
            // Move toward target
            let moveDir = simd_normalize(simd_float2(toTarget.x, toTarget.z))
            let speed = type.speed * 0.5  // Patrol at half speed
            
            position.x += moveDir.x * speed * dt
            position.z += moveDir.y * speed * dt
            
            // Update facing direction
            yaw = atan2(moveDir.x, -moveDir.y)
            
            // Update walk animation
            walkPhase += speed * dt * 2.0
        }
    }
    
    private func updateChase(dt: Float, playerPosition: simd_float3, distanceToPlayer: Float, terrain: Terrain) {
        // Check if player is out of range (give up chase)
        if distanceToPlayer > type.detectionRange * 1.5 {
            state = .idle
            stateTimer = 0
            hasSpottedPlayer = false  // Reset so they can spot again later
            return
        }
        
        // Check if in attack range
        if distanceToPlayer < type.attackRange {
            if attackCooldown <= 0 {
                // Start attack
                state = .attacking
                stateTimer = 0
                attackPhase = 0
                attackCooldown = type.attackCooldown
            }
            return
        }
        
        // Move toward player
        let toPlayer = playerPosition - position
        let moveDir = simd_normalize(simd_float2(toPlayer.x, toPlayer.z))
        let speed = type.speed
        
        position.x += moveDir.x * speed * dt
        position.z += moveDir.y * speed * dt
        
        // Update facing direction
        yaw = atan2(moveDir.x, -moveDir.y)
        
        // Update walk animation
        walkPhase += speed * dt * 2.0
    }
    
    private func pickNewPatrolTarget() {
        let angle = Float.random(in: 0...(2 * .pi))
        let distance = Float.random(in: 2.0...patrolRadius)
        patrolTarget = simd_float3(
            patrolCenter.x + cos(angle) * distance,
            0,  // Y will be set by terrain
            patrolCenter.z + sin(angle) * distance
        )
    }
}

// MARK: - Damage Number

/// A floating damage number to display on screen
struct DamageNumber: Identifiable {
    let id: UUID
    let amount: Int
    let isCritical: Bool
    let isHeal: Bool
    let isBlock: Bool
    var worldPosition: simd_float3
    var age: Float = 0
    var velocity: simd_float3
    
    static let lifetime: Float = 1.5
    
    init(amount: Int, position: simd_float3, isCritical: Bool = false, isHeal: Bool = false, isBlock: Bool = false) {
        self.id = UUID()
        self.amount = amount
        self.worldPosition = position + simd_float3(0, 2.0, 0)  // Start above target
        self.isCritical = isCritical
        self.isHeal = isHeal
        self.isBlock = isBlock
        // Random upward velocity with slight horizontal drift
        self.velocity = simd_float3(
            Float.random(in: -0.5...0.5),
            Float.random(in: 1.5...2.5),
            Float.random(in: -0.5...0.5)
        )
    }
    
    var isExpired: Bool { age >= DamageNumber.lifetime }
    
    var alpha: Float {
        if age < 0.2 {
            return age / 0.2  // Fade in
        } else if age > DamageNumber.lifetime - 0.5 {
            return (DamageNumber.lifetime - age) / 0.5  // Fade out
        }
        return 1.0
    }
    
    mutating func update(deltaTime dt: Float) {
        age += dt
        worldPosition += velocity * dt
        velocity.y -= 2.0 * dt  // Gravity
    }
}

// MARK: - Enemy Manager

/// Manages all enemies in the game world
final class EnemyManager {
    private(set) var enemies: [Enemy] = []
    var damageNumbers: [DamageNumber] = []
    
    /// Spawn an enemy at a position with optional level scaling
    /// - Parameters:
    ///   - type: The type of enemy to spawn
    ///   - position: World position to spawn at
    ///   - playerLevel: The player's current level (used to scale enemy level)
    func spawnEnemy(type: EnemyType, at position: simd_float3, playerLevel: Int = 1) {
        // Enemy level is player level +/- 1, minimum 1
        let levelVariation = Int.random(in: -1...1)
        let enemyLevel = max(1, playerLevel + levelVariation)
        let enemy = Enemy(type: type, position: position, level: enemyLevel)
        enemies.append(enemy)
    }
    
    /// Remove dead enemies after corpse despawn time (60 seconds)
    func removeDeadEnemies() {
        enemies.removeAll { enemy in
            enemy.state == .dead && enemy.stateTimer > 60.0
        }
    }
    
    /// Update all enemies
    func update(deltaTime dt: Float, playerPosition: simd_float3, terrain: Terrain, playerRadius: Float = 0.3) {
        let enemyRadius: Float = 0.4
        
        for enemy in enemies {
            if enemy.isAlive {
                enemy.update(deltaTime: dt, playerPosition: playerPosition, terrain: terrain)
                
                // Enemy-player collision - push enemy away from player
                let enemyPos2D = simd_float2(enemy.position.x, enemy.position.z)
                let playerPos2D = simd_float2(playerPosition.x, playerPosition.z)
                let toEnemy = enemyPos2D - playerPos2D
                let distance = simd_length(toEnemy)
                let minDist = enemyRadius + playerRadius
                
                if distance < minDist && distance > 0.001 {
                    let pushDirection = simd_normalize(toEnemy)
                    let pushAmount = (minDist - distance) * 0.5 + 0.01  // Push enemy half the overlap
                    enemy.position.x += pushDirection.x * pushAmount
                    enemy.position.z += pushDirection.y * pushAmount
                }
            } else {
                // Update dead enemies' state timer for death animation
                enemy.stateTimer += dt
            }
        }
        
        // Enemy-enemy collision resolution
        for i in 0..<enemies.count {
            guard enemies[i].isAlive else { continue }
            for j in (i+1)..<enemies.count {
                guard enemies[j].isAlive else { continue }
                
                let pos1 = simd_float2(enemies[i].position.x, enemies[i].position.z)
                let pos2 = simd_float2(enemies[j].position.x, enemies[j].position.z)
                let toSecond = pos2 - pos1
                let distance = simd_length(toSecond)
                let minDist = enemyRadius * 2
                
                if distance < minDist && distance > 0.001 {
                    let pushDirection = simd_normalize(toSecond)
                    let pushAmount = (minDist - distance) * 0.5 + 0.005
                    
                    // Push both enemies apart equally
                    enemies[i].position.x -= pushDirection.x * pushAmount
                    enemies[i].position.z -= pushDirection.y * pushAmount
                    enemies[j].position.x += pushDirection.x * pushAmount
                    enemies[j].position.z += pushDirection.y * pushAmount
                }
            }
        }
        
        // Remove enemies that have been dead for too long (1 minute after death)
        enemies.removeAll { $0.state == .dead && $0.stateTimer > 60.0 }
        
        // Update damage numbers
        for i in damageNumbers.indices.reversed() {
            damageNumbers[i].update(deltaTime: dt)
        }
        damageNumbers.removeAll { $0.isExpired }
    }
    
    /// Add a damage number to display
    func addDamageNumber(_ amount: Int, at position: simd_float3, isCritical: Bool = false, isHeal: Bool = false) {
        let damageNum = DamageNumber(amount: amount, position: position, isCritical: isCritical, isHeal: isHeal)
        damageNumbers.append(damageNum)
    }
    
    /// Add a block indicator to display (shows "BLOCKED!" text)
    func addBlockIndicator(at position: simd_float3) {
        // Use damage number system with 0 damage and special flag
        let blockNum = DamageNumber(amount: 0, position: position, isCritical: false, isHeal: false, isBlock: true)
        damageNumbers.append(blockNum)
    }
    
    /// Get enemies within attack range of a position
    func enemiesInRange(of position: simd_float3, range: Float) -> [Enemy] {
        enemies.filter { enemy in
            guard enemy.isAlive else { return false }
            let dist = simd_distance(
                simd_float2(position.x, position.z),
                simd_float2(enemy.position.x, enemy.position.z)
            )
            return dist <= range
        }
    }
    
    /// Check if any enemy is attacking and in range to hit the player
    func checkEnemyAttacks(playerPosition: simd_float3) -> [(enemy: Enemy, damage: Int)] {
        var hits: [(Enemy, Int)] = []
        
        for enemy in enemies where enemy.isAlive && enemy.state == .attacking {
            // Check if attack lands (at peak of attack animation)
            if enemy.attackPhase > 0.4 && enemy.attackPhase < 0.6 {
                let dist = simd_distance(
                    simd_float2(playerPosition.x, playerPosition.z),
                    simd_float2(enemy.position.x, enemy.position.z)
                )
                if dist <= enemy.type.attackRange * 1.2 {
                    hits.append((enemy, enemy.damage))
                }
            }
        }
        
        return hits
    }
    
    /// Get enemy count
    var count: Int { enemies.count }
    var aliveCount: Int { enemies.filter { $0.isAlive }.count }
    
    /// Clear all enemies
    func clearEnemies() {
        enemies.removeAll()
    }
    
    /// Find a lootable corpse near the player
    func findLootableCorpse(near position: simd_float3, range: Float = 2.0) -> Enemy? {
        for enemy in enemies {
            guard enemy.state == .dead && !enemy.isLooted else { continue }
            
            let dist = simd_distance(
                simd_float2(position.x, position.z),
                simd_float2(enemy.position.x, enemy.position.z)
            )
            
            if dist <= range {
                return enemy
            }
        }
        return nil
    }
}

