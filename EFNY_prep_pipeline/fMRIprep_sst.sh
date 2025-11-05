#!/bin/bash
#SBATCH -J sst
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=8
#SBATCH --mem-per-cpu 20gb
#SBATCH -p q_fat_c
#SBATCH -q high_c


module load singularity/3.7.0
#!/bin/bash
#User inputs:
BidsDir=/ibmgpfs/cuizaixu_lab/xuhaoshu/QC_folder/BIDS
wd=/ibmgpfs/cuizaixu_lab/xuhaoshu/QC_folder/wd
output=/ibmgpfs/cuizaixu_lab/xuhaoshu/QC_folder/results
fs_license=/ibmgpfs/cuizaixu_lab/xuhaoshu/freesurfer_license
templateflow=/ibmgpfs/cuizaixu_lab/xuhaoshu/packages/templateflow
fs_dir=/ibmgpfs/cuizaixu_lab/xuhaoshu/QC_folder/freesurfer
subj=$1
nthreads=40
#Run fmriprep
echo ""
echo "Running fmriprep on participant: $subj"
echo ""

#mkdir
if [ ! -d $wd/fmriprep_sst ]; then
mkdir $wd/fmriprep_sst
fi
if [ ! -d $wd/fmriprep_sst/${subj} ]; then
mkdir $wd/fmriprep_sst/${subj}
fi
if [ ! -d $output/fmriprep_sst ]; then
mkdir $output/fmriprep_sst
fi
if [ ! -d $output/fmriprep_sst/${subj} ]; then
mkdir $output/fmriprep_sst/${subj}
fi

#Run fmriprep
export SINGULARITYENV_TEMPLATEFLOW_HOME='/ibmgpfs/cuizaixu_lab/xuhaoshu/packages/templateflow'
unset PYTHONPATH; singularity run --cleanenv \
    -B $wd/fmriprep_sst/${subj}:/wd \
    -B $BidsDir:/BIDS \
    -B $output/fmriprep_sst/${subj}:/output \
    -B $fs_license:/fs_license \
    -B $fs_dir:/fs_dir \
    -B $templateflow:/ibmgpfs/cuizaixu_lab/xuhaoshu/packages/templateflow \
    /usr/nzx-cluster/apps/fmriprep/singularity/fmriprep-20.2.1.simg \
    /BIDS /output participant \
    --participant_label ${subj} -w /wd \
    --task-id sst \
    --fs-subjects-dir /fs_dir \
    --fs-license-file /fs_license/license.txt \
    --output-spaces T1w MNI152NLin2009cAsym MNI152NLin6Asym fsLR fsaverage \
    --return-all-components \
    --notrack --verbose \
    --ignore slicetiming \
    --skip-bids-validation \
    --debug all \
    --stop-on-first-crash \
    --resource-monitor \
    --cifti-output 91k \
    --use-aroma
