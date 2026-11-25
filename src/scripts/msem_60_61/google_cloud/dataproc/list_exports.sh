#!/bin/bash

# ----------------------------------------------------------------------------
# Lists the exported volumes in Google storage for one wafer 60 or 61 render project, e.g. for
# --project w61_serial_070_to_079:
#
#   gs://janelia-spark-test/hess_wafers_60_61_export/render/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_asoi_3d___pixel
#   gs://janelia-spark-test/hess_wafers_60_61_export/render/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i___pixel
#   gs://janelia-spark-test/hess_wafers_60_61_export/render/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i___mask
#
# or for --project w60_serial_360_to_369:
#
#   gs://janelia-spark-test/hess_wafers_60_61_export/render/w60_serial_360_to_369/w60_s360_r00_d20_gc_align___20250320_131555
#
# Any volume named <stack>___<dataset suffix> is listed: ___pixel and ___mask exports, ones renamed by
# move_exports.sh (e.g. ..._asoi_3d___pixel_20260925), and earlier exports (mostly wafer 60) whose
# dataset suffix is the run time (11_run_n5_export.sh --dataset-suffix, or the run time appended to a
# name that already existed).

# keep this in sync with N5_PATH in 11_run_n5_export.sh
EXPORT_BASE_URL="gs://janelia-spark-test/hess_wafers_60_61_export/render"
# exports are <stack>___<dataset suffix>, e.g. <stack>___pixel, <stack>___mask, <stack>___pixel_20260925,
# or <stack>___20250320_131555
DATASET_MARKER_PATTERN="___[A-Za-z0-9]"

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_PROJECT=""
ARG_LEVELS="false"

usage() {
  echo "
USAGE $0 --project <project> [--levels]

  --project  render project of the exports to list, e.g. w61_serial_070_to_079
             or w60_serial_360_to_369 (required)
  --levels   also list the scale levels (s0, s1, ...) of each export

Lists every <stack>___<dataset suffix> volume (e.g. ___pixel, ___mask, or ___20250320_131555) in
${EXPORT_BASE_URL}/<project>

Examples:
  $0 --project w61_serial_070_to_079
  $0 --project w61_serial_070_to_079 --levels
  $0 --project w60_serial_360_to_369
"
  exit 1
}

if (( $# < 1 )); then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --project)
      ARG_PROJECT="${2:?'--project requires a value'}"
      shift 2
      ;;
    --levels)
      ARG_LEVELS="true"
      shift
      ;;
    *)
      echo "ERROR: unrecognized parameter '${1}'"
      usage
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Validate parameters

# a trailing slash (e.g. from tab completion) is harmless, so drop it
ARG_PROJECT="${ARG_PROJECT%/}"

if [[ ! "${ARG_PROJECT}" =~ ^w6[01]_serial_[0-9]{3}_to_[0-9]{3}$ ]]; then
  echo "ERROR: --project must look like w61_serial_070_to_079 or w60_serial_360_to_369 (not '${ARG_PROJECT}')"
  exit 1
fi

PROJECT_URL="${EXPORT_BASE_URL}/${ARG_PROJECT}"

# ----------------------------------------------------------------------------
# List exports

# gcloud storage ls fails when nothing matches, so no output means the project does not exist
PROJECT_LISTING=$(gcloud storage ls "${PROJECT_URL}/" 2>/dev/null)

if [ -z "${PROJECT_LISTING}" ]; then
  printf "\nno exports found, %s does not exist\n\n" "${PROJECT_URL}"
  exit 1
fi

# directory entries are listed with a trailing slash, which is dropped for display
EXPORT_URLS=()
while IFS= read -r EXPORT_URL; do
  EXPORT_URLS+=("${EXPORT_URL%/}")
done < <(echo "${PROJECT_LISTING}" | grep -E "/[^/]*${DATASET_MARKER_PATTERN}[^/]*/$" | sort)

if (( ${#EXPORT_URLS[@]} == 0 )); then
  printf "\nno exports found in %s\n\n" "${PROJECT_URL}"
  exit 1
fi

printf "\n"

for EXPORT_URL in "${EXPORT_URLS[@]}"; do
  if [ "${ARG_LEVELS}" = "true" ]; then
    LEVEL_NAMES=$(gcloud storage ls "${EXPORT_URL}/" 2>/dev/null |
                    sed -nE 's#.*/(s[0-9]+)/$#\1#p' | sort -V | paste -sd ' ' -)
    printf "%s  [%s]\n" "${EXPORT_URL}" "${LEVEL_NAMES:-no levels}"
  else
    printf "%s\n" "${EXPORT_URL}"
  fi
done

printf "\nfound %d export(s) in %s\n\n" "${#EXPORT_URLS[@]}" "${PROJECT_URL}"
