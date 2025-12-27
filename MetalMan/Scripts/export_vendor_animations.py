"""
Blender Python Script: Export NPC Vendor Model and Animations to USDZ

This script processes each vendor FBX file (which contains the model with
its animation) and exports them as individual USDZ files for use in MetalMan.

Usage:
1. Open Blender (tested with Blender 3.6+)
2. Open the Scripting workspace
3. Open this script in the text editor
4. Run the script (Alt+P or click "Run Script")

OR run from command line:
    /Applications/Blender.app/Contents/MacOS/Blender --background --python export_vendor_animations.py

Requirements:
- Blender 3.6+ (for USDZ export support)
- The vendor FBX files in SOURCE_DIR
"""

import bpy
import os
import re
from pathlib import Path

# ============================================================================
# CONFIGURATION - Modify these paths as needed
# ============================================================================

# Directory containing the vendor FBX files
SOURCE_DIR = "/Users/maxdavis/Projects/MetalMan/animation_source/npc_vendor_model_animation"

# Output directory for USDZ files
OUTPUT_DIR = "/Users/maxdavis/Projects/MetalMan/MetalMan/NPCAnimations"

# Whether to skip files that already exist in output
SKIP_EXISTING = True

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
    
    # Replace spaces and underscores with dashes
    name = name.replace(' ', '-')
    name = name.replace('_', '-')
    
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


def process_vendor_fbx(fbx_file, output_dir, skip_existing=True):
    """
    Process a single vendor FBX file:
    1. Clear scene
    2. Import the FBX (contains model + animation)
    3. Set up frame range from the action
    4. Export as USDZ
    
    Returns: True if exported, False if failed, None if skipped
    """
    fbx_name = os.path.basename(fbx_file)
    clean_name = clean_filename(fbx_name)
    output_path = os.path.join(output_dir, f"{clean_name}.usdz")
    
    # Skip if output already exists
    if skip_existing and os.path.exists(output_path):
        print(f"  SKIPPED: {clean_name}.usdz already exists")
        return None
    
    print(f"\n{'='*60}")
    print(f"Processing: {fbx_name}")
    print(f"Output: {clean_name}.usdz")
    print(f"{'='*60}")
    
    # Clear the scene
    clear_scene()
    
    # Clear all actions
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    
    # Import the FBX
    print(f"  Importing: {fbx_file}")
    import_fbx(fbx_file)
    
    # Get armature and meshes
    armature = get_armature()
    meshes = get_mesh_objects()
    
    if not armature:
        print(f"  WARNING: No armature found in {fbx_name}")
    else:
        print(f"  Armature: {armature.name}")
    
    if not meshes:
        print(f"  WARNING: No meshes found in {fbx_name}")
    else:
        print(f"  Meshes: {[m.name for m in meshes]}")
    
    # Check for animation
    if armature and armature.animation_data and armature.animation_data.action:
        action = armature.animation_data.action
        frame_start = int(action.frame_range[0])
        frame_end = int(action.frame_range[1])
        print(f"  Action: {action.name}")
        print(f"  Frame range: {frame_start} to {frame_end} ({frame_end - frame_start} frames)")
        
        # Set scene frame range
        bpy.context.scene.frame_start = frame_start
        bpy.context.scene.frame_end = frame_end
        bpy.context.scene.frame_current = frame_start
    else:
        print(f"  No animation found on armature")
        # Check if there are any actions at all
        if bpy.data.actions:
            print(f"  Available actions: {list(bpy.data.actions.keys())}")
            # Try to apply the first action
            if armature and bpy.data.actions:
                action = list(bpy.data.actions)[0]
                if not armature.animation_data:
                    armature.animation_data_create()
                armature.animation_data.action = action
                frame_start = int(action.frame_range[0])
                frame_end = int(action.frame_range[1])
                bpy.context.scene.frame_start = frame_start
                bpy.context.scene.frame_end = frame_end
                print(f"  Applied action: {action.name}")
    
    # Export to USDZ
    print(f"  Exporting to: {output_path}")
    try:
        export_usdz(output_path)
        print(f"  SUCCESS: Exported {clean_name}.usdz")
        return True
    except Exception as e:
        print(f"  ERROR during export: {e}")
        return False


def main():
    """Main function to process all vendor FBX files"""
    print("\n" + "="*60)
    print("MetalMan NPC Vendor Animation Export Script")
    print("="*60)
    
    # Check source directory
    if not os.path.exists(SOURCE_DIR):
        print(f"ERROR: Source directory not found: {SOURCE_DIR}")
        return
    
    # Create output directory
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    # Find all FBX files
    fbx_files = []
    for filename in os.listdir(SOURCE_DIR):
        if filename.lower().endswith('.fbx'):
            fbx_files.append(os.path.join(SOURCE_DIR, filename))
    
    fbx_files.sort()
    
    print(f"\nFound {len(fbx_files)} FBX files:")
    for f in fbx_files:
        print(f"  - {os.path.basename(f)}")
    print(f"\nOutput directory: {OUTPUT_DIR}")
    print(f"Skip existing: {SKIP_EXISTING}")
    
    # Process each FBX file
    success_count = 0
    skip_count = 0
    fail_count = 0
    
    for fbx_file in fbx_files:
        try:
            result = process_vendor_fbx(fbx_file, OUTPUT_DIR, SKIP_EXISTING)
            if result is True:
                success_count += 1
            elif result is None:
                skip_count += 1
            else:
                fail_count += 1
        except Exception as e:
            print(f"ERROR processing {fbx_file}: {e}")
            import traceback
            traceback.print_exc()
            fail_count += 1
    
    # Summary
    print("\n" + "="*60)
    print("EXPORT COMPLETE")
    print("="*60)
    print(f"Successful exports: {success_count}")
    print(f"Skipped (already exist): {skip_count}")
    print(f"Failed exports: {fail_count}")
    print(f"Output directory: {OUTPUT_DIR}")
    
    # List exported files
    if os.path.exists(OUTPUT_DIR):
        exported = [f for f in os.listdir(OUTPUT_DIR) if f.endswith('.usdz')]
        if exported:
            print(f"\nExported files ({len(exported)}):")
            for f in sorted(exported):
                print(f"  - {f}")


if __name__ == "__main__":
    main()

