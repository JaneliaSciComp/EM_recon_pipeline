#!/bin/bash

set -e

if (( $# < 1 )); then
  echo "USAGE $0 <wafer id> ...     (e.g. 60)
"
  exit 1
fi

WAFER_ID="${1}"
RUN_TIME=$(date +"%Y%m%d_%H%M%S")

source /groups/hess/hesslab/render/bin/source_miniforge3.sh

conda activate janelia_emrp_3_12

EMRP_ROOT="/groups/hess/hesslab/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/msem/build_google_beam_correction_xlog.py ${WAFER_ID}"

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
"""

# shellcheck disable=SC2086
python ${ARGS} 2>&1

JANELIA_BC_XLOG_ZARR=/groups/hess/hesslab/render/xlog/beam_correction/xlog_wafer_${WAFER_ID}.zarr
GOOGLE_BC_XLOG_ZARR=gs://janelia-spark-test/library/xlog_wafer_${WAFER_ID}.zarr

# rsync would leave any existing objects in place and mix them with the new data,
# so require the old zarr to be renamed or removed first
if gcloud storage ls "${GOOGLE_BC_XLOG_ZARR}" > /dev/null 2>&1; then
  echo "
ERROR: ${GOOGLE_BC_XLOG_ZARR} already exists, rename or remove it before copying.
"
  exit 1
fi

read -r -p "
Copy ${JANELIA_BC_XLOG_ZARR}
  to ${GOOGLE_BC_XLOG_ZARR} ? (y/n) " COPY_TO_GOOGLE

if [[ ! "${COPY_TO_GOOGLE}" =~ ^[Yy] ]]; then
  echo "
Skipping copy to Google storage.
"
  exit 0
fi

echo "copying data to Google ..."

# --no-user-output-enabled hides the 'Copying file:...' line printed for every zarr chunk
gcloud storage rsync --recursive --no-user-output-enabled "${JANELIA_BC_XLOG_ZARR}" "${GOOGLE_BC_XLOG_ZARR}"

echo "confirming that all data was copied to Google ..."
JANELIA_BC_XLOG_FILE_COUNT=$(find "${JANELIA_BC_XLOG_ZARR}" -type f | wc -l)

# gcloud storage ls fails when nothing matches, so ignore its exit status here (set -e would stop the script)
# and let the checks below report what is missing
GOOGLE_BC_XLOG_FILE_COUNT=$(gcloud storage ls --recursive "${GOOGLE_BC_XLOG_ZARR}/**" 2>/dev/null | wc -l || true)
GOOGLE_BC_XLOG_ZMETA=$(gcloud storage ls "${GOOGLE_BC_XLOG_ZARR}/.zmetadata" 2>/dev/null || true)

COPY_PROBLEMS=0

# arithmetic comparison ignores any padding wc adds around the counts
if (( JANELIA_BC_XLOG_FILE_COUNT == GOOGLE_BC_XLOG_FILE_COUNT )); then
  echo "  OK:    both locations have ${JANELIA_BC_XLOG_FILE_COUNT} files"
else
  echo "  ERROR: ${JANELIA_BC_XLOG_ZARR} has $(( JANELIA_BC_XLOG_FILE_COUNT )) files but ${GOOGLE_BC_XLOG_ZARR} has $(( GOOGLE_BC_XLOG_FILE_COUNT ))"
  COPY_PROBLEMS=$(( COPY_PROBLEMS + 1 ))
fi

if [ -n "${GOOGLE_BC_XLOG_ZMETA}" ]; then
  echo "  OK:    found ${GOOGLE_BC_XLOG_ZMETA}"
else
  echo "  ERROR: ${GOOGLE_BC_XLOG_ZARR}/.zmetadata is missing"
  COPY_PROBLEMS=$(( COPY_PROBLEMS + 1 ))
fi

if (( COPY_PROBLEMS > 0 )); then
  echo "
Found ${COPY_PROBLEMS} problem(s) with the copy to Google storage.
"
  exit 1
fi

echo "
All data was copied to Google storage.
"