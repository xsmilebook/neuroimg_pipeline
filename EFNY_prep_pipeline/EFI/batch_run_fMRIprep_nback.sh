#! /bin/bash
for i in `cat sublist.txt`
do
sbatch -o /ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/THU/log/nback/$i.out fMRIprep_nback.sh $i
done
