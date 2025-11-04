# FSL dMRI 预处理 Shell 管线（WSL）

该管线将现有的 Python FSL 流程改写为 Bash 脚本，便于在 WSL 中直接运行。逻辑与原流程一致：从 DWI 提取 b0 -> 与反向相位编码的 EPI 合并 -> 生成 acqparams -> 运行 TOPUP -> 基于 unwarped b0 生成脑掩膜 -> 运行 eddy。

## 目录与命名要求
- BIDS 根目录默认：`/mnt/e/projects/neuroimg_pipeline/datasets/BIDS`
- 需要以下文件（每个受试者）：
  - DWI：`dwi/<subj>_dir-PA_dwi.nii[.gz]`, `dwi/<subj>_dir-PA_dwi.bvec`, `dwi/<subj>_dir-PA_dwi.bval`, `dwi/<subj>_dir-PA_dwi.json`
  - 反向 EPI（用于 TOPUP）：`fmap/<subj>_acq-dwi_dir-AP_epi.nii[.gz]`, `fmap/<subj>_acq-dwi_dir-AP_epi.json`
- 输出位置：`BIDS/derivatives/fsl/<subj>/{dwi,fmap}`

## 依赖
- FSL：`fslroi`, `fslmerge`, `topup`, `bet`, `eddy` 或 `eddy_openmp`
- `jq`：解析 JSON 元数据

## 运行示例（WSL）
- 处理单个受试者：
```bash
bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_topup_eddy.sh \
  --bids_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS \
  --subject sub-001
```

- 批量处理所有 `sub-*`：
```bash
bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_topup_eddy.sh \
  --bids_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS \
  --subject all
```

## 说明与可配置项
- `acqparams.txt` 的两行按合并顺序生成：第一行为 DWI 的 PA，第二行为 EPI 的 AP；每行格式：`i j k TotalReadoutTime`，其中 `i/j/k` 根据 `PhaseEncodingDirection` 自动映射。
- 如果 `TotalReadoutTime` 缺失，脚本会用 `EffectiveEchoSpacing * (ReconMatrixPE - 1)` 回退计算。
- TOPUP 配置默认使用 `b02b0.cnf`；如未找到可通过环境变量覆盖：
  - `export TOPUP_CONFIG=$FSLDIR/etc/flirtsch/b02b0.cnf`
- `eddy` 优先使用 `eddy_openmp`（若存在），否则使用 `eddy`。

## 产出文件示例
- `derivatives/fsl/<subj>/fmap/topup_results*`
- `derivatives/fsl/<subj>/fmap/unwarped_b0.nii.gz`
- `derivatives/fsl/<subj>/fmap/fieldmap_hz.nii.gz`
- `derivatives/fsl/<subj>/dwi/nodif_brain_mask.nii.gz`
- `derivatives/fsl/<subj>/dwi/<subj>_eddy.nii.gz`

## 常见问题
- 若提示缺少命令，请在 WSL 中安装 FSL，并确保命令在 `PATH` 中；`jq` 可通过 `sudo apt-get install jq` 安装。
- 如数据命名不采用 `dir-PA`/`dir-AP` 约定，可按脚本里的命名规则调整对应文件定位逻辑。