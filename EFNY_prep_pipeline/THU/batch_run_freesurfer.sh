#!/bin/bash

for subj in `cat sublist.txt`
do
   sbatch -o /ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/THU/log/fs/${subj}_freesurfer.out freesurfer.sh $subj
done



