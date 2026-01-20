#!/bin/bash

set -e

umask 0002

FIBSEMXFER_DIR="/groups/fibsem/home/fibsemxfer"

 # ./02_convert_dats.sh config/volume_transfer_info.jrc_mus-hippocampus-1.json 1 /groups/cellmap/cellmap/data/jrc_mus-hippocampus-1/dat 239 Merlin-6049_23-07-17_090058_0-0-0.dat Merlin-6049_23-07-17_090058_0-1-1.dat
if (( $# < 3 )); then
  echo "USAGE $0 <transfer info file> <num workers> <parent work_dir> [lsf_runtime_limit] [first_dat] [last_dat]"
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

# need this to avoid errors from dask
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="${FIBSEMXFER_DIR}/git/EM_recon_pipeline"
PIXI_RUN="${FIBSEMXFER_DIR}/.pixi/bin/pixi run --manifest-path ${EMRP_ROOT}/pyproject.toml --enviornment janelia_emrp"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/dat_converter.py"
ARGS="${ARGS} --volume_transfer_info ${TRANSFER_INFO}"
ARGS="${ARGS} --num_workers ${NUM_WORKERS}"
ARGS="${ARGS} --parent_work_dir ${PARENT_WORK_DIR}"

if (( $# > 3 )); then
  ARGS="${ARGS} --lsf_runtime_limit ${4}"
  if (( $# > 4 )); then
    ARGS="${ARGS} --first_dat ${5}"
    if (( $# > 5 )); then
      ARGS="${ARGS} --last_dat ${6}"
    fi
  fi
fi

echo """
On ${HOSTNAME} at ${RUN_DATE_AND_TIME}

Running:
  ${PIXI_RUN} ${ARGS}
"""

# The exit status of a pipeline is the exit status of the last command in the pipeline,
# unless the pipefail option is enabled (see The Set Builtin).
# If pipefail is enabled, the pipeline's return status is the value of the last (rightmost) command
# to exit with a non-zero status, or zero if all commands exit successfully.
set -o pipefail

# shellcheck disable=SC2086
${PIXI_RUN} ${ARGS} 2>&1
RETURN_CODE="$?"

echo "python return code is ${RETURN_CODE}"
exit ${RETURN_CODE}