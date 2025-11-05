#! /bin/bash
for i in `cat sublist.txt`
do
sbatch -o ../log_fmriprepsst/$i.out fMRIprep_sst.sh $i
done
