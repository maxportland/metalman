# MetalMan Development Notes

## Project Overview
A Metal-based 3D RPG game for macOS featuring:
- Skeletal animation for player and enemy characters
- USD/USDZ model loading for environment objects
- Day/night cycle with dynamic lighting
- Procedural terrain generation
- Interactive objects (treasure chests, NPCs)

---

## Recent Work (Dec 26, 2025)

### 1. Tree Model Rendering ✅ FIXED
**Problem:** Trees from USDC files weren't showing up, then appeared upside down with wrong textures.

**What Worked:**
- Changed `rotationX(-.pi / 2)` to `rotationX(.pi / 2)` in `drawTrees()` to flip trees right-side up
- Modified `USDModelLoader.extractMeshVertices()` to detect material names from submeshes (e.g., "bark", "leaf") and assign correct `MaterialIndex`
- Updated `TextureGenerator` to load actual tree textures from `LandscapeModels/textures` folder

**What Didn't Work:**
- Using procedural textures for tree bark/foliage (didn't match the model's UV mapping)

---

### 2. Procedural Landscape Objects Removal ✅ DONE
**Task:** Remove rocks, houses, ruins, bridges, poles - keep only 3D model-rendered objects.

**Changes Made:**
- Removed `rockVertexBuffer`, `poleVertexBuffer`, `structureVertexBuffer` and related generation/drawing code
- Removed `lanternPositions` and point light calculations
- Kept: ground terrain, trees (USDC), cabin (USDC), treasure chests (USDZ)

---

### 3. Treasure Chest Model Integration 🔄 IN PROGRESS
**Task:** Replace procedural chests with `treasure_chest.usdz` model with animated lid.

**Current State:**
- Model loads and renders
- Lid animation works (pivots on hinge when opened)
- **Issue:** Rendering has "holes" (bad normals/culling)

**What Worked:**
- Separating lid submeshes ("topdetail_low", "topwood_low") into separate vertex buffer
- Calculating hinge position from lid bounds: `simd_float3((lidMinBound.x + lidMaxBound.x) / 2, lidMinBound.y, lidMaxBound.z)`
- Using `rotationX(.pi / 2)` to flip chest upright
- Lid opens with `rotationX(lidAngle)` around hinge point

**What Didn't Work:**
- Original winding order `[0, 1, 2]` - faces were inverted
- Negating normals - made lighting worse
- Various rotation combinations for orientation

**Latest Fix Applied (not yet tested):**
1. Disabled backface culling for chest: `encoder.setCullMode(.none)` in `drawChests()`
2. Reading normals from model data (like skeletal mesh loader) instead of calculating face normals

---

## Key Code Patterns

### Model Loading Winding Order
All working models use **reversed winding**: `[Int(ptr[i]), Int(ptr[i+2]), Int(ptr[i+1])]`
- `SkeletalMesh.swift` (player/enemy) - line ~1115
- `USDModelLoader.extractMeshVertices()` (cabin/trees) - line ~308
- `USDModelLoader.extractChestMeshVertices()` (chest) - line ~651

### Normal Handling
- **Skeletal Mesh Loader:** Reads normals from model, falls back to face normal if length < 0.001
- **Standard USD Loader:** Calculates face normals from geometry
- **Chest Loader (updated):** Now reads model normals like skeletal loader

### Orientation Fixes
- Y-up models from Blender often need `rotationX(.pi / 2)` or `rotationX(-.pi / 2)` to stand upright
- Player model uses complex detection: checks if `bounds.min.y` is near zero to determine Y-up vs Z-up

---

## File Structure

```
MetalMan/
├── Rendering/
│   ├── Renderer.swift        # Main render loop, draw functions
│   ├── USDModelLoader.swift  # Loads USDC/USDZ static models
│   ├── TextureGenerator.swift # Procedural and file-based textures
│   └── Shaders.metal         # Metal shaders
├── Character/
│   ├── SkeletalMesh.swift    # Skeletal mesh loading with animation
│   └── AnimatedCharacter.swift
├── Core/
│   ├── GameTypes.swift       # SwingType, Interactable, etc.
│   └── RPGTypes.swift        # Player, inventory, equipment
└── World/
    └── GeometryGenerator.swift # Terrain, paths, procedural geometry
```

---

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| `xcodebuild` fails with CommandLineTools error | Run `sudo xcode-select -switch /Applications/Xcode.app/Contents/Developer` |
| Model appears underground | Center model at origin, apply lift offset based on scaled height |
| Model upside down | Try `rotationX(.pi / 2)` or `rotationX(-.pi / 2)` |
| Model has holes/see-through faces | Disable backface culling: `encoder.setCullMode(.none)` |
| Wrong material/texture on model parts | Check submesh/material names, map to correct `MaterialIndex` |
| Normals look wrong | Try reading normals from model data instead of calculating |

---

## TODO
- [ ] Test chest rendering with culling disabled
- [ ] Add smooth animation interpolation for chest lid opening
- [ ] Consider adding chest texture loading from USDZ

---

*Last updated: Dec 26, 2025*

