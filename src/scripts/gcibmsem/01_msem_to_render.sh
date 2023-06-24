#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/import_${RUN_TIME}.log"

#DASK_WORKER_SPACE="${LOG_DIR}/dask_work_${RUN_TIME}"
#mkdir -p ${DASK_WORKER_SPACE}

source /groups/flyem/data/render/bin/miniconda3/source_me.sh

conda activate janelia_emrp

# need this to avoid errors from render-python?
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="/groups/flyem/data/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/gcibmsem/gcibmsem_to_render.py"
ARGS="${ARGS} --render_host ${RENDER_HOST} --render_owner ${RENDER_OWNER}"
ARGS="${ARGS} --wafer_base_path ${WAFER_BASE_PATH}"
ARGS="${ARGS} --exclude_scan_name scan_000"
ARGS="${ARGS} --import_scan_name scan_001 scan_042"
#ARGS="${ARGS} --import_project_name cut_350_to_359"

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

# shellcheck disable=SC2086
python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"