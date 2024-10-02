#!/bin/bash

set -e

umask 0002

DAT_TRANSFER_DIR="/groups/flyem/home/flyem/bin/dat_transfer/2022"

if (( $# != 2 )); then
  echo "USAGE $0 <scope> <max_transfer_minutes> (e.g. jeiss5.hhmi.org 9)"
  exit 1
fi

SCOPE="$1"
MAX_TRANSFER_MINUTES="$2"

RUN_DATE_AND_TIME=$(date +"%Y%m%d_%H%M%S")
RUN_YEAR_MONTH=$(echo "${RUN_DATE_AND_TIME}" | cut -c1-6)
LOG_DIR="${DAT_TRANSFER_DIR}/logs/copy_dat/${SCOPE}"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/${SCOPE}__${RUN_YEAR_MONTH}.log"

source /groups/flyem/data/render/bin/miniconda3/source_me.sh

conda activate janelia_emrp

EMRP_ROOT="/groups/flyem/data/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/dat_copier.py"
ARGS="${ARGS} --volume_transfer_dir ${DAT_TRANSFER_DIR}/config"
ARGS="${ARGS} --scope ${SCOPE}"
ARGS="${ARGS} --max_transfer_minutes ${MAX_TRANSFER_MINUTES}"

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