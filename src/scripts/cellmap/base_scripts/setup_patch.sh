#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
CONFIG_FILE="${SCRIPT_DIR}/00_config.sh"
source "${CONFIG_FILE}"

if [[ -z ${OLD_ACQUIRE_TRIMMED_STACK} ]]; then
  echo "ERROR: need to setup OLD_ACQUIRE_TRIMMED_STACK in config"
  exit 1
fi

OLD_ACQUIRE_TRIMMED_STACK="${ACQUIRE_TRIMMED_STACK}"
OLD_ACQUIRE_V_NUMBER=$(echo "${OLD_ACQUIRE_TRIMMED_STACK}" | cut -c2)
STACK_SUFFIX=$(echo "${OLD_ACQUIRE_TRIMMED_STACK}" | cut -c4-)
ACQUIRE_V_NUMBER=$(( OLD_ACQUIRE_V_NUMBER + 1 ))
PATCH_VERSION="v${ACQUIRE_V_NUMBER}"
ACQUIRE_TRIMMED_STACK="${PATCH_VERSION}_${STACK_SUFFIX}"

PATCH_DIR="${SCRIPT_DIR}/${PATCH_VERSION}_patch"

if [[ -d ${PATCH_DIR} ]]; then
  echo "ERROR: ${PATCH_DIR} already exists"
  exit 1
fi

mkdir "${PATCH_DIR}"

sed -i "s/^ACQUIRE_TRIMMED_STACK=.*/ACQUIRE_TRIMMED_STACK=\"${ACQUIRE_TRIMMED_STACK}\"/" "${CONFIG_FILE}"
sed -i "s/^OLD_ACQUIRE_TRIMMED_STACK=.*/OLD_ACQUIRE_TRIMMED_STACK=\"${OLD_ACQUIRE_TRIMMED_STACK}\"/" "${CONFIG_FILE}"

echo "
Updated ${CONFIG_FILE}:
"
grep "ACQUIRE_TRIMMED_STACK" "${CONFIG_FILE}"

PATCH_SOURCE_DIR="/groups/flyem/data/render/git/EM_recon_pipeline/src/scripts/cellmap/base_scripts/patch"
cp ${PATCH_SOURCE_DIR}/* ${PATCH_DIR}

sed -i "
  s/\"RENDER_OWNER\"  # TODO.*/\"${RENDER_OWNER}\"/g
  s/\"RENDER_PROJECT\"  # TODO.*/\"${RENDER_PROJECT}\"/g
  s/\"ACQUIRE_TRIMMED_STACK\"  # TODO.*/\"${ACQUIRE_TRIMMED_STACK}\"/g
" ${PATCH_DIR}/06_patch_tile_specs.py

sed -i "
  s/'RENDER_OWNER', 'RENDER_PROJECT', 'ACQUIRE_TRIMMED_STACK'/\"${RENDER_OWNER}\", \"${RENDER_PROJECT}\", \"${ACQUIRE_TRIMMED_STACK}\"/
  s/'MATCH_COLLECTION'/\"${MATCH_COLLECTION}\"/g
" ${PATCH_DIR}/copy_match_pair_for_edge_gap.py

EXCLUDED_COLUMNS_JSON="${SCRIPT_DIR}/excluded_columns.json"
if [ -f "${EXCLUDED_COLUMNS_JSON}" ]; then
  cp "${EXCLUDED_COLUMNS_JSON}" "${PATCH_DIR}"
fi
 
if (( $# > 0 )); then
  echo "
Copy these patch tile id lines into 
${PATCH_DIR}/06_patch_tile_specs.py:
"

  STACK_URL="http://${SERVICE_HOST}/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${OLD_ACQUIRE_TRIMMED_STACK}"
  for PATCH_Z in "$@"; do
    for TILE_ID in $( curl -s "${STACK_URL}/z/${PATCH_Z}/layoutFile" | awk '{print $2}' ); do
      echo "         (\"${TILE_ID}\", -1),  # patch from prior layer"
    done
  done

  echo "
After patching, generate match pairs by running:
./11_gen_new_pairs.sh $*
"

else

  echo "
Setup patch directory:
${PATCH_DIR}
"

fi
