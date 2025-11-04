#!/usr/bin/env bash
set -euo pipefail

log() { echo "[SUBMIT] $*"; }

BIDS_DIR="/mnt/e/projects/neuroimg_pipeline/datasets/BIDS"
PIPE_DIR="/mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines"
export FSLOUTPUTTYPE=NIFTI_GZ

# Iterate selected subjects only
for SUBJ in sub-002 sub-003 sub-004 sub-005; do
  SUBJ_DIR="$BIDS_DIR/$SUBJ"
  [[ -d "$SUBJ_DIR" ]] || continue
  # keep SUBJ as is
  log "Processing $SUBJ"

  DWI_PA_NII="$SUBJ_DIR/dwi/${SUBJ}_dir-PA_dwi.nii"
  DWI_PA_BVAL="$SUBJ_DIR/dwi/${SUBJ}_dir-PA_dwi.bval"
  DWI_PA_BVEC="$SUBJ_DIR/dwi/${SUBJ}_dir-PA_dwi.bvec"
  # AP EPI is subject-specific file under fmap

  FMAP_DIR="$SUBJ_DIR/fmap"
  AP_EPI_NII="$FMAP_DIR/${SUBJ}_acq-dwi_dir-AP_epi.nii"
  AP_EPI_GZ="$FMAP_DIR/${SUBJ}_acq-dwi_dir-AP_epi.nii.gz"
  AP_EPI="$AP_EPI_GZ"
  mkdir -p "$FMAP_DIR"

#   # 1) Prepare AP/PA b0 inputs
#   # AP: expect subject's AP EPI already present (as shown in your dataset)
#   if [[ ! -f "$AP_EPI_GZ" ]]; then
#     if [[ -f "$AP_EPI_NII" ]]; then
#       gzip -c "$AP_EPI_NII" > "$AP_EPI_GZ"
#       AP_EPI="$AP_EPI_GZ"
#       log "Compressed AP EPI to .nii.gz: $AP_EPI_GZ"
#     else
#       log "Missing subject AP EPI: $AP_EPI_GZ (will skip TOPUP/EDDY for $SUBJ)"
#     fi
#   fi
#   # PA: extract b0s to PA EPI if inputs exist
#   if [[ -f "$DWI_PA_NII" && -f "$DWI_PA_BVAL" ]]; then
#     bash "$PIPE_DIR/extract_b0s.sh" \
#       --in_nii "$DWI_PA_NII" \
#       --in_bval "$DWI_PA_BVAL" \
#       --out_nii "$FMAP_DIR/${SUBJ}_acq-dwi_dir-PA_epi.nii.gz" \
#       --num_b0 5 || true
#   else
#     log "Skip PA extract_b0s: missing PA DWI or bval for $SUBJ"
#   fi

#   # 2) Merge AP/PA b0s for TOPUP
#   PA_EPI="$FMAP_DIR/${SUBJ}_acq-dwi_dir-PA_epi.nii.gz"
#   if [[ -f "$AP_EPI" && -f "$PA_EPI" ]]; then
#     bash "$PIPE_DIR/merge_ap_pa_b0.sh" \
#       --ap_nii "$AP_EPI" \
#       --pa_nii "$PA_EPI" \
#       --out_nii "$FMAP_DIR/${SUBJ}_ap_pa_b0.nii.gz"
#   else
#     log "Skip merge_ap_pa_b0: missing AP/PA EPI for $SUBJ"
#   fi

#   # 2.1) Ensure acqparams(.txt) exists; copy from sub-001
#   if [[ ! -f "$FMAP_DIR/acqparams.txt" && ! -f "$FMAP_DIR/acqparams" ]]; then
#     REF_SUBJ_DIR="$BIDS_DIR/sub-001/fmap"
#     if [[ -f "$REF_SUBJ_DIR/acqparams.txt" ]]; then
#       cp -f "$REF_SUBJ_DIR/acqparams.txt" "$FMAP_DIR/acqparams.txt"
#       log "Copied acqparams.txt from sub-001 → $SUBJ"
#     elif [[ -f "$REF_SUBJ_DIR/acqparams" ]]; then
#       cp -f "$REF_SUBJ_DIR/acqparams" "$FMAP_DIR/acqparams"
#       log "Copied acqparams from sub-001 → $SUBJ"
#     else
#       log "No acqparams(.txt) in sub-001 to copy"
#     fi
#   fi

