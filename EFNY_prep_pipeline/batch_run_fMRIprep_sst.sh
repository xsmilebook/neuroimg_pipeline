#! /bin/bash
for i in `cat sublist.txt`
do
sbatch -o /ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/THU/log/sst/$i.out fMRIprep_sst.sh $i
done
