#!/bin/bash

set -e

RENDER_OWNER="hess_wafers_60_61"
RENDER_PROJECT="w61_serial_100_to_109"
FROM_STACK="w61_s109_r00_gc_par_crc_align"

BASE_DATA_URL="http://renderer.int.janelia.org:8080/render-ws/v1"
FROM_STACK_URL="${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${FROM_STACK}"

TO_PROJECT="test_ic2d"
WIDTH=4000
HEIGHT=4000
SCALE="0.15"

AREA_NAME="problem_area_1"
EXPORT_X=97105
EXPORT_Y=25483
EXPORT_Z=18

#AREA_NAME="problem_area_2"
#EXPORT_X=82218
#EXPORT_Y=47280
#EXPORT_Z=28

#AREA_NAME="problem_area_3"
#EXPORT_X=53464
#EXPORT_Y=58922
#EXPORT_Z=11

TO_STACK="${FROM_STACK}_${AREA_NAME}"

MIN_BOUNDS=$(curl -X GET --silent --header 'Accept: application/json' "${FROM_STACK_URL}" | jq -r '. | "\(.stats.stackBounds.minX) \(.stats.stackBounds.minY) \(.stats.stackBounds.minZ)"')
STACK_MIN_X=$(echo "${MIN_BOUNDS}" | cut -d' ' -f1 | cut -f1 -d'.')
STACK_MIN_Y=$(echo "${MIN_BOUNDS}" | cut -d' ' -f2 | cut -f1 -d'.')
STACK_MIN_Z=$(echo "${MIN_BOUNDS}" | cut -d' ' -f3 | cut -f1 -d'.')

X=$(( EXPORT_X - (WIDTH / 2) + STACK_MIN_X ))
Y=$(( EXPORT_Y - (HEIGHT / 2) + STACK_MIN_Y ))
Z=$(( EXPORT_Z + STACK_MIN_Z ))

BOX_URL="${FROM_STACK_URL}/z/${Z}/box/${X},${Y},${WIDTH},${HEIGHT},${SCALE}"
BOX_RP_URL="${BOX_URL}/render-parameters"
TILE_IDS_JSON_FILE="./tile-ids.${EXPORT_X}_${EXPORT_Y}_${EXPORT_Z}.json"
curl -X GET --silent --header 'Accept: application/json' "${BOX_RP_URL}" | jq -r '[.tileSpecs[].tileId]' > "${TILE_IDS_JSON_FILE}"

echo "
tile IDs are:
$(cat ${TILE_IDS_JSON_FILE})
"

ARGS="org.janelia.render.client.CopyStackClient"
ARGS="${ARGS} --baseDataUrl ${BASE_DATA_URL} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
ARGS="${ARGS} --fromStack ${FROM_STACK} --toProject ${TO_PROJECT} --toStack ${TO_STACK}"
ARGS="${ARGS} --includedTileIdsJson ${TILE_IDS_JSON_FILE}"
ARGS="${ARGS} --keepExisting --completeToStackAfterCopy"
ARGS="${ARGS} --z ${Z}"

/groups/flyTEM/flyTEM/render/bin/run_ws_client.sh 1G ${ARGS}