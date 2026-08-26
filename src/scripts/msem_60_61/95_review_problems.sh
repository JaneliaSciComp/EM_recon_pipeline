#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/review_problems_${RUN_TIME}.log"

if (( $# != 3 )); then
  echo "
USAGE:
  $0 <wafer id> <first serial slab id> <last serial slab id>

Highlights the slab scans with non-USE review actions for a range of serial slabs,
ignoring the scans already excluded from import by 01_msem_to_render.sh.
Use this to find problems that were not accounted for during import.

EXAMPLES:
  $0 61 70 89
  REVIEW_STRATEGY=0 $0 60 0 19

ENVIRONMENT:
  REVIEW_STRATEGY  review strategy id (default 0)
"
  exit 1
fi

WAFER_ID="${1}"
FIRST_SERIAL_SLAB="${2}"
LAST_SERIAL_SLAB="${3}"

REVIEW_STRATEGY="${REVIEW_STRATEGY:-0}"

# NOTE: review_report.py derives the xlog path from the wafer id, converts the serial
#       slab ids to magc ids using the xlog, and defaults to skipping the scans that
#       01_msem_to_render.sh already excludes for the wafer

source /groups/hess/hesslab/render/bin/source_miniforge3.sh

conda activate janelia_emrp_3_12

EMRP_ROOT="/groups/hess/hesslab/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/msem/review_report.py"
ARGS="${ARGS} --wafer_id ${WAFER_ID}"
ARGS="${ARGS} --serial_slab_range ${FIRST_SERIAL_SLAB} ${LAST_SERIAL_SLAB}"
ARGS="${ARGS} --review_strategy ${REVIEW_STRATEGY}"
ARGS="${ARGS} --problems_only"

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

# shellcheck disable=SC2086
python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"
