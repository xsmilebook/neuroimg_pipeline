# -*- coding: utf-8 -*-
"""
Script to convert BIDS format data back to a structure resembling the original HCP format.
This script copies files from the input BIDS directory to a new output directory,
reorganizing and renaming them according to inferred HCP conventions.
It does not modify the original BIDS data.
"""

import os
import shutil
import json
import re
import argparse

def load_json(filepath):
    """Loads a JSON file."""
    with open(filepath, 'r') as f:
        return json.load(f)

def get_phase_encoding_info(json_data, filename):
    """
    Extracts phase encoding direction from BIDS JSON metadata.
    Maps BIDS 'i', 'i-', 'j', 'j-' to HCP-like 'LR', 'RL', 'AP', 'PA'.
    Falls back to inferring from filename if not found in JSON.
    """
    pe_dir_bids = json_data.get("PhaseEncodingDirection")
    if pe_dir_bids:
        # Standard BIDS mapping to HCP-like acquisition directions
        pe_map = {
            'i': 'LR', 'i-': 'RL',
            'j': 'AP', 'j-': 'PA'
        }
        return pe_map.get(pe_dir_bids.upper(), pe_dir_bids)
    else:
        # Fallback: Infer from filename if JSON is missing or lacks PE info
        # Common in BIDS where direction is part of the name (e.g., _dir-AP_)
        match = re.search(r'_dir-([A-Z]{2})', filename)
        if match:
            return match.group(1)
        # Or infer from _acq- if present
        match = re.search(r'_acq-([A-Z]{2})', filename)
        if match:
            return match.group(1)
        # Or infer from _run- if it contains direction info (less common but possible)
        # match = re.search(r'_run-([A-Z]{2})', filename) # Uncomment if needed
        # if match:
        #     return match.group(1)
    return "UNKNOWN"

def get_bids_info_from_filename(filename):
    """
    Extracts information from a BIDS filename.
    Returns a dictionary with keys like 'sub', 'ses', 'task', 'acq', 'dir', 'run', 'echo', 'modality', 'suffix', 'extension'.
    """
    # Regex to match BIDS filename components
    # Example: sub-APBN20250607101ZYF_ses-01_task-REST_run-1_echo-1_bold.nii
    pattern = r"sub-(?P<sub>[^_]+)_ses-(?P<ses>[^_]+)(?:_task-(?P<task>[^_]+))?(?:_acq-(?P<acq>[^_]+))?(?:_dir-(?P<dir>[^_]+))?(?:_run-(?P<run>[^_]+))?(?:_echo-(?P<echo>[^_]+))?(?:_mod-(?P<mod>[^_]+))?(?P<suffix>_T1w|_T2w|_dwi|_epi|_bold|_sbref|_phase|_magnitude)(?P<extension>\.[^\.]+(?:\.[^\.]+)?)$"
    match = re.search(pattern, os.path.basename(filename))
    if not match:
        return None
    
    info = match.groupdict()
    # Determine modality based on suffix if not explicitly stated
    if not info.get('modality') and info.get('suffix'):
        suffix_to_mod = {
            '_bold': 'bold',
            '_dwi': 'dwi',
            '_epi': 'epi', # Could be fmap or dwi sbref
            '_sbref': 'sbref',
            '_T1w': 'T1w',
            '_T2w': 'T2w',
            '_phase': 'phase',
            '_magnitude': 'magnitude'
        }
        info['modality'] = suffix_to_mod.get(info['suffix'], info['suffix'][1:]) # Remove leading underscore
    return info

