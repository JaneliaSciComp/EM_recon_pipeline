#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/bg_correct_${RUN_TIME}.log"

RENDER_HOST="em-services-1.int.janelia.org"
WAFER_ID="68"
RENDER_OWNER="hess_sample_${WAFER_ID}_full"
SOURCE_SUFFIX="_par_align_c"
NUM_THREADS=60

source /groups/hess/hesslab/render/bin/source_miniforge3.sh

conda activate janelia_emrp_3_12

# need this to avoid errors from render-python?
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="/groups/hess/hesslab/render/git_hayworth/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/msem/background_correction/w_68_local.py"
ARGS="${ARGS} --host ${RENDER_HOST} --owner ${RENDER_OWNER}"
ARGS="${ARGS} --output-path ${OUTPUT_PATH}"
ARGS="${ARGS} --suffix ${SOURCE_SUFFIX}"  # Stack name suffix to match (e.g. '_pa_mat_render_align'). If not given, matches bare region stacks like w68_s000_r00.
ARGS="${ARGS} --invert"                   # Invert the images after background correction.
#ARGS="${ARGS} --shading-storage-path ..." # Storage path for shading (shading is not stored if path is not given).
ARGS="${ARGS} --num-threads ${NUM_THREADS}"

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

# shellcheck disable=SC2086
python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"