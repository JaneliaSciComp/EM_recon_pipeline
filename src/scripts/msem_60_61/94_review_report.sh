#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/review_report_${RUN_TIME}.log"

if (( $# < 2 )); then
  echo "
USAGE:
  $0 <wafer id> <serial slab id> [serial slab id] ...

EXAMPLES:
  $0 60 296 297
  REVIEW_STRATEGY=0 SHOW_ALL_SCANS=y $0 60 296
  REPORT_EXCLUDED_SCANS=y $0 61 10

ENVIRONMENT:
  REVIEW_STRATEGY        review strategy id (default 0)
  SHOW_ALL_SCANS         y to also list scans whose mfovs are all USE (default n)
  REPORT_EXCLUDED_SCANS  y to also report wafer-wide excluded scans, slow (default n)
"
  exit 1
fi

WAFER_ID="${1}"
shift
SERIAL_SLABS="$*"

REVIEW_STRATEGY="${REVIEW_STRATEGY:-0}"
SHOW_ALL_SCANS="${SHOW_ALL_SCANS:-n}"
REPORT_EXCLUDED_SCANS="${REPORT_EXCLUDED_SCANS:-n}"

# NOTE: review_report.py derives the xlog path from the wafer id and converts the
#       serial slab ids to magc ids using the xlog, so there is no need to build the
#       path or to look the ids up in slab_info.w<wafer>.txt here

source /groups/hess/hesslab/render/bin/source_miniforge3.sh

conda activate janelia_emrp_3_12

EMRP_ROOT="/groups/hess/hesslab/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/msem/review_report.py"
ARGS="${ARGS} --wafer_id ${WAFER_ID}"
ARGS="${ARGS} --serial_slab ${SERIAL_SLABS}"
ARGS="${ARGS} --review_strategy ${REVIEW_STRATEGY}"

case "${SHOW_ALL_SCANS}" in
  y|Y) ARGS="${ARGS} --show_all_scans" ;;
  n|N) ;;
  *) echo "ERROR: SHOW_ALL_SCANS must be 'y' or 'n'"; exit 1 ;;
esac

case "${REPORT_EXCLUDED_SCANS}" in
  y|Y) ARGS="${ARGS} --report_excluded_scans" ;;
  n|N) ;;
  *) echo "ERROR: REPORT_EXCLUDED_SCANS must be 'y' or 'n'"; exit 1 ;;
esac

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

# shellcheck disable=SC2086
python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"
