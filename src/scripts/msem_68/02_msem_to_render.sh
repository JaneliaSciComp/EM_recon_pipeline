#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

RUN_TIME=$(date +"%Y%m%d_%H%M%S")
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/import_${RUN_TIME}.log"

SINGLE_SLAB_JSON="$1"

if (( $# != 1 )); then
  echo "
USAGE $0 <single slab json file>     (e.g. sample_68_image_coord.json)
"
  exit 1
fi

if [ ! -f "${SINGLE_SLAB_JSON}" ]; then
  echo "
single slab json file ${SINGLE_SLAB_JSON} is not a file
"
  exit 1
fi

RENDER_HOST="em-services-1.int.janelia.org"
WAFER_ID="68"
RENDER_OWNER="hess_sample_${WAFER_ID}"

source /groups/hess/hesslab/render/bin/source_miniforge3.sh

conda activate janelia_emrp_3_12

# need this to avoid errors from render-python?
export OPENBLAS_NUM_THREADS=1

EMRP_ROOT="/groups/hess/hesslab/render/git_hayworth/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/msem/msem_to_render.py"
ARGS="${ARGS} --render_host ${RENDER_HOST} --render_owner ${RENDER_OWNER}"
ARGS="${ARGS} --wafer_id ${WAFER_ID} --path_single_slab_json ${SINGLE_SLAB_JSON}"

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
""" | tee -a "${LOG_FILE}"

# shellcheck disable=SC2086
python ${ARGS} 2>&1 | tee -a "${LOG_FILE}"