def determine_hcp_modality_and_task(bids_info, bids_json_data):
    """
    Determines the HCP-like modality and task name based on BIDS info.
    """
    suffix = bids_info.get('suffix', '')
    task = bids_info.get('task', 'UNKNOWN')
    modality = bids_info.get('modality', 'UNKNOWN')
    
    # Map BIDS suffixes to HCP-like categories
    if suffix in ['_T1w', '_T2w']:
        hcp_modality = 'anat' # HCP puts T1w/T2w in anat-like structure
        hcp_task_or_mod = suffix[1:] # e.g., 'T1w', 'T2w'
    elif suffix in ['_dwi']:
        hcp_modality = 'dwi'
        hcp_task_or_mod = 'Diffusion' # HCP standard name for dwi folder
    elif suffix in ['_bold', '_sbref']:
        hcp_modality = 'func'
        # Determine if it's a task fMRI or rest
        if task and task.lower() in ['rest', 'rest1', 'rest2']:
             # HCP naming for resting state: rfMRI_REST1_LR
             # Use run number if available to distinguish REST1/REST2, otherwise default
             hcp_task = f"rfMRI_REST{bids_info.get('run', '1')}" # Simplified, assumes run 1/2 maps to REST1/REST2
        else:
            # HCP naming for task fMRI: tfMRI_TASKNAME_LR
            # Map BIDS task names to HCP task names if known
            hcp_task_map = {
                'emotion': 'EMOTION',
                'gambling': 'GAMBLING',
                'language': 'LANGUAGE',
                'relational': 'RELATIONAL',
                'motor': 'MOTOR',
                'social': 'SOCIAL',
                'wm': 'WM',
                'rest': 'REST'
            }
            hcp_task = f"tfMRI_{hcp_task_map.get(task.lower(), task.upper())}"
        hcp_task_or_mod = hcp_task
    elif suffix in ['_epi']: # Could be field maps or dwi sbref
        # Check JSON IntendedFor to guess if it's fmap or dwi sbref
        intended_for = bids_json_data.get("IntendedFor", "")
        if isinstance(intended_for, list) and intended_for:
            intended_for = intended_for[0]
        if 'dwi' in intended_for.lower() or 'diffusion' in intended_for.lower():
            hcp_modality = 'dwi'
            hcp_task_or_mod = 'Diffusion' # For dwi sbref
        else:
            hcp_modality = 'fmap'
            hcp_task_or_mod = 'SpinEchoFieldMap' # Generic name, could be more specific
    elif suffix in ['_magnitude', '_phase']:
        hcp_modality = 'fmap' # Typically associated with field maps
        hcp_task_or_mod = f"T1w_M{suffix[1:]}" if 'T1w' in bids_json_data.get("IntendedFor", "") else f"T2w_M{suffix[1:]}"
    else:
        # Fallback
        hcp_modality = 'unknown'
        hcp_task_or_mod = modality

    return hcp_modality, hcp_task_or_mod

