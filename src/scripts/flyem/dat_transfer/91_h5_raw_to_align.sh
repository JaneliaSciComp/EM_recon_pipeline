#!/bin/bash

set -e

umask 0002

if (( $# < 3 )); then
  echo "USAGE $0 <transfer info file> <num workers> <parent work_dir> [lsf_runtime_limit] [first_raw_h5] [last_raw_h5]"
  exit 1
fi

TRANSFER_INFO="$1"
NUM_WORKERS="$2"
PARENT_WORK_DIR="$3"

if [[ "${HOSTNAME}" =~ ^(e05u15|e05u16) ]]; then
  echo "ERROR: running on login1 or login2, need to bsub this job first ..."
  exit 1
fi

RUN_DATE_AND_TIME=$(date +"%Y%m%d_%H%M%S")

source /groups/flyem/data/render/bin/miniconda3/source_me.sh

conda activate janelia_emrp

# need this to avoid errors from dask
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="/groups/flyem/data/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/h5_raw_to_align.py"
ARGS="${ARGS} --volume_transfer_info ${TRANSFER_INFO}"
ARGS="${ARGS} --num_workers ${NUM_WORKERS}"
ARGS="${ARGS} --parent_work_dir ${PARENT_WORK_DIR}"

if (( $# > 3 )); then
  ARGS="${ARGS} --lsf_runtime_limit ${4}"
  if (( $# > 4 )); then
    ARGS="${ARGS} --first_h5 ${5}"
    if (( $# > 5 )); then
      ARGS="${ARGS} --last_h5 ${6}"
    fi
  fi
fi

echo """
On ${HOSTNAME} at ${RUN_DATE_AND_TIME}

Running:
  python ${ARGS}
"""

# The exit status of a pipeline is the exit status of the last command in the pipeline,
# unless the pipefail option is enabled (see The Set Builtin).
# If pipefail is enabled, the pipeline's return status is the value of the last (rightmost) command
# to exit with a non-zero status, or zero if all commands exit successfully.
set -o pipefail

python ${ARGS} 2>&1
RETURN_CODE="$?"

echo "python return code is ${RETURN_CODE}"
exit ${RETURN_CODE}
