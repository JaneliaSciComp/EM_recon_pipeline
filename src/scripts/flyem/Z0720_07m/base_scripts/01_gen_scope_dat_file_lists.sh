#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

# HACK NOTE: specify any parameter ( e.g. ./01_gen_scope_dat_file_lists.sh nearline )
#            to generate scope list from /nearline/hess instead of from scope
if (( $# == 0 )); then
  FETCH_FROM_SCOPE="Y"
else
  unset FETCH_FROM_SCOPE
fi

WORKING_DIR="${PWD}"

# /groups/flyem/data/Z0720-07m_BR_Sec25/logs
LOGS_DIR="/groups/flyem/data/${FLY_REGION_TAB}/logs"

# /nearline/flyem2/data/Z0720-07m_BR_Sec25/dat
DAT_DIR="/nearline/flyem2/data/${FLY_REGION_TAB}/dat"

echo """
-----------------------------------------
processing ${DAT_DIR} ...
"""

  if [[ ! -d ${DAT_DIR} ]]; then
    echo "ERROR: ${DAT_DIR} not found"
    exit 1
  fi

  ONE_DAT_FILE=$(ls -f ${DAT_DIR} | grep "dat$" | head -1)

  if [[ ! -f ${DAT_DIR}/${ONE_DAT_FILE} ]]; then
    echo "ERROR: no dat files found in ${DAT_DIR}"
    exit 1
  fi

  DAT_FILE_NAME_REGEX="^(Merlin.*_([0-9][0-9])-([0-9][0-9])-([0-9][0-9])_.*).dat"

  if [[ ${ONE_DAT_FILE} =~ ${DAT_FILE_NAME_REGEX} ]]; then

    BASE_FILE_NAME="${BASH_REMATCH[1]}"
    YY="${BASH_REMATCH[2]}"
    MM="${BASH_REMATCH[3]}"
    DD="${BASH_REMATCH[4]}"

    JEISS_NUM=$(/groups/flyem/data/render/bin/print_dat_header.sh --key MachineID --file ${DAT_DIR}/${ONE_DAT_FILE} | grep MachineID | sed -r 's@.*Jeiss([1-9])/.*@\1@')
    JEISS_HOST="jeiss${JEISS_NUM}.hhmi.org"

  else

    echo "ERROR: dat file name '${ONE_DAT_FILE}' does not match regex '${DAT_FILE_NAME_REGEX}'"
    exit 1

  fi

  if [[ -n ${FETCH_FROM_SCOPE} && "${USER}" != "flyem" ]]; then
    echo "ERROR: must run as 'flyem' user to connect to Jeiss scopes"
    exit 1
  fi

  cd ${LOGS_DIR}
  arr=($(ls -1))
  cd ${WORKING_DIR}

  # echo ${arr[1]}
  IFS="_"
  read -ra DATEARRF <<< "${arr[1]}"
  read -ra DATEARRL <<< "${arr[*]: -1}"
  IFS="-"
  read -ra YMDF <<< "${DATEARRF[1]}"
  read -ra YMDL <<< "${DATEARRL[1]}"
  IFS="\n"
  DATE_START="20${YMDF[0]}-${YMDF[1]}-${YMDF[2]}"
  DATE_LAST="20${YMDL[0]}-${YMDL[1]}-${YMDL[2]}"
  echo "log date range is ${DATE_START} to ${DATE_LAST}"
  d=$(date -I -d "$DATE_START - 2 days")
  STOP_DATE=$(date -I -d "$DATE_LAST")

  SCOPE_DAT_LIST="${FLY_REGION_TAB}_${JEISS_HOST}_scope_dat.txt"
  echo "writing scope dat paths to ${SCOPE_DAT_LIST}"
  > "${SCOPE_DAT_LIST}"

  chmod 664 ${SCOPE_DAT_LIST}

  set +e
  while [ $(date -d "$d" +%s) -le $(date -d "$STOP_DATE" +%s) ]; do
      echo "checking scope dat files acquired on ${d}"
      IFS="-"
      read -ra YMD <<< "${d}"
      IFS=$'\n'
      if [[ -n ${FETCH_FROM_SCOPE} ]]; then
        SCOPE_STORAGE_ROOT=$(echo "${SCOPE_STORAGE_ROOT}" | sed 's/\\//g') # hack to remove backslash in Fly Brain
        SCOPE_DAT=$(ssh -o StrictHostKeyChecking=no ${JEISS_HOST} find "${SCOPE_STORAGE_ROOT}/Y${YMD[0]}/M${YMD[1]}/D${YMD[2]}/" -name=*.dat)
      else
        SCOPE_DAT=$(ls -1 /nearline/hess/Images\ Jeiss${JEISS_NUM}/Fly\ Brain/Y${YMD[0]}/M${YMD[1]}/D${YMD[2]}/*.dat)
      fi
      echo "${SCOPE_DAT}" >> ${SCOPE_DAT_LIST}
      d=$(date -I -d "$d + 1 day")
  done
  set -e
