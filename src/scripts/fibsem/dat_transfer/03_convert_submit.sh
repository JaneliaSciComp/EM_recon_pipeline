#!/bin/bash

umask 0002

FIBSEMXFER_DIR="/groups/fibsem/home/fibsemxfer"

# Set up LSF
source /misc/lsf/conf/profile.lsf

# loading LSF profile returns error code, so need to wait until here to set -e
set -e

RUN_DATE_AND_TIME=$(date +"%Y%m%d_%H%M%S")
RUN_YEAR_MONTH=$(echo "${RUN_DATE_AND_TIME}" | cut -c1-6)
RUN_DAY=$(echo "${RUN_DATE_AND_TIME}" | cut -c7-8)
LOG_DIR="${FIBSEMXFER_DIR}/logs/convert_submit/${RUN_YEAR_MONTH}/${RUN_DAY}"
mkdir -p "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/convert_submit.${RUN_DATE_AND_TIME}.log"

source ${FIBSEMXFER_DIR}/bin/source_miniforge3.sh

conda activate janelia_emrp

EMRP_ROOT="${FIBSEMXFER_DIR}/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/dat_converter_submitter.py"
ARGS="${ARGS} --volume_transfer_dir ${FIBSEMXFER_DIR}/config"
#ARGS="${ARGS} --max_batch_count 1"
#ARGS="${ARGS} --dats_per_hour 20"

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

# shellcheck disable=SC2086
python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"
RETURN_CODE="$?"

echo "python return code is ${RETURN_CODE}"
exit ${RETURN_CODE}