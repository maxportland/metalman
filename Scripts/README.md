# Animation Export Scripts

## Blender Animation Exporter

The `export_animation.py` script exports skeletal animation from Blender to JSON format that MetalMan can load.

### How to Use

1. **Open your animated model in Blender**
   - Open the FBX file from Mixamo (e.g., `Walking.fbx`)

2. **Select the Armature**
   - In the Outliner, click on the Armature object

3. **Run the export script**
   - Go to the **Scripting** workspace (top tabs)
   - Click **Open** and select `export_animation.py`
   - Click **Run Script** (▶️ button)

4. **Find the output**
   - The JSON file will be saved next to your .blend file
   - It will be named like `Walking_animation.json`

5. **Copy to Xcode project**
   - Copy the JSON file to the MetalMan project
   - Add it to the Xcode project (drag into Xcode, select "Copy items if needed")
   - Make sure it's added to the target

### Expected JSON Filenames

The game looks for these animation files:
- `Walking_animation.json` - Used for walk animation
- `Idle_animation.json` - Used for idle animation

### Command Line Export

You can also run from the command line:

```bash
blender Walking.fbx --background --python export_animation.py
```

### Exporting Multiple Animations

To export all actions in a blend file, modify the script's main section:

```python
if __name__ == "__main__":
    export_all_actions()  # Instead of export_animation()
```

### Troubleshooting

- **"No armature found"**: Make sure you have an armature in the scene
- **"No animation action found"**: Make sure the armature has an animation assigned
- **Bones don't match**: Check that bone names match between Blender and the USDZ skeleton

### JSON Format

The exported JSON has this structure:

```json
{
  "name": "Walking",
  "duration": 1.0,
  "fps": 30,
  "boneCount": 99,
  "keyframeCount": 30,
  "bones": [
    {"name": "mixamorig_Hips", "index": 0, "parentIndex": -1},
    ...
  ],
  "keyframes": [
    {
      "time": 0.0,
      "boneTransforms": [
        [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1],  // 4x4 matrix, column-major
        ...
      ]
    },
    ...
  ]
}
```


