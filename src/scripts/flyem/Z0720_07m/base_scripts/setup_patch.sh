#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

if (( $# < 1 )); then
  echo "USAGE: $0 <patch version> [patch z] ..."
  echo "  e.g. $0 v2 12345"
  exit 1
fi

PATCH_VERSION="$1"
shift 1

if [[ -z OLD_ACQUIRE_TRIMMED_STACK ]] || [[ "${OLD_ACQUIRE_TRIMMED_STACK}" == "TBD" ]]; then
  echo "ERROR: need to setup OLD_ACQUIRE_TRIMMED_STACK in config"
  exit 1
fi

PATCH_DIR="${SCRIPT_DIR}/${PATCH_VERSION}_patch"

if [[ -d ${PATCH_DIR} ]]; then
  echo "ERROR: ${PATCH_DIR} already exists"
  exit 1
fi

mkdir ${PATCH_DIR}

PATCH_SOURCE_DIR="/groups/flyem/data/alignment/flyem-alignment-ett/Z0720-07m/base_scripts/patch"
cp ${PATCH_SOURCE_DIR}/* ${PATCH_DIR}

sed -i "
  s/Z0720_07m_??/${RENDER_OWNER}/g
  s/Sec??/${RENDER_PROJECT}/g
  s/??_acquire_trimmed/${PATCH_VERSION}_acquire_trimmed/g
" ${PATCH_DIR}/06_patch_tile_specs.py

cp excluded_columns.json ${PATCH_DIR}
 
if (( $# > 0 )); then

  echo """
Copy these patch tile id lines into 
${PATCH_DIR}/06_patch_tile_specs.py:
"""

  STACK_URL="http://${SERVICE_HOST}/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${OLD_ACQUIRE_TRIMMED_STACK}"
  for PATCH_Z in $*; do
    for TILE_ID in $( curl -s "${STACK_URL}/z/${PATCH_Z}/layoutFile" | awk '{print $2}' ); do
      echo "         (\"${TILE_ID}\", -1),  # patch from prior layer"
    done
  done

  echo """
After patching, generate match pairs by running:
./11_gen_new_pairs.sh $*
"""

fi
