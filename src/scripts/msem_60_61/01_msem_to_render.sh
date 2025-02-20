#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/import_${RUN_TIME}.log"

if (( $# < 2 )); then
  echo "USAGE $0 <wafer id> <magc slab id> [magc slab id] ...     (e.g. 60 399)
"
  exit 1
fi

WAFER_ID="${1}"
shift
MAGC_SLABS="$*"

WAFER_XLOG_DIR="/groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_${WAFER_ID}/xlog/xlog_wafer_${WAFER_ID}.zarr"

if [ "${WAFER_ID}" == "60" ]; then
  WAFER_EXCLUDED_SCAN_ARG="--exclude_scan 0 1 2 3 7 18"
elif [ "${WAFER_ID}" == "61" ]; then
  WAFER_EXCLUDED_SCAN_ARG="--exclude_scan TBD"
else
  echo "ERROR: invalid wafer number ${WAFER_ID}"
  exit 1
fi

if [ ! -d "${WAFER_XLOG_DIR}" ]; then
  echo "ERROR: ${WAFER_XLOG_DIR} not found"
  exit 1
fi

source /groups/hess/hesslab/render/bin/source_miniforge3.sh

conda activate janelia_emrp_3_12

# need this to avoid errors from render-python?
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="/groups/hess/hesslab/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/msem/msem_to_render.py"
ARGS="${ARGS} --render_host ${RENDER_HOST} --render_owner ${RENDER_OWNER}"
ARGS="${ARGS} --wafer_id ${WAFER_ID} --path_xlog ${WAFER_XLOG_DIR} ${WAFER_EXCLUDED_SCAN_ARG}"
ARGS="${ARGS} --import_magc_slab ${MAGC_SLABS}"

#ARGS="${ARGS} --include_scan 6" # will override excluded scan arg

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

# shellcheck disable=SC2086
python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"