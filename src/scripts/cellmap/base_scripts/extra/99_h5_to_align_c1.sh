#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

VOL_XFER_INFO="${SCRIPT_DIR}/volume_transfer_info.${VOLUME_NAME}.channel-1.json"
if [ ! -f "${VOL_XFER_INFO}" ]; then
  echo "ERROR: ${VOL_XFER_INFO} does not exist"
  exit 1
fi

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/h5_to_c1_${RUN_TIME}.log"

echo "
Running $0 on ${HOSTNAME} at ${RUN_TIME} ...
" | tee -a ${LOG_FILE}

DASK_WORKER_SPACE="${LOG_DIR}/dask_work_${RUN_TIME}"
mkdir -p ${DASK_WORKER_SPACE}

source /groups/fibsem/home/fibsemxfer/bin/source_miniforge3.sh

conda activate janelia_emrp

# need this to avoid errors from render-python?
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="/groups/fibsem/home/fibsemxfer/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"


ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/h5_raw_to_align.py"
ARGS="${ARGS} --volume_transfer_info ${VOL_XFER_INFO}"
#ARGS="${ARGS} --num_workers 1"
ARGS="${ARGS} --num_workers 30"
ARGS="${ARGS} --parent_work_dir ${DASK_WORKER_SPACE}"
ARGS="${ARGS} --channel_index 1"
#ARGS="${ARGS} --first_h5 Merlin-6284_24-04-23_104107.raw-archive.h5 --last_h5 Merlin-6284_24-04-23_104144.raw-archive.h5"

echo "
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
" | tee -a ${LOG_FILE}

python ${ARGS} 2>&1 | tee -a ${LOG_FILE}