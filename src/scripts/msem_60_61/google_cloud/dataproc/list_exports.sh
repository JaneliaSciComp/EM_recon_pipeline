#!/bin/bash

# ----------------------------------------------------------------------------
# Lists the exported pixel and mask volumes in Google storage for one render project, e.g. for
# --project w61_serial_070_to_079:
#
#   gs://janelia-spark-test/hess_wafers_60_61_export/render/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_asoi_3d___pixel
#   gs://janelia-spark-test/hess_wafers_60_61_export/render/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i___pixel
#   gs://janelia-spark-test/hess_wafers_60_61_export/render/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_aso_3d_s3i___mask
#
# Any volume whose name contains ___pixel or ___mask is listed, including ones renamed by move_exports.sh
# (e.g. ..._asoi_3d___pixel_20260925).

# keep this in sync with N5_PATH in 11_run_n5_export.sh
EXPORT_BASE_URL="gs://janelia-spark-test/hess_wafers_60_61_export/render"
# exports are <stack>___pixel or <stack>___mask, optionally followed by a suffix
DATASET_MARKER_PATTERN="___(pixel|mask)"

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_PROJECT=""
ARG_LEVELS="false"

usage() {
  echo "
USAGE $0 --project <project> [--levels]

  --project  render project of the exports to list, e.g. w61_serial_070_to_079 (required)
  --levels   also list the scale levels (s0, s1, ...) of each export

Lists every <stack>*___pixel* and <stack>*___mask* volume in
${EXPORT_BASE_URL}/<project>

Examples:
  $0 --project w61_serial_070_to_079
  $0 --project w61_serial_070_to_079 --levels
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

if [[ ! "${ARG_PROJECT}" =~ ^w[0-9]+_serial_[0-9]{3}_to_[0-9]{3}$ ]]; then
  echo "ERROR: --project must look like w61_serial_070_to_079 (not '${ARG_PROJECT}')"
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
