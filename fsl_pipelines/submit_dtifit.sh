#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

usage() {
  cat <<EOF
Submit dtifit for subjects sub-001 .. sub-010 using run_dtifit.sh

Examples (WSL):
  bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/submit_dtifit.sh \
    --bids_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS

Options:
  --bids_dir   Path to BIDS root (default: /mnt/e/projects/neuroimg_pipeline/datasets/BIDS)
  --start N    Start index (default: 1)
  --end M      End index (default: 10)
  --subjects   Comma-separated list (overrides start/end), e.g. "sub-001,sub-002"
EOF
}

# ------------------------- args -------------------------
BIDS_DIR="${BIDS_DIR:-/mnt/e/projects/neuroimg_pipeline/datasets/BIDS}"
START=1
END=10
SUBJECTS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bids_dir) shift; BIDS_DIR="${1:-}" ;;
    --start)    shift; START="${1:-}" ;;
    --end)      shift; END="${1:-}" ;;
    --subjects) shift; SUBJECTS="${1:-}" ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true
done

[[ -d "$BIDS_DIR" ]] || die "BIDS dir not found: $BIDS_DIR"

PIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DTIFIT="$PIPE_DIR/run_dtifit.sh"
[[ -f "$RUN_DTIFIT" ]] || die "run_dtifit.sh not found: $RUN_DTIFIT"

# Ensure FSL writes .nii.gz
export FSLOUTPUTTYPE=NIFTI_GZ

build_subject_list() {
  local list=()
  if [[ -n "$SUBJECTS" ]]; then
    IFS=',' read -ra arr <<< "$SUBJECTS"
    for s in "${arr[@]}"; do
      s=$(echo "$s" | xargs)
      if [[ "$s" =~ ^sub-[0-9]{3}$ ]]; then
        list+=("$s")
      elif [[ "$s" =~ ^[0-9]{1,3}$ ]]; then
        list+=("sub-$(printf "%03d" "$s")")
      else
        die "Invalid subject format: $s"
      fi
    done
  else
    for ((i=START; i<=END; i++)); do
      list+=("sub-$(printf "%03d" "$i")")
    done
  fi
  echo "${list[@]}"
}

subjects=( $(build_subject_list) )
[[ ${#subjects[@]} -gt 0 ]] || die "No subjects to process"

log "Submitting dtifit for ${#subjects[@]} subjects"
for subj in "${subjects[@]}"; do
  log "Subject: $subj"
  dwi_dir="$BIDS_DIR/$subj/dwi"
  [[ -d "$dwi_dir" ]] || { err "Missing dwi dir: $dwi_dir"; continue; }

  dwi_base="$dwi_dir/${subj}_dir-PA_dwi"
  bval="$dwi_base.bval"
  [[ -f "$bval" ]] || { err "bval not found: $bval"; continue; }

  # Detect eddy output base: prefer subject dwi dir; fallback to derivatives
  eddy_base=""
  if [[ -f "$dwi_dir/eddy.nii.gz" || -f "$dwi_dir/eddy.nii" ]]; then
    eddy_base="$dwi_dir/eddy"
  elif [[ -f "$dwi_dir/${subj}_eddy.nii.gz" || -f "$dwi_dir/${subj}_eddy.nii" ]]; then
    eddy_base="$dwi_dir/${subj}_eddy"
  elif [[ -f "$BIDS_DIR/derivatives/fsl/$subj/dwi/${subj}_eddy.nii.gz" || -f "$BIDS_DIR/derivatives/fsl/$subj/dwi/${subj}_eddy.nii" ]]; then
    eddy_base="$BIDS_DIR/derivatives/fsl/$subj/dwi/${subj}_eddy"
  else
    err "Eddy output not found under $dwi_dir or derivatives."
    continue
  fi

  # Mask path: prefer alongside eddy in subject dwi dir, else derivatives
  mask_path="$dwi_dir/nodif_brain_mask.nii.gz"
  if [[ ! -f "$mask_path" ]]; then
    mask_path="$BIDS_DIR/derivatives/fsl/$subj/dwi/nodif_brain_mask.nii.gz"
  fi
  [[ -f "$mask_path" ]] || { err "Mask not found: $mask_path"; continue; }

  # Output next to subject dwi for TBSS collection
  out_base="$dwi_dir/dtifit"

  log "Running dtifit: eddy=$eddy_base bval=$bval mask=$mask_path out=$out_base"
  bash "$RUN_DTIFIT" "$eddy_base" -b "$bval" -m "$mask_path" -o "$out_base" || {
    err "dtifit failed for $subj"; continue;
  }

  log "Done: $subj (FA at ${out_base}_FA.nii.gz)"
done

log "Submission finished. Outputs under: $BIDS_DIR/sub-XXX/dwi/dtifit_*"