def bids_to_hcp(input_bids_dir, output_hcp_dir):
    """
    Main function to convert BIDS structure to HCP-like structure.
    """
    os.makedirs(output_hcp_dir, exist_ok=True)

    # Walk through BIDS directory
    for root, dirs, files in os.walk(input_bids_dir):
        # Check if we are in a functional, anatomical, dwi, or fmap directory within a session
        if any(subdir in root for subdir in ['func', 'anat', 'dwi', 'fmap']):
            bids_path_parts = root.split(os.sep)
            # Find the index of the session part to get subject and session
            try:
                ses_idx = next(i for i, part in enumerate(bids_path_parts) if part.startswith('ses-'))
                sub_part = bids_path_parts[ses_idx - 1]
                if sub_part.startswith('sub-'):
                    subject_id = sub_part.split('-')[1]
                    session_id = bids_path_parts[ses_idx].split('-')[1]
                else:
                    print(f"Warning: Could not parse subject/session from path: {root}")
                    continue
            except StopIteration:
                print(f"Warning: Could not find session directory in path: {root}")
                continue

            for file in files:
                if not (file.endswith('.nii') or file.endswith('.nii.gz') or 
                        file.endswith('.bval') or file.endswith('.bvec') or
                        file.endswith('.json')):
                    continue # Skip non-data files

                bids_file_path = os.path.join(root, file)
                
                # Determine HCP output path
                bids_info = get_bids_info_from_filename(file)
                if not bids_info:
                    print(f"Warning: Could not parse BIDS filename: {file} in {root}")
                    continue

                # Load associated JSON if it's an image file
                json_data = {}
                if file.endswith(('.nii', '.nii.gz')):
                    json_file = file.replace('.nii.gz', '.json').replace('.nii', '.json')
                    json_path = os.path.join(root, json_file)
                    if os.path.exists(json_path):
                        try:
                            json_data = load_json(json_path)
                        except json.JSONDecodeError:
                            print(f"Warning: Could not decode JSON file: {json_path}")
                            pass
                
                hcp_modality, hcp_task_or_mod = determine_hcp_modality_and_task(bids_info, json_data)
                pe_dir = get_phase_encoding_info(json_data, file)

                # Construct HCP-like output path
                # HCP typically has: /sub01/unprocessed/3T/[MODALITY]/[SCAN_NAME]/
                # Guessing scan name based on task/modality and direction
                if hcp_modality == 'func':
                    # For func, the scan name often includes the task and direction
                    scan_name = f"{hcp_task_or_mod}_{pe_dir}"
                elif hcp_modality == 'dwi':
                    # For dwi, the scan name is often just 'Diffusion'
                    scan_name = f"{hcp_task_or_mod}_{pe_dir}"
                elif hcp_modality == 'fmap':
                    # For fmap, often 'SpinEchoFieldMap' or similar
                    scan_name = f"{hcp_task_or_mod}_{pe_dir}"
                elif hcp_modality == 'anat':
                    # For anat, often just the modality name, might be under T1w/T2w folders
                    scan_name = hcp_task_or_mod # e.g., T1w, T2w
                else: # unknown
                    scan_name = f"{hcp_task_or_mod}_{pe_dir}"

                # HCP raw data path structure
                hcp_output_sub_dir = os.path.join(output_hcp_dir, f"sub{subject_id}")
                hcp_output_raw_dir = os.path.join(hcp_output_sub_dir, "unprocessed", "3T", hcp_modality, scan_name)

                os.makedirs(hcp_output_raw_dir, exist_ok=True)

                # Determine final HCP-like filename
                # This is the tricky part as BIDS names are more generic
                # We'll reconstruct a name based on the original BIDS components
                # This is an approximation, as original HCP names might have been more specific (e.g., rfMRI_REST1_LR)
                
                # Example BIDS: sub-01_ses-01_task-rest_run-1_bold.nii
                # Example HCP (inferred): rfMRI_REST1_LR.nii
                
                # A simple reconstruction, might need adjustment based on exact HCP naming
                hcp_filename_parts = []
                
                # For func/dwi/fmap, include task/direction
                if hcp_modality == 'func':
                    # Use the reconstructed scan_name part (e.g., rfMRI_EMOTION)
                    # and append direction
                    # Original HCP might have run-specific names like REST1/REST2
                    run_part = f"_{bids_info.get('run', '1')}" if 'REST' in hcp_task_or_mod else ""
                    hcp_filename_parts.append(f"{hcp_task_or_mod}{run_part}_{pe_dir}")
                elif hcp_modality == 'dwi':
                     hcp_filename_parts.append(f"{scan_name}") # Diffusion_LR etc.
                elif hcp_modality == 'fmap':
                     hcp_filename_parts.append(f"{scan_name}") # SpinEchoFieldMap_LR etc.
                elif hcp_modality == 'anat':
                     # For anat, might need to go into a subfolder like T1w/ or T2w/
                     # Let's assume the file name is simpler, like orig_name.nii
                     # We'll keep the BIDS-derived name but remove sub/ses prefixes
                     # Original HCP: T1w_acpc_dc_restore.nii.gz
                     # BIDS: sub-01_ses-01_run-1_T1w.nii
                     # We can't get exact original, so let's use a generic one or reconstruct from bids_info
                     # Let's try to reconstruct based on modality and run
                     run_part = f"_run-{bids_info.get('run', '1')}" if bids_info.get('run') else ""
                     hcp_filename_parts.append(f"{hcp_task_or_mod}{run_part}")
                else: # unknown
                    hcp_filename_parts.append(file) # Fallback

                # Add original file extension
                hcp_filename_parts.append(bids_file_path.split('.')[-1]) # Gets 'nii' or 'gz'
                if bids_file_path.endswith('.nii.gz'):
                    hcp_filename_parts.insert(-1, 'nii') # Re-insert 'nii' before 'gz'
                
                # Combine parts, removing empty strings
                hcp_filename = '_'.join([p for p in hcp_filename_parts if p])
                
                # Handle specific files like .bval, .bvec
                if file.endswith('.bval') or file.endswith('.bvec'):
                    # These belong to dwi, often named as Diffusion.bval/vec in HCP
                    hcp_filename = f"{hcp_task_or_mod}.{file.split('.')[-1]}"

                hcp_output_file_path = os.path.join(hcp_output_raw_dir, hcp_filename)

                print(f"Copying BIDS: {bids_file_path} -> HCP: {hcp_output_file_path}")
                shutil.copy2(bids_file_path, hcp_output_file_path)

