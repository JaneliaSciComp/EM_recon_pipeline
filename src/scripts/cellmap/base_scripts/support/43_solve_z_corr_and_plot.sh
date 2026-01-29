#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/../00_config.sh"

if (( $# != 2 )); then
  echo "USAGE: $0 <solve base parameters file> <inference options file>"
  exit 1
fi

SOLVE_BASE_PARAMETERS_FILE=$(readlink -m "${1}")
INFERENCE_OPTIONS_FILE=$(readlink -m "${2}")

if [[ ! -f ${SOLVE_BASE_PARAMETERS_FILE} ]]; then
  echo "ERROR: ${SOLVE_BASE_PARAMETERS_FILE} not found"
  exit 1
fi

if [[ ! -f ${INFERENCE_OPTIONS_FILE} ]]; then
  echo "ERROR: ${INFERENCE_OPTIONS_FILE} not found"
  exit 1
fi

RUN_DIR=$(dirname "${SOLVE_BASE_PARAMETERS_FILE}")
RUN_NAME=$(basename "${RUN_DIR}")

LOGS_DIR="${RUN_DIR}/logs"
mkdir -p "${LOGS_DIR}"

# use shell group to tee all output to log file
{

# ---------------------------
# run solve

JAVA_CLASS="org.janelia.render.client.zspacing.ZPositionCorrectionClient"

ARGS=$(cat "${SOLVE_BASE_PARAMETERS_FILE}")
ARGS="${ARGS} --solveExisting"
ARGS="${ARGS} --optionsJson ${INFERENCE_OPTIONS_FILE}"
ARGS="${ARGS} --normalizedEdgeLayerCount 30"

# shellcheck disable=SC2086
${RENDER_CLIENT_SCRIPT} ${RENDER_CLIENT_HEAP} ${JAVA_CLASS} ${ARGS}


# ---------------------------
# merge cc data

CC_BATCHES_DIR="${RENDER_NRS_ROOT}/z_corr/${RENDER_OWNER}/${RENDER_PROJECT}/${ALIGN_STACK}/${RUN_NAME}/cc_batches"

if [[ ! -d ${CC_BATCHES_DIR} ]]; then
  echo "ERROR: ${CC_BATCHES_DIR} not found"
  exit 1
fi

JAVA_CLASS="org.janelia.render.client.zspacing.CrossCorrelationDataMerger"

# shellcheck disable=SC2086
${RENDER_CLIENT_SCRIPT} ${RENDER_CLIENT_HEAP} ${JAVA_CLASS} ${CC_BATCHES_DIR}

} 1>>"${LOGS_DIR}"/cc_solve.log 2>&1

echo
grep Zcoords.txt "${LOGS_DIR}"/cc_solve.log
echo

# ---------------------------
# generate plots

export PYTHONPATH="${EMRP_ROOT}/src/python"

Z_CORR_SCRIPTS_DIR="${EMRP_ROOT}/src/python/janelia_emrp/zcorr"
ARGS="--base_dir ${RENDER_NRS_ROOT}/z_corr --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${ALIGN_STACK} --run ${RUN_NAME}"

for SCRIPT in plot_cross_correlation.py plot_z_coords.py plot_regional_cross_correlation.py; do
  echo "
Running:
  ${PIXI_RUN} ${Z_CORR_SCRIPTS_DIR}/${SCRIPT} ${ARGS}
  "
  # shellcheck disable=SC2086
  ${PIXI_RUN} ${Z_CORR_SCRIPTS_DIR}/${SCRIPT} ${ARGS}
done
