#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

usage() {
  cat <<EOF
Submit TBSS (Steps 1–4) over a BIDS directory

Examples (run in WSL):
  bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/submit_tbss.sh \
    --bids_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS \
    --tbss_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/derivatives/tbss \
    --threshold 0.2 --no_viewer

Options:
  --bids_dir   Path to BIDS root (containing sub-*/dwi)
  --tbss_dir   Output TBSS working directory
  --threshold  tbss_4_prestats threshold (default: 0.2)
  --no_viewer  Disable GUI viewers (unset DISPLAY) during step 1
EOF
}

# ------------------------- args -------------------------
BIDS_DIR=""
TBSS_DIR=""
THRESHOLD="0.2"
NO_VIEWER="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bids_dir)  shift; BIDS_DIR="${1:-}" ;;
    --tbss_dir)  shift; TBSS_DIR="${1:-}" ;;
    --threshold) shift; THRESHOLD="${1:-}" ;;
    --no_viewer)       NO_VIEWER="1" ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true
done

[[ -n "$BIDS_DIR" ]] || die "Missing --bids_dir"
[[ -d "$BIDS_DIR" ]] || die "BIDS dir not found: $BIDS_DIR"
[[ -n "$TBSS_DIR" ]] || die "Missing --tbss_dir"

need_cmd bash
need_cmd gzip

# Ensure FSL writes .nii.gz
export FSLOUTPUTTYPE=NIFTI_GZ

# Build FA patterns and ensure .nii files are compressed to .nii.gz
FA_PATTERNS=("$BIDS_DIR/sub-*/dwi/dtifit_FA.nii.gz" "$BIDS_DIR/sub-*/dwi/dti_FA.nii.gz")
FA_PATTERNS_NII=("$BIDS_DIR/sub-*/dwi/dtifit_FA.nii" "$BIDS_DIR/sub-*/dwi/dti_FA.nii")

# Compress any .nii FA to .nii.gz (leave original intact)
for pattern in "${FA_PATTERNS_NII[@]}"; do
  for fa_file in $pattern; do
    # Skip if pattern didn't match (contains wildcard)
    if [[ "$fa_file" == *"*"* ]]; then
      continue
    fi
    if [[ -f "$fa_file" ]]; then
      gz_path="${fa_file}.gz"
      if [[ ! -f "$gz_path" ]]; then
        log "Compressing FA to .nii.gz: $fa_file -> $gz_path"
        gzip -c "$fa_file" > "$gz_path"
      else
        log "Already compressed: $gz_path"
      fi
    fi
  done
done

# After compression, use only .nii.gz for TBSS collection
FA_PATTERN="${FA_PATTERNS[0]} ${FA_PATTERNS[1]}"

PIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_TBSS="$PIPE_DIR/run_tbss.sh"

[[ -f "$RUN_TBSS" ]] || die "run_tbss.sh not found: $RUN_TBSS"

log "Submitting TBSS to run on FA pattern(s): $FA_PATTERN"
log "TBSS working directory: $TBSS_DIR"

if [[ "$NO_VIEWER" == "1" ]]; then
  unset DISPLAY || true
fi

bash "$RUN_TBSS" \
  --tbss_dir "$TBSS_DIR" \
  --fa_pattern "$FA_PATTERN" \
  --run_all \
  --threshold "$THRESHOLD" \
  ${NO_VIEWER:+--no_viewer}

log "TBSS submission completed"