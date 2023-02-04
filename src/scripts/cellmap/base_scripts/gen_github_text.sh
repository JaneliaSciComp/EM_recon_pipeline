#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh" "${TAB}"

JQ="/groups/flyem/data/render/bin/jq"

# ----------------------------------------------
# Source Images

VOLUME_TRANSFER_INFO="${SCRIPT_DIR}/volume_transfer_info.${VOLUME_NAME}.json"
RAW_H5=$(${JQ} '.archive_root_paths.raw_h5' "${VOLUME_TRANSFER_INFO}" | sed 's/"//g')
ALIGN_H5=$(${JQ} '.cluster_root_paths.align_h5' "${VOLUME_TRANSFER_INFO}" | sed 's/"//g')

# ----------------------------------------------
# Thickness Correction paths

# /nrs/flyem/render/z_corr/Z0720_07m_BR/Sec14/v4_acquire_trimmed_align/run_20210827_101623_480_z_corr/solve_20210827_104130/Zcoords.txt
STACK_Z_CORR_DIR="${RENDER_NRS_ROOT}/z_corr/${RENDER_OWNER}/${RENDER_PROJECT}/${ALIGN_STACK}"

unset Z_COORDS_FILE ALIGN_STACK_DATA

if [[ -d ${STACK_Z_CORR_DIR} ]]; then

  shopt -s nullglob
  Z_COORDS_FILES=("${STACK_Z_CORR_DIR}"/*/*/Zcoords.txt)
  shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
  FILE_COUNT=${#Z_COORDS_FILES[@]}
  if (( FILE_COUNT == 0 )); then
    echo "WARNING: no Zcoords.txt files found in ${STACK_Z_CORR_DIR}"
  elif (( FILE_COUNT == 1 )); then
    Z_COORDS_FILE=${Z_COORDS_FILES[0]}
  else
    PS3="Choose a Zcoords.txt file: "
    select Z_COORDS_FILE in "${Z_COORDS_FILES[@]}"; do
      break
    done
  fi

  if [[ -f ${Z_COORDS_FILE} ]]; then
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
    ALIGN_STACK_DATA="[cross correlation plot](${BASE_PLOT_URL}/cc_with_next_plot.html), [z correction delta plot](${BASE_PLOT_URL}/delta_z_plot.html)"

  fi

fi

# ----------------------------------------------
# N5 paths

# 45_spark_render_to_n5.sh:                  --n5Dataset /render/${RENDER_PROJECT}/${STACK}___${RUN_TIME}"
# 53_spark_render_intensity_corrected_n5.sh: --n5Dataset /render/${RENDER_PROJECT}/${INTENSITY_CORRECTED_STACK}___${RUN_TIME}"
# 54_spark_render_z_corr_n5.sh:              --n5Dataset /z_corr/${RENDER_PROJECT}/${INTENSITY_CORRECTED_STACK}___${RUN_TIME}"

# /nrs/cellmap/data/jrc_mus-liv-zon-2/jrc_mus-liv-zon-2.n5/render/jrc_mus_liv_zon_2/v3_acquire_align_ic___20221222_202401
# /nrs/cellmap/data/jrc_mus-liv-zon-2/jrc_mus-liv-zon-2.n5/em/fibsem-uint8

unset RENDERED_N5_PATH
shopt -s nullglob
DIRS=("${N5_PATH}"/*/"${RENDER_PROJECT}"/*/ "${N5_PATH}"/em/*/)
shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
DIR_COUNT=${#DIRS[@]}
if (( DIR_COUNT == 0 )); then
  echo "WARNING: no ${RENDER_PROJECT} project n5 directories found in ${N5_PATH}"
fi

unset RENDERED_N5_DATASETS

for RENDERED_N5_PATH in "${DIRS[@]}"; do

  # trim trailing slash
  RENDERED_N5_PATH="${RENDERED_N5_PATH%/}"

  N5_JSON="${RENDERED_N5_PATH}/attributes.json"
  if [[ ! -f ${N5_JSON} ]]; then
    echo "ERROR: ${N5_JSON} not found"
    exit 1
  fi

  RENDERED_DATA_SET="${RENDERED_N5_PATH##${N5_PATH}}"

  # /groups/flyem/data/render/bin/jq '.translate[0]' /nrs/flyem/render/n5/Z0720_07m_BR/z_corr/Sec14/v4_acquire_trimmed_align_ic___20210827_131509/attributes.json
  OFFSET_X=$(${JQ} '.translate[0]' ${N5_JSON})
  OFFSET_Y=$(${JQ} '.translate[1]' ${N5_JSON})
  OFFSET_Z=$(${JQ} '.translate[2]' ${N5_JSON})

  N5_PATH_DATASET_AND_OFFSET="-i ${N5_PATH} -d ${RENDERED_DATA_SET} -o ${OFFSET_X},${OFFSET_Y},${OFFSET_Z}"
  if [ -z "${RENDERED_N5_DATASETS}" ]; then
    RENDERED_N5_DATASETS="  ${N5_PATH_DATASET_AND_OFFSET}"
  else
    RENDERED_N5_DATASETS=$(printf "%s\n  %s" "${RENDERED_N5_DATASETS}" "${N5_PATH_DATASET_AND_OFFSET}")
  fi

done

VIEW_URL="http://tem-services.int.janelia.org:8080/render-ws/view"
VIEW_STACKS_URL="${VIEW_URL}/stacks.html"
VIEW_PME_URL="${VIEW_URL}/point-match-explorer.html"

STACK_DATA_URL="http://tem-services.int.janelia.org:8080/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${ACQUIRE_TRIMMED_STACK}"

VIEW_STACK_PARAMS="renderStackOwner=${RENDER_OWNER}&renderStackProject=${RENDER_PROJECT}&dynamicRenderHost=renderer.int.janelia.org%3A8080&catmaidHost=renderer-catmaid.int.janelia.org%3A8000"
VIEW_PME_PARAMS="${VIEW_STACK_PARAMS}&renderStack=${ACQUIRE_TRIMMED_STACK}&matchOwner=${RENDER_OWNER}&matchCollection=${MATCH_COLLECTION}&renderDataHost=tem-services.int.janelia.org%3A8080"

echo "
## Filesystem Paths

\`\`\`bash
Source Images:
  ${RAW_H5}
  ${ALIGN_H5}
               
Alignment Prep:
  ${SCRIPT_DIR}

Thickness Correction Data:
  ${Z_COORDS_FILE}
  
N5 Volumes:
${RENDERED_N5_DATASETS}
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
* ${ALIGN_STACK} data: ${ALIGN_STACK_DATA}


## Notes

* [volume_transfer_info](https://github.com/JaneliaSciComp/EM_recon_pipeline/blob/main/src/resources/transfer_info/${RENDER_OWNER}/volume_transfer_info.${VOLUME_NAME}.json)
"
