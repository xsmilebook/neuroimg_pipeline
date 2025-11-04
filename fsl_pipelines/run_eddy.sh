#!/usr/bin/env bash
set -euo pipefail

# Run FSL eddy using outputs from TOPUP.
# This script prepares brain mask from TOPUP iout (unwarped b0) and
# creates index.txt, then runs eddy (prefer eddy_openmp if available).
#
# Usage example (WSL):
#   bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_eddy.sh \
#     --dwi_nii /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/dwi/sub-001_dir-PA_dwi.nii \
#     --bvecs   /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/dwi/sub-001_dir-PA_dwi.bvec \
#     --bvals   /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/dwi/sub-001_dir-PA_dwi.bval \
#     --acqparams /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/fmap/fieldmap/acqparams.txt \
#     --topup_prefix /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/fmap/topup_results \
#     --iout     /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/fmap/unwarped_b0 \
#     --out      /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/dwi/sub-001_eddy
#
# Optional:
#   --mask <path to brain mask NIfTI> (if provided, skip mask generation)
#   --index <path to index.txt> (if provided, validate and reuse)
#   --index_row <int> acqparams row to use for all volumes (default: 1)
#   --data_is_shelled  Do not check that data is shelled (trust user)
#   --bet_frac <float> brain extraction fractional intensity threshold (default: 0.2)
#   --log_file <path> append logs to file
#
# Requires: eddy/eddy_openmp, fslmaths, bet, fslnvols, fslroi

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }
choose_eddy() { if command -v eddy_openmp >/dev/null 2>&1; then echo eddy_openmp; elif command -v eddy >/dev/null 2>&1; then echo eddy; else die "Missing FSL eddy/eddy_openmp"; fi; }

usage() { sed -n '1,120p' "$0" | sed 's/^# \{0,1\}//'; }
resolve_nii() {
  local base=$1
  if [[ -f "${base}.nii.gz" ]]; then echo "${base}.nii.gz"; elif [[ -f "${base}.nii" ]]; then echo "${base}.nii"; else echo ""; fi
}

# ------------------------- args -------------------------
DWI_NII=""; BVEC=""; BVAL=""; ACQPARAMS=""; TOPUP_PREFIX=""; IOUT_BASE=""
OUT_PREFIX=""; MASK_PATH=""; INDEX_PATH=""; LOG_FILE=""; BET_FRAC="0.2"; INDEX_ROW="1"; DATA_IS_SHELLED="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dwi_nii) shift; DWI_NII="${1:-}" ;;
    --bvecs)   shift; BVEC="${1:-}" ;;
    --bvals)   shift; BVAL="${1:-}" ;;
    --acqparams) shift; ACQPARAMS="${1:-}" ;;
    --topup_prefix) shift; TOPUP_PREFIX="${1:-}" ;;
    --iout)    shift; IOUT_BASE="${1:-}" ;;
    --out)     shift; OUT_PREFIX="${1:-}" ;;
    --mask)    shift; MASK_PATH="${1:-}" ;;
    --index)   shift; INDEX_PATH="${1:-}" ;;
    --index_row) shift; INDEX_ROW="${1:-}" ;;
    --data_is_shelled) DATA_IS_SHELLED="1" ;;
    --bet_frac) shift; BET_FRAC="${1:-}" ;;
    --log_file) shift; LOG_FILE="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true
done

if [[ -n "$LOG_FILE" ]]; then mkdir -p "$(dirname "$LOG_FILE")"; exec > >(tee -a "$LOG_FILE") 2>&1; fi

# ----------------------- validation ----------------------
[[ -n "$DWI_NII" ]] || die "Missing --dwi_nii"
[[ -n "$BVEC" ]]    || die "Missing --bvecs"
[[ -n "$BVAL" ]]    || die "Missing --bvals"
[[ -n "$ACQPARAMS" ]] || die "Missing --acqparams"
[[ -n "$TOPUP_PREFIX" ]] || die "Missing --topup_prefix"
[[ -n "$IOUT_BASE" ]] || die "Missing --iout (TOPUP iout prefix)"
[[ -n "$OUT_PREFIX" ]] || die "Missing --out"

[[ -f "$DWI_NII" ]] || die "DWI NIfTI not found: $DWI_NII"
[[ -f "$BVEC" ]]    || die "bvecs not found: $BVEC"
[[ -f "$BVAL" ]]    || die "bvals not found: $BVAL"
[[ -f "$ACQPARAMS" ]] || die "acqparams not found: $ACQPARAMS"

need_cmd fslmaths; need_cmd bet; need_cmd fslnvols; EDDY_CMD=$(choose_eddy); log "Using $EDDY_CMD"

# ensure output dirs
mkdir -p "$(dirname "$OUT_PREFIX")"

# -------------------- mask generation --------------------
IOUT_IMG=$(resolve_nii "$IOUT_BASE")
[[ -n "$IOUT_IMG" ]] || die "TOPUP iout image not found: ${IOUT_BASE}.nii(.gz)"

if [[ -z "$MASK_PATH" ]]; then
  NODIF_MEAN="$(dirname "$OUT_PREFIX")/nodif_mean"
  log "Generating mean b0 from TOPUP iout: $IOUT_IMG -> ${NODIF_MEAN}.nii.gz"
  fslmaths "$IOUT_IMG" -Tmean "$NODIF_MEAN"
  log "Creating brain mask with BET (frac=$BET_FRAC)"
  bet "$NODIF_MEAN" "$(dirname "$OUT_PREFIX")/nodif_brain" -m -f "$BET_FRAC"
  MASK_PATH="$(dirname "$OUT_PREFIX")/nodif_brain_mask.nii.gz"