def bids_to_hcp_example(input_bids_dir, output_hcp_dir):
    """
    Convert BIDS structure to the example HCP-like structure shown in
    HCP_folder_structure.txt:

    <subject>/
      anat/unprocessed/
        T1w/T1w_1.nii.gz, T1w_2.nii.gz, ...
        T2w/T2w_1.nii.gz, T2w_2.nii.gz, ...
      func/unprocessed/
        field_maps/AP_S{S}_R{R}.nii.gz, PA_S{S}_R{R}.nii.gz, *.json
        rest/session_{S}/run_{R}/Rest_S{S}_R{R}_E{E}.* and Sbref_S{S}_R{R}_E{E}.*

    Notes:
    - Preserves original file extensions (.nii or .nii.gz).
    - Copies JSONs for field_maps and REST BOLD.
    - Skips DWI volumes, as they are not present in the example layout.
    """
    os.makedirs(output_hcp_dir, exist_ok=True)

    # Counters for anat numbering per subject
    anat_counts = {}

    def get_session_number(ses_str):
        try:
            return int(re.sub(r"^0+", "", str(ses_str))) if str(ses_str) else 1
        except ValueError:
            return 1

    for root, dirs, files in os.walk(input_bids_dir):
        if not any(subdir in root for subdir in ['func', 'anat', 'fmap']):
            continue

        parts = root.split(os.sep)
        try:
            ses_idx = next(i for i, part in enumerate(parts) if part.startswith('ses-'))
            sub_part = parts[ses_idx - 1]
            if not sub_part.startswith('sub-'):
                print(f"Warning: Could not parse subject/session from path: {root}")
                continue
            subject_id = sub_part.split('-')[1]
            session_id = parts[ses_idx].split('-')[1]
        except StopIteration:
            print(f"Warning: Could not find session directory in path: {root}")
            continue

        subj_out_dir = os.path.join(output_hcp_dir, subject_id)
        os.makedirs(subj_out_dir, exist_ok=True)

        if subject_id not in anat_counts:
            anat_counts[subject_id] = {'T1w': 0, 'T2w': 0}

        for file in files:
            if not (file.endswith('.nii') or file.endswith('.nii.gz') or file.endswith('.json')):
                continue

            bids_info = get_bids_info_from_filename(file)
            if not bids_info:
                print(f"Warning: Could not parse BIDS filename: {file} in {root}")
                continue

            modality = bids_info.get('modality', '').lower()
            ses_num = get_session_number(bids_info.get('ses'))
            run = bids_info.get('run') or '1'
            echo = bids_info.get('echo') or None
            direction = bids_info.get('dir')

            src_path = os.path.join(root, file)
            ext = '.nii.gz' if file.endswith('.nii.gz') else ('.nii' if file.endswith('.nii') else '.json')

            # ANAT: T1w/T2w
            if modality in ['t1w', 't2w']:
                if ext == '.json':
                    continue
                mod_key = 'T1w' if modality == 't1w' else 'T2w'
                anat_counts[subject_id][mod_key] += 1
                num = anat_counts[subject_id][mod_key]
                dest_dir = os.path.join(subj_out_dir, 'anat', 'unprocessed', mod_key)
                os.makedirs(dest_dir, exist_ok=True)
                dest_name = f"{mod_key}_{num}{ext}"
                dest_path = os.path.join(dest_dir, dest_name)
                print(f"Copying ANAT: {src_path} -> {dest_path}")
                shutil.copy2(src_path, dest_path)
                continue

            # REST: bold / sbref
            if modality in ['bold', 'sbref']:
                task = bids_info.get('task', '')
                if task.lower() != 'rest':
                    continue
                dest_dir = os.path.join(subj_out_dir, 'func', 'unprocessed', 'rest', f'session_{ses_num}', f'run_{run}')
                os.makedirs(dest_dir, exist_ok=True)
                if modality == 'bold':
                    if echo is None:
                        echo = '1'
                    base = f"Rest_S{ses_num}_R{run}_E{echo}"
                    dest_img = os.path.join(dest_dir, f"{base}{ext}")
                    print(f"Copying REST BOLD: {src_path} -> {dest_img}")
                    shutil.copy2(src_path, dest_img)
                    json_src = src_path.replace('.nii.gz', '.json').replace('.nii', '.json')
                    if os.path.exists(json_src):
                        dest_json = os.path.join(dest_dir, f"{base}.json")
                        print(f"Copying REST JSON: {json_src} -> {dest_json}")
                        shutil.copy2(json_src, dest_json)
                else:
                    if echo is None:
                        echo = '1'
                    base = f"Sbref_S{ses_num}_R{run}_E{echo}"
                    dest_img = os.path.join(dest_dir, f"{base}{ext}")
                    print(f"Copying REST SBREF: {src_path} -> {dest_img}")
                    shutil.copy2(src_path, dest_img)
                continue

            # FIELD MAPS: epi
            if modality == 'epi':
                dest_dir = os.path.join(subj_out_dir, 'func', 'unprocessed', 'field_maps')
                os.makedirs(dest_dir, exist_ok=True)
                dir_tag = (direction or '').upper()
                if dir_tag not in ['AP', 'PA']:
                    json_data = {}
                    json_src = src_path.replace('.nii.gz', '.json').replace('.nii', '.json')
                    if os.path.exists(json_src):
                        try:
                            json_data = load_json(json_src)
                        except json.JSONDecodeError:
                            pass
                    dir_tag = get_phase_encoding_info(json_data, file).upper()
                    if dir_tag == 'UNKNOWN':
                        dir_tag = 'AP'
                base = f"{dir_tag}_S{ses_num}_R{run}"
                if ext == '.json':
                    dest_json = os.path.join(dest_dir, f"{base}.json")
                    print(f"Copying FMAP JSON: {src_path} -> {dest_json}")
                    shutil.copy2(src_path, dest_json)
                else:
                    dest_img = os.path.join(dest_dir, f"{base}{ext}")
                    print(f"Copying FMAP: {src_path} -> {dest_img}")
                    shutil.copy2(src_path, dest_img)
                continue

            # Skip other modalities (e.g., dwi)
            continue


def main():
    parser = argparse.ArgumentParser(
        description="Convert BIDS format data to a structure resembling HCP format."
    )
    parser.add_argument(
        "input_bids_dir",
        help="Path to the input BIDS dataset directory."
    )
    parser.add_argument(
        "output_hcp_dir",
        help="Path to the output directory for the HCP-like dataset. This directory will be created if it doesn't exist."
    )

    args = parser.parse_args()

    input_dir = args.input_bids_dir
    output_dir = args.output_hcp_dir

    if not os.path.isdir(input_dir):
        print(f"Error: Input directory does not exist: {input_dir}")
        return

    # Use the example-style converter to match HCP_folder_structure.txt
    bids_to_hcp_example(input_dir, output_dir)
    print(f"\nConversion complete. HCP-like data is located at: {output_dir}")


if __name__ == '__main__':
    main()