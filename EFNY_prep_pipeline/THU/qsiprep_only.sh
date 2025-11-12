#!/bin/bash
#SBATCH -J qsiprep
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=8
#SBATCH -p q_fat

#this script is only for preprocess

module load singularity/3.7.0
module load freesurfer

#User inputs:
bids_root_dir=/ibmgpfs/cuizaixu_lab/liyang/BrainProject25/Tsinghua_data/BIDS
bids_root_dir_output=/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/THU/results
bids_root_dir_output_wd4singularity=/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/THU/wd/qsiprep
freesurfer_dir=/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/THU/freesurfer
templateflow=/ibmgpfs/cuizaixu_lab/xuhaoshu/packages/templateflow
subj=$1
nthreads=8

#Run qsiprep
echo ""
echo "Running qsiprep on participant: ${subj}"
echo ""

SUBJECTS_DIR=$freesurfer_dir
# #Make freesurfer directory and participant directory in derivatives folder
# if [ ! -d $freesurfer_dir/${subj} ]; then
#     mkdir $freesurfer_dir/${subj}
#     mkdir $freesurfer_dir/${subj}/mri
#     mkdir $freesurfer_dir/${subj}/mri/orig
# fi

# freesurfer
#mri_convert $bids_root_dir/${subj}/anat/${subj}_T1w.nii $freesurfer_dir/${subj}/mri/orig/001.mgz
#mri_convert $bids_root_dir/${subj}/anat/${subj}_T1w.nii $freesurfer_dir/${subj}/mri/orig.mgz

#recon-all -s ${subj} -all -qcache -no-isrunning

#Make qsiprep directory and participant directory in derivatives folder
if [ ! -d $bids_root_dir_output/qsiprep/${subj} ]; then
    mkdir $bids_root_dir_output/qsiprep/${subj}
fi

if [ ! -d $bids_root_dir_output/qsiprep ]; then
    mkdir $bids_root_dir_output/qsiprep
fi

if [ ! -d $bids_root_dir_output/qsiprep/${subj} ]; then
    mkdir $bids_root_dir_output/qsiprep/${subj}
fi
if [ ! -d $bids_root_dir_output_wd4singularity/qsiprep ]; then  
    mkdir $bids_root_dir_output_wd4singularity/qsiprep
fi

if [ ! -d $bids_root_dir_output_wd4singularity/qsiprep/${subj} ]; then
    mkdir $bids_root_dir_output_wd4singularity/qsiprep/${subj}
fi


#Run qsiprep_prep
export SINGULARITYENV_TEMPLATEFLOW_HOME='/ibmgpfs/cuizaixu_lab/xuhaoshu/packages/templateflow'
unset PYTHONPATH; singularity run --cleanenv --bind $bids_root_dir \
    -B $bids_root_dir_output_wd4singularity/qsiprep/${subj}:/wd \
    -B $bids_root_dir:/inputbids \
    -B $bids_root_dir_output/qsiprep/${subj}:/output \
    -B $bids_root_dir_output/qsiprep:/recon_input \
    -B $freesurfer_dir:/freesurfer \
    -B $templateflow:/ibmgpfs/cuizaixu_lab/xuhaoshu/packages/templateflow \
    -B /ibmgpfs/cuizaixu_lab/xuhaoshu/packages/freesurfer_license:/freesurfer_license \
    /ibmgpfs/cuizaixu_lab/xuhaoshu/packages/singularity/qsiprep.sif \
    /inputbids /output \
    participant \
    --participant_label ${subj} \
    --unringing-method mrdegibbs \
    --output-resolution 1.8 \
    --skip-bids-validation \
    -w /wd \
    --verbose \
    --notrack \
    --nthreads $nthreads \
    --mem-mb 32000 \
    --fs-license-file /freesurfer_license/license.txt
