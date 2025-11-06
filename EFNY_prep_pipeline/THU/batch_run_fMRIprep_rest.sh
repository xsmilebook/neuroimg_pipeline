#! /bin/bash
for i in `cat sublist.txt`
do
sbatch -o /ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/THU/log/rest/$i.out fMRIprep_rest.sh $i
done
