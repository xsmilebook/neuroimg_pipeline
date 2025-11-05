#! /bin/bash
for i in `cat sublist.txt`
do
sbatch -o ../log_fmriprepswitch/$i.out fMRIprep_switch.sh $i
done
