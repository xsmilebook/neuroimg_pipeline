#!/usr/bin/env bash
set -euo pipefail

# TBSS Steps (1–4): Prepare and run standard TBSS pipeline
# - Step 1: tbss_1_preproc on collected FA images (*.nii.gz)
# - Step 2: tbss_2_reg (default: -T to FMRIB58_FA; or -t <target>)
# - Step 3: tbss_3_postreg (default: -S if Step2 used -T; else no -S)
# - Step 4: tbss_4_prestats <threshold> (default: 0.2)
#
# This script can run Step 1 alone (default when providing inputs),
# or run the full pipeline with --run_all, with options to customize
# threshold and target template.
#
# Usage examples (run in WSL):
#   1) Pattern-based collection
#      bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_tbss.sh \
#        --tbss_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/derivatives/tbss_step1 \
#        --fa_pattern "/mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-*/dwi/dtifit_FA.nii.gz"
#
#   2) Explicit subjects from a BIDS directory
#      bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_tbss.sh \
#        --tbss_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/derivatives/tbss_step1 \
#        --subjects "sub-001,sub-002,sub-003" \
#        --bids_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS
#
#   3) Group ordering (controls first, then patients)
#      bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_tbss.sh \
#        --tbss_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/derivatives/tbss_step1 \
#        --controls "sub-001,sub-002" --patients "sub-003,sub-004" \
#        --bids_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS
#
#   4) Run full TBSS 1–4 with defaults
#      bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_tbss.sh \
#        --tbss_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/derivatives/tbss \
#        --fa_pattern "/mnt/e/projects/neuroimg_pipeline/datasets/BIDS/sub-*/dwi/dtifit_FA.nii.gz" \
#        --run_all --threshold 0.2
#
# Options:
#   --no_viewer     Disable GUI viewers (unset DISPLAY) during step 1
#   --run_all       Run steps 1–4 after collecting inputs
#   --skip_step1    Skip tbss_1_preproc (use existing FA/ and origdata/)
#   --threshold X   Threshold for tbss_4_prestats (default: 0.2)
#   --target PATH   Custom target FA for tbss_2_reg (-t PATH); if absent, use -T
#
# Environment: ensure .nii.gz outputs from FSL
export FSLOUTPUTTYPE=NIFTI_GZ

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

usage() { sed -n '1,60p' "$0" | sed 's/^# \{0,1\}//'; }

# ------------------------- args -------------------------
TBSS_DIR=""
FA_PATTERN=""
SUBJECTS=""
BIDS_DIR=""
CONTROLS=""
PATIENTS=""
NO_VIEWER="0"

# Additional options
THRESHOLD="0.2"
TARGET=""
SKIP_STEP1="0"
RUN_ALL="0"
DO_STEP2="0"
DO_STEP3="0"
DO_STEP4="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tbss_dir)   shift; TBSS_DIR="${1:-}" ;;
    --fa_pattern) shift; FA_PATTERN="${1:-}" ;;
    --subjects)   shift; SUBJECTS="${1:-}" ;;
    --bids_dir)   shift; BIDS_DIR="${1:-}" ;;
    --controls)   shift; CONTROLS="${1:-}" ;;
    --patients)   shift; PATIENTS="${1:-}" ;;
    --no_viewer)        NO_VIEWER="1" ;;
    --threshold)  shift; THRESHOLD="${1:-}" ;;
    --target)     shift; TARGET="${1:-}" ;;
    --skip_step1)       SKIP_STEP1="1" ;;
    --run_all)          RUN_ALL="1" ;;
    --do_step2)         DO_STEP2="1" ;;
    --do_step3)         DO_STEP3="1" ;;
    --do_step4)         DO_STEP4="1" ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true
done

# ----------------------- validation ----------------------
[[ -n "$TBSS_DIR" ]] || die "Missing --tbss_dir"
need_cmd tbss_1_preproc
need_cmd tbss_2_reg
need_cmd tbss_3_postreg
need_cmd tbss_4_prestats

if [[ "$NO_VIEWER" == "1" ]]; then
  unset DISPLAY || true
  log "GUI disabled (DISPLAY unset)"
fi

# Create TBSS working directory
mkdir -p "$TBSS_DIR"
cd "$TBSS_DIR"
log "Working in TBSS directory: $TBSS_DIR"

# -------------------- collect FA images -------------------
# Copy FA inputs to the root of the working directory
INPUT_DIR="$TBSS_DIR"

fa_count=0

if [[ -n "$FA_PATTERN" ]]; then
  log "Collecting FA images using pattern: $FA_PATTERN"
  # Enable nullglob to handle non-matching patterns gracefully
  shopt -s nullglob
  for fa_file in $FA_PATTERN; do
    # Skip if the pattern itself is returned (no matches)
    if [[ "$fa_file" == *"*"* ]]; then
      log "Pattern did not match any files: $fa_file"
      continue
    fi
    if [[ -f "$fa_file" ]]; then
      subj_id=$(basename "$(dirname "$(dirname "$fa_file")")" || echo "unknown")
      [[ "$subj_id" =~ ^sub-[0-9]+$ ]] || { log "Warning: invalid subject id from $fa_file"; continue; }
      cp "$fa_file" "$INPUT_DIR/${subj_id}_FA.nii.gz"
      log "Copied: $fa_file -> $INPUT_DIR/${subj_id}_FA.nii.gz"
      ((fa_count++)) || true
    else
      log "File not found: $fa_file"
    fi
  done
  # Restore default nullglob behavior
  shopt -u nullglob
