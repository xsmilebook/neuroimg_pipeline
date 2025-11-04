#!/usr/bin/env bash
set -euo pipefail

# Minimal wrapper to run FSL eddy_quad for QC, reusing files from prior eddy.
#
# Usage:
#   bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_eddy_qc.sh \
#     <eddy_output_basename> -idx <index.txt> -par <acqparams.txt> -m <nodif_mask.nii.gz> -b <bvals>
#
# Notes:
# - If -idx or -m are omitted, defaults will be inferred from the directory of <eddy_output_basename>:
#     -idx  -> <dirname(eddy_out)>/index.txt
#     -m    -> <dirname(eddy_out)>/nodif_brain_mask.nii.gz
# - -par and -b are required.
# - <eddy_output_basename> should be the same basename used for eddy's --out.

log() { echo "[INFO] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

resolve_nii() {
  local base=$1
  if [[ -f "${base}.nii.gz" ]]; then echo "${base}.nii.gz";
  elif [[ -f "${base}.nii" ]]; then echo "${base}.nii";
  else echo ""; fi
}

EDDY_OUT=""; INDEX_PATH=""; ACQPARAMS=""; MASK_PATH=""; BVALS="";

if [[ $# -eq 0 ]]; then
  cat <<EOF
Usage: $(basename "$0") <eddy_output_basename> -idx <index.txt> -par <acqparams.txt> -m <nodif_mask.nii.gz> -b <bvals>
EOF
  exit 1
fi

# Parse: positional basename + flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -idx|--index)      shift; INDEX_PATH="${1:-}" ;;
    -par|--acqparams)  shift; ACQPARAMS="${1:-}" ;;
    -m|--mask)         shift; MASK_PATH="${1:-}" ;;
    -b|--bvals)        shift; BVALS="${1:-}" ;;
    -h|--help)         shift || true; cat <<EOF
Usage: $(basename "$0") <eddy_output_basename> -idx <index.txt> -par <acqparams.txt> -m <nodif_mask.nii.gz> -b <bvals>
EOF
                        exit 0 ;;
    *)
      if [[ -z "$EDDY_OUT" ]]; then EDDY_OUT="$1"; else die "Unexpected argument: $1"; fi ;;
  esac
  shift || true
done

[[ -n "$EDDY_OUT" ]] || die "Missing <eddy_output_basename>"
need_cmd eddy_quad

# Verify eddy output exists (nii)
EDDY_IMG=$(resolve_nii "$EDDY_OUT")
[[ -n "$EDDY_IMG" ]] || die "Eddy output image not found: ${EDDY_OUT}.nii(.gz)"

out_dir=$(dirname "$EDDY_OUT")
[[ -n "$INDEX_PATH" ]] || INDEX_PATH="${out_dir}/index.txt"
[[ -n "$MASK_PATH"  ]] || MASK_PATH="${out_dir}/nodif_brain_mask.nii.gz"

[[ -f "$INDEX_PATH" ]] || die "index.txt not found: $INDEX_PATH"
[[ -f "$MASK_PATH"  ]] || die "Mask not found: $MASK_PATH"
[[ -n "$ACQPARAMS" ]]   || die "Missing -par <acqparams.txt>"
[[ -n "$BVALS"    ]]    || die "Missing -b <bvals>"
[[ -f "$ACQPARAMS" ]] || die "acqparams not found: $ACQPARAMS"
[[ -f "$BVALS"    ]] || die "bvals not found: $BVALS"

log "Running eddy_quad"
CMD=(eddy_quad "$EDDY_OUT" -idx "$INDEX_PATH" -par "$ACQPARAMS" -m "$MASK_PATH" -b "$BVALS")
log "Command: ${CMD[*]}"
"${CMD[@]}"

log "Done. QC outputs written next to: $EDDY_OUT"