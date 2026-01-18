#!/bin/bash

set -e

umask 0002

if (( $# < 2 )); then
  echo "USAGE $0 <dat output directory> <h5 path> [h5 path] ..."
  exit 1
fi

DAT_OUTPUT_DIR="$1"
shift

if [[ ! -d "${DAT_OUTPUT_DIR}" ]]; then
  echo "ERROR: ${DAT_OUTPUT_DIR} not found!"
  exit 1
fi

RUN_DATE_AND_TIME=$(date +"%Y%m%d_%H%M%S")

FIBSEMXFER_DIR="/groups/fibsem/home/fibsemxfer"
EMRP_ROOT="${FIBSEMXFER_DIR}/git/EM_recon_pipeline"

source ${FIBSEMXFER_DIR}/bin/source_miniforge3.sh

conda activate janelia_emrp

# need this to avoid errors from dask
export OPENBLAS_NUM_THREADS=1

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/h5_to_dat.py"
ARGS="${ARGS} --dat_parent_path ${DAT_OUTPUT_DIR}"
ARGS="${ARGS} --restore_dat_files"
ARGS="${ARGS} --h5_path $*"

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

# shellcheck disable=SC2086
python ${ARGS} 2>&1
RETURN_CODE="$?"

echo "python return code is ${RETURN_CODE}"
exit ${RETURN_CODE}
