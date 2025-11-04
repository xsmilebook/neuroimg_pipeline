#!/usr/bin/env bash
set -euo pipefail

# Minimal wrapper to run FSL dtifit using eddy outputs.
# It reuses:
# - data:        <eddy_out>.nii[.gz]
# - mask:        <dirname(eddy_out)>/nodif_brain_mask.nii.gz (default, overridable)
# - bvecs:       <eddy_out>.eddy_rotated_bvecs (default, overridable)
# - bvals:       REQUIRED (-b). If omitted, tries <dirname>/bvals_flat.txt.
#
# Usage:
#   bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_dtifit.sh \
#     <eddy_output_basename> -b <bvals> [-m <mask>] [-r <bvecs>] [-o <out_basename>]
#
# Example:
#   bash .../run_dtifit.sh /mnt/e/.../dwi/eddy -b /mnt/e/.../dwi/sub-001_dir-PA_dwi.bval -o /mnt/e/.../dwi/dtifit

log() { echo "[INFO] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

resolve_nii() {
  local base=$1
  if [[ -f "${base}.nii.gz" ]]; then echo "${base}.nii.gz";
  elif [[ -f "${base}.nii" ]]; then echo "${base}.nii";
  else echo ""; fi
}

EDDY_OUT=""; BVALS=""; MASK_PATH=""; BVECS=""; OUT_BASE="";

if [[ $# -eq 0 ]]; then
  cat <<EOF
Usage: $(basename "$0") <eddy_output_basename> -b <bvals> [-m <mask>] [-r <bvecs>] [-o <out_basename>]
EOF
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--bvals) shift; BVALS="${1:-}" ;;
    -m|--mask)  shift; MASK_PATH="${1:-}" ;;
    -r|--bvecs) shift; BVECS="${1:-}" ;;
    -o|--out)   shift; OUT_BASE="${1:-}" ;;
    -h|--help)  shift || true; cat <<EOF
Usage: $(basename "$0") <eddy_output_basename> -b <bvals> [-m <mask>] [-r <bvecs>] [-o <out_basename>]
EOF
                 exit 0 ;;
    *)
      if [[ -z "$EDDY_OUT" ]]; then EDDY_OUT="$1"; else die "Unexpected argument: $1"; fi ;;
  esac
  shift || true
done

[[ -n "$EDDY_OUT" ]] || die "Missing <eddy_output_basename>"
need_cmd dtifit

DATA_IMG=$(resolve_nii "$EDDY_OUT")
[[ -n "$DATA_IMG" ]] || die "Eddy output image not found: ${EDDY_OUT}.nii(.gz)"

out_dir=$(dirname "$EDDY_OUT")
[[ -n "$MASK_PATH" ]] || MASK_PATH="${out_dir}/nodif_brain_mask.nii.gz"
[[ -n "$BVECS"     ]] || BVECS="${EDDY_OUT}.eddy_rotated_bvecs"
[[ -n "$OUT_BASE"  ]] || OUT_BASE="${out_dir}/dtifit"

# bvals required; try fallback if not provided
if [[ -z "$BVALS" ]]; then
  if [[ -f "${out_dir}/bvals_flat.txt" ]]; then
    BVALS="${out_dir}/bvals_flat.txt"
  else
    die "Missing -b <bvals>; no fallback found in ${out_dir}"
  fi
fi

[[ -f "$MASK_PATH" ]] || die "Mask not found: $MASK_PATH"
[[ -f "$BVECS"    ]] || die "Rotated bvecs not found: $BVECS"
[[ -f "$BVALS"    ]] || die "bvals not found: $BVALS"

log "Running dtifit"
CMD=(dtifit -k "$DATA_IMG" -o "$OUT_BASE" -m "$MASK_PATH" -r "$BVECS" -b "$BVALS")
log "Command: ${CMD[*]}"
"${CMD[@]}"

log "Done. DTIFIT outputs at: ${OUT_BASE}_* (FA, MD, L1/L2/L3, V1/V2/V3, etc.)"