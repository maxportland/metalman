# MetalMan Architecture

This document provides detailed technical documentation for the MetalMan game engine.

## Table of Contents
1. [Overview](#overview)
2. [Rendering System](#rendering-system)
3. [Game Loop](#game-loop)
4. [Input Handling](#input-handling)
5. [Character System](#character-system)
6. [World Generation](#world-generation)
7. [Collision System](#collision-system)
8. [RPG Systems](#rpg-systems)
9. [UI System](#ui-system)

---

## Overview

MetalMan is built on a custom game engine using Apple's Metal API for rendering and SwiftUI for the user interface overlay. The architecture follows a component-based design with clear separation between:

- **Rendering** - Metal-based graphics pipeline
- **Game Logic** - Character, world, and RPG systems
- **UI** - SwiftUI overlay for HUD and menus
- **Input** - Keyboard handling for macOS

---

## Rendering System

### Pipeline Overview

The renderer uses a **two-pass rendering** approach:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Shadow Pass │ ──▶ │  Main Pass  │ ──▶ │   Present   │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Shadow Pass

**Purpose**: Generate depth information from the light's perspective for shadow mapping.

**Pipeline State**:
- Vertex Function: `vertex_shadow`
- Fragment Function: `fragment_shadow`
- Output: 2048x2048 depth texture

**Process**:
1. Set up orthographic projection from sun/moon position
2. Render all shadow-casting geometry
3. Store depth values in shadow texture

### Main Pass

**Purpose**: Render the final scene with lighting and shadows.

**Pipeline State**:
- Vertex Function: `vertex_lit`
- Fragment Function: `fragment_lit`
- Depth Format: `.depth32Float`
- Color Format: `.bgra8Unorm`

**Process**:
1. Render skybox (special case - no lighting)
2. Render ground with normal mapping
3. Render landscape objects (trees, rocks, buildings)
4. Render character with equipment
5. Apply shadow mapping from shadow pass
6. Apply day/night lighting adjustments

### Shader Architecture

#### Vertex Shader (`vertex_lit`)
```metal
vertex LitVertexOut vertex_lit(
    TexturedVertexIn in [[stage_in]],
    constant LitUniforms& uniforms [[buffer(1)]]
) {
    // Transform position to clip space
    // Transform normal to world space
    // Calculate shadow map coordinates
    // Pass through texture coordinates and material index
}
```

#### Fragment Shader (`fragment_lit`)
```metal
fragment float4 fragment_lit(
    LitVertexOut in [[stage_in]],
    // 17 texture slots for different materials
    // Normal map textures
    constant LitUniforms& uniforms [[buffer(1)]]
) {
    // Sample diffuse texture based on material index
    // Sample normal map and transform to world space
    // Calculate lighting (ambient + diffuse)
    // Apply shadow mapping with PCF
    // Apply day/night sky rendering for skybox
    // Return final color
}
```

### Texture System

#### Material Indices
```swift
enum MaterialIndex: UInt32 {
    case ground = 0
    case treeTrunk = 1
    case foliage = 2
    case rock = 3
    case pole = 4
    case character = 5
    case path = 6
    case stoneWall = 7
    case roof = 8
    case woodPlank = 9
    case sky = 10
    case treasureChest = 11
}
```

Each material has:
- Diffuse texture (color)
- Normal map (surface detail)

#### Texture Loading Priority
1. Look for file-based texture (JPEG from textures folder)
2. Fall back to procedural generation

---

## Game Loop

The game loop runs at 60 FPS via `MTKViewDelegate`:

```swift
func draw(in view: MTKView) {
    // 1. Calculate delta time
    let dt = min(Float(now - lastFrameTime), 0.1)
    
    // 2. Update game state
    updateTimeOfDay(deltaTime: dt)      // Day/night cycle
    handleInteraction()                  // E key for chests
    updateCharacter(deltaTime: dt)       // Movement & physics
    updateCamera(deltaTime: dt)          // Camera following
    
    // 3. Update matrices
    viewMatrix = buildViewMatrix()
    updateLightMatrix()
    
    // 4. Regenerate animated meshes
    characterMesh.update(walkPhase, isJumping, hasSwordEquipped)
    
    // 5. Render
    renderShadowPass(commandBuffer)
    renderMainPass(commandBuffer)
    
    // 6. Present
    commandBuffer.present(drawable)
    commandBuffer.commit()
}
```

---

## Input Handling

### macOS Keyboard Input

Input is captured via a custom `MTKView` subclass:

```swift
class KeyboardMTKView: MTKView {
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        keyboardDelegate?.keyDown(event)
    }
    
    override func keyUp(with event: NSEvent) {
        keyboardDelegate?.keyUp(event)
    }
}
```

### Key Mapping

| Key Code | Key | Action |
|----------|-----|--------|
| 123 | Left Arrow | Rotate left (x = -1) |
| 124 | Right Arrow | Rotate right (x = +1) |
| 125 | Down Arrow | Move backward (y = -1) |
| 126 | Up Arrow | Move forward (y = +1) |
| 49 | Space | Jump |
| 14 | E | Interact |
| 34 | I | Toggle inventory |

### Movement Vector

Input is converted to a 2D movement vector:
- `x` component: Rotation input (-1 to +1)
- `y` component: Forward/backward input (-1 to +1)

---

## Character System

### Character State

```swift
// Position and orientation
var characterPosition: simd_float3
var characterYaw: Float  // Facing direction
var characterVelocity: simd_float3

// Animation
var walkPhase: Float     // 0 to 2π
var isMoving: Bool
var isJumping: Bool
var verticalVelocity: Float
```

### Movement Physics

**Tank Controls**:
```swift
// Rotation from left/right input
characterYaw += movementVector.x * rotationSpeed * dt

// Forward/backward movement
let forwardDir = simd_float3(sin(characterYaw), 0, -cos(characterYaw))
let targetVelocity = forwardDir * movementVector.y * characterSpeed
```

**Acceleration/Deceleration**:
- Smooth acceleration when starting to move
- Smooth deceleration when stopping
- Configurable `acceleration` and `deceleration` values

**Jump Physics**:
```swift
if jumpPressed && !isJumping {
    isJumping = true
    verticalVelocity = jumpForce  // 8.0
}

if isJumping {
    verticalVelocity -= gravity * dt  // 20.0
    characterPosition.y += verticalVelocity * dt
}
```

### Procedural Mesh Generation

The character is rebuilt every frame with current animation state:

```swift
func update(walkPhase: Float, isJumping: Bool, hasSwordEquipped: Bool) {
    var vertices: [TexturedVertex] = []
    
    // HEAD - Sphere
    addSphere(center: headPosition, radius: 0.22, ...)
    
    // NECK - Cylinder
    addLimb(from: shoulderPos, to: neckPos, radius: 0.08, ...)
    
    // TORSO - Box
    addBox(center: torsoCenter, size: torsoSize, ...)
    
    // ARMS - Animated based on walkPhase/isJumping
    // Left arm: shoulder → elbow → hand
    // Right arm: shoulder → elbow → hand + sword
    
    // LEGS - Animated based on walkPhase/isJumping
    // Left leg: hip → knee → ankle → foot
    // Right leg: hip → knee → ankle → foot
    
    // Copy to GPU buffer
    memcpy(vertexBuffer.contents(), vertices, ...)
}
```

### Walk Animation

Animation is driven by distance traveled:

```swift
let distanceThisFrame = simd_length(characterVelocity) * dt
let radiansPerStep = 2 * .pi
walkPhase += distanceThisFrame * stepsPerUnitDistance * radiansPerStep
```

Limb positions are calculated using `sin(walkPhase)`:
- Arms swing opposite to legs
- Knees bend during stride
- Body bobs slightly

---

## World Generation

### Terrain

Terrain height uses layered sine waves:

```swift
static func heightAt(x: Float, z: Float) -> Float {
    var height: Float = 0
    
    // Large rolling hills
    height += sin(x * 0.02) * cos(z * 0.02) * 3.0
    
    // Medium bumps
    height += sin(x * 0.05 + 1.0) * cos(z * 0.07) * 1.5
    
    // Small details
    height += sin(x * 0.15) * sin(z * 0.12) * 0.5
    
    return height
}
```

### Object Placement

Objects are placed using a seeded random system with collision avoidance:

```swift
// Track occupied areas
static var occupiedAreas: [OccupiedArea] = []

// Check before placing
if isPositionClear(x: pos.x, z: pos.z, radius: objectRadius) {
    markOccupied(x: pos.x, z: pos.z, radius: objectRadius)
    // Place object
}
```

**Placement Order** (larger objects first):
1. Character spawn exclusion zone (8-unit radius at origin)
2. Structures (houses, ruins, watchtowers)
3. Trees
4. Rocks
5. Poles
6. Treasure chests

### Tree Generation

Two tree types:

**Pine Trees**:
- Cylindrical trunk
- Multiple cone-shaped foliage layers
- Decreasing size toward top

**Oak Trees**:
- Thicker trunk
- Sphere-based foliage clusters
- More organic appearance

### Building Generation

**Houses**:
- Four walls with door opening
- Pitched roof
- Box colliders for walls

**Ruins**:
- Partial walls at varying heights
- No roof
- Multiple box colliders for walkable interior

**Watchtowers**:
- Tall central structure
- Platform at top
- Single circle collider

---

## Collision System

### Collider Types

```swift
enum ColliderType {
    case circle    // Simple radius check
    case box       // Oriented bounding box
    case climbable // Circle + height for standing on top
}

struct Collider {
    var type: ColliderType
    var position: simd_float2    // X, Z center
    var radius: Float            // For circles
    var halfExtents: simd_float2 // For boxes
    var rotation: Float          // Box rotation
    var height: Float            // Climbable height
    var baseY: Float             // Terrain height at base
}
```

### Collision Detection

**Circle Colliders**:
```swift
let dx = characterPos.x - collider.position.x
let dz = characterPos.z - collider.position.y
let dist = sqrt(dx*dx + dz*dz)
let overlap = (characterRadius + collider.radius) - dist
```

**Box Colliders**:
```swift
// Transform to box local space
let localX = dx * cos(-rotation) - dz * sin(-rotation)
let localZ = dx * sin(-rotation) + dz * cos(-rotation)

// Check overlap with half-extents
let overlapX = halfExtents.x + characterRadius - abs(localX)
let overlapZ = halfExtents.y + characterRadius - abs(localZ)
```

### Collision Response

- **Push out**: Move character by overlap distance along collision normal
- **Slide**: Allow movement parallel to collision surface
- **Climbable**: Set character Y to surface height when on top

---

## RPG Systems

### Player Character

```swift
final class PlayerCharacter {
    let name: String
    var attributes: CharacterAttributes  // STR, DEX, INT
    var vitals: CharacterVitals          // HP, XP, Level
    let inventory: Inventory             // 20 slots
    let equipment: Equipment             // Weapon, armor slots
    var unspentAttributePoints: Int
}
```

### Attributes

Base stats that affect gameplay:
- **Strength**: Damage bonus, carry weight
- **Dexterity**: Movement speed, dodge chance
- **Intelligence**: Magic power, XP gain

### Items

```swift
struct Item {
    let id: UUID
    let name: String
    let category: ItemCategory  // weapon, armor, consumable, etc.
    let rarity: ItemRarity      // common → legendary
    let stackable: Bool
    let maxStackSize: Int
    let value: Int              // Gold value
    
    // Stat modifiers
    var strengthBonus: Int
    var dexterityBonus: Int
    var damageBonus: Int
    var armorBonus: Int
    var hpBonus: Int
    
    // Equipment info
    var equipSlot: EquipmentSlot?
    
    // Consumable info
    var healAmount: Int
}
```

### Inventory

```swift
final class Inventory {
    var slots: [ItemStack?]  // 20 optional slots
    var gold: Int
    
    func addItem(_ item: Item, quantity: Int) -> Bool
    func removeItem(at index: Int) -> Item?
    func contains(_ item: Item) -> Bool
}
```

### Equipment

```swift
final class Equipment {
    var slots: [EquipmentSlot: Item]
    
    func equip(_ item: Item) -> Item?  // Returns previous
    func unequip(_ slot: EquipmentSlot) -> Item?
    func itemIn(_ slot: EquipmentSlot) -> Item?
    
    var hasSwordEquipped: Bool  // For visual rendering
}
```

---

## UI System

### Architecture

```
ContentView
└── MetalGameContainer
    ├── MetalGameView (NSViewRepresentable)
    │   └── KeyboardMTKView
    │       └── Renderer
    └── GameHUD (SwiftUI overlay)
        └── GameHUDViewModel (@Observable)
```

### HUD Components

1. **Top Bar**:
   - HP bar with color gradient
   - XP bar
   - Level display
   - Gold counter

2. **Bottom Bar**:
   - Attribute display (STR, DEX, INT)

3. **Inventory Panel** (toggle with I):
   - Equipment slots (left)
   - Inventory grid (right, 4x5)
   - Item tooltips

4. **Loot Notification**:
   - Animated popup when opening chests
   - Shows gold and item with rarity color
   - Auto-dismisses after 3 seconds

### Hit Testing

```swift
GameHUD(viewModel: hudViewModel)
    .allowsHitTesting(hudViewModel.isInventoryOpen)
```

- Disabled when inventory closed (game receives all input)
- Enabled when inventory open (buttons are clickable)

---

## Performance Considerations

### Current Optimizations
- Static geometry is generated once at startup
- Only character mesh is regenerated each frame
- Uniform buffers are reused with different offsets
- Textures use mipmaps for distance rendering

### Future Optimizations
- Instanced rendering for trees and rocks
- Frustum culling for off-screen objects
- Level-of-detail (LOD) for distant geometry
- Occlusion culling for buildings

---

## Debug Features

### Console Logging

Key events are logged to Xcode console:
- `[Inventory]` - Equip/unequip actions
- `[Chest]` - Loot collection
- `[UI]` - Button interactions

### Commented Debug Code

The renderer contains commented debug prints for:
- Character position
- Camera position
- Collision events
- Texture loading status

---

*Last updated: December 2024*

