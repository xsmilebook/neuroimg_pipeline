#! /bin/bash
for i in `cat sublist.txt`
do
sbatch -o ../log_qsiprep/$i.out qsiprep_only.sh $i
done