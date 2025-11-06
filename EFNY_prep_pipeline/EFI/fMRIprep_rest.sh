#!/bin/bash
#SBATCH --job-name=EFI_rest
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=8
#SBATCH -p q_fat

module load singularity/3.7.0
#!/bin/bash
#User inputs:
BidsDir=/ibmgpfs/cuizaixu_lab/liyang/BrainProject25/EFI_data/BIDS
wd=/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/EFI/wd/rest
output=/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/EFI/results
fs_license=/ibmgpfs/cuizaixu_lab/xuhaoshu/packages/freesurfer_license
templateflow=/ibmgpfs/cuizaixu_lab/xuhaoshu/packages/templateflow
fs_dir=/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/EFI/freesurfer

subj=$1
nthreads=40
#Run fmriprep
echo ""
echo "Running fmriprep on participant: $subj"
echo ""

#mkdir
if [ ! -d $wd/fmriprep_rest ]; then
mkdir $wd/fmriprep_rest
fi
if [ ! -d $wd/fmriprep_rest/${subj} ]; then
mkdir $wd/fmriprep_rest/${subj}
fi
if [ ! -d $output/fmriprep_rest ]; then
mkdir $output/fmriprep_rest
fi
if [ ! -d $output/fmriprep_rest/${subj} ]; then
mkdir $output/fmriprep_rest/${subj}
fi

#Run fmriprep
export SINGULARITYENV_TEMPLATEFLOW_HOME=$templateflow
unset PYTHONPATH; singularity run --cleanenv \
    -B $wd/fmriprep_rest/${subj}:/wd \
    -B $BidsDir:/BIDS \
    -B $output/fmriprep_rest/${subj}:/output \
    -B $fs_license:/fs_license \
    -B $fs_dir:/fs_dir \
    -B $templateflow:/ibmgpfs/cuizaixu_lab/xuhaoshu/packages/templateflow \
    /usr/nzx-cluster/apps/fmriprep/singularity/fmriprep-20.2.1.simg \
    /BIDS /output participant \
    --participant_label ${subj} -w /wd \
    --task-id rest \
    --fs-subjects-dir /fs_dir \
    --fs-license-file /fs_license/license.txt \
    --output-spaces T1w MNI152NLin2009cAsym MNI152NLin6Asym fsLR fsaverage \
    --return-all-components \
    --notrack --verbose \
    --ignore slicetiming \
    --bids-filter-file /ibmgpfs/cuizaixu_lab/xuhaoshu/QC_folder/batchcode/bidsfilter_func.json \
    --skip-bids-validation \
    --debug all \
    --stop-on-first-crash \
    --resource-monitor \
    --cifti-output 91k \
    --use-aroma
