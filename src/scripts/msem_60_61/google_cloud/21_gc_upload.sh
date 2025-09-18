#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(realpath --no-symlinks "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/gc_upload_${RUN_TIME}.log"

if (( $# < 3 )); then
  echo "USAGE $0 <number of threads> <wafer> <serial slab> [serial slab] ...     (e.g. 32 60 360 361)
"
  exit 1
fi

NUM_THREADS="$1"
WAFER="$2"
shift 2
SERIAL_SLABS="$*"

RENDER_OWNER="hess_wafers_60_61"
BASE_PATH="hess_wafer_${WAFER}_data"

source /groups/hess/hesslab/render/bin/source_miniforge3.sh

conda activate janelia_emrp_3_12

# need this to avoid errors from render-python?
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="/groups/hess/hesslab/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/msem/wafer_60_gc_upload/gc_upload.py"

ARGS="${ARGS} --host http://em-services-1.int.janelia.org:8080/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --wafer ${WAFER} --slabs ${SERIAL_SLABS}"
ARGS="${ARGS} --num-threads ${NUM_THREADS}"
ARGS="${ARGS} --base-path ${BASE_PATH}"
ARGS="${ARGS} --invert"

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

# shellcheck disable=SC2086
python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"