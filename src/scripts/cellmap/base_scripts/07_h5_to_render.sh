#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/run_${RUN_TIME}.log"

TRANSFER_INFO_JSON=$(ls "${SCRIPT_DIR}"/volume_transfer_info.*.json)
if [[ -f "${TRANSFER_INFO_JSON}" ]]; then
    LAST_DAT=$(${JQ} -r '.scope_data_set.last_dat_name' "${TRANSFER_INFO_JSON}")
    # "last_dat_name": "Merlin-6262_25-04-08_153541_0-1-2.dat"
    if [[ "${LAST_DAT}" != Merlin* ]]; then
        echo "ERROR: invalid ${TRANSFER_INFO_JSON}, last_dat_name '${LAST_DAT}' does not start with 'Merlin'"
        exit 1
    fi
else
  echo "ERROR: ${TRANSFER_INFO_JSON} not found!"
  exit 1
fi

echo "
Running $0 on ${HOSTNAME} at ${RUN_TIME} ...
" | tee -a "${LOG_FILE}"

DASK_WORKER_SPACE="${LOG_DIR}/dask_work_${RUN_TIME}"
mkdir -p "${DASK_WORKER_SPACE}"

# need this to avoid errors from render-python
export OPENBLAS_NUM_THREADS=1

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/h5_to_render.py"
ARGS="${ARGS} --volume_transfer_info ${SCRIPT_DIR}/volume_transfer_info.${VOLUME_NAME}.json"
#ARGS="${ARGS} --num_workers 1"
ARGS="${ARGS} --num_workers 30"
ARGS="${ARGS} --num_threads 4"
ARGS="${ARGS} --dask_worker_space ${DASK_WORKER_SPACE}"
#ARGS="${ARGS} --min_layer_index 0 --max_layer_index 2027"

echo "
On ${HOSTNAME} at ${RUN_TIME}

Running:
  ${PIXI_RUN} ${ARGS}
" | tee -a "${LOG_FILE}"

# shellcheck disable=SC2086
${PIXI_RUN} ${ARGS} 2>&1 | tee -a "${LOG_FILE}"
