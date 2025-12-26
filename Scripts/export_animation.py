"""
Blender Animation Exporter for MetalMan
========================================
This script exports skeletal animation data from Blender to JSON format
that can be loaded by the MetalMan game.

Usage:
1. Open your animated model in Blender
2. Select the Armature
3. Run this script (Text Editor > Run Script, or paste in Python Console)
4. The JSON file will be saved next to the .blend file

Or run from command line:
    blender yourfile.blend --background --python export_animation.py
"""

import bpy
import json
import mathutils
import os
from math import degrees

def get_bone_transform(pose_bone):
    """Get the local transform matrix of a pose bone."""
    if pose_bone.parent:
        # Get transform relative to parent
        parent_matrix = pose_bone.parent.matrix
        local_matrix = parent_matrix.inverted() @ pose_bone.matrix
    else:
        # Root bone - use armature-space matrix
        local_matrix = pose_bone.matrix
    
    return local_matrix

def matrix_to_list(matrix):
    """Convert a Blender matrix to a flat list (column-major for Metal/simd)."""
    # Metal uses column-major matrices
    result = []
    for col in range(4):
        for row in range(4):
            result.append(matrix[row][col])
    return result

def export_animation(armature_name=None, output_path=None):
    """Export animation data from the specified armature."""
    
    # Find the armature
    armature = None
    if armature_name:
        armature = bpy.data.objects.get(armature_name)
    else:
        # Find first armature in scene
        for obj in bpy.context.scene.objects:
            if obj.type == 'ARMATURE':
                armature = obj
                break
    
    if not armature:
        print("ERROR: No armature found!")
        return None
    
    print(f"Exporting animation from armature: {armature.name}")
    
    # Get the action (animation)
    if not armature.animation_data or not armature.animation_data.action:
        print("ERROR: No animation action found on armature!")
        return None
    
    action = armature.animation_data.action
    print(f"Action: {action.name}")
    
    # Get frame range
    frame_start = int(action.frame_range[0])
    frame_end = int(action.frame_range[1])
    fps = bpy.context.scene.render.fps
    
    print(f"Frame range: {frame_start} to {frame_end} at {fps} FPS")
    
    # Build bone hierarchy info
    bones_info = []
    bone_name_to_index = {}
    
    for idx, bone in enumerate(armature.pose.bones):
        parent_idx = -1
        if bone.parent:
            parent_idx = bone_name_to_index.get(bone.parent.name, -1)
        
        # Convert underscores for Mixamo naming (mixamorig:Hips -> mixamorig_Hips)
        bone_name = bone.name.replace(":", "_")
        
        bone_name_to_index[bone.name] = idx
        bones_info.append({
            "name": bone_name,
            "index": idx,
            "parentIndex": parent_idx
        })
    
    print(f"Found {len(bones_info)} bones")
    
    # Sample animation at each frame
    keyframes = []
    
    # Determine sample rate (every frame or subsample for large animations)
    total_frames = frame_end - frame_start + 1
    sample_step = 1
    if total_frames > 300:
        sample_step = 2  # Sample every other frame for long animations
    
    sampled_frames = list(range(frame_start, frame_end + 1, sample_step))
    # Always include the last frame
    if sampled_frames[-1] != frame_end:
        sampled_frames.append(frame_end)
    
    print(f"Sampling {len(sampled_frames)} frames...")
    
    for frame in sampled_frames:
        bpy.context.scene.frame_set(frame)
        
        time = (frame - frame_start) / fps
        
        bone_transforms = []
        for bone in armature.pose.bones:
            local_matrix = get_bone_transform(bone)
            bone_transforms.append(matrix_to_list(local_matrix))
        
        keyframes.append({
            "time": time,
            "boneTransforms": bone_transforms
        })
    
    duration = (frame_end - frame_start) / fps
    
    # Build the output data
    animation_data = {
        "name": action.name.replace(":", "_"),
        "duration": duration,
        "fps": fps,
        "boneCount": len(bones_info),
        "keyframeCount": len(keyframes),
        "bones": bones_info,
        "keyframes": keyframes
    }
    
    # Determine output path
    if not output_path:
        blend_path = bpy.data.filepath
        if blend_path:
            output_path = os.path.splitext(blend_path)[0] + "_animation.json"
        else:
            output_path = f"/tmp/{action.name}_animation.json"
    
    # Write JSON
    with open(output_path, 'w') as f:
        json.dump(animation_data, f, indent=2)
    
    print(f"✅ Exported animation to: {output_path}")
    print(f"   Duration: {duration:.2f}s")
    print(f"   Bones: {len(bones_info)}")
    print(f"   Keyframes: {len(keyframes)}")
    
    return output_path

def export_all_actions(armature_name=None, output_dir=None):
    """Export all actions as separate animation files."""
    
    # Find the armature
    armature = None
    if armature_name:
        armature = bpy.data.objects.get(armature_name)
    else:
        for obj in bpy.context.scene.objects:
            if obj.type == 'ARMATURE':
                armature = obj
                break
    
    if not armature:
        print("ERROR: No armature found!")
        return
    
    if not output_dir:
        blend_path = bpy.data.filepath
        if blend_path:
            output_dir = os.path.dirname(blend_path)
        else:
            output_dir = "/tmp"
    
    # Store original action
    original_action = armature.animation_data.action if armature.animation_data else None
    
    exported = []
    for action in bpy.data.actions:
        # Assign this action to the armature
        if not armature.animation_data:
            armature.animation_data_create()
        armature.animation_data.action = action
        
        output_path = os.path.join(output_dir, f"{action.name.replace(':', '_')}_animation.json")
        result = export_animation(armature.name, output_path)
        if result:
            exported.append(result)
    
    # Restore original action
    if original_action:
        armature.animation_data.action = original_action
    
    print(f"\n✅ Exported {len(exported)} animations")
    return exported


# Run when script is executed
if __name__ == "__main__":
    # Export the current animation
    export_animation()
    
    # Or export all actions:
    # export_all_actions()