#   # 2.2) Ensure b02b0.cnf exists; copy from sub-001
#   if [[ ! -f "$FMAP_DIR/b02b0.cnf" ]]; then
#     REF_CNF="$BIDS_DIR/sub-001/fmap/b02b0.cnf"
#     if [[ -f "$REF_CNF" ]]; then
#       cp -f "$REF_CNF" "$FMAP_DIR/b02b0.cnf"
#       log "Copied b02b0.cnf from sub-001 → $SUBJ"
#     else
#       log "No b02b0.cnf in sub-001 to copy"
#     fi
#   fi

#   # 3) TOPUP (requires acqparams(.txt) and b02b0.cnf in fmap)
#   DAT_FILE=""
#   if [[ -f "$FMAP_DIR/acqparams.txt" ]]; then DAT_FILE="acqparams.txt"; elif [[ -f "$FMAP_DIR/acqparams" ]]; then DAT_FILE="acqparams"; fi
#   if [[ -f "$FMAP_DIR/${SUBJ}_ap_pa_b0.nii.gz" && -n "$DAT_FILE" && -f "$FMAP_DIR/b02b0.cnf" ]]; then
#     ( cd "$FMAP_DIR" && bash "$PIPE_DIR/run_topup.sh" \
#         --imain "${SUBJ}_ap_pa_b0.nii.gz" \
#         --datain "$DAT_FILE" \
#         --config "b02b0.cnf" \
#         --out "topup_results" \
#         --iout "unwarped_b0" \
#         --fout "fieldmap_hz" )
#   else
#     log "Skip TOPUP: missing inputs or config for $SUBJ"
#   fi

#   # 4) EDDY (uses PA DWI as main input by default)
#   if [[ -f "$DWI_PA_NII" && -f "$DWI_PA_BVAL" && -f "$DWI_PA_BVEC" && -d "$FMAP_DIR" ]]; then
#     bash "$PIPE_DIR/run_eddy.sh" \
#       --dwi_nii "$DWI_PA_NII" \
#       --bvecs   "$DWI_PA_BVEC" \
#       --bvals   "$DWI_PA_BVAL" \
#       --acqparams "$FMAP_DIR/${DAT_FILE:-acqparams.txt}" \
#       --topup_prefix "$FMAP_DIR/topup_results" \
#       --iout     "$FMAP_DIR/unwarped_b0" \
#       --out      "$SUBJ_DIR/dwi/eddy" \
#       --index_row 6 \
#       --data_is_shelled || true
#   else
#     log "Skip EDDY: missing DWI/AP/PA files or fmap for $SUBJ"
#   fi

#   # 5) EDDY QC (optional)
#   if [[ -d "$SUBJ_DIR/dwi/eddy" ]]; then
#     bash "$PIPE_DIR/run_eddy_qc.sh" \
#       "$SUBJ_DIR/dwi/eddy" \
#       -idx "$SUBJ_DIR/dwi/index.txt" \
#       -par "$FMAP_DIR/${DAT_FILE:-acqparams.txt}" \
#       -m   "$SUBJ_DIR/dwi/nodif_brain_mask.nii.gz" \
#       -b   "$DWI_PA_BVAL" || true
#   fi

  # 6) DTIFIT
  if [[ -d "$SUBJ_DIR/dwi/eddy" && -f "$DWI_PA_BVAL" ]]; then
    bash "$PIPE_DIR/run_dtifit.sh" \
      "$SUBJ_DIR/dwi/eddy.nii.gz" \
      -b "$DWI_PA_BVAL" \
      -o "$SUBJ_DIR/dwi/dti" || true
  else
    log "Skip DTIFIT: missing eddy output or bval for $SUBJ"
  fi
done

# # # 7) TBSS group analysis (Step 1 implemented; Step 2+ handled inside run_tbss.sh later)
# # TBSS_DIR="$BIDS_DIR/derivatives/tbss"
# # bash "$PIPE_DIR/run_tbss.sh" \
# #   --tbss_dir "$TBSS_DIR" \
# #   --fa_pattern "$BIDS_DIR/sub-*/dwi/dti_FA.nii.gz $BIDS_DIR/sub-*/dwi/dtifit_FA.nii.gz" \
# #   --no_viewer

# # log "Pipeline completed across subjects. TBSS (step1) outputs in: $TBSS_DIR"


# bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/submit_tbss.sh \
#     --bids_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS \
#     --tbss_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS/derivatives/tbss \
#     --threshold 0.2 --no_viewer

