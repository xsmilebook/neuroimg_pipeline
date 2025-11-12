#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import os
from pathlib import Path
from glob import glob
import pandas as pd

def find_subject_dirs(root_glob: str):
    """
    模仿 MATLAB: dir('/.../results/fmriprep/sub-*/fmriprep/sub-*')
    返回每个被试的路径 Path 对象
    """
    return [Path(p) for p in glob(root_glob) if Path(p).is_dir()]

def read_fd_from_confounds(confounds_path: Path) -> pd.Series:
    """
    从单个 confounds.tsv 读出 rmsd 序列（跳过首行）
    处理 'n/a'、'' 等为缺失，并转为 float。返回 1: 末尾（0-based）的序列
    """
    # 以字符串读入，避免混型导致的解析问题
    df = pd.read_csv(confounds_path, sep='\t', dtype=str, low_memory=False)
    if 'rmsd' not in df.columns:
        # 某些版本列名可能不同，给出友好提示并返回空序列
        return pd.Series(dtype='float64')

    s = df['rmsd'].replace(
        {'n/a': pd.NA, 'N/A': pd.NA, 'NA': pd.NA, '': pd.NA}
    )
    s = pd.to_numeric(s, errors='coerce')  # 非数一律变 NaN
    # 跳过第一行（与 MATLAB 2:end 一致）
    return s.iloc[1:]

def mean_fd_for_subject(subject_dir: Path, taskID: str, runID: str = '') -> float | None:
    """
    对一个被试，收集 func/*task-xxx*desc-confounds_timeseries.tsv（可能不止一个）
    将每个文件的 FD 均值再取平均，得到该被试的 mean FD
    若没有有效数据则返回 None
    """
    func_dir = subject_dir / 'func'
    task_glob = f'*{taskID}*desc-confounds_timeseries.tsv'
    if runID:
        task_glob = f'*{taskID}*{runID}*desc-confounds_timeseries.tsv'

    confounds_files = sorted(func_dir.glob(task_glob))
    if not confounds_files:
        return None

    per_file_means = []
    for f in confounds_files:
        s = read_fd_from_confounds(f)
        if s.size == 0:
            continue
        m = s.mean(skipna=True)
        if pd.notna(m):
            per_file_means.append(m)

    if len(per_file_means) == 0:
        return None
    return float(pd.Series(per_file_means).mean())

def f_headmotion_Jenkinson(fMRIprep_subjDir, taskID, runID, threshold_meanfd, threshold_framefd, frameNum_threshould, threshold_framefdmax):
    headmotion_report = []
    gooddata = []
    ifoutlier_meanfd = []
    ifoutlier_fdframeNum = []
    ifoutlier_maxfd = []
    
    for SN, subj_dir in enumerate(fMRIprep_subjDir):
        if subj_dir.is_dir():
            subjName = subj_dir.name
            meanfd = mean_fd_for_subject(subj_dir, taskID, runID)

            if meanfd is None:
                continue
            
            # Assume 'rmsd' columns in confounds files
            confounds_file = sorted(subj_dir.glob(f'func/*{taskID}*desc-confounds_timeseries.tsv'))[0]
            confd_tsv = pd.read_csv(confounds_file, sep='\t')

            rmse_timeseries = pd.to_numeric(confd_tsv['rmsd'], errors='coerce')
            rmse_timeseries = rmse_timeseries[1:]  # Skip the first frame as MATLAB does (2:end)
            
            outlier_count = (rmse_timeseries >= threshold_framefd).sum()
            outlier_count_max = (rmse_timeseries >= threshold_framefdmax).sum()

            if outlier_count_max != 0:
                ifoutlier_maxfd.append(True)
            else:
                ifoutlier_maxfd.append(False)

            if meanfd >= threshold_meanfd:
                ifoutlier_meanfd.append(True)
            else:
                ifoutlier_meanfd.append(False)

            if outlier_count >= frameNum_threshould:
                ifoutlier_fdframeNum.append(True)
            else:
                ifoutlier_fdframeNum.append(False)

            gooddata.append(not (ifoutlier_meanfd[-1] or ifoutlier_fdframeNum[-1] or ifoutlier_maxfd[-1]))

            # Collect the data for this subject
            headmotion_report.append({
                'subject_name': subjName,
                'mean_fd': meanfd,
                'good_data': gooddata[-1],
                'if_meanfd_outlier': ifoutlier_meanfd[-1],
                'if_fdframeNum_outlier': ifoutlier_fdframeNum[-1],
                'if_meanfd_max': ifoutlier_maxfd[-1],
                'threshold_mean_fd': threshold_meanfd,
                'threshold_fd_frame': threshold_framefd,
                'outlier_framecount': outlier_count,
                'threshould_fdframeNum': frameNum_threshould,
            })

    # Add summary row
    headmotion_report.append({
        'subject_name': 'SUM',
        'mean_fd': None,
        'good_data': sum(gooddata),
        'if_meanfd_outlier': sum(ifoutlier_meanfd),
        'if_fdframeNum_outlier': sum(ifoutlier_fdframeNum),
        'if_meanfd_max': sum(ifoutlier_maxfd),
        'threshold_mean_fd': threshold_meanfd,
        'threshold_fd_frame': threshold_framefd,
        'outlier_framecount': None,
        'threshould_fdframeNum': frameNum_threshould,
    })

    # Save the file
    output_floder = '/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/THU/QC_folder'
    output_file = os.path.join(output_floder, f'Tsinghua_BOLDheadmotion_{taskID}_summary.csv')

    df_report = pd.DataFrame(headmotion_report)
    df_report.to_csv(output_file, index=False)
    print(f'Report saved to: {output_file}')

def main():
    parser = argparse.ArgumentParser(description='Compute head-motion (mean FD) report for different tasks.')
    parser.add_argument(
        '--threshold-meanfd',
        type=float,
        default=0.2,
        help='Mean framewise displacement threshold'
    )
    parser.add_argument(
        '--threshold-framefd',
        type=float,
        default=0.2,
        help='Framewise displacement threshold'
    )
    parser.add_argument(
        '--frame-num-threshould',
        type=int,
        default=20,
        help='Number of frames threshold'
    )
    parser.add_argument(
        '--threshold-framefdmax',
        type=float,
        default=3,
        help='Maximum framewise displacement threshold'
    )
    args = parser.parse_args()

    # 处理不同任务的路径
    task_paths = {
        'task-switch': '/ibmgpfs/cuizaixu_lab/liyang/BrainProject25/Tsinghua_data/results/fmriprep_switch/sub-*/fmriprep/sub-*',
        'task-sst': '/ibmgpfs/cuizaixu_lab/liyang/BrainProject25/Tsinghua_data/results/fmriprep_sst/sub-*/fmriprep/sub-*',
        'task-nback': '/ibmgpfs/cuizaixu_lab/liyang/BrainProject25/Tsinghua_data/results/fmriprep_nback/sub-*/fmriprep/sub-*'
    }

    for taskID, path_pattern in task_paths.items():
        subject_dirs = find_subject_dirs(path_pattern)
        f_headmotion_Jenkinson(
            fMRIprep_subjDir=subject_dirs,
            taskID=taskID,
            runID='',
            threshold_meanfd=args.threshold_meanfd,
            threshold_framefd=args.threshold_framefd,
            frameNum_threshould=args.frame_num_threshould,
            threshold_framefdmax=args.threshold_framefdmax
        )

if __name__ == '__main__':
    main()
