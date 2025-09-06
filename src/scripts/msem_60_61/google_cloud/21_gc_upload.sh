#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/gc_upload_${RUN_TIME}.log"

if (( $# < 2 )); then
  echo "USAGE $0 <wafer> <magc slab> [magc slab] ...     (e.g. 60 399)

  wafer 60 serial slab 360 = magc slab 399
  wafer 60 serial slab 361 = magc slab 298
  wafer 60 serial slab 362 = magc slab 295
  wafer 60 serial slab 363 = magc slab 70
  wafer 60 serial slab 364 = magc slab 391
  wafer 60 serial slab 365 = magc slab 410
  wafer 60 serial slab 366 = magc slab 27
  wafer 60 serial slab 367 = magc slab 381
  wafer 60 serial slab 368 = magc slab 7
  wafer 60 serial slab 369 = magc slab 380
"
  exit 1
fi

WAFER="$1"
shift
SLABS="$*"

RENDER_OWNER="hess_wafers_60_61"
NUM_THREADS=32

source /groups/hess/hesslab/render/bin/source_miniforge3.sh

conda activate janelia_emrp_3_12

# need this to avoid errors from render-python?
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="/groups/hess/hesslab/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/msem/wafer_60_gc_upload/gc_upload.py"

ARGS="${ARGS} --host http://em-services-1.int.janelia.org:8080/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --wafer ${WAFER} --slabs ${SLABS}"
ARGS="${ARGS} --num-threads ${NUM_THREADS}"
ARGS="${ARGS} --base-path  hess_wafer_60_data"
ARGS="${ARGS} --invert"

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

# shellcheck disable=SC2086
python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"