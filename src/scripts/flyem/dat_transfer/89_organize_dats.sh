#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`

if (( $# < 2 )); then
  echo "USAGE $0 <source dir> <target dir> ( e.g. /nrs/fibsem/data/jrc_tough-resin_RD/dat_scope /nrs/fibsem/data/jrc_tough-resin_RD/dat )"
  exit 1
fi

SOURCE_DIR="$1"
TARGET_DIR="$2"

mkdir -p "${TARGET_DIR}"

RUN_TIME=$(date +"%Y%m%d_%H%M%S")

source /groups/flyem/data/render/bin/miniconda3/source_me.sh 

conda activate janelia_emrp

EMRP_ROOT="/groups/flyem/data/render/git/EM_recon_pipeline"

export PYTHONPATH="${EMRP_ROOT}/src/python"

ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/dat_path.py"
ARGS="${ARGS} --source ${SOURCE_DIR}"
ARGS="${ARGS} --target ${TARGET_DIR}"

echo """
On ${HOSTNAME} at ${RUN_TIME}

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
