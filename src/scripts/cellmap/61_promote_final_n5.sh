#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh" "${TAB}"

# /nrs/cellmap/data/jrc_mus-liv-zon-2/jrc_mus-liv-zon-2.n5/em/fibsem-uint8
FINAL_DATA_SET="/em/fibsem-uint8"
FINAL_N5_PATH="${N5_PATH}${FINAL_DATA_SET}"

if [ -d "${FINAL_N5_PATH}" ]; then
  echo "ERROR: ${FINAL_N5_PATH} already exists!"
  exit 1
fi

JQ="/groups/flyem/data/render/bin/jq"

# ----------------------------------------------
# N5 paths

# 45_spark_render_to_n5.sh:                  --n5Dataset /render/${RENDER_PROJECT}/${STACK}___${RUN_TIME}"
# 53_spark_render_intensity_corrected_n5.sh: --n5Dataset /render/${RENDER_PROJECT}/${INTENSITY_CORRECTED_STACK}___${RUN_TIME}"
# 54_spark_render_z_corr_n5.sh:              --n5Dataset /z_corr/${RENDER_PROJECT}/${INTENSITY_CORRECTED_STACK}___${RUN_TIME}"

# /nrs/cellmap/data/jrc_mus-liv-zon-2/jrc_mus-liv-zon-2.n5/render/jrc_mus_liv_zon_2/v3_acquire_align_ic___20221222_202401

unset RENDERED_N5_PATH
shopt -s nullglob
DIRS=("${N5_PATH}"/*/"${RENDER_PROJECT}"/*/ "${N5_PATH}"/em/*/)
shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
DIR_COUNT=${#DIRS[@]}
if (( DIR_COUNT == 0 )); then
  echo "WARNING: no ${RENDER_PROJECT} project n5 directories found in ${N5_PATH}"
elif (( DIR_COUNT == 1 )); then
  RENDERED_N5_PATH=${DIRS[0]}
else
  PS3="Choose N5 to promote as final alignment: "
  select RENDERED_N5_PATH in "${DIRS[@]}"; do
    break
  done
fi

# trim trailing slash
RENDERED_N5_PATH="${RENDERED_N5_PATH%/}"

N5_JSON="${RENDERED_N5_PATH}/attributes.json"
if [[ ! -f ${N5_JSON} ]]; then
  echo "ERROR: ${N5_JSON} not found"
  exit 1
fi

# /groups/flyem/data/render/bin/jq '.translate[0]' /nrs/flyem/render/n5/Z0720_07m_BR/z_corr/Sec14/v4_acquire_trimmed_align_ic___20210827_131509/attributes.json
OFFSET_X=$(${JQ} '.translate[0]' "${N5_JSON}")
OFFSET_Y=$(${JQ} '.translate[1]' "${N5_JSON}")
OFFSET_Z=$(${JQ} '.translate[2]' "${N5_JSON}")

echo """
moving ${RENDERED_N5_PATH}
to     ${FINAL_N5_PATH}

update GitHub with:
  -i ${N5_PATH} -d ${FINAL_DATA_SET} -o ${OFFSET_X},${OFFSET_Y},${OFFSET_Z}
"""

FINAL_N5_PARENT_DIR=$(dirname "${FINAL_N5_PATH}")
mkdir -p "${FINAL_N5_PARENT_DIR}"
mv "${RENDERED_N5_PATH}" "${FINAL_N5_PATH}"

ls -ald "${FINAL_N5_PATH}"