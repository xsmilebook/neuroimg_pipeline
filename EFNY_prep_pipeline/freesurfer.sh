#!/bin/bash
#SBATCH -J freesurfer
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=16
#SBATCH -p q_fat
#SBATCH -q high

#this script is only for preprocess

module load singularity/3.7.0
module load freesurfer

#User inputs:
bids_root_dir=/ibmgpfs/cuizaixu_lab/liyang/BrainProject25/Tsinghua_data/BIDS
bids_root_dir_output=/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/THU/results
bids_root_dir_output_wd4singularity=/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/THU/wd
freesurfer_dir=/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/THU/freesurfer
subj=$1
nthreads=16

#Run freesurfer
echo ""
echo "Running freesurfer on participant: ${subj}"
echo ""

SUBJECTS_DIR=$freesurfer_dir
#Make freesurfer directory and participant directory in derivatives folder
if [ ! -d $freesurfer_dir/${subj} ]; then
    mkdir $freesurfer_dir/${subj}
    mkdir $freesurfer_dir/${subj}/mri
    mkdir $freesurfer_dir/${subj}/mri/orig
fi

# freesurfer
mri_convert $bids_root_dir/${subj}/anat/${subj}_run-1_T1w.nii $freesurfer_dir/${subj}/mri/orig/001.mgz
mri_convert $bids_root_dir/${subj}/anat/${subj}_run-1_T1w.nii $freesurfer_dir/${subj}/mri/orig.mgz

recon-all -s ${subj} -all -qcache -no-isrunning

