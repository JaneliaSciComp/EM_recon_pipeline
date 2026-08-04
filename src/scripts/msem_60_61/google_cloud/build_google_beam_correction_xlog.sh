#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

if (( $# < 1 )); then
  echo "USAGE $0 <wafer id> ...     (e.g. 60)
"
  exit 1
fi

WAFER_ID="${1}"

source /groups/hess/hesslab/render/bin/source_miniforge3.sh

conda activate janelia_emrp_3_12

EMRP_ROOT="/groups/hess/hesslab/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/msem/build_google_beam_correction_xlog.py ${WAFER_ID}"

echo """
On ${HOSTNAME} at ${RUN_TIME}

Running:
  python ${ARGS}
"""

# shellcheck disable=SC2086
python ${ARGS} 2>&1