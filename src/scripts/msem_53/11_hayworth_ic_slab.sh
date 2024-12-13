#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

USAGE="
USAGE $0 <slab index> <scan index> e.g. 110 19
      $0 job <scan index>          e.g. job 19    to run with LSB_JOBINDEX as the slab index
"

if (( $# != 2 )); then
  echo "Error: Invalid number of arguments ($#) ${USAGE}"
  exit 1
fi

SLAB_INDEX="${1}"
SCAN_INDEX="${2}"

if [ "${SLAB_INDEX}" == "job" ]; then
  if [[ ${LSB_JOBINDEX} == 'undefined' || -z ${LSB_JOBINDEX} ]]; then
    echo "Error: LSB_JOBINDEX is not defined ${USAGE}"
    exit 1
  fi
  SLAB_INDEX="${LSB_JOBINDEX}"
fi

PREFIXED_SLAB_INDEX=$(printf "%03d" "${SLAB_INDEX}")
PREFIXED_SCAN_INDEX=$(printf "%03d" "${SCAN_INDEX}")

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs/slab_${PREFIXED_SLAB_INDEX}"
mkdir -p "${LOG_DIR}"

LOG_FILE="${LOG_DIR}/scan_${PREFIXED_SCAN_INDEX}.run_${RUN_TIME}.log"

echo """
Running $0 on ${HOSTNAME} at ${RUN_TIME} ...
""" | tee -a "${LOG_FILE}"

source /groups/flyem/data/render/bin/miniconda3/source_me.sh

conda activate janelia_emrp

# need this to avoid errors from render-python?
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="/groups/flyem/data/render/git/EM_recon_pipeline"

PYTHON_SCRIPT="${EMRP_ROOT}/src/python/janelia_emrp/msem/wafer_53_hayworth_adjust_sfov_contrast.py"
PARAMETERS_DIR="${EMRP_ROOT}/src/resources/wafer_53"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${PYTHON_SCRIPT} ${PARAMETERS_DIR} ${SLAB_INDEX} ${SCAN_INDEX}"

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

# shellcheck disable=SC2086
python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"