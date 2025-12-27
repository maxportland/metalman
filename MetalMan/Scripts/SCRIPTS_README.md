# MetalMan Blender Scripts

This folder contains Blender Python scripts for asset preparation.

**Note:** Blender is not in the system PATH. Use the absolute path to run scripts:
```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python <script.py>
```

---

## export_animations_to_usdz.py

Batch exports player character animations to USDZ format.

### What it does:
1. Takes a character mesh FBX and multiple animation FBX files
2. Combines each animation with the character mesh
3. Strips root motion (optional) to make walk-in-place animations
4. Exports each as a separate USDZ file with clean filenames

### Filename Cleaning:
- `sword and shield attack (2).fbx` → `sword-and-shield-attack-2.usdz`
- Removes special characters, replaces spaces with dashes, converts to lowercase

### Usage:
```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python export_animations_to_usdz.py
```

---

## export_enemy_animations.py

Batch exports enemy (Mutant/Castle Guard) animations to USDZ format.

### What it does:
1. Uses `castle_guard_01.fbx` as the base mesh
2. Combines it with each animation FBX from the Creature Pack folder
3. Also scans `animation_source/` root for additional animations (e.g., Reaction.fbx, Taking Punch.fbx)
4. Strips root motion and exports to `MetalMan/EnemyAnimations/`

### Usage:
```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python export_enemy_animations.py
```

---

## export_vendor_animations.py

Exports NPC vendor model and animations to USDZ format.

### What it does:
1. Processes each FBX file in `animation_source/npc_vendor_model_animation/`
2. Each FBX contains the vendor model with its animation
3. Exports each as a separate USDZ to `MetalMan/NPCAnimations/`

### Source Files:
- `vendor_e_action.fbx` → `vendor-e-action.usdz`
- `vendor_happy_idle.fbx` → `vendor-happy-idle.usdz`
- `vendor_waving.fbx` → `vendor-waving.usdz`

### Usage:
```bash
/Applications/Blender.app/Contents/MacOS/Blender --background --python export_vendor_animations.py
```

---

## Common Notes

- Requires **Blender 3.6+** for USDZ export support
- Scripts skip files that already exist in the output directory
- Output directories are created automatically
- Add exported USDZ files to the Xcode project after running

