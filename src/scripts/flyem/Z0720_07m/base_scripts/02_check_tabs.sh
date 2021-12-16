#!/bin/bash

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

RUN_TIME=`date +"%Y%m%d_%H%M%S"`

ABSOLUTE_SCOPE_DAT=`readlink -m ${SCRIPT_DIR}/${FLY_REGION_TAB}*_scope_dat.txt`
if [[ ! -f ${ABSOLUTE_SCOPE_DAT} ]]; then
  echo "ERROR: missing ${SCRIPT_DIR}/${FLY_REGION_TAB}*_scope_dat.txt"
  exit 1
fi

# Z0620-23m_VNC_Sec25_jeiss9.hhmi.org_scope_dat.txt
SCOPE_DAT=`basename ${ABSOLUTE_SCOPE_DAT}`


#SCOPE=`echo "${SCOPE_DAT}" | cut -f4 -d'_'`
SCOPE=${SCOPE_DAT#"${FLY_REGION_TAB}_"}
SCOPE=${SCOPE%"_scope_dat.txt"}

BASE_OUTPUT_PATH="${SCRIPT_DIR}/${FLY_REGION_TAB}_${SCOPE}"
CHECK_TABS="${BASE_OUTPUT_PATH}_check_tabs.txt"
MISSING_DAT="${BASE_OUTPUT_PATH}_missing_dat.json"

if [[ -f ${CHECK_TABS} ]]; then
  mv ${CHECK_TABS} ${CHECK_TABS}.${RUN_TIME}
fi

if [[ -f ${MISSING_DAT} ]]; then
  mv ${MISSING_DAT} ${MISSING_DAT}.${RUN_TIME}
fi

source /groups/flyem/data/render/bin/miniconda3/source_me.sh 

conda activate fib_sem_tools

python ${SCRIPT_DIR}/check_tabs.py ${SCRIPT_DIR} > ${CHECK_TABS}

echo """
${CHECK_TABS} :

"""

cut -c1-120 ${CHECK_TABS}

grep "missing dat:" ${CHECK_TABS} | sed "
 s/.*\[/\[/
 s/'/\"/g
" > ${MISSING_DAT}
