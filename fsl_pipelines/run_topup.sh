#!/usr/bin/env bash
set -euo pipefail

# Run FSL TOPUP to process B0 fieldmap data.
# Intended for WSL; uses FSL tools.
#
# Example (relative paths from subject fmap dir):
#   cd /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/fmap
#   bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_topup.sh \
#     --imain sub-001_ap_pa_b0.nii.gz \
#     --datain fieldmap/acqparams.txt \
#     --config fieldmap/b02b0.cnf \
#     --out topup_results \
#     --iout unwarped_b0 \
#     --fout fieldmap_hz
#
# Options:
#   --imain   Input B0 4D NIfTI (merged AP+PA)
#   --datain  acqparams.txt path (phase encoding parameters)
#   --config  b02b0.cnf path (TOPUP configuration)
#   --out     TOPUP output prefix (not a dir)
#   --iout    Unwarped B0 output prefix
#   --fout    Fieldmap-in-Hz output prefix
#   --log_file  Optional log file path (append)
#   -h, --help  Show help
#
# Requires: topup, fslnvols (FSL)

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

usage() {
  sed -n '1,80p' "$0" | sed 's/^# \{0,1\}//'
}

IMAIN=""
DATAIN=""
CONFIG=""
OUT_PREFIX=""
IOUT=""
FOUT=""
LOG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --imain)   shift; IMAIN="${1:-}" ;;
    --datain)  shift; DATAIN="${1:-}" ;;
    --config)  shift; CONFIG="${1:-}" ;;
    --out)     shift; OUT_PREFIX="${1:-}" ;;
    --iout)    shift; IOUT="${1:-}" ;;
    --fout)    shift; FOUT="${1:-}" ;;
    --log_file) shift; LOG_FILE="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true
done

if [[ -n "$LOG_FILE" ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

# Validation
[[ -n "$IMAIN" ]]     || die "Missing --imain"
[[ -n "$DATAIN" ]]    || die "Missing --datain"
[[ -n "$CONFIG" ]]    || die "Missing --config"
[[ -n "$OUT_PREFIX" ]]|| die "Missing --out"
[[ -n "$IOUT" ]]      || die "Missing --iout"
[[ -n "$FOUT" ]]      || die "Missing --fout"
[[ -f "$IMAIN" ]]     || die "Input NIfTI not found: $IMAIN"
[[ -f "$DATAIN" ]]    || die "acqparams not found: $DATAIN"
[[ -f "$CONFIG" ]]    || die "config not found: $CONFIG"

need_cmd topup
need_cmd fslnvols

log "IMAIN:  $IMAIN"
log "DATAIN: $DATAIN"
log "CONFIG: $CONFIG"
log "OUT:    $OUT_PREFIX"
log "IOUT:   $IOUT"
log "FOUT:   $FOUT"

# Ensure output parent dirs exist (prefixes may include directory components)
mkdir -p "$(dirname "$OUT_PREFIX")" "$(dirname "$IOUT")" "$(dirname "$FOUT")"

# Check volumes vs acqparams lines (each volume needs one row)
IMAIN_VOL=$(fslnvols "$IMAIN")
DATAIN_LINES=$(awk 'NF>0{c++} END{print c+0}' "$DATAIN")
log "Input vols: $IMAIN_VOL | acqparams rows: $DATAIN_LINES"
[[ "$DATAIN_LINES" -eq "$IMAIN_VOL" ]] || die "acqparams rows ($DATAIN_LINES) must equal input volumes ($IMAIN_VOL)"

# Run TOPUP
log "Running TOPUP"
CMD=(topup "--imain=${IMAIN}" "--datain=${DATAIN}" "--config=${CONFIG}" "--out=${OUT_PREFIX}" "--iout=${IOUT}" "--fout=${FOUT}")
log "Command: ${CMD[*]}"
"${CMD[@]}"

# Verify outputs exist (.nii.gz preferred, allow .nii fallback)
resolve_out() {
  local base=$1
  if [[ -f "${base}.nii.gz" ]]; then echo "${base}.nii.gz"; elif [[ -f "${base}.nii" ]]; then echo "${base}.nii"; else echo ""; fi
}
IOUT_PATH=$(resolve_out "$IOUT")
FOUT_PATH=$(resolve_out "$FOUT")
[[ -n "$IOUT_PATH" ]] || die "Missing iout image: ${IOUT}.nii(.gz)"
[[ -n "$FOUT_PATH" ]] || die "Missing fout image: ${FOUT}.nii(.gz)"
log "TOPUP outputs: iout=${IOUT_PATH} | fout=${FOUT_PATH}"

log "Done."