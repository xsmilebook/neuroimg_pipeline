#!/bin/bash
#SBATCH --job-name=rest
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=8
#SBATCH --mem-per-cpu 20gb
#SBATCH -p q_fat_c
#SBATCH -q high

module load singularity/3.7.0
#!/bin/bash
#User inputs:
BidsDir=/ibmgpfs/cuizaixu_lab/tanlirou1/Tsinghua/BIDS
wd=/home/cuizaixu_lab/xuhaoshu/DATA_C/brainproject_prep_proc/QC_folder/wd
output=/home/cuizaixu_lab/xuhaoshu/DATA_C/brainproject_prep_proc/QC_folder/results
fs_license=/home/cuizaixu_lab/xuhaoshu/DATA_C/scripts/freesurfer_license
fs_dir=/ibmgpfs/cuizaixu_lab/tanlirou1/Tsinghua/freesurfer
templateflow=/home/cuizaixu_lab/xuhaoshu/DATA_C/packages/templateflow
bidsfilter=/home/cuizaixu_lab/xuhaoshu/DATA_C/brainproject_prep_proc/QC_folder/batchcode
echo $bidsfilter
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
    -B $bidsfilter:/bidsfilter \
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
