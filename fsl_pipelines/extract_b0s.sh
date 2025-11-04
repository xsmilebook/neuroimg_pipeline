#!/usr/bin/env bash
set -euo pipefail

# Extract N b=0 volumes from an input DWI NIfTI using its .bval file.
# Intended for WSL; uses FSL tools. Maintains BIDS-friendly naming.
#
# Usage:
#   bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/extract_b0s.sh \
#     --in_nii /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/dwi/sub-001_dir-PA_dwi.nii \
#     --in_bval /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/dwi/sub-001_dir-PA_dwi.bval \
#     --out_nii /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/fmap/sub-001_acq-dwi_dir-AP_epi.nii \
#     --num_b0 5
#
# Options:
#   --in_nii       Path to input NIfTI (e.g., .../dwi/sub-XXX_dir-PA_dwi.nii)
#   --in_bval      Path to .bval file   (e.g., .../dwi/sub-XXX_dir-PA_dwi.bval)
#   --out_nii      Path to output NIfTI (e.g., .../fmap/sub-XXX_acq-dwi_dir-AP_epi.nii)
#   --num_b0       Number of b=0 volumes to extract (default: 5)
#   --threshold    Numeric tolerance; treat |b|<=threshold as b=0 (default: 0)
#   --log_file     Log file path (append); stdout only if not set
#   -h, --help     Show help
#
# Requires: fslselectvols, fslnvols (FSL)

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

usage() {
  sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'
}

IN_NII=""
IN_BVAL=""
OUT_NII=""
NUM_B0=5
THRESHOLD=0
LOG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in_nii)      shift; IN_NII="${1:-}" ;;
    --in_bval)     shift; IN_BVAL="${1:-}" ;;
    --out_nii)     shift; OUT_NII="${1:-}" ;;
    --num_b0)      shift; NUM_B0="${1:-}" ;;
    --threshold)   shift; THRESHOLD="${1:-}" ;;
    --log_file)    shift; LOG_FILE="${1:-}" ;;
    -h|--help)     usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true

done

if [[ -n "$LOG_FILE" ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

[[ -n "$IN_NII" ]]  || die "Missing --in_nii"
[[ -n "$IN_BVAL" ]] || die "Missing --in_bval"
[[ -n "$OUT_NII" ]] || die "Missing --out_nii"
[[ -f "$IN_NII" ]]  || die "Input NIfTI not found: $IN_NII"
[[ -f "$IN_BVAL" ]] || die "bval file not found: $IN_BVAL"
[[ "$NUM_B0" =~ ^[0-9]+$ ]] || die "--num_b0 must be an integer"
[[ "$THRESHOLD" =~ ^[0-9]+(\.[0-9]+)?$ ]] || die "--threshold must be numeric"

need_cmd fslselectvols
need_cmd fslnvols

log "Input NIfTI: $IN_NII"
log "Input bval:  $IN_BVAL"
log "Output NIfTI: $OUT_NII"
log "Num b0 to extract: $NUM_B0; threshold: $THRESHOLD"

# Parse b=0 indices (0-based) across possibly multiple lines in bval
mapfile -t B0_IDX < <(awk -v thr="$THRESHOLD" '
  BEGIN { c=0 }
  {
    for (i=1; i<=NF; i++) {
      v = $i + 0;
      if (thr==0) {
        if (v==0) printf "%d\n", c;
      } else {
        if (v <= thr && v >= -thr) printf "%d\n", c;
      }
      c++;
    }
  }
' "$IN_BVAL")

# Remove any empty entries from indices (defensive)
mapfile -t B0_IDX < <(printf "%s\n" "${B0_IDX[@]}" | awk 'NF>0')

TOTAL="${#B0_IDX[@]}"
log "Found $TOTAL b=0 candidate indices: ${B0_IDX[*]}"

if (( TOTAL < NUM_B0 )); then
  die "Insufficient b=0 volumes: found $TOTAL, need $NUM_B0"
fi

# Select exactly NUM_B0 earliest indices
SELECTED=("${B0_IDX[@]:0:NUM_B0}")
SELECTED_CSV=$(printf "%s\n" "${SELECTED[@]}" | paste -sd ",")
log "Selecting indices: ${SELECTED_CSV}"
# Log selected b-values for verification
SELECTED_BVALS=$(awk -v idxs="$SELECTED_CSV" '
  BEGIN { n=split(idxs, a, ","); c=0 }
  { for (i=1;i<=NF;i++){ vals[c]=$i+0; c++ } }
  END { for (i=1;i<=n;i++) printf "%d ", vals[a[i]] }
' "$IN_BVAL")
log "Selected bvals: ${SELECTED_BVALS}"

# Ensure output directory exists
mkdir -p "$(dirname "$OUT_NII")"

# Extract with fslselectvols; output uncompressed if .nii is used
log "Running: fslselectvols -i \"$IN_NII\" -o \"$OUT_NII\" --vols=\"$SELECTED_CSV\""
fslselectvols -i "$IN_NII" -o "$OUT_NII" --vols="$SELECTED_CSV"

# Verify output volume count
OUT_VOL=$(fslnvols "$OUT_NII")
log "Output volumes: $OUT_VOL"
if [[ "$OUT_VOL" != "$NUM_B0" ]]; then
  die "Output volume count ($OUT_VOL) != requested ($NUM_B0)"
fi

log "Done. Saved: $OUT_NII"