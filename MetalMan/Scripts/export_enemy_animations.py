"""
Blender Python Script: Export Enemy (Mutant/Castle Guard) Animations to USDZ

This script combines the enemy mesh with each animation FBX file
and exports them as individual USDZ files for use in the MetalMan game.

Usage:
1. Open Blender (tested with Blender 3.6+)
2. Open the Scripting workspace
3. Open this script in the text editor
4. Run the script (Alt+P or click "Run Script")

OR run from command line:
    blender --background --python export_enemy_animations.py

Requirements:
- Blender 3.6+ (for USDZ export support)
- The animation FBX files and character mesh in SOURCE_DIR
"""

import bpy
import os
import re
from pathlib import Path

# ============================================================================
# CONFIGURATION - Modify these paths as needed
# ============================================================================

# Directory containing the animation FBX files and character mesh
SOURCE_DIR = "/Users/maxdavis/Projects/MetalMan/animation_source/Creature Pack"

# Output directory for USDZ files (separate from player animations)
OUTPUT_DIR = "/Users/maxdavis/Projects/MetalMan/MetalMan/EnemyAnimations"

# Character mesh file name (the base model with rig)
CHARACTER_MESH_FILE = "castle_guard_01.fbx"

# Whether to strip root motion (horizontal movement) from animations
STRIP_ROOT_MOTION = True

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def clean_filename(name):
    """
    Clean a filename by:
    - Removing special characters (keeping alphanumeric, spaces, dashes, underscores)
    - Replacing spaces with dashes
    - Converting to lowercase
    - Removing duplicate dashes
    """
    # Remove file extension if present
    name = os.path.splitext(name)[0]
    
    # Remove parentheses and their contents, or just normalize (2) to -2
    name = re.sub(r'\s*\((\d+)\)', r'-\1', name)
    
    # Remove any remaining special characters except alphanumeric, spaces, dashes
    name = re.sub(r'[^\w\s\-]', '', name)
    
    # Replace spaces with dashes
    name = name.replace(' ', '-')
    
    # Convert to lowercase
    name = name.lower()
    
    # Remove duplicate dashes
    name = re.sub(r'-+', '-', name)
    
    # Remove leading/trailing dashes
    name = name.strip('-')
    
    return name


def clear_scene():
    """Remove all objects from the scene"""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    
    # Clear orphan data
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in bpy.data.armatures:
        if block.users == 0:
            bpy.data.armatures.remove(block)
    for block in bpy.data.materials:
        if block.users == 0:
            bpy.data.materials.remove(block)
    for block in bpy.data.textures:
        if block.users == 0:
            bpy.data.textures.remove(block)
    for block in bpy.data.images:
        if block.users == 0:
            bpy.data.images.remove(block)
    for block in bpy.data.actions:
        if block.users == 0:
            bpy.data.actions.remove(block)


def import_fbx(filepath):
    """Import an FBX file"""
    bpy.ops.import_scene.fbx(
        filepath=filepath,
        use_anim=True,
        ignore_leaf_bones=False,
        automatic_bone_orientation=False,
        use_prepost_rot=True,
        use_custom_props=True
    )


def get_armature():
    """Find the armature in the scene"""
    for obj in bpy.context.scene.objects:
        if obj.type == 'ARMATURE':
            return obj
    return None


