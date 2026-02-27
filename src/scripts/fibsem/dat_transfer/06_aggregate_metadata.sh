#!/bin/bash

set -e

umask 0002

FIBSEMXFER_DIR="/groups/fibsem/home/fibsemxfer"
PLOT_ROOT="/groups/fibsem/fibsem/hosted/metadata_plots"

if (( $# < 1 )); then
  echo "USAGE $0 <transfer JSON directory>     e.g. /groups/fibsem/home/fibsemxfer/config"
  exit 1
fi

TRANSFER_JSON_DIR="${1}"
if [ ! -d "${TRANSFER_JSON_DIR}" ]; then
  echo "ERROR: ${TRANSFER_JSON_DIR} is not a directory"
  exit 1
else
  echo "
Using transfer JSON directory: ${TRANSFER_JSON_DIR}
"
fi

if compgen -G "${TRANSFER_JSON_DIR}/volume_transfer_info.*.json" > /dev/null; then
    cd "${TRANSFER_JSON_DIR}"
    TRANSFER_JSON_FILES=$(ls volume_transfer_info.*.json)
else
  echo "WARNING: no volume_transfer_info JSON files found in ${TRANSFER_JSON_DIR}"
  exit 0
fi

#-----------------------------------------------------------
# Setup Python environment ...

EMRP_ROOT="${FIBSEMXFER_DIR}/git/EM_recon_pipeline"
PIXI_RUN="${FIBSEMXFER_DIR}/.pixi/bin/pixi run --manifest-path ${EMRP_ROOT}/pyproject.toml --environment fibsem --frozen python"

export PYTHONPATH="${EMRP_ROOT}/src/python"

JQ="${FIBSEMXFER_DIR}/bin/jq"

echo "
Generating FIBSEM metadata plots at https://fibsem-data.int.janelia.org/metadata_plots
"

#-----------------------------------------------------------
# Loop over all transfer JSON files and aggregate metadata for each one ...

for TRANSFER_JSON_FILE in ${TRANSFER_JSON_FILES}; do

  echo "
checking ${TRANSFER_JSON_FILE} for EXPORT_PREVIEW_VOLUME task ..."
  EXPORT_PREVIEW_VOLUME_COUNT=$(grep -c "EXPORT_PREVIEW_VOLUME" "${TRANSFER_JSON_FILE}" || true)

  echo "EXPORT_PREVIEW_VOLUME_COUNT is ${EXPORT_PREVIEW_VOLUME_COUNT}"

  if (( EXPORT_PREVIEW_VOLUME_COUNT == 1 )); then

    RENDER_HOST=$(${JQ} -r '.render_data_set.connect.host' "${TRANSFER_JSON_FILE}")
    RENDER_PORT=$(${JQ} -r '.render_data_set.connect.port' "${TRANSFER_JSON_FILE}")
    RENDER_OWNER=$(${JQ} -r '.render_data_set.owner' "${TRANSFER_JSON_FILE}")
    RENDER_PROJECT=$(${JQ} -r '.render_data_set.project' "${TRANSFER_JSON_FILE}")
    ALIGN_H5_PATH=$(${JQ} -r '.cluster_root_paths.align_h5 // "undefined"' "${TRANSFER_JSON_FILE}")
    N_WORKERS=$(${JQ} -r '.number_of_preview_workers // "4"' "${TRANSFER_JSON_FILE}")

    if [ "${ALIGN_H5_PATH}" == "undefined" ]; then

      echo "cluster_root_paths.align_h5 not defined in ${TRANSFER_JSON_FILE}, nothing to do"

    elif [ ! -d "${ALIGN_H5_PATH}" ]; then

      echo "cluster_root_paths.align_h5 ${ALIGN_H5_PATH} in ${TRANSFER_JSON_FILE} does not exist, nothing to do"

    else

      OUTPUT_DIR="${PLOT_ROOT}/${RENDER_PROJECT}"
      LOG_DIR="${ALIGN_H5_PATH}/logs"
      mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}"

      LOG_FILE="${LOG_DIR}/aggregate-metadata-$(date +"%Y%m%d_%H%M%S").log"

      ARGS="${EMRP_ROOT}/src/python/janelia_emrp/fibsem/aggregate_metadata.py"
      ARGS="${ARGS} --base-data-url ${RENDER_HOST}:${RENDER_PORT}"
      ARGS="${ARGS} --owner ${RENDER_OWNER}"
      ARGS="${ARGS} --project ${RENDER_PROJECT}"
      ARGS="${ARGS} --stack imaging_preview"
      ARGS="${ARGS} --output-dir ${OUTPUT_DIR}"
      ARGS="${ARGS} --n-workers ${N_WORKERS}"

# use shell group to tee all output to log file
{
  echo "
Running:
  ${PIXI_RUN} ${ARGS}
"
  # shellcheck disable=SC2086
  ${PIXI_RUN} ${ARGS}
} 2>&1 | tee -a "${LOG_FILE}"

    fi

  fi

  # wait a few seconds before processing next volume
  sleep 2

done
