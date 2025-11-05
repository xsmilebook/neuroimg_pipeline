#! /bin/bash
for i in `cat sublist.txt`
do
sbatch -o ../log_fmriprepnback/$i.out fMRIprep_nback.sh $i
done
