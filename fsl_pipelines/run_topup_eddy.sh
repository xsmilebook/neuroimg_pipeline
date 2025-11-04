#!/usr/bin/env bash
set -euo pipefail

# FSL DWI preprocessing (TOPUP + eddy) for BIDS data
# - Designed for WSL. Default BIDS dir: /mnt/e/projects/neuroimg_pipeline/datasets/BIDS
# - Requires: FSL (fslroi, fslmerge, topup, bet, eddy or eddy_openmp), jq
#
# Usage examples (in WSL):
#   bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_topup_eddy.sh \
#     --bids_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS --subject sub-001
#
#   # Process all subjects (sub-*)
#   bash /mnt/e/projects/neuroimg_pipeline/src/fsl_pipelines/run_topup_eddy.sh \
#     --bids_dir /mnt/e/projects/neuroimg_pipeline/datasets/BIDS --subject all

# ---------------------------- helpers ----------------------------
log() { echo "[INFO] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

# prefer eddy_openmp when available
choose_eddy() {
  if command -v eddy_openmp >/dev/null 2>&1; then echo "eddy_openmp"; elif command -v eddy >/dev/null 2>&1; then echo "eddy"; else die "Missing FSL eddy or eddy_openmp"; fi
}

phase_dir_to_vec() {
  case "$1" in
    i)   echo "1 0 0" ;;
    i-)  echo "-1 0 0" ;;
    j)   echo "0 1 0" ;;
    j-)  echo "0 -1 0" ;;
    k)   echo "0 0 1" ;;
    k-)  echo "0 0 -1" ;;
    *)   die "Unknown PhaseEncodingDirection: $1" ;;
  esac
}

json_field() {
  local json=$1 key=$2
  jq -r ".${key} // empty" "$json"
}

# resolve .nii.gz or .nii for a base path (without extension)
resolve_nii() {
  local base=$1
  if [ -f "${base}.nii.gz" ]; then echo "${base}.nii.gz"; elif [ -f "${base}.nii" ]; then echo "${base}.nii"; else die "Missing NIfTI file: ${base}.nii(.gz)"; fi
}

count_vols_from_bval() {
  local bval=$1
  awk '{for(i=1;i<=NF;i++) if($i!="") c++} END{if(c>0) print c; else print 0}' "$bval"
}

# ---------------------------- arg parse ----------------------------
BIDS_DIR="${BIDS_DIR:-/mnt/e/projects/neuroimg_pipeline/datasets/BIDS}"
SUBJECT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --bids_dir) shift; BIDS_DIR="$1" ;;
    --subject)  shift; SUBJECT="$1" ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift || true
done

[ -d "$BIDS_DIR" ] || die "BIDS dir not found: $BIDS_DIR"
[ -n "$SUBJECT" ] || die "Please provide --subject (e.g., sub-001 or all)"

# ---------------------------- checks ----------------------------
need_cmd jq
need_cmd fslroi
need_cmd fslmerge
need_cmd topup
need_cmd bet
EDDY_CMD=$(choose_eddy)
log "Using eddy command: $EDDY_CMD"

# Use FSL config file name; if not found, you can export FSLDIR and use $FSLDIR/etc/flirtsch/b02b0.cnf
TOPUP_CONFIG="${TOPUP_CONFIG:-b02b0.cnf}"

