#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

TRANSFER_INFO_JSON=$(ls "${SCRIPT_DIR}"/volume_transfer_info.*.json)
if [[ ! -f "${TRANSFER_INFO_JSON}" ]]; then
  echo "ERROR: ${TRANSFER_INFO_JSON} not found!"
  exit 1
fi

JQ="/groups/flyem/data/render/bin/jq"
SCOPE=$(${JQ} '.scope_data_set.host' "${TRANSFER_INFO_JSON}")

SWEEP_LOG_DIR="${SCRIPT_DIR}/logs/sweep"
mkdir -p "${SWEEP_LOG_DIR}"
LOG_FILE="${SWEEP_LOG_DIR}/sweep_dat.log"

source /groups/flyem/data/render/bin/miniconda3/source_me.sh

conda activate janelia_emrp

EMRP_ROOT="/groups/flyem/data/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/dat_sweeper.py"
ARGS="${ARGS} --volume_transfer_dir ${SCRIPT_DIR}"
ARGS="${ARGS} --scope ${SCOPE}"
ARGS="${ARGS} --max_transfer_minutes 240"
ARGS="${ARGS} --num_workers 8 --parent_work_dir ${SWEEP_LOG_DIR} $*"

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running (as flyem user for connection to scope):
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

su -c "umask 0002; python ${ARGS} 2>&1 | tee -a ${LOG_FILE}" flyem