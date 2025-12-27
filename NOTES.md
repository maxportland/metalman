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
| `blender` command not found | Use full path: `/Applications/Blender.app/Contents/MacOS/Blender` |
| Model appears underground | Center model at origin, apply lift offset based on scaled height |
| Model upside down | Try `rotationX(.pi / 2)` or `rotationX(-.pi / 2)` |
| Model has holes/see-through faces | Disable backface culling: `encoder.setCullMode(.none)` |
| Wrong material/texture on model parts | Check submesh/material names, map to correct `MaterialIndex` |
| Normals look wrong | Try reading normals from model data instead of calculating |

---

## Tool Paths

**Blender** is not in PATH. Use the absolute path:
```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python <script.py>
```

Example - export enemy animations:
```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python /Users/maxdavis/Projects/MetalMan/MetalMan/Scripts/export_enemy_animations.py
```

---

## USDZ Material & Texture Loading Guide

### Overview

When loading USDZ models with embedded textures (like character models from Mixamo), there are several critical steps to ensure textures display correctly:

### 1. UV Coordinate Convention (V-Flip)

**The Problem:** USDZ files exported from Blender/Mixamo use OpenGL's UV convention where V=0 is at the **bottom** of the texture. Metal uses V=0 at the **top**.

**The Solution:** Flip the V coordinate during mesh loading:

```swift
// In SkeletalMeshLoader.loadSkeletalMesh()
if shouldFlipUV {
    texCoord = simd_float2(rawU, 1.0 - rawV)  // Flip V
} else {
    texCoord = simd_float2(rawU, rawV)
}
```

**Usage:**
```swift
// Most Mixamo/Blender models need flipUV: true (the default)
skeletalLoader.loadSkeletalMesh(from: url, materialIndex: MaterialIndex.character.rawValue)

// Some models may already use Metal's convention
skeletalLoader.loadSkeletalMesh(from: url, materialIndex: MaterialIndex.vendor.rawValue, flipUV: false)
```

**How to tell if you need V-flip:**
- Texture appears upside-down or mirrored vertically → needs flip
- Texture appears scrambled/misaligned on multi-part UV atlas → needs flip
- Use edit mode's "Flip V" toggle to test at runtime

### 2. Material Index Assignment

Each skeletal mesh needs a `MaterialIndex` that tells the shader which texture slot to sample from:

| MaterialIndex | Value | Texture Slot | Used For |
|---------------|-------|--------------|----------|
| `.character` | 5 | index 6 | Player character |
| `.enemy` | 12 | index 17 | Enemy characters |
| `.vendor` | 13 | index 18 | NPC vendors |

**Critical:** Match the material index to the correct texture slot binding!

```swift
// Loading the model with correct material index
skeletalLoader.loadSkeletalMesh(from: url, materialIndex: MaterialIndex.vendor.rawValue)
                                                          ^^^^^^^^^^^^^^^^^^^^^^^^
                                                          This determines which case in the shader
```

### 3. Embedded Texture Extraction

The `SkeletalMeshLoader` automatically extracts textures embedded in USDZ files:

```swift
// In SkeletalMesh.swift - extractTextureFromMeshes()
// Checks material properties for textures:
// - .baseColor (most common)
// - .emission, .metallic, .roughness, etc.
// Returns MTLTexture or nil
```

The extracted texture is stored in `skeletalMesh.texture`.

### 4. Binding the Embedded Texture

**This is the most commonly missed step!** You must bind the embedded texture before drawing:

```swift
// In drawEnemies() - CORRECT
if let texture = skeletalMesh.texture {
    encoder.setFragmentTexture(texture, index: 17)  // Enemy texture slot
}

// In drawNPCs() - CORRECT  
if let texture = skeletalMesh.texture {
    encoder.setFragmentTexture(texture, index: 18)  // Vendor texture slot
}
```

**Without this binding**, the shader will sample from the procedural fallback texture (usually solid color), resulting in missing/wrong textures.

### 5. Texture Slot Mapping Reference

| Texture Variable | Slot Index | MaterialIndex Case |
|------------------|------------|-------------------|
| `groundTex` | 5 | 0 (ground) |
| `characterTex` | 6 | 5 (character) |
| `enemyTex` | 17 | 12 (enemy) |
| `vendorTex` | 18 | 13 (vendor) |
| `cabinTex` | 19 | 14 (cabin) |

### 6. Checklist for Loading New USDZ Models

1. **Choose correct MaterialIndex** - matches the shader case and texture slot
2. **Set flipUV appropriately** - most Mixamo/Blender models need `true`
3. **Bind embedded texture** - call `setFragmentTexture(mesh.texture, index: N)` before drawing
4. **Verify in shader** - ensure `fragment_lit` has a case for your MaterialIndex

### 7. Debugging Texture Issues

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| Solid color instead of texture | Embedded texture not bound | Add `setFragmentTexture()` call |
| Texture upside down | Wrong UV convention | Try `flipUV: true` |
| Texture scrambled on mesh | Wrong UV convention | Try `flipUV: true` |
| Magenta (pink) texture | Invalid MaterialIndex | Check shader has case for your index |
| Wrong texture entirely | Wrong MaterialIndex | Match index to texture slot |
| Texture on wrong body parts | Single mesh with UV atlas issues | Check UV bounds in logs |

### 8. Single Mesh vs Multi-Submesh Models

**Multi-submesh (e.g., player):** Each submesh (sword, shield, helmet, body) has its own UV islands. All share the same texture atlas.

**Single mesh (e.g., vendor):** All body parts combined into one mesh with a complex UV atlas layout. Works the same way - just one submesh with many UV islands.

Both types work with the same loading code. The key is ensuring the embedded texture is bound correctly.

---

## TODO
- [x] Test chest rendering with culling disabled
- [x] Add smooth animation interpolation for chest lid opening
- [x] Consider adding chest texture loading from USDZ

---

## Performance Analysis (Dec 26, 2025)

### ✅ OPTIMIZATIONS APPLIED

#### 1. GPU Instancing for Trees ✅ DONE
- Added `vertex_lit_instanced` and `vertex_shadow_instanced` shaders
- Trees now render with ONE draw call per tree model type (8 draw calls total instead of ~250)
- Pre-computed model matrices stored in `treeInstanceBuffers`
- Both main pass and shadow pass use instancing

#### 2. Distance Culling ✅ DONE
- Trees: 80 unit draw distance (instance buffers rebuilt with visible only)
- Enemies: 60 unit draw distance 
- Chests: 50 unit draw distance
- Frustum planes extracted each frame from view-projection matrix

#### 3. Reduced Ground Resolution ✅ DONE
- Changed from 100×100 grid to 50×50 grid
- Reduced vertices from 60,000 to 15,000 (75% reduction)

#### 4. Reduced Tree Density ✅ DONE
- Changed spawn chance from 75% to 50%
- Approximately 33% fewer trees

### New Draw Call Summary

| Object Type | Draw Calls/Frame | Notes |
|-------------|------------------|-------|
| Trees | ~8 | One per tree model type (GPU instanced!) |
| Chests | 0-40 | Only visible within 50 units |
| Enemies | 0-20 | Only visible within 60 units |
| Ground | 1 | 15,000 vertices (50x50 grid) |
| Player | 1-3 | Depends on equipment |
| Cabin | 1 | |
| Skybox | 1 | |

**Total:** ~15-30 draw calls (down from 500+)

### Remaining Optimization Opportunities

#### 🟡 MEDIUM - Terrain Height Caching

`Terrain.heightAt()` still called per-frame for visible chests.

**Solution:** Cache terrain heights at spawn time since terrain is static.

#### 🟡 MEDIUM - Enemy GPU Instancing

Enemies still use individual draw calls. Could batch if all use same mesh.

#### 🟢 LOW - Print Statements

142 print statements, but most gated by startup-only flags.

### Key Code Changes Made

| File | Change |
|------|--------|
| `Shaders.swift` | Added `vertex_lit_instanced`, `vertex_shadow_instanced` |
| `Renderer.swift` | Added `instancedLitPipelineState`, `instancedShadowPipelineState` |
| `Renderer.swift` | Added `buildTreeInstanceBuffers()` for pre-computed matrices |
| `Renderer.swift` | Updated `drawTrees()` to use instanced rendering |
| `Renderer.swift` | Added `extractFrustumPlanes()`, `isSphereInFrustum()`, `isWithinDistance()` |
| `Renderer.swift` | Added distance culling to `drawEnemies()`, `drawChests()` |
| `GeometryGenerator.swift` | Reduced ground resolution from 100 to 50 |
| `Renderer.swift` | Reduced tree spawn chance from 0.75 to 0.50 |
4. **Shadow Optimization** - Cull objects not in shadow frustum
5. **Cache Terrain Heights** - Pre-compute for static objects

### Quick Wins (Low Effort)

1. **Reduce tree count:** Currently generates trees on 75% of valid positions
2. **Reduce ground resolution:** Change from 100×100 to 50×50 (15,000 verts instead of 60,000)
3. **Limit shadow casters:** Only cast shadows for objects within N units of camera

### Code Locations for Optimization

| Optimization | File | Function |
|--------------|------|----------|
| Tree instancing | Renderer.swift | `drawTrees()` ~line 3312 |
| Enemy batching | Renderer.swift | `drawEnemies()` ~line 1602 |
| Chest batching | Renderer.swift | `drawChests()` ~line 3011 |
| Ground resolution | GeometryGenerator.swift | `makeGroundMesh()` line 146 |
| Tree density | Renderer.swift | `generateTreeInstances()` ~line 3253 |
| Frustum culling | Renderer.swift | Add new utility function |

---

*Last updated: Dec 26, 2025*

