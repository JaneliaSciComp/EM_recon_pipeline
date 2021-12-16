#!/bin/bash
set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

if [[ "${USER}" != "flyem" ]]; then
  echo "ERROR: must run as 'flyem' user to connect to Jeiss scopes"
  exit 1
fi

# Z0720-07m_BR_Sec35_jeiss2.hhmi.org_scope_dat.txt
MISSING_DAT_JSON=`ls ${SCRIPT_DIR}/${FLY_REGION_TAB}*_missing_dat.json`
JEISS_HOST=`basename ${MISSING_DAT_JSON} | cut -d'_' -f4`

#DAT_DIR="/groups/flyem/data/${FLY_REGION_TAB}/dat"
DAT_DIR="/nearline/flyem2/data/${FLY_REGION_TAB}/dat"

# /groups/flyem/data/Z0720-07m_BR_Sec37/InLens/Merlin-6049_20-12-17_142416_0-0-0-InLens.png
PNG_PARENT_DIR="/groups/flyem/data/${FLY_REGION_TAB}"

for DAT in `cat ${SCRIPT_DIR}/${FLY_REGION_TAB}*_missing_dat.json | sed 's/[][",]//g'`; do

  # DAT = Merlin-6262_20-12-14_062933_0-0-0

  FULL_DAT_FILE="${DAT_DIR}/${DAT}.dat"

  DATE=`echo ${DAT} | cut -d'_' -f2`
  SCOPE_DATE_DAT="Y20${DATE:0:2}/M${DATE:3:2}/D${DATE:6:2}/${DAT}.dat"


  if [[ -f ${FULL_DAT_FILE} ]]; then
    echo "WARNING: ${FULL_DAT_FILE} already exists"
  else

    echo "copying ${JEISS_HOST}:${SCOPE_DATE_DAT} to ${DAT_DIR}"

    # on newer OS, might need -T flag to avoid protocol error: filename does not match request
    scp -o StrictHostKeyChecking=no ${JEISS_HOST}:\"/cygdrive/e/Images/Fly\ Brain/${SCOPE_DATE_DAT}\" ${DAT_DIR}

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