process_subject() {
  local subj=$1
  log "Processing $subj"

  local dwi_dir="$BIDS_DIR/$subj/dwi"
  local fmap_dir="$BIDS_DIR/$subj/fmap"
  [ -d "$dwi_dir" ] || die "Missing dwi dir: $dwi_dir"
  [ -d "$fmap_dir" ] || die "Missing fmap dir: $fmap_dir"

  local dwi_base="$dwi_dir/${subj}_dir-PA_dwi"
  local dwi_nii; dwi_nii=$(resolve_nii "$dwi_base")
  local dwi_bvec="$dwi_base.bvec"
  local dwi_bval="$dwi_base.bval"
  local dwi_json="$dwi_base.json"
  [ -f "$dwi_bvec" ] || die "Missing bvec: $dwi_bvec"
  [ -f "$dwi_bval" ] || die "Missing bval: $dwi_bval"
  [ -f "$dwi_json" ] || die "Missing JSON: $dwi_json"

  local ap_base="$fmap_dir/${subj}_acq-dwi_dir-AP_epi"
  local ap_epi_nii; ap_epi_nii=$(resolve_nii "$ap_base")
  local ap_epi_json="$ap_base.json"
  [ -f "$ap_epi_json" ] || die "Missing JSON: $ap_epi_json"

  # derivatives
  local deriv="$BIDS_DIR/derivatives/fsl/$subj"
  local deriv_dwi="$deriv/dwi"
  local deriv_fmap="$deriv/fmap"
  mkdir -p "$deriv_dwi" "$deriv_fmap"

  # read JSON metadata
  local dwi_phase ap_phase dwi_trt ap_trt
  dwi_phase=$(json_field "$dwi_json" PhaseEncodingDirection)
  ap_phase=$(json_field "$ap_epi_json" PhaseEncodingDirection)
  dwi_trt=$(json_field "$dwi_json" TotalReadoutTime)
  ap_trt=$(json_field "$ap_epi_json" TotalReadoutTime)

  if [ -z "$dwi_phase" ] || [ -z "$ap_phase" ]; then die "PhaseEncodingDirection missing in JSON"; fi

  # fallback TOT: EffectiveEchoSpacing * (ReconMatrixPE - 1)
  if [ -z "$dwi_trt" ] || [ -z "$ap_trt" ]; then
    local dwi_eff ap_eff dwi_recon ap_recon
    dwi_eff=$(json_field "$dwi_json" EffectiveEchoSpacing)
    ap_eff=$(json_field "$ap_epi_json" EffectiveEchoSpacing)
    dwi_recon=$(json_field "$dwi_json" ReconMatrixPE)
    ap_recon=$(json_field "$ap_epi_json" ReconMatrixPE)
    if [ -z "$dwi_trt" ] && [ -n "$dwi_eff" ] && [ -n "$dwi_recon" ]; then
      dwi_trt=$(awk -v eff="$dwi_eff" -v rpe="$dwi_recon" 'BEGIN{printf("%f", eff*(rpe-1))}')
    fi
    if [ -z "$ap_trt" ] && [ -n "$ap_eff" ] && [ -n "$ap_recon" ]; then
      ap_trt=$(awk -v eff="$ap_eff" -v rpe="$ap_recon" 'BEGIN{printf("%f", eff*(rpe-1))}')
    fi
  fi
  [ -n "$dwi_trt" ] || die "TotalReadoutTime missing (DWI) and cannot be derived"
  [ -n "$ap_trt" ] || die "TotalReadoutTime missing (AP EPI) and cannot be derived"

  # 1) Extract first b0 from full DWI
  local pa_b0_from_dwi="$deriv_fmap/${subj}_acq-dwi_dir-PA_dwi.nii.gz"
  log "Extracting b0 from DWI: $dwi_nii -> $pa_b0_from_dwi"
  fslroi "$dwi_nii" "$pa_b0_from_dwi" 0 1

  # 1b) Merge PA (from DWI) first, then AP epi to 4D
  local ap_pa_b0="$deriv_fmap/${subj}_ap_pa_b0.nii.gz"
  log "Merging PA b0 and AP epi to 4D: $ap_pa_b0"
  fslmerge -t "$ap_pa_b0" "$pa_b0_from_dwi" "$ap_epi_nii"

  # 1c) Write acqparams.txt matching merged order: [PA (from dwi), AP (epi)]
  local pa_vec ap_vec
  pa_vec=$(phase_dir_to_vec "$dwi_phase")
  ap_vec=$(phase_dir_to_vec "$ap_phase")
  local acqparams="$deriv/acqparams.txt"
  printf "%s %s\n%s %s\n" "$pa_vec" "$dwi_trt" "$ap_vec" "$ap_trt" > "$acqparams"
  log "Wrote acqparams: $acqparams"

  # 2) Run TOPUP
  local topup_out_prefix="$deriv_fmap/topup_results"
  local unwarped_b0="$deriv_fmap/unwarped_b0"
  local fieldmap_hz="$deriv_fmap/fieldmap_hz"
  log "Running TOPUP"
  topup --imain="$ap_pa_b0" --datain="$acqparams" --config="$TOPUP_CONFIG" --out="$topup_out_prefix" --iout="$unwarped_b0" --fout="$fieldmap_hz"

  # 3) Brain mask from first unwarped b0 (corresponding to PA)
  local nodif="$deriv_dwi/nodif.nii.gz"
  fslroi "${unwarped_b0}.nii.gz" "$nodif" 0 1
  log "Running BET to create brain mask"
  bet "$nodif" "$deriv_dwi/nodif_brain" -m -f 0.2
  local nodif_mask="$deriv_dwi/nodif_brain_mask.nii.gz"
  [ -f "$nodif_mask" ] || die "BET did not produce nodif_brain_mask.nii.gz"

  # 4) index.txt for eddy: use line 1 (PA) for all volumes in DWI
  local nvols; nvols=$(count_vols_from_bval "$dwi_bval")
  [ "$nvols" -gt 0 ] || die "Failed to count volumes from bval: $dwi_bval"
  local index="$deriv/index.txt"
  yes 1 | head -n "$nvols" | paste -sd " " - > "$index"
  log "Wrote index with $nvols volumes: $index"

  # 5) Run eddy
  local eddy_out_prefix="$deriv_dwi/${subj}_eddy"
  log "Running $EDDY_CMD"
  "$EDDY_CMD" --imain="$dwi_nii" --mask="$nodif_mask" --acqp="$acqparams" --index="$index" --bvecs="$dwi_bvec" --bvals="$dwi_bval" --topup="$topup_out_prefix" --out="$eddy_out_prefix"

  echo
  echo "Done. Outputs:"
  echo "TOPUP: ${topup_out_prefix}*, ${unwarped_b0}.nii.gz, ${fieldmap_hz}.nii.gz"
  echo "Mask: $nodif_mask"
  echo "Eddy: ${eddy_out_prefix}.nii.gz and related files"
}

if [ "$SUBJECT" = "all" ]; then
  for d in "$BIDS_DIR"/sub-*; do
    [ -d "$d" ] || continue
    s=$(basename "$d")
    process_subject "$s" || log "Skipping $s due to error"
  done
else
  process_subject "$SUBJECT"
fi