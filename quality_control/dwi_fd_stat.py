#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import os
from pathlib import Path
from glob import glob
import pandas as pd

def find_subject_dirs(root_glob: str):
    """
    模仿 MATLAB: dir('/.../results/qsiprep/sub-*/qsiprep/sub-*')
    返回每个被试的路径 Path 对象
    """
    return [Path(p) for p in glob(root_glob) if Path(p).is_dir()]

def read_fd_from_confounds(confounds_path: Path) -> pd.Series:
    """
    从单个 confounds.tsv 读出 framewise_displacement 序列（跳过首行）
    处理 'n/a'、'' 等为缺失，并转为 float。返回 1: 末尾（0-based）的序列
    """
    # 以字符串读入，避免混型导致的解析问题
    df = pd.read_csv(confounds_path, sep='\t', dtype=str, low_memory=False)
    if 'framewise_displacement' not in df.columns:
        # 某些版本列名可能不同，给出友好提示并返回空序列
        return pd.Series(dtype='float64')

    s = df['framewise_displacement'].replace(
        {'n/a': pd.NA, 'N/A': pd.NA, 'NA': pd.NA, '': pd.NA}
    )
    s = pd.to_numeric(s, errors='coerce')  # 非数一律变 NaN
    # 跳过第一行（与 MATLAB 2:end 一致）
    return s.iloc[1:]

def mean_fd_for_subject(subject_dir: Path) -> float | None:
    """
    对一个被试，收集 dwi/*confounds.tsv（可能不止一个）
    将每个文件的 FD 均值再取平均，得到该被试的 mean FD
    若没有有效数据则返回 None
    """
    dwi_dir = subject_dir / 'dwi'
    confounds_files = sorted(dwi_dir.glob('*confounds.tsv'))
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

def main():
    parser = argparse.ArgumentParser(description='Compute head-motion (mean FD) report from QSIPrep confounds.')
    parser.add_argument(
        '--subjects-glob',
        default='/ibmgpfs/cuizaixu_lab/liyang/BrainProject25/EFI_data/results/qsiprep/sub-*/qsiprep/sub-*',
        help='Glob pattern for subject directories (default matches your MATLAB 代码)'
    )
    parser.add_argument(
        '--out-dir',
        default='/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/datasets/EFNY/EFI/QC_folder',
        help='输出 CSV 的目录'
    )
    parser.add_argument(
        '--out-filename',
        default='thu_Diffusionheadmotion_THU251105.csv',
        help='输出文件名（默认沿用你现在的命名）'
    )
    args = parser.parse_args()

    subject_dirs = find_subject_dirs(args.subjects_glob)
    rows = []
    for subj_dir in subject_dirs:
        subj_name = subj_dir.name
        mean_fd = mean_fd_for_subject(subj_dir)
        rows.append({'subject_name': subj_name, 'mean_fd': mean_fd})

    # 追加一行 'SUM'（与 MATLAB 脚本一致；保留空 mean_fd）
    rows.append({'subject_name': 'SUM', 'mean_fd': None})

    report = pd.DataFrame(rows, columns=['subject_name', 'mean_fd'])

    # 保存
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    out_csv = out_dir / args.out_filename
    report.to_csv(out_csv, index=False)
    print(f'Wrote: {out_csv}')

if __name__ == '__main__':
    main()
