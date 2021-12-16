#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

if (( $# != 2 )); then
  echo "USAGE: $0 <solve base parameters file> <inference options file>"
  exit 1
fi

SOLVE_BASE_PARAMETERS_FILE=$(readlink -m $1)
INFERENCE_OPTIONS_FILE=$(readlink -m $2)

if [[ ! -f ${SOLVE_BASE_PARAMETERS_FILE} ]]; then
  echo "ERROR: ${SOLVE_BASE_PARAMETERS_FILE} not found"
  exit 1
fi

if [[ ! -f ${INFERENCE_OPTIONS_FILE} ]]; then
  echo "ERROR: ${INFERENCE_OPTIONS_FILE} not found"
  exit 1
fi

RUN_DIR=$(dirname ${SOLVE_BASE_PARAMETERS_FILE})
RUN_NAME=$(basename ${RUN_DIR})

LOGS_DIR="${RUN_DIR}/logs"
mkdir -p ${LOGS_DIR}

# use shell group to tee all output to log file
{

# ---------------------------
# run solve

JAVA_CLASS="org.janelia.render.client.zspacing.ZPositionCorrectionClient"

ARGS=$(cat ${SOLVE_BASE_PARAMETERS_FILE})
ARGS="${ARGS} --solveExisting"
ARGS="${ARGS} --optionsJson ${INFERENCE_OPTIONS_FILE}"
ARGS="${ARGS} --normalizedEdgeLayerCount 30"

${RENDER_CLIENT_SCRIPT} ${RENDER_CLIENT_HEAP} ${JAVA_CLASS} ${ARGS}


# ---------------------------
# merge cc data

CC_BATCHES_DIR="/nrs/flyem/render/z_corr/${RENDER_OWNER}/${RENDER_PROJECT}/${ALIGN_STACK}/${RUN_NAME}/cc_batches"

if [[ ! -d ${CC_BATCHES_DIR} ]]; then
  echo "ERROR: ${CC_BATCHES_DIR} not found"
  exit 1
fi

JAVA_CLASS="org.janelia.render.client.zspacing.CrossCorrelationDataMerger"

${RENDER_CLIENT_SCRIPT} ${RENDER_CLIENT_HEAP} ${JAVA_CLASS} ${CC_BATCHES_DIR}

} 2>&1 1>>${LOGS_DIR}/cc_solve.log

echo
grep Zcoords.txt ${LOGS_DIR}/cc_solve.log
echo

# ---------------------------
# generate plots

Z_CORR_SCRIPTS_DIR="/groups/flyem/data/trautmane/z_corr"

ARGS="${RENDER_OWNER} ${RENDER_PROJECT} ${ALIGN_STACK} ${RUN_NAME}"

${Z_CORR_SCRIPTS_DIR}/plot_cross_correlation.sh ${ARGS}

${Z_CORR_SCRIPTS_DIR}/plot_z_coords.sh ${ARGS}