def get_mesh_objects():
    """Get all mesh objects in the scene"""
    return [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']


def strip_root_motion_from_action(action, root_bone_name="mixamorig:Hips"):
    """
    Strip horizontal root motion from an action.
    Keeps vertical (Y) movement but removes X and Z translation.
    """
    if not action:
        return
    
    # Get fcurves - handle both old and new Blender API
    try:
        if hasattr(action, 'fcurves'):
            fcurves = action.fcurves
        elif hasattr(action, 'layers') and len(action.layers) > 0:
            fcurves = []
            for layer in action.layers:
                for strip in layer.strips:
                    if hasattr(strip, 'fcurves'):
                        fcurves.extend(strip.fcurves)
        else:
            print(f"    Warning: Could not access fcurves for action {action.name}")
            return
    except Exception as e:
        print(f"    Warning: Error accessing fcurves: {e}")
        return
    
    # Find the root bone location channels
    x_curve = None
    z_curve = None
    
    for fcurve in fcurves:
        if root_bone_name in fcurve.data_path and 'location' in fcurve.data_path:
            if fcurve.array_index == 0:  # X
                x_curve = fcurve
            elif fcurve.array_index == 2:  # Z
                z_curve = fcurve
    
    # Get the first frame value and make all keyframes use that value
    if x_curve and len(x_curve.keyframe_points) > 0:
        first_x = x_curve.keyframe_points[0].co[1]
        for kp in x_curve.keyframe_points:
            kp.co[1] = first_x
            kp.handle_left[1] = first_x
            kp.handle_right[1] = first_x
    
    if z_curve and len(z_curve.keyframe_points) > 0:
        first_z = z_curve.keyframe_points[0].co[1]
        for kp in z_curve.keyframe_points:
            kp.co[1] = first_z
            kp.handle_left[1] = first_z
            kp.handle_right[1] = first_z


def export_usdz(output_path):
    """Export the current scene as USDZ"""
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    bpy.ops.object.select_all(action='SELECT')
    
    blender_version = bpy.app.version
    
    try:
        if blender_version >= (4, 0, 0):
            bpy.ops.wm.usd_export(
                filepath=output_path,
                selected_objects_only=False,
                export_animation=True,
                export_uvmaps=True,
                export_normals=True,
                export_materials=True,
                evaluation_mode='RENDER',
                generate_preview_surface=True
            )
        else:
            bpy.ops.wm.usd_export(
                filepath=output_path,
                selected_objects_only=False,
                export_animation=True,
                export_hair=False,
                export_uvmaps=True,
                export_normals=True,
                export_materials=True,
                use_instancing=False,
                evaluation_mode='RENDER',
                generate_preview_surface=True,
                export_textures=True,
                overwrite_textures=True,
                relative_paths=True
            )
    except TypeError as e:
        print(f"    Trying minimal export parameters due to: {e}")
        bpy.ops.wm.usd_export(
            filepath=output_path,
            export_animation=True
        )


def process_animation(anim_file, character_file, output_dir, strip_root=True):
    """
    Process a single animation file:
    1. Clear scene
    2. Import character mesh
    3. Import animation (to get the action)
    4. Apply animation to character armature
    5. Export as USDZ
    """
    anim_name = os.path.basename(anim_file)
    clean_name = clean_filename(anim_name)
    output_path = os.path.join(output_dir, f"{clean_name}.usdz")
    
    print(f"\n{'='*60}")
    print(f"Processing: {anim_name}")
    print(f"Output: {clean_name}.usdz")
    print(f"{'='*60}")
    
    clear_scene()
    
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    
    actions_before_char = set(bpy.data.actions.keys())
    
    print(f"  Importing character mesh: {character_file}")
    import_fbx(character_file)
    
    char_armature = get_armature()
    if not char_armature:
        print(f"  ERROR: No armature found in character mesh!")
        return False
    
    char_armature_name = char_armature.name
    
    if char_armature.animation_data and char_armature.animation_data.action:
        print(f"  Clearing character's default action: {char_armature.animation_data.action.name}")
        char_armature.animation_data.action = None
    
    actions_after_char = set(bpy.data.actions.keys())
    char_actions = actions_after_char - actions_before_char
    print(f"  Character brought actions: {list(char_actions)}")
    
    char_meshes = get_mesh_objects()
    char_mesh_names = [m.name for m in char_meshes]
    
    print(f"  Character armature: {char_armature_name}")
    print(f"  Character meshes: {char_mesh_names}")
    
    actions_before_anim = set(bpy.data.actions.keys())
    
    print(f"  Importing animation: {anim_file}")
    import_fbx(anim_file)
    
    actions_after_anim = set(bpy.data.actions.keys())
    new_actions = actions_after_anim - actions_before_anim
    
    print(f"  New actions from animation file: {list(new_actions)}")
    
    new_action = None
    if new_actions:
        new_action_name = list(new_actions)[0]
        new_action = bpy.data.actions.get(new_action_name)
        print(f"  Selected action: {new_action_name}")
    else:
        print(f"  No new actions detected, checking imported armatures...")
        for obj in bpy.context.scene.objects:
            if obj.type == 'ARMATURE' and obj.name != char_armature_name:
                if obj.animation_data and obj.animation_data.action:
                    new_action = obj.animation_data.action
                    print(f"  Found action on imported armature: {new_action.name}")
                    break
    
    if new_action:
        print(f"  Using action: {new_action.name}")
        
        frame_start = int(new_action.frame_range[0])
        frame_end = int(new_action.frame_range[1])
        print(f"  Action frame range: {frame_start} to {frame_end} ({frame_end - frame_start} frames)")
        
        if strip_root:
            print(f"  Stripping root motion...")
            root_bone_names = [
                "mixamorig:Hips",
                "mixamorig_Hips", 
                "Hips",
                "Root",
                "pelvis",
                "Mutant:Hips",
                "Mutant_Hips"
            ]
            for bone_name in root_bone_names:
                strip_root_motion_from_action(new_action, bone_name)
        
        char_armature = bpy.data.objects.get(char_armature_name)
        if char_armature:
            if not char_armature.animation_data:
                char_armature.animation_data_create()
            char_armature.animation_data.action = new_action
            print(f"  Applied action to character armature")
            
            bpy.context.scene.frame_start = frame_start
            bpy.context.scene.frame_end = frame_end
            bpy.context.scene.frame_current = frame_start
            print(f"  Set scene frame range: {frame_start} to {frame_end}")
    else:
        print(f"  WARNING: No action found in animation file")
        print(f"  Available actions: {list(bpy.data.actions.keys())}")
    
    for obj in bpy.context.scene.objects:
        if obj.type == 'ARMATURE' and obj.name != char_armature_name:
            print(f"  Removing duplicate armature: {obj.name}")
            bpy.data.objects.remove(obj, do_unlink=True)
        elif obj.type == 'MESH' and obj.name not in char_mesh_names:
            print(f"  Removing duplicate mesh: {obj.name}")
            bpy.data.objects.remove(obj, do_unlink=True)
    
    print(f"  Exporting to: {output_path}")
    try:
        export_usdz(output_path)
        print(f"  SUCCESS: Exported {clean_name}.usdz")
        return True
    except Exception as e:
        print(f"  ERROR during export: {e}")
        return False


def main():
    """Main function to process all animations"""
    print("\n" + "="*60)
    print("MetalMan Enemy Animation Export Script")
    print("="*60)
    
    if not os.path.exists(SOURCE_DIR):
        print(f"ERROR: Source directory not found: {SOURCE_DIR}")
        return
    
    character_path = os.path.join(SOURCE_DIR, CHARACTER_MESH_FILE)
    if not os.path.exists(character_path):
        print(f"ERROR: Character mesh not found: {character_path}")
        return
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Find all animation FBX files (excluding the character mesh)
    animation_files = []
    for filename in os.listdir(SOURCE_DIR):
        if filename.endswith('.fbx') and filename != CHARACTER_MESH_FILE:
            animation_files.append(os.path.join(SOURCE_DIR, filename))
    
    animation_files.sort()
    
    print(f"\nFound {len(animation_files)} animation files")
    print(f"Character mesh: {CHARACTER_MESH_FILE}")
    print(f"Output directory: {OUTPUT_DIR}")
    print(f"Strip root motion: {STRIP_ROOT_MOTION}")
    
    success_count = 0
    fail_count = 0
    
    for anim_file in animation_files:
        try:
            if process_animation(anim_file, character_path, OUTPUT_DIR, STRIP_ROOT_MOTION):
                success_count += 1
            else:
                fail_count += 1
        except Exception as e:
            print(f"ERROR processing {anim_file}: {e}")
            fail_count += 1
    
    print("\n" + "="*60)
    print("EXPORT COMPLETE")
    print("="*60)
    print(f"Successful exports: {success_count}")
    print(f"Failed exports: {fail_count}")
    print(f"Output directory: {OUTPUT_DIR}")
    
    if os.path.exists(OUTPUT_DIR):
        exported = [f for f in os.listdir(OUTPUT_DIR) if f.endswith('.usdz')]
        print(f"\nExported files ({len(exported)}):")
        for f in sorted(exported):
            print(f"  - {f}")


if __name__ == "__main__":
    main()

