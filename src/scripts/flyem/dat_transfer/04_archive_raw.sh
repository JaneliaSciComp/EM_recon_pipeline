#!/bin/bash

set -e

umask 0002

DAT_TRANSFER_DIR="/groups/flyem/home/flyem/bin/dat_transfer/2022"

if (( $# < 1 )); then
  echo "USAGE $0 <num rsync processes>"
  exit 1
fi

NUM_PROCESSES="$1"

RUN_DATE_AND_TIME=$(date +"%Y%m%d_%H%M%S")
RUN_YEAR_MONTH=$(echo "${RUN_DATE_AND_TIME}" | cut -c1-6)
RUN_DAY=$(echo "${RUN_DATE_AND_TIME}" | cut -c7-8)
LOG_DIR="${DAT_TRANSFER_DIR}/logs/archive_raw/${RUN_YEAR_MONTH}/${RUN_DAY}"
mkdir -p "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/archive_raw.${RUN_DATE_AND_TIME}.log"

source /groups/flyem/data/render/bin/miniconda3/source_me.sh

conda activate janelia_emrp

EMRP_ROOT="/groups/flyem/data/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/h5_archivist.py"
ARGS="${ARGS} --volume_transfer_dir ${DAT_TRANSFER_DIR}/config"
ARGS="${ARGS} --processes ${NUM_PROCESSES}"

echo """
On ${HOSTNAME} at ${RUN_DATE_AND_TIME}

Running:
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

# The exit status of a pipeline is the exit status of the last command in the pipeline,
# unless the pipefail option is enabled (see The Set Builtin).
# If pipefail is enabled, the pipeline's return status is the value of the last (rightmost) command
# to exit with a non-zero status, or zero if all commands exit successfully.
set -o pipefail

python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"
RETURN_CODE="$?"

echo "python return code is ${RETURN_CODE}"
exit ${RETURN_CODE}