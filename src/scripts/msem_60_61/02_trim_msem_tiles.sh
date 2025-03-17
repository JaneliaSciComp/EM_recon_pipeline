#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/trim_${RUN_TIME}.log"

if (( $# < 5 )); then
  echo "
USAGE:
  $0 <wafer id> <dilation> <exclude resin flag: y|n> <render project> <stack> [stack] ...

EXAMPLES:
  $0 60 30 n w60_serial_360_to_369 w60_s360_r00
  $0 60 20 y w60_serial_360_to_369 w60_s360_r00
"
  exit 1
fi

WAFER_ID="${1}"
DILATION="${2}"
EXCLUDE_RESIN="${3}"
RENDER_PROJECT="${4}"
shift 4
RENDER_STACKS="$*"

WAFER_XLOG_DIR="/groups/hess/hesslab/ibeammsem/system_02/wafers/wafer_${WAFER_ID}/xlog/xlog_wafer_${WAFER_ID}.zarr"

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

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/msem/msem_tile_trimmer.py"
ARGS="${ARGS} --dilation ${DILATION} --path_xlog ${WAFER_XLOG_DIR}"
ARGS="${ARGS} --render_host ${RENDER_HOST} --render_owner ${RENDER_OWNER}"
ARGS="${ARGS} --render_project ${RENDER_PROJECT} --render_stack ${RENDER_STACKS}"

case "${EXCLUDE_RESIN}" in
  y|Y) ARGS="${ARGS} --exclude_resin" ;;
  n|N) ;;
  *) echo "ERROR: exclude resin flag must be 'y' or 'n'"; exit 1 ;;
esac

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

# shellcheck disable=SC2086
python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"