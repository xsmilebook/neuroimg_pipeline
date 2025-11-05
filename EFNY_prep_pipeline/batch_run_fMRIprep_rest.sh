#! /bin/bash
for i in `cat sublist.txt`
do
sbatch -o ../log_fmripreprest/$i.out fMRIprep_rest.sh $i
done