elif [[ -n "$SUBJECTS" && -n "$BIDS_DIR" ]]; then
  log "Collecting FA images for subjects: $SUBJECTS"
  IFS=',' read -ra SUBJ_ARRAY <<< "$SUBJECTS"
  for subj in "${SUBJ_ARRAY[@]}"; do
    subj=$(echo "$subj" | xargs)
    fa_file="$BIDS_DIR/$subj/dwi/dtifit_FA.nii.gz"
    if [[ -f "$fa_file" ]]; then
      cp "$fa_file" "$INPUT_DIR/${subj}_FA.nii.gz"
      log "Copied: $fa_file -> $INPUT_DIR/${subj}_FA.nii.gz"
      ((fa_count++)) || true
    else
      log "Warning: FA not found for $subj: $fa_file"
    fi
  done
elif [[ ( -n "$CONTROLS" || -n "$PATIENTS" ) && -n "$BIDS_DIR" ]]; then
  log "Collecting FA with group ordering (controls first, then patients)"
  if [[ -n "$CONTROLS" ]]; then
    IFS=',' read -ra CTRL_ARRAY <<< "$CONTROLS"
    for subj in "${CTRL_ARRAY[@]}"; do
      subj=$(echo "$subj" | xargs)
      fa_file="$BIDS_DIR/$subj/dwi/dtifit_FA.nii.gz"
      if [[ -f "$fa_file" ]]; then
        cp "$fa_file" "$INPUT_DIR/CON_${subj}_FA.nii.gz"
        log "Copied: $fa_file -> $INPUT_DIR/CON_${subj}_FA.nii.gz"
        ((fa_count++)) || true
      else
        log "Warning: FA not found for control $subj: $fa_file"
      fi
    done
  fi
  if [[ -n "$PATIENTS" ]]; then
    IFS=',' read -ra PAT_ARRAY <<< "$PATIENTS"
    for subj in "${PAT_ARRAY[@]}"; do
      subj=$(echo "$subj" | xargs)
      fa_file="$BIDS_DIR/$subj/dwi/dtifit_FA.nii.gz"
      if [[ -f "$fa_file" ]]; then
        cp "$fa_file" "$INPUT_DIR/PAT_${subj}_FA.nii.gz"
        log "Copied: $fa_file -> $INPUT_DIR/PAT_${subj}_FA.nii.gz"
        ((fa_count++)) || true
      else
        log "Warning: FA not found for patient $subj: $fa_file"
      fi
    done
  fi
else
  die "Must provide either --fa_pattern OR (--subjects & --bids_dir) OR (--controls/--patients & --bids_dir)"
fi

[[ "$fa_count" -gt 0 ]] || die "No FA images collected"
log "Collected $fa_count FA images"

# -------------------- TBSS Step 1: preproc ----------------
if [[ "$SKIP_STEP1" == "0" ]]; then
  log "Step 1: tbss_1_preproc - preparing FA data"
  tbss_1_preproc *.nii.gz
  log "tbss_1_preproc completed"
else
  log "Skipping Step 1 (tbss_1_preproc) as requested"
fi

# Determine subsequent steps
if [[ "$RUN_ALL" == "1" ]]; then
  DO_STEP2="1"; DO_STEP3="1"; DO_STEP4="1"
fi

# -------------------- TBSS Step 2: registration ----------------
if [[ "$DO_STEP2" == "1" ]]; then
  if [[ -n "$TARGET" ]]; then
    log "Step 2: tbss_2_reg -t $TARGET"
    tbss_2_reg -t "$TARGET"
  else
    log "Step 2: tbss_2_reg -T (FMRIB58_FA template)"
    tbss_2_reg -T
  fi
  log "tbss_2_reg completed"
else
  log "Step 2: tbss_2_reg skipped"
fi

# -------------------- TBSS Step 3: post-registration ----------------
if [[ "$DO_STEP3" == "1" ]]; then
  if [[ -n "$TARGET" ]]; then
    log "Step 3: tbss_3_postreg (no -S, custom target used in Step 2)"
    tbss_3_postreg
  else
    log "Step 3: tbss_3_postreg -S (used -T in Step 2)"
    tbss_3_postreg -S
  fi
  log "tbss_3_postreg completed"
else
  log "Step 3: tbss_3_postreg skipped"
fi

# -------------------- TBSS Step 4: prestats ----------------
if [[ "$DO_STEP4" == "1" ]]; then
  log "Step 4: tbss_4_prestats with threshold: $THRESHOLD"
  tbss_4_prestats "$THRESHOLD"
  log "tbss_4_prestats completed"
else
  log "Step 4: tbss_4_prestats skipped"
fi

# -------------------- Summary ----------------
log "Outputs summary:"
log "  - Step 1: origdata/ (original) and FA/ (preprocessed); slicesdir/index.html"
log "  - Step 2: all_FA images registered to target"
log "  - Step 3: mean FA skeleton and projected data"
log "  - Step 4: stats/ ready inputs at chosen threshold ($THRESHOLD)"