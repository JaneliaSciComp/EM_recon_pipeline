#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh" "${TAB}"

DAT_DIR="/nearline/flyem2/data/${FLY_REGION_TAB}/dat"

# ----------------------------------------------
# Thickness Correction paths

# /nrs/flyem/render/z_corr/Z0720_07m_BR/Sec14/v4_acquire_trimmed_align/run_20210827_101623_480_z_corr/solve_20210827_104130/Zcoords.txt
STACK_Z_CORR_DIR="${RENDER_NRS_ROOT}/z_corr/${RENDER_OWNER}/${RENDER_PROJECT}/${ALIGN_STACK}"

if [[ ! -d ${STACK_Z_CORR_DIR} ]]; then
  echo "ERROR: ${STACK_Z_CORR_DIR} not found"
  exit 1
fi
shopt -s nullglob
Z_COORDS_FILES=("${STACK_Z_CORR_DIR}"/*/*/Zcoords.txt)
shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
FILE_COUNT=${#Z_COORDS_FILES[@]}
if (( FILE_COUNT == 0 )); then
  echo "ERROR: no Zcoords.txt files found in ${PROJECT_Z_CORR_DIR}"
  exit 1
elif (( FILE_COUNT == 1 )); then
  Z_COORDS_FILE=${Z_COORDS_FILES[0]}
else
  PS3="Choose a Zcoords.txt file: "
  select Z_COORDS_FILE in "${Z_COORDS_FILES[@]}"; do
    break
  done
fi

if [[ ! -f ${Z_COORDS_FILE} ]]; then
  echo "ERROR: ${Z_COORDS_FILE} not found"
  exit 1
fi

SOLVE_DIR=$(dirname "${Z_COORDS_FILE}")
RUN_DIR=$(dirname "${SOLVE_DIR}")
RUN_NAME=$(basename "${RUN_DIR}")

CC_WITH_NEXT_PLOT="${RUN_DIR}/cc_with_next_plot.html"
if [[ ! -f ${CC_WITH_NEXT_PLOT} ]]; then
  echo "ERROR: ${CC_WITH_NEXT_PLOT} not found"
  exit 1
fi

DELTA_Z_PLOT="${RUN_DIR}/delta_z_plot.html"
if [[ ! -f ${DELTA_Z_PLOT} ]]; then
  echo "ERROR: ${DELTA_Z_PLOT} not found"
  exit 1
fi

BASE_PLOT_URL="http://renderer-data4.int.janelia.org:8080/z_corr_plots/${RENDER_OWNER}/${RENDER_PROJECT}/${ALIGN_STACK}/${RUN_NAME}"

# ----------------------------------------------
# N5 paths

N5_DATASET_ROOT="/z_corr/${RENDER_PROJECT}/${ALIGN_STACK}"

unset Z_CORR_N5_PATH
shopt -s nullglob
DIRS=("${N5_PATH}${N5_DATASET_ROOT}"*/)
shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
DIR_COUNT=${#DIRS[@]}
if (( DIR_COUNT == 0 )); then
  echo "WARNING: no directories found in ${N5_PATH}${N5_DATASET_ROOT}"
elif (( DIR_COUNT == 1 )); then
  Z_CORR_N5_PATH=${DIRS[0]}
else
  PS3="Choose a source directory: "
  select Z_CORR_N5_PATH in "${DIRS[@]}"; do
    break
  done
fi

if [[ -n "${Z_CORR_N5_PATH}" ]]; then

  # trim trailing slash
  Z_CORR_N5_PATH="${Z_CORR_N5_PATH%/}"

  N5_JSON="${Z_CORR_N5_PATH}/attributes.json"
  if [[ ! -f ${N5_JSON} ]]; then
    echo "ERROR: ${N5_JSON} not found"
    exit 1
  fi

  Z_CORR_DATA_SET="${Z_CORR_N5_PATH##${N5_PATH}}"

  # /groups/flyem/data/render/bin/jq '.translate[0]' /nrs/flyem/render/n5/Z0720_07m_BR/z_corr/Sec14/v4_acquire_trimmed_align_ic___20210827_131509/attributes.json
  JQ="/groups/flyem/data/render/bin/jq"

  OFFSET_X=$(${JQ} '.translate[0]' ${N5_JSON})
  OFFSET_Y=$(${JQ} '.translate[1]' ${N5_JSON})
  OFFSET_Z=$(${JQ} '.translate[2]' ${N5_JSON})

  N5_DATASET_AND_OFFSET="-d ${Z_CORR_DATA_SET} -o ${OFFSET_X},${OFFSET_Y},${OFFSET_Z}"

else
  N5_DATASET_AND_OFFSET="-d TBD -o TBD"
fi

VIEW_URL="http://tem-services.int.janelia.org:8080/render-ws/view"
VIEW_STACKS_URL="${VIEW_URL}/stacks.html"
VIEW_PME_URL="${VIEW_URL}/point-match-explorer.html"

STACK_DATA_URL="http://tem-services.int.janelia.org:8080/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${ACQUIRE_TRIMMED_STACK}"

VIEW_STACK_PARAMS="renderStackOwner=${RENDER_OWNER}&renderStackProject=${RENDER_PROJECT}&dynamicRenderHost=renderer.int.janelia.org%3A8080&catmaidHost=renderer-catmaid.int.janelia.org%3A8000"
VIEW_PME_PARAMS="${VIEW_STACK_PARAMS}&renderStack=${ACQUIRE_TRIMMED_STACK}&matchOwner=${RENDER_OWNER}&matchCollection=${MATCH_COLLECTION}&renderDataHost=tem-services.int.janelia.org%3A8080"

echo """
## Filesystem Paths

\`\`\`bash
Source Images:
  ${DAT_DIR}
  ${STACK_DATA_DIR}
               
Alignment Prep:
  ${SCRIPT_DIR}

Thickness Correction Data:
  ${Z_COORDS_FILE}
  
N5 Volumes:
  intensity and z corrected: -i ${N5_PATH} ${N5_DATASET_AND_OFFSET}

Surface Finding Height Fields (--n5FieldPath ${N5_PATH}):
  min: --n5Field /heightfields/${RENDER_PROJECT}/<TBD>/s1/min
  max: --n5Field /heightfields/${RENDER_PROJECT}/<TBD>/s1/max
\`\`\`

## Render Data

\`\`\`json
{
  \"owner\": \"${RENDER_OWNER}\", 
  \"project\" : \"${RENDER_PROJECT}\", 
  \"stack\" : \"${ACQUIRE_TRIMMED_STACK}\", 
  \"matchCollection\" : \"${MATCH_COLLECTION}\"
}
\`\`\`
* render links: [project stacks](${VIEW_STACKS_URL}?${VIEW_STACK_PARAMS}), [restart tiles](${STACK_DATA_URL}/resolvedTiles?groupId=restart), [point match explorer](${VIEW_PME_URL}?${VIEW_PME_PARAMS})
* ${ALIGN_STACK} data: [cross correlation plot](${BASE_PLOT_URL}/cc_with_next_plot.html), [z correction delta plot](${BASE_PLOT_URL}/delta_z_plot.html)
* neuroglancer links: ${ALIGN_STACK} intensity and z corrected TBD

## Notes

* new v9 dat header
"""
