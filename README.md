# MetalMan

A 3D open-world RPG game built with Metal and SwiftUI for macOS. Features a procedurally generated world with terrain, buildings, vegetation, and a day/night cycle.

![Platform](https://img.shields.io/badge/platform-macOS-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)
![Metal](https://img.shields.io/badge/Graphics-Metal-red)

## Features

### 🎮 Gameplay
- **Third-person camera** that follows behind the player
- **Tank-style controls** for intuitive movement
- **Jumping** with realistic physics
- **Collision detection** with environment objects
- **Treasure chests** with randomized loot
- **Equipment system** with visual sword rendering

### 🌍 World
- **Procedural terrain** with rolling hills
- **Day/night cycle** with dynamic lighting
- **Shadow mapping** with soft shadows
- **Multiple tree types** (pine and oak varieties)
- **Rock formations** (climbable)
- **Buildings**: Houses, ruins, watchtowers, bridges
- **Paths and roads** winding through the landscape
- **Skybox** with clouds and atmospheric effects

### 👤 Character
- **3D humanoid mesh** with procedural animation
- **Walking animation** with arm and leg movement
- **Jumping animation** with tucked legs
- **Equipment rendering** (sword in hand when equipped)
- **Smooth movement** with acceleration/deceleration

### 📦 RPG Systems
- **Player stats**: HP, XP, Level
- **Attributes**: Strength, Dexterity, Intelligence
- **Inventory system** with 20 slots
- **Equipment slots** for weapons and armor
- **Items**: Weapons, armor, consumables, materials
- **Item rarity**: Common, Uncommon, Rare, Epic, Legendary
- **Gold currency**

## Controls

| Key | Action |
|-----|--------|
| ↑ (Up Arrow) | Walk forward |
| ↓ (Down Arrow) | Walk backward |
| ← (Left Arrow) | Turn left |
| → (Right Arrow) | Turn right |
| Space | Jump |
| E | Interact (open chests) |
| I | Toggle inventory |

### Inventory Controls
- **Double-click** an item to equip it
- **Double-click** an equipped item to unequip it

## Architecture

### Project Structure

```
MetalMan/
├── App/
│   └── MetalManApp.swift          # App entry point
├── Core/
│   ├── GameTypes.swift            # Vertex, uniform, collider structs
│   ├── MathHelpers.swift          # Matrix and vector math utilities
│   └── RPGTypes.swift             # RPG system classes (Player, Items, etc.)
├── Character/
│   └── CharacterMesh.swift        # Procedural character mesh generation
├── Rendering/
│   ├── Renderer.swift             # Main rendering coordinator
│   ├── Shaders.swift              # Metal shader source code
│   └── TextureGenerator.swift     # Procedural and file-based textures
├── World/
│   └── GeometryGenerator.swift    # World geometry generation
├── Views/
│   ├── ContentView.swift          # Root SwiftUI view
│   ├── MetalGameContainer.swift   # Metal view container
│   ├── MetalGameView.swift        # Metal view + input handling
│   └── GameHUD.swift              # HUD overlay (stats, inventory)
└── textures/                      # External texture files
```

### Rendering Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                      Frame Update                            │
├─────────────────────────────────────────────────────────────┤
│  1. Process Input (keyboard/mouse)                          │
│  2. Update Game State                                        │
│     - Character position/rotation                            │
│     - Animation phase                                        │
│     - Day/night cycle                                        │
│     - Collision detection                                    │
│  3. Update Camera                                            │
│  4. Regenerate Character Mesh (with animation)               │
├─────────────────────────────────────────────────────────────┤
│                      Shadow Pass                             │
├─────────────────────────────────────────────────────────────┤
│  - Render scene from light's perspective                     │
│  - Output: Depth texture for shadow mapping                  │
├─────────────────────────────────────────────────────────────┤
│                      Main Pass                               │
├─────────────────────────────────────────────────────────────┤
│  - Render skybox                                             │
│  - Render ground with normal mapping                         │
│  - Render trees, rocks, poles                                │
│  - Render buildings (houses, ruins, watchtowers)             │
│  - Render paths                                              │
│  - Render treasure chests                                    │
│  - Render character with equipment                           │
│  - Apply shadow mapping                                      │
│  - Apply day/night lighting                                  │
└─────────────────────────────────────────────────────────────┘
```

### Key Classes

#### `Renderer`
The main rendering coordinator. Manages:
- Metal device, command queue, pipeline states
- All vertex buffers and textures
- Game state (player, world objects, time)
- Two-pass rendering (shadow + main)

#### `CharacterMesh`
Generates the 3D character mesh procedurally each frame:
- Head, neck, torso
- Arms with elbow joints
- Legs with knee joints
- Feet
- Equipment (sword when equipped)
- Walking and jumping animations

#### `GeometryGenerator`
Static methods for generating world geometry:
- `makeGroundMesh()` - Terrain with height variation
- `makeTreeMeshes()` - Pine and oak trees
- `makeRockMeshes()` - Climbable rock formations
- `makePoleMeshes()` - Fence posts
- `makeStructureMeshes()` - Buildings and ruins
- `makePathMeshes()` - Roads and trails
- `makeTreasureChestMeshes()` - Lootable chests
- `makeSkyboxMesh()` - Sky dome

#### `TextureGenerator`
Handles texture creation:
- Procedural textures (character, sky, etc.)
- File-based textures (ground, rocks, trees)
- Normal maps for surface detail

#### `PlayerCharacter`
RPG player class with:
- Attributes (STR, DEX, INT)
- Vitals (HP, XP, Level)
- Inventory (20 slots)
- Equipment (weapon, armor slots)

#### `GameHUDViewModel`
Observable view model for the HUD:
- Syncs with PlayerCharacter
- Manages inventory display
- Handles equip/unequip actions
- Shows loot notifications

## Technical Details

### Graphics
- **API**: Metal
- **Shading**: Custom vertex and fragment shaders
- **Shadows**: Shadow mapping with PCF soft shadows
- **Textures**: RGBA8 with mipmaps
- **Normal Mapping**: Tangent-space normal maps
- **Lighting**: Directional sun/moon with ambient

### Vertex Format
```swift
struct TexturedVertex {
    var position: simd_float3   // World position
    var normal: simd_float3     // Surface normal
    var texCoord: simd_float2   // UV coordinates
    var tangent: simd_float3    // For normal mapping
    var materialIndex: UInt32   // Texture selection
}
```

### Uniform Data
```swift
struct LitUniforms {
    var modelMatrix: simd_float4x4
    var viewProjectionMatrix: simd_float4x4
    var lightViewProjectionMatrix: simd_float4x4
    var lightDirection: simd_float3
    var cameraPosition: simd_float3
    var ambientIntensity: Float
    var diffuseIntensity: Float
    var skyColorTop: simd_float3
    var skyColorHorizon: simd_float3
    var sunColor: simd_float3
    var timeOfDay: Float
}
```

### Collision System
Three collider types:
- **Circle**: Trees, poles (simple radius check)
- **Box**: Building walls (oriented bounding box)
- **Climbable**: Rocks (allows standing on top)

### Day/Night Cycle
- Full 24-hour cycle
- Sun position changes over time
- Sky color gradients (sunrise → day → sunset → night)
- Dynamic shadow direction
- Ambient/diffuse intensity variation

## Building and Running

### Requirements
- macOS 13.0+ (Ventura or later)
- Xcode 15.0+
- Metal-capable Mac

### Build Steps
1. Open `MetalMan.xcodeproj` in Xcode
2. Select the MetalMan scheme
3. Choose your Mac as the run destination
4. Press ⌘R to build and run

### Texture Files
The game looks for textures in `/Users/[username]/Projects/MetalMan/textures/`. 
Supported textures:
- `grass_01_diffuse.jpg` - Ground texture
- `tree_01_diffuse.jpg` - Tree bark
- `leaves_01_diffuse.jpg` - Foliage
- `rock_01_diffuse.jpg` - Rock surfaces
- `path_01_diffuse.jpg` - Paths/roads
- `wood_wall_01_diffuse.jpg` - Building walls

If textures aren't found, procedural textures are generated automatically.

## Future Enhancements

### Planned Features
- [ ] Combat system with sword attacks
- [ ] Enemy NPCs
- [ ] Quest system
- [ ] More equipment types (helmets, armor, shields)
- [ ] Crafting system
- [ ] Save/load game state
- [ ] Sound effects and music
- [ ] Particle effects (dust, magic, etc.)
- [ ] Water bodies with reflections
- [ ] Weather system (rain, fog)

### Technical Improvements
- [ ] Instanced rendering for vegetation
- [ ] Level-of-detail (LOD) for distant objects
- [ ] Frustum culling
- [ ] Ambient occlusion
- [ ] Bloom and post-processing
- [ ] Controller support

## License

This project is for educational purposes.

## Credits

Built with:
- [Metal](https://developer.apple.com/metal/) - Apple's low-level graphics API
- [SwiftUI](https://developer.apple.com/swiftui/) - Declarative UI framework
- [simd](https://developer.apple.com/documentation/simd) - Vector and matrix math

---

*Made with ❤️ and Metal*

