#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`

if (( $# != 2 )); then
  echo "USAGE: $0 <region> <tab>  ( e.g. $0 VNC Sec32 )"
  exit 1
fi

REGION="$1"
TAB="$2"

BASE_SCRIPTS_DIR="${SCRIPT_DIR}/base_scripts"

WORK_DIR="${SCRIPT_DIR}/${REGION}/${TAB}"

mkdir -p ${WORK_DIR}
chmod 775 ${WORK_DIR}

cp ${BASE_SCRIPTS_DIR}/* ${WORK_DIR}
cp -r ${BASE_SCRIPTS_DIR}/patch_match ${WORK_DIR}

mkdir ${WORK_DIR}/logs
chmod 775 ${WORK_DIR}/logs

echo "created ${WORK_DIR}"
