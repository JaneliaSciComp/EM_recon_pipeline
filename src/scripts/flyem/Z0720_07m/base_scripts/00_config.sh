#!/bin/bash

set -e

FLY="Z0720-07m"

ABSOLUTE_CONFIG=$(readlink -m $0)
CONFIG_DIR=$(dirname ${ABSOLUTE_CONFIG})

# /groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/VNC/Sec31/alignment_scripts
REGION_DIR=$(echo "${CONFIG_DIR}" | sed 's@.*'"${FLY}"'/@@')
REGION=$(echo ${REGION_DIR} | sed 's@/.*@@')
TAB_DIR=$(echo "${REGION_DIR}" | sed 's@.*'"${REGION}"'/@@')
TAB=$(echo ${TAB_DIR} | sed 's@/.*@@')

FLY_REGION_TAB="${FLY}_${REGION}_${TAB}"

# owner of the render stacks and match collections
# - must only contain alphanumeric or underscore characters 
#   (but no consecutive underscores)
RENDER_OWNER=`echo "${FLY}_${REGION}" | sed 's/-/_/g'`

# render project used to group related stacks
# - must only contain alphanumeric or underscore characters
#   (but no consecutive underscores)
# - examples: fly_em_pre_iso, flyem_04male_082017
RENDER_PROJECT="${TAB}"

# base name pre-pended to render stacks to help group stacks within a project
# - must only contain alphanumeric or underscore characters
#   (but no consecutive underscores)
# - examples: column_22, Z0416_04male_Sec10_D07_08
BASE_STACK_NAME="v1"

# group name to which all cluster jobs should be billed
export BILL_TO="flyem"

# number of Dask workers for dat_to_render process
DASK_DAT_TO_RENDER_WORKERS="32"

SCAPES_ROOT_DIR="/nrs/flyem/render/scapes"

# ============================================================================
# The following parameters are either derived from ones above or have static
# standard values.  There is no need to modify these unless you want to
# specify non-standard values.

# IP address and port for the render web services
RENDER_HOST="10.40.3.162"
RENDER_PORT="8080"
SERVICE_HOST="${RENDER_HOST}:${RENDER_PORT}"
RENDER_CLIENT_SCRIPTS="/groups/flyTEM/flyTEM/render/bin"
RENDER_CLIENT_SCRIPT="$RENDER_CLIENT_SCRIPTS/run_ws_client.sh"
RENDER_CLIENT_HEAP="1G"

# stack for storing raw image tile specs
ACQUIRE_STACK="${BASE_STACK_NAME}_acquire"

# stack to use for determining tile pairs for matching
LOCATION_STACK="${ACQUIRE_STACK}"

# acquire stack with resin tiles trimmed out (removed)
ACQUIRE_TRIMMED_STACK="${ACQUIRE_STACK}_trimmed"
OLD_ACQUIRE_TRIMMED_STACK="TBD"

ALIGN_STACK="${ACQUIRE_TRIMMED_STACK}_align"
INTENSITY_CORRECTED_STACK="${ALIGN_STACK}_ic"

# collection for storing acquisition tile point matches
MATCH_OWNER="${RENDER_OWNER}"
MATCH_COLLECTION="${RENDER_PROJECT}_${BASE_STACK_NAME}"

MONTAGE_PAIR_ARGS="--zNeighborDistance 0 --xyNeighborFactor 0.6 --excludeCornerNeighbors true --excludeSameLayerNeighbors false"
MONTAGE_PASS_PAIR_SECONDS="6"

CROSS_PAIR_ARGS="--zNeighborDistance 6 --xyNeighborFactor 0.1 --excludeCornerNeighbors false --excludeSameLayerNeighbors true"
CROSS_PASS_PAIR_SECONDS="5"

# Try to allocate 10 minutes of match derivation work to each file.
# Each pair takes roughly 10 seconds to process when using default match parameters, so 60 pairs per file is a good default.
MAX_PAIRS_PER_FILE=30

# root directory containing acquisition images with name format: 
#     <scope>_yy-mm-dd_HHMMSS_0_<row>_<column>.png
#
# - examples: /groups/flyem/data/Z0115-22_Sec27/InLens
#             /groups/flyem/data/Z0416-04male_Sec10_D07-08
STACK_DATA_DIR="/groups/flyem/data/${FLY_REGION_TAB}/InLens"
