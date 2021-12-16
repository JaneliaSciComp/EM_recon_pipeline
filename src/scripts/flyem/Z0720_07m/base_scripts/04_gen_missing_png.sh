#!/bin/bash
set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

DEFAULT_TABS_LOG=$(ls *hhmi.org_check_tabs.txt)
CHECK_TABS_LOG="${1:-${DEFAULT_TABS_LOG}}"

if [[ "${USER}" != "flyem" ]]; then
  echo "ERROR: must run as 'flyem' user to connect to Jeiss scopes"
  exit 1
fi

echo "checking ${CHECK_TABS_LOG} for missing png names"

# Z0720-07m_BR_Sec35_jeiss2.hhmi.org_scope_dat.txt
MISSING_DAT_JSON=`ls ${SCRIPT_DIR}/${FLY_REGION_TAB}*_missing_dat.json`
JEISS_HOST=`basename ${MISSING_DAT_JSON} | cut -d'_' -f4`

#DAT_DIR="/groups/flyem/data/${FLY_REGION_TAB}/dat"
DAT_DIR="/nearline/flyem2/data/${FLY_REGION_TAB}/dat"

# /groups/flyem/data/Z0720-07m_BR_Sec37/InLens/Merlin-6049_20-12-17_142416_0-0-0-InLens.png
PNG_PARENT_DIR="/groups/flyem/data/${FLY_REGION_TAB}"

for DAT in $(grep "missing InLens" ${CHECK_TABS_LOG} | cut -f2 -d'[' | sed "s/[]'[,]//g"); do

  FULL_DAT_FILE="${DAT_DIR}/${DAT}.dat"
  if [[ ! -f ${FULL_DAT_FILE} ]]; then
    echo "ERROR: ${FULL_DAT_FILE} is missing"
    exit 1
  fi

  PNG_FILE="${PNG_PARENT_DIR}/InLens/${DAT}-InLens.png"

  if [[ -f ${PNG_FILE} ]]; then
    echo "WARNING: ${PNG_FILE} already exists"
  else

    echo """
---------------------------------------------------------------
Generating: ${PNG_FILE}
From:       ${FULL_DAT_FILE}

"""
    cd ${PNG_PARENT_DIR}
    /groups/flyem/home/flyem/bin/compress_dats/Compress ${FULL_DAT_FILE} 0 InLens logs -N 1

  fi
  
done
