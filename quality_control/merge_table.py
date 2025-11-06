#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
合并 QC_folder 下的多个 QC 表到一个总表：
- 以 `checkup_BIDS_EFI.csv` 的 `subj_ID` 为主键
- 其他表使用 `subject_name` 与之合并

合并并重命名的列：
1) CAS_anat_snr_all_251105.csv: T1w -> T1w_SNR, T2w -> T2w_SNR
2) thu_Diffusionheadmotion_THU251105.csv: mean_fd -> dwi_fd
3) Tsinghua_BOLDheadmotion_rest_run-1_summary.csv: mean_fd -> rest1_fd, good_data -> rest1_good
4) Tsinghua_BOLDheadmotion_rest_run-2_summary.csv: mean_fd -> rest2_fd, good_data -> rest2_good
5) Tsinghua_BOLDheadmotion_task-nback_summary.csv: mean_fd -> nback_fd, good_data -> nback_good
6) Tsinghua_BOLDheadmotion_task-sst_summary.csv: mean_fd -> sst_fd, good_data -> sst_good
7) Tsinghua_BOLDheadmotion_task-switch_summary.csv: mean_fd -> switch_fd, good_data -> switch_good

默认保存到 QC_folder 下 `EFI_QC_merged.csv`。
"""

from __future__ import annotations

import argparse
from pathlib import Path
import pandas as pd


def _read_csv(path: Path) -> pd.DataFrame:
    """统一读取 CSV，自动处理编码问题。"""
    return pd.read_csv(path)


def _prepare_subject_table(df: pd.DataFrame, keep_cols: list[str], rename_map: dict[str, str] | None = None) -> pd.DataFrame:
    """过滤掉汇总行、只保留需要的列并重命名。"""
    if 'subject_name' in df.columns:
        df = df[df['subject_name'].notna()]
        df = df[df['subject_name'] != 'SUM']
    # 仅保留需要的列
    cols = [c for c in keep_cols if c in df.columns]
    df = df[cols].copy()
    if rename_map:
        df = df.rename(columns=rename_map)
    return df


def merge_qc_tables(qc_dir: Path, output_path: Path) -> Path:
    # 基表：checkup
    base_path = qc_dir / 'checkup_BIDS_EFI.csv'
    base_df = _read_csv(base_path)
    if 'subj_ID' not in base_df.columns:
        raise ValueError('checkup_BIDS_EFI.csv 缺少 subj_ID 列')
    # 统一 key 名，避免 merge 时混淆
    base_df = base_df.copy()
    base_df['subj_ID'] = base_df['subj_ID'].astype(str)

    # 1) CAS_anat_snr
    snr_path = qc_dir / 'CAS_anat_snr_all_251105.csv'
    if snr_path.exists():
        snr_df = _read_csv(snr_path)
        snr_df = _prepare_subject_table(
            snr_df,
            keep_cols=['subject_name', 'T1w', 'T2w'],
            rename_map={'T1w': 'T1w_SNR', 'T2w': 'T2w_SNR'},
        )
        base_df = base_df.merge(snr_df, left_on='subj_ID', right_on='subject_name', how='left')
        base_df = base_df.drop(columns=['subject_name'])

    # 2) DWI FD
    dwi_path = qc_dir / 'thu_Diffusionheadmotion_THU251105.csv'
    if dwi_path.exists():
        dwi_df = _read_csv(dwi_path)
        dwi_df = _prepare_subject_table(
            dwi_df,
            keep_cols=['subject_name', 'mean_fd'],
            rename_map={'mean_fd': 'dwi_fd'},
        )
        base_df = base_df.merge(dwi_df, left_on='subj_ID', right_on='subject_name', how='left')
        base_df = base_df.drop(columns=['subject_name'])

    # 3) Rest run-1
    rest1_path = qc_dir / 'Tsinghua_BOLDheadmotion_rest_run-1_summary.csv'
    if rest1_path.exists():
        rest1_df = _read_csv(rest1_path)
        rest1_df = _prepare_subject_table(
            rest1_df,
            keep_cols=['subject_name', 'mean_fd', 'good_data'],
            rename_map={'mean_fd': 'rest1_fd', 'good_data': 'rest1_good'},
        )
        base_df = base_df.merge(rest1_df, left_on='subj_ID', right_on='subject_name', how='left')
        base_df = base_df.drop(columns=['subject_name'])

    # 4) Rest run-2
    rest2_path = qc_dir / 'Tsinghua_BOLDheadmotion_rest_run-2_summary.csv'
    if rest2_path.exists():
        rest2_df = _read_csv(rest2_path)
        rest2_df = _prepare_subject_table(
            rest2_df,
            keep_cols=['subject_name', 'mean_fd', 'good_data'],
            rename_map={'mean_fd': 'rest2_fd', 'good_data': 'rest2_good'},
        )
        base_df = base_df.merge(rest2_df, left_on='subj_ID', right_on='subject_name', how='left')
        base_df = base_df.drop(columns=['subject_name'])

    # 5) Task nback
    nback_path = qc_dir / 'Tsinghua_BOLDheadmotion_task-nback_summary.csv'
    if nback_path.exists():
        nback_df = _read_csv(nback_path)
        nback_df = _prepare_subject_table(
            nback_df,
            keep_cols=['subject_name', 'mean_fd', 'good_data'],
            rename_map={'mean_fd': 'nback_fd', 'good_data': 'nback_good'},
        )
        base_df = base_df.merge(nback_df, left_on='subj_ID', right_on='subject_name', how='left')
        base_df = base_df.drop(columns=['subject_name'])

    # 6) Task sst
    sst_path = qc_dir / 'Tsinghua_BOLDheadmotion_task-sst_summary.csv'
    if sst_path.exists():
        sst_df = _read_csv(sst_path)
        sst_df = _prepare_subject_table(
            sst_df,
            keep_cols=['subject_name', 'mean_fd', 'good_data'],
            rename_map={'mean_fd': 'sst_fd', 'good_data': 'sst_good'},
        )
        base_df = base_df.merge(sst_df, left_on='subj_ID', right_on='subject_name', how='left')
        base_df = base_df.drop(columns=['subject_name'])

    # 7) Task switch
    switch_path = qc_dir / 'Tsinghua_BOLDheadmotion_task-switch_summary.csv'
    if switch_path.exists():
        switch_df = _read_csv(switch_path)
        switch_df = _prepare_subject_table(
            switch_df,
            keep_cols=['subject_name', 'mean_fd', 'good_data'],
            rename_map={'mean_fd': 'switch_fd', 'good_data': 'switch_good'},
        )
        base_df = base_df.merge(switch_df, left_on='subj_ID', right_on='subject_name', how='left')
        base_df = base_df.drop(columns=['subject_name'])

    # 输出
    output_path.parent.mkdir(parents=True, exist_ok=True)
    base_df.to_csv(output_path, index=False)
    return output_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='合并 QC 表到一个总表')
    parser.add_argument(
        '--qc_dir',
        type=Path,
        default=Path(r'e:\projects\neuroimg_pipeline\datasets\EFNY\EFI\QC_folder'),
        help='QC_folder 目录路径'
    )
    parser.add_argument(
        '--output',
        type=Path,
        default=Path(r'e:\projects\neuroimg_pipeline\datasets\EFNY\EFI\QC_folder\EFI_QC_merged.csv'),
        help='合并后的输出 CSV 路径'
    )
    return parser.parse_args()


def main():
    args = parse_args()
    out = merge_qc_tables(args.qc_dir, args.output)
    print(f'合并完成，保存到: {out}')


if __name__ == '__main__':
    main()