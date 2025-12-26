# MetalMan Blender Scripts

This folder contains Blender Python scripts for asset preparation.

## export_animations_to_usdz.py

Batch exports character animations to USDZ format for use in the game.

### What it does:
1. Takes a character mesh FBX and multiple animation FBX files
2. Combines each animation with the character mesh
3. Strips root motion (optional) to make walk-in-place animations
4. Exports each as a separate USDZ file with clean filenames

### Filename Cleaning:
- `sword and shield attack (2).fbx` → `sword-and-shield-attack-2.usdz`
- Removes special characters
- Replaces spaces with dashes
- Converts to lowercase

### Usage:
1. Open Blender 3.6 or later
2. Go to the **Scripting** workspace
3. Click **Open** and select `export_animations_to_usdz.py`
4. Modify the configuration section at the top if needed:
   ```python
   SOURCE_DIR = "/path/to/animation/files"
   OUTPUT_DIR = "/path/to/output"
   CHARACTER_MESH_FILE = "YourCharacter.fbx"
   STRIP_ROOT_MOTION = True
   ```
5. Click **Run Script** (or press Alt+P)

### Output:
USDZ files will be created in the OUTPUT_DIR, ready to add to the Xcode project.

### Notes:
- Requires Blender 3.6+ for USDZ export support
- The script strips horizontal root motion by default (keeps vertical bobbing)
- Each animation FBX should contain the armature with animation keyframes

