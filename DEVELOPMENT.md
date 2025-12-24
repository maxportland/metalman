# MetalMan Development Guide

This guide covers how to set up, develop, and extend the MetalMan project.

## Table of Contents
1. [Development Setup](#development-setup)
2. [Project Configuration](#project-configuration)
3. [Adding New Features](#adding-new-features)
4. [Common Tasks](#common-tasks)
5. [Troubleshooting](#troubleshooting)

---

## Development Setup

### Prerequisites

- **macOS 13.0+** (Ventura or later recommended)
- **Xcode 15.0+** with Command Line Tools
- **Git** for version control
- A Mac with Metal-capable GPU (all Macs since 2012)

### Initial Setup

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd MetalMan
   ```

2. **Open in Xcode**:
   ```bash
   open MetalMan.xcodeproj
   ```

3. **Select scheme and destination**:
   - Scheme: `MetalMan`
   - Destination: `My Mac`

4. **Build and Run**:
   - Press `⌘R` or click the Play button

### Texture Setup (Optional)

For higher-quality textures, create a `textures` folder:

```bash
mkdir -p textures
```

Add JPEG textures with these names:
- `grass_01_diffuse.jpg`
- `tree_01_diffuse.jpg`
- `leaves_01_diffuse.jpg`
- `rock_01_diffuse.jpg`
- `path_01_diffuse.jpg`
- `wood_wall_01_diffuse.jpg`
- `concrete_01_diffuse.jpg`

The game will use procedural textures if these files are missing.

---

## Project Configuration

### Build Settings

Key build settings in the Xcode project:

| Setting | Value |
|---------|-------|
| Deployment Target | macOS 13.0 |
| Swift Language Version | Swift 5 |
| Metal API Validation | Enabled (Debug) |

### Entitlements

The app uses minimal entitlements:
- **App Sandbox**: Disabled (for texture file access)

### Scheme Configuration

- **Debug**: Full debugging, Metal API validation enabled
- **Release**: Optimized, validation disabled

---

## Adding New Features

### Adding a New Item Type

1. **Define the item template** in `RPGTypes.swift`:
   ```swift
   // In ItemTemplates extension
   static func shield(rarity: ItemRarity = .common) -> Item {
       var item = Item(
           name: "\(rarity.name) Shield",
           description: "Blocks incoming attacks.",
           category: .armor,
           rarity: rarity,
           value: 40 * (rarity.rawValue + 1)
       )
       item.equipSlot = .offHand
       item.armorBonus = 3 + (rarity.rawValue * 2)
       return item
   }
   ```

2. **Update icon mapping** in `GameHUD.swift`:
   ```swift
   private func iconForItem(_ iconName: String) -> String {
       switch iconName {
       // ... existing cases ...
       case "shield": return "shield.fill"
       default: return "questionmark.square.fill"
       }
   }
   ```

3. **Add to loot tables** in `GeometryGenerator.swift` (treasure chests).

### Adding a New World Object

1. **Create geometry generator** in `GeometryGenerator.swift`:
   ```swift
   static func makeNewObjectMeshes(device: MTLDevice) -> (MTLBuffer, Int, [Collider]) {
       var vertices: [TexturedVertex] = []
       var colliders: [Collider] = []
       
       // Generate geometry
       addNewObject(at: position, vertices: &vertices)
       
       // Add collider
       colliders.append(Collider.circle(
           position: simd_float2(pos.x, pos.z),
           radius: 1.0
       ))
       
       let buffer = device.makeBuffer(bytes: vertices, ...)
       return (buffer!, vertices.count, colliders)
   }
   ```

2. **Add vertex buffer property** in `Renderer.swift`:
   ```swift
   private var newObjectVertexBuffer: MTLBuffer!
   private var newObjectVertexCount: Int = 0
   ```

3. **Initialize in `Renderer.init()`**:
   ```swift
   let newObjectResult = GeometryGenerator.makeNewObjectMeshes(device: device)
   newObjectVertexBuffer = newObjectResult.0
   newObjectVertexCount = newObjectResult.1
   allColliders.append(contentsOf: newObjectResult.2)
   ```

4. **Draw in `drawLandscape()`**:
   ```swift
   encoder.setVertexBuffer(newObjectVertexBuffer, offset: 0, index: 0)
   encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: newObjectVertexCount)
   ```

### Adding a New Material/Texture

1. **Add material index** in `GameTypes.swift`:
   ```swift
   enum MaterialIndex: UInt32 {
       // ... existing cases ...
       case newMaterial = 12
   }
   ```

2. **Create texture** in `TextureGenerator.swift`:
   ```swift
   func createNewMaterialTexture() -> MTLTexture {
       // Try loading from file first
       if let fileTexture = loadTexture(named: "new_material_diffuse.jpg") {
           return fileTexture
       }
       // Fall back to procedural
       let size = 64
       var pixels = [UInt8](repeating: 0, count: size * size * 4)
       // Fill pixels...
       return createTexture(from: pixels, size: size, label: "New Material")
   }
   ```

3. **Add texture property and initialization** in `Renderer.swift`.

4. **Bind texture in `bindTextures()`**:
   ```swift
   encoder.setFragmentTexture(newMaterialTexture, index: 12)
   ```

5. **Handle in shader** (`Shaders.swift`):
   ```metal
   case 12: texColor = newMaterialTex.sample(texSampler, in.texCoord); break;
   ```

### Adding Character Equipment Visuals

1. **Add equipment check** in `Equipment` class:
   ```swift
   var hasShieldEquipped: Bool {
       guard let item = slots[.offHand] else { return false }
       return item.category == .armor && item.name.contains("Shield")
   }
   ```

2. **Add parameter** to `CharacterMesh.update()`:
   ```swift
   func update(walkPhase: Float, isJumping: Bool, 
               hasSwordEquipped: Bool, hasShieldEquipped: Bool) {
   ```

3. **Add rendering in `CharacterMesh`**:
   ```swift
   if hasShieldEquipped {
       addShield(at: leftHandPos, vertices: &vertices)
   }
   ```

4. **Implement `addShield()` method** with geometry generation.

5. **Update calls** in `Renderer.swift`.

---

## Common Tasks

### Adjusting Character Speed

In `Renderer.swift`:
```swift
private let characterSpeed: Float = 6.0    // Movement speed
private let rotationSpeed: Float = 3.0      // Turn speed (radians/sec)
private let acceleration: Float = 40.0      // How fast to reach max speed
private let deceleration: Float = 35.0      // How fast to stop
```

### Adjusting Camera

In `Renderer.swift`:
```swift
private let cameraHeight: Float = 4.0       // Height above character
private let cameraDistance: Float = 8.0     // Distance behind character
```

### Adjusting Day/Night Cycle

In `Renderer.swift`:
```swift
private let dayNightSpeed: Float = 0.02     // Speed of day cycle
// Lower = slower cycle, 0 = frozen time
```

### Adjusting Walk Animation

In `Renderer.swift`:
```swift
private let stepsPerUnitDistance: Float = 0.5
// Higher = faster leg movement for same distance
```

### Adjusting Jump Physics

In `Renderer.swift`:
```swift
private let jumpForce: Float = 8.0          // Initial upward velocity
private let gravity: Float = 20.0           // Downward acceleration
```

### Adding Debug Output

```swift
// In Renderer.swift
print("[Debug] Position: \(characterPosition), Yaw: \(characterYaw)")

// In GameHUD.swift
print("[UI] Slot \(slot.id) clicked")

// In RPGTypes.swift
print("[Item] Created \(item.name) with \(item.damageBonus) damage")
```

---

## Troubleshooting

### Common Issues

#### Pink/Magenta Textures
**Cause**: Material index mismatch or texture not loaded.

**Solution**:
1. Check that `materialIndex` in vertices matches `MaterialIndex` enum
2. Verify texture is bound in `bindTextures()`
3. Check shader switch statement handles the material index

#### Character Falls Through Ground
**Cause**: Terrain height not being applied correctly.

**Solution**:
1. Verify `Terrain.heightAt(x:z:)` returns correct values
2. Check that `characterPosition.y` is set to terrain height
3. Ensure climbable colliders have correct `baseY`

#### Buttons Don't Work in Inventory
**Cause**: Hit testing disabled on HUD overlay.

**Solution**:
Check `MetalGameContainer.swift`:
```swift
GameHUD(viewModel: hudViewModel)
    .allowsHitTesting(hudViewModel.isInventoryOpen)  // Must be true when inventory open
```

#### Objects Overlap/Spawn on Each Other
**Cause**: Placement tracking not working.

**Solution**:
1. Ensure `GeometryGenerator.clearOccupiedAreas()` is called at start
2. Verify `isPositionClear()` is checked before placement
3. Check object radii are appropriate

#### Shadow Artifacts (Peter Panning, Acne)
**Cause**: Shadow bias or near/far plane issues.

**Solution**:
In shader, adjust shadow bias:
```metal
float bias = max(0.005 * (1.0 - NdotL), 0.0005);
```

In `Renderer.swift`, adjust light matrix projection.

#### Keyboard Input Not Working
**Cause**: View not first responder.

**Solution**:
In `MetalGameView.swift`:
```swift
DispatchQueue.main.async {
    view.window?.makeFirstResponder(view)
}
```

### Performance Issues

#### Low Frame Rate
1. Check Metal API Validation is disabled in Release builds
2. Reduce shadow map resolution (2048 → 1024)
3. Reduce tree/rock count in `GeometryGenerator`

#### Memory Usage High
1. Check for texture leaks (textures not being reused)
2. Verify vertex buffers are appropriate size
3. Consider instanced rendering for repeated objects

### Build Errors

#### "Module not found"
```bash
# Clean build folder
rm -rf ~/Library/Developer/Xcode/DerivedData/MetalMan-*
```

#### "Type checking took too long"
Break up complex expressions into intermediate variables:
```swift
// Bad
let corners = [center + a + b + c, center + a + b - c, ...]

// Good
let abc = a + b + c
let corner0 = center + abc
```

---

## Code Style Guidelines

### Naming Conventions

- **Types**: `PascalCase` (e.g., `PlayerCharacter`, `TexturedVertex`)
- **Properties/Variables**: `camelCase` (e.g., `characterPosition`, `walkPhase`)
- **Constants**: `camelCase` (e.g., `maxVertices`, `stepsPerUnitDistance`)
- **Functions**: `camelCase` with verb (e.g., `updateCharacter`, `addSphere`)

### File Organization

Each file should have clear `// MARK:` sections:
```swift
// MARK: - Properties
// MARK: - Initialization
// MARK: - Public Methods
// MARK: - Private Methods
// MARK: - Helper Functions
```

### Comments

- Use `///` for documentation comments
- Use `//` for inline explanations
- Add `// MARK: -` for section headers

---

## Testing

### Manual Testing Checklist

- [ ] Character moves with arrow keys
- [ ] Character rotates left/right correctly
- [ ] Camera follows behind character
- [ ] Jump physics work correctly
- [ ] Collision with trees/rocks works
- [ ] Can climb on rocks
- [ ] Can walk inside ruins
- [ ] Treasure chests can be opened with E
- [ ] Loot notification appears
- [ ] Inventory opens with I
- [ ] Items display correctly in inventory
- [ ] Double-click equips items
- [ ] Sword appears in hand when equipped
- [ ] Double-click unequips items
- [ ] Day/night cycle progresses
- [ ] Shadows move with sun

---

*Happy coding! 🎮*

