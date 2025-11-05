#!/bin/bash
#SBATCH --job-name=BIDS
#SBATCH --partition=q_fat
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4

# 批量将 /ibmgpfs/.../NIFTI 下的每个 subject 目录转换为 BIDS 文件夹结构
# 依次调用 e:\projects\neuroimg_pipeline\src\nifti2bids\nifti2bids.py 脚本
#
# 使用：
#   sbatch src/nifti2bids/run_nifti2bids.sh
# 参数固定于脚本顶部变量，无需额外输入。

set -euo pipefail

# 固定参数：无需命令行输入，按需修改以下变量
NIFTI_ROOT="/ibmgpfs/cuizaixu_lab/xuhaoshu/cuilab_folder/BP_QC_folder/raw_data/NIFTI"
BIDS_ROOT="/ibmgpfs/cuizaixu_lab/xuhaoshu/cuilab_folder/BP_QC_folder/EFI_240830/BIDS"
# Python 转换脚本路径（脚本会自动选择存在的路径）
PY_SCRIPT_LNX="/ibmgpfs/cuizaixu_lab/xuhaoshu/code/neuroimg_pipeline/src/nifti2bids/nifti2bids.py"
PY_SCRIPT_WIN='e:\\projects\\neuroimg_pipeline\\src\\nifti2bids\\nifti2bids.py'
DRY_RUN=false

# 选择 Python 解释器
if command -v python >/dev/null 2>&1; then
  PYCMD=python
elif command -v python3 >/dev/null 2>&1; then
  PYCMD=python3
else
  echo "ERROR: 未检测到 python 或 python3。" >&2
  exit 1
fi

# 选择转换脚本路径
if [[ -f "$PY_SCRIPT_LNX" ]]; then
  PY_SCRIPT="$PY_SCRIPT_LNX"
elif [[ -f "$PY_SCRIPT_WIN" ]]; then
  PY_SCRIPT="$PY_SCRIPT_WIN"
else
  echo "ERROR: 未找到转换脚本：$PY_SCRIPT_LNX 或 $PY_SCRIPT_WIN" >&2
  exit 1
fi

SUBLIST_FILE="$NIFTI_ROOT/sublist.txt"
if [[ ! -f "$SUBLIST_FILE" ]]; then
  echo "ERROR: 未找到 sublist.txt: $SUBLIST_FILE" >&2
  exit 1
fi

echo "Batch converting subjects listed in: $SUBLIST_FILE"
echo "Using converter: $PY_SCRIPT"
echo "Output root: $BIDS_ROOT"
[[ "$DRY_RUN" == true ]] && echo "Mode: DRY-RUN (不实际复制)" || echo "Mode: COPY"

TOTAL=0
SUCCESS=0
FAILED=0

while IFS= read -r line || [[ -n "$line" ]]; do
  # 去除回车和首尾空白
  subject=$(echo "$line" | tr -d '\r' | sed 's/^\s\+//;s/\s\+$//')
  # 跳过空行和注释
  [[ -z "$subject" ]] && continue
  [[ "$subject" =~ ^# ]] && continue

  TOTAL=$((TOTAL+1))
  SRC_DIR="$NIFTI_ROOT/$subject"
  OUT_DIR="$BIDS_ROOT/$subject"

  if [[ ! -d "$SRC_DIR" ]]; then
    echo "[SKIP] 源目录不存在: $SRC_DIR"
    FAILED=$((FAILED+1))
    continue
  fi

  mkdir -p "$OUT_DIR"
  echo "[RUN] subject=$subject | src=$SRC_DIR -> out=$OUT_DIR"

  if [[ "$DRY_RUN" == true ]]; then
    if "$PYCMD" "$PY_SCRIPT" --src-dir "$SRC_DIR" --out-dir "$OUT_DIR" --dry-run; then
      SUCCESS=$((SUCCESS+1))
    else
      echo "[ERROR] 转换失败: $subject" >&2
      FAILED=$((FAILED+1))
    fi
  else
    if "$PYCMD" "$PY_SCRIPT" --src-dir "$SRC_DIR" --out-dir "$OUT_DIR"; then
      SUCCESS=$((SUCCESS+1))
    else
      echo "[ERROR] 转换失败: $subject" >&2
      FAILED=$((FAILED+1))
    fi
  fi
done < "$SUBLIST_FILE"

echo "完成。总计: $TOTAL, 成功: $SUCCESS, 失败: $FAILED"