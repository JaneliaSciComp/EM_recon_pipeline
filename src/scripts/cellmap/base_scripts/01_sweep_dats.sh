#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

TRANSFER_INFO_JSON=$(ls "${SCRIPT_DIR}"/volume_transfer_info.*.json)
if [[ ! -f "${TRANSFER_INFO_JSON}" ]]; then
  echo "ERROR: ${TRANSFER_INFO_JSON} not found!"
  exit 1
fi

SCOPE=$(${JQ} '.scope_data_set.host' "${TRANSFER_INFO_JSON}")

SWEEP_LOG_DIR="${SCRIPT_DIR}/logs/sweep"
mkdir -p "${SWEEP_LOG_DIR}"
LOG_FILE="${SWEEP_LOG_DIR}/sweep_dat.log"

# shellcheck source=???
source "${SOURCE_MINIFORGE3_SCRIPT}"

conda activate janelia_emrp

# save environment python executable path so that it can be used when running as fibsemxfer user in last line below
PYTHON_EXE=$(type python | awk '{print $3}')

# export path to scripts
export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/dat_sweeper.py"
ARGS="${ARGS} --volume_transfer_dir ${SCRIPT_DIR}"
ARGS="${ARGS} --scope ${SCOPE}"
ARGS="${ARGS} --max_transfer_minutes 240"
ARGS="${ARGS} --num_workers 8 --parent_work_dir ${SWEEP_LOG_DIR} $*"

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running (as fibsemxfer user for connection to scope):
  ${PYTHON_EXE} ${ARGS}
""" | tee -a "${LOG_FILE}"

su -c "umask 0002; ${PYTHON_EXE} ${ARGS} 2>&1 | tee -a ${LOG_FILE}" fibsemxfer