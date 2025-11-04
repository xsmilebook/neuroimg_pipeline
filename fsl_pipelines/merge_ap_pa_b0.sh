#!/usr/bin/env bash
set -euo pipefail

# Merge AP and PA b0 images into a single 4D NIfTI along time axis.
# Intended for WSL; uses FSL tools.
#
# Usage examples:
#   bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/merge_ap_pa_b0.sh \
#     --ap_nii /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/fmap/sub-001_acq-dwi_dir-AP_epi.nii \
#     --pa_nii /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/fmap/sub-001_acq-dwi_dir-PA_epi.nii \
#     --out_nii /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-001/fmap/sub-001_ap_pa_b0.nii.gz
#
# Options:
#   --ap_nii    Path to AP b0 NIfTI
#   --pa_nii    Path to PA b0 NIfTI
#   --out_nii   Path to output merged NIfTI (.nii or .nii.gz)
#   --log_file  Log file path (append); default stdout only
#   -h, --help  Show help
#
# Requires: fslmerge, fslnvols, fslhd (FSL)

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

usage() {
  sed -n '1,80p' "$0" | sed 's/^# \{0,1\}//'
}

AP_NII=""
PA_NII=""
OUT_NII=""
LOG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ap_nii)   shift; AP_NII="${1:-}" ;;
    --pa_nii)   shift; PA_NII="${1:-}" ;;
    --out_nii)  shift; OUT_NII="${1:-}" ;;
    --log_file) shift; LOG_FILE="${1:-}" ;;
    -h|--help)  usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true
done

if [[ -n "$LOG_FILE" ]]; then
  mkdir -p "$(dirname "$LOG_FILE")"
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

[[ -n "$AP_NII" ]]  || die "Missing --ap_nii"
[[ -n "$PA_NII" ]]  || die "Missing --pa_nii"
[[ -n "$OUT_NII" ]] || die "Missing --out_nii"
[[ -f "$AP_NII" ]]  || die "AP NIfTI not found: $AP_NII"
[[ -f "$PA_NII" ]]  || die "PA NIfTI not found: $PA_NII"

need_cmd fslmerge
need_cmd fslnvols
need_cmd fslhd

log "AP:  $AP_NII"
log "PA:  $PA_NII"
log "OUT: $OUT_NII"

# Check spatial dimensions compatibility
read -r AP_DX AP_DY AP_DZ < <(fslhd -x "$AP_NII" | awk '/^dim1|^dim2|^dim3/{print $3}' | paste -sd ' ' -)
read -r PA_DX PA_DY PA_DZ < <(fslhd -x "$PA_NII" | awk '/^dim1|^dim2|^dim3/{print $3}' | paste -sd ' ' -)
log "AP dims: ${AP_DX}x${AP_DY}x${AP_DZ} | PA dims: ${PA_DX}x${PA_DY}x${PA_DZ}"
[[ "$AP_DX" == "$PA_DX" && "$AP_DY" == "$PA_DY" && "$AP_DZ" == "$PA_DZ" ]] || die "AP/PA spatial dims mismatch"

AP_VOL=$(fslnvols "$AP_NII")
PA_VOL=$(fslnvols "$PA_NII")
log "AP vols: $AP_VOL | PA vols: $PA_VOL"

# Merge along time
mkdir -p "$(dirname "$OUT_NII")"
log "Running: fslmerge -t \"$OUT_NII\" \"$AP_NII\" \"$PA_NII\""
fslmerge -t "$OUT_NII" "$AP_NII" "$PA_NII"

OUT_VOL=$(fslnvols "$OUT_NII")
log "OUT vols: $OUT_VOL (expected $((AP_VOL + PA_VOL)))"
[[ "$OUT_VOL" == "$((AP_VOL + PA_VOL))" ]] || die "Merged volume count mismatch"

log "Done. Saved: $OUT_NII"