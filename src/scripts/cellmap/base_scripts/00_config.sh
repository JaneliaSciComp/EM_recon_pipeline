#!/bin/bash

set -e

export LAB_OR_PROJECT_GROUP="?"; echo "ERROR: unedited config template!"; exit 1
export LAYOUT="?" # single_tile, single_row, or multi_row

ABSOLUTE_CONFIG=$(readlink -m "${BASH_SOURCE[0]}")
CONFIG_DIR=$(dirname ${ABSOLUTE_CONFIG})

VOLUME_NAME=$(basename "${CONFIG_DIR}")
RENDER_NRS_ROOT="/nrs/${LAB_OR_PROJECT_GROUP}/data/${VOLUME_NAME}"

RENDER_OWNER="${LAB_OR_PROJECT_GROUP}"
RENDER_PROJECT=$(echo "${VOLUME_NAME}" | sed 's/-/_/g')

# group name to which all cluster jobs should be billed
export BILL_TO="${LAB_OR_PROJECT_GROUP}"

# number of Dask workers for dat_to_render process
DASK_DAT_TO_RENDER_WORKERS="32"

#SCAPES_ROOT_DIR="${RENDER_NRS_ROOT}/scapes"
N5_PATH="${RENDER_NRS_ROOT}/${VOLUME_NAME}.n5"

# ============================================================================
# The following parameters are either derived from ones above or have static
# standard values.  There is no need to modify these unless you want to
# specify non-standard values.

# IP address and port for the render web services
RENDER_HOST="10.40.3.113"
RENDER_PORT="8080"
SERVICE_HOST="${RENDER_HOST}:${RENDER_PORT}"
RENDER_CLIENT_SCRIPTS="/groups/flyTEM/flyTEM/render/bin"
RENDER_CLIENT_SCRIPT="$RENDER_CLIENT_SCRIPTS/run_ws_client.sh"
RENDER_CLIENT_HEAP="1G"

# stack for storing raw image tile specs
ACQUIRE_STACK="v1_acquire"

# stack to use for determining tile pairs for matching
LOCATION_STACK="${ACQUIRE_STACK}"

# acquire stack with unconnected section removed
ACQUIRE_TRIMMED_STACK="${ACQUIRE_STACK}"
#ACQUIRE_TRIMMED_STACK="${ACQUIRE_STACK}_trimmed"
OLD_ACQUIRE_TRIMMED_STACK="TBD"

ALIGN_STACK="${ACQUIRE_TRIMMED_STACK}_align"
INTENSITY_CORRECTED_STACK="${ALIGN_STACK}_ic"
#INTENSITY_CORRECTED_STACK="${ALIGN_STACK}"

# collection for storing acquisition tile point matches
MATCH_OWNER="${RENDER_OWNER}"
MATCH_COLLECTION="${RENDER_PROJECT}_v1"

MONTAGE_PAIR_ARGS="--zNeighborDistance 0 --xyNeighborFactor 0.6 --excludeCornerNeighbors true --excludeSameLayerNeighbors false"
MONTAGE_PASS_PAIR_SECONDS="8"

#CROSS_PAIR_ARGS="--zNeighborDistance 6 --xyNeighborFactor 0.1 --excludeCornerNeighbors false --excludeSameLayerNeighbors true"
CROSS_PAIR_ARGS="--zNeighborDistance 6 --xyNeighborFactor 0.1 --excludeCornerNeighbors true --excludeSameLayerNeighbors true"
CROSS_PASS_PAIR_SECONDS="1"

# Try to allocate 10 minutes of match derivation work to each file.
# Each pair takes roughly 10 seconds to process when using default match parameters, so 60 pairs per file is a good default.
MAX_PAIRS_PER_FILE=30

MATCH_PARAMETERS_DIR="${CONFIG_DIR}/match_single_row"

if [[ "${LAYOUT}" == "multi_row" ]]; then
  MATCH_RUN_TYPES="montage_top_bottom montage_left_right cross"
  MATCH_PARAMETERS_DIR="${CONFIG_DIR}/match_multi_row"
elif [[ "${LAYOUT}" == "single_tile" ]]; then
  MATCH_RUN_TYPES="cross"
  if [[ "${RENDER_PROJECT}" == *"leaf"* ]]; then
    MATCH_PARAMETERS_DIR="${CONFIG_DIR}/match_leaf"
  fi
else # single_row
  MATCH_RUN_TYPES="montage cross"
fi

# ============================================================================
# Common Spark job parameters

# Write spark logs to backed-up filesystem rather than user home so that they are readable by others for analysis.
# NOTE: must consolidate logs when changing run parent dir
export SPARK_JANELIA_ARGS="--consolidate_logs --run_parent_dir /groups/${LAB_OR_PROJECT_GROUP}/${LAB_OR_PROJECT_GROUP}/render/spark_output/${USER}"

# Avoid GSON read errors
GSON_JAR="/groups/flyem/data/render/lib/gson/gson-2.10.1.jar"

# Avoid "Could not initialize class ch.systemsx.cisd.hdf5.CharacterEncoding" exceptions
# (see https://github.com/PreibischLab/BigStitcher-Spark/issues/8 ).
H5_LIBPATH="-Dnative.libpath.jhdf5=/groups/flyem/data/render/lib/jhdf5/native/jhdf5/amd64-Linux/libjhdf5.so"

export SUBMIT_ARGS="--conf \"spark.executor.extraJavaOptions=${GSON_JAR} ${H5_LIBPATH}\" --conf spark.driver.extraJavaOptions=\"${GSON_JAR} ${H5_LIBPATH}\""

export LSF_PROJECT="${BILL_TO}"