fi
[[ -f "$MASK_PATH" ]] || die "Brain mask not found: $MASK_PATH"
log "Mask: $MASK_PATH"

# -------------------- index & vectors -------------------
DWI_VOL=$(fslnvols "$DWI_NII")
[[ "$DWI_VOL" =~ ^[0-9]+$ ]] || die "Cannot determine DWI volumes"

# Validate bvals/bvecs shape and consistency
BVAL_TOKENS=$(awk '{for(i=1;i<=NF;i++) c++} END{print c+0}' "$BVAL")
if [[ "$BVAL_TOKENS" -ne "$DWI_VOL" ]]; then
  log "bvals tokens ($BVAL_TOKENS) != DWI volumes ($DWI_VOL); flattening to single-line"
  BVAL_FLAT="$(dirname "$OUT_PREFIX")/bvals_flat.txt"
  paste -sd ' ' "$BVAL" > "$BVAL_FLAT"
  BVAL="$BVAL_FLAT"
  BVAL_TOKENS=$(awk '{for(i=1;i<=NF;i++) c++} END{print c+0}' "$BVAL")
  [[ "$BVAL_TOKENS" -eq "$DWI_VOL" ]] || die "bvals still mismatched after flatten: $BVAL_TOKENS != $DWI_VOL"
fi
NZ_COUNT=$(awk '{for(i=1;i<=NF;i++) if($i+0>0) nz++} END{print nz+0}' "$BVAL")
[[ "$NZ_COUNT" -ge 1 ]] || die "bvals contain no non-zero entries; eddy requires at least one non-zero shell"

# Ensure bvecs has 3 rows and matches volume count
BVECS_ROWS=$(awk 'END{print NR+0}' "$BVEC")
BVECS_COLS=$(awk 'NR==1{print NF+0}' "$BVEC")
if [[ "$BVECS_ROWS" -ne 3 ]]; then
  log "bvecs has $BVECS_ROWS rows; expecting 3. Attempting to convert to 3-row format."
  tmp_bvec="$(dirname "$OUT_PREFIX")/bvecs_3row.txt"
  awk '
    {row1[NR]=$1; row2[NR]=$2; row3[NR]=$3}
    END{
      for(i=1;i<=NR;i++){printf "%s%s", row1[i], (i<NR?" ":"\n")}
      for(i=1;i<=NR;i++){printf "%s%s", row2[i], (i<NR?" ":"\n")}
      for(i=1;i<=NR;i++){printf "%s%s", row3[i], (i<NR?" ":"\n")}
    }' "$BVEC" > "$tmp_bvec" || die "Failed to transpose bvecs to 3-row format"
  BVEC="$tmp_bvec"
  BVECS_ROWS=3
  BVECS_COLS=$(awk 'NR==1{print NF+0}' "$BVEC")
fi
[[ "$BVECS_COLS" -eq "$DWI_VOL" ]] || die "bvecs columns ($BVECS_COLS) != DWI volumes ($DWI_VOL)"

# -------------------- index generation -------------------
if [[ -z "$INDEX_PATH" ]]; then INDEX_PATH="$(dirname "$OUT_PREFIX")/index.txt"; fi
ACQ_LINES=$(awk 'NF>0{c++} END{print c+0}' "$ACQPARAMS")
# validate INDEX_ROW
[[ "$INDEX_ROW" =~ ^[0-9]+$ ]] || die "--index_row must be an integer"
[[ "$INDEX_ROW" -ge 1 && "$INDEX_ROW" -le "$ACQ_LINES" ]] || die "--index_row ($INDEX_ROW) must be between 1 and $ACQ_LINES"
log "Creating index row $INDEX_ROW for $DWI_VOL volumes: $INDEX_PATH"
{
  idx=""; for ((i=1;i<=DWI_VOL;i++)); do idx+=" $INDEX_ROW"; done; echo "${idx# }";
} > "$INDEX_PATH"

# quick check: acqparams rows >= max(index value) and index tokens == volumes
TOKENS=$(awk '{print NF+0}' "$INDEX_PATH")
log "acqparams rows: $ACQ_LINES | index tokens: $TOKENS"
[[ "$TOKENS" -eq "$DWI_VOL" ]] || die "index tokens ($TOKENS) != DWI volumes ($DWI_VOL)"

# ------------------------- run eddy -----------------------
log "Running eddy"
CMD=("$EDDY_CMD" \
  "--imain=$DWI_NII" \
  "--mask=$MASK_PATH" \
  "--acqp=$ACQPARAMS" \
  "--index=$INDEX_PATH" \
  "--bvecs=$BVEC" \
  "--bvals=$BVAL" \
  "--topup=$TOPUP_PREFIX" \
  "--out=$OUT_PREFIX")
# add optional flags
if [[ "$DATA_IS_SHELLED" == "1" ]]; then
  CMD+=("--data_is_shelled")
fi
log "Command: ${CMD[*]}"
"${CMD[@]}"

OUT_IMG=$(resolve_nii "$OUT_PREFIX")
[[ -n "$OUT_IMG" ]] || die "Eddy output not found: ${OUT_PREFIX}.nii(.gz)"

log "Done. Eddy output: $OUT_IMG"