#!/bin/bash

function echoMessage {
  echo """
The following log files $1:
"""
}

function listLogFiles {
  for LOG_FILE in $*; do
    echo ${LOG_FILE}
  done
  echo
}

function listLogFileErrors {
  if (( $# > 1 )); then
    grep -ic ERROR $* | awk -F':' '{printf("%6d %s\n", $2, $1)}' | sort -nr
  else
    ERROR_COUNT=`grep -ic ERROR $1 | awk '{printf("%6d", $1)}' `
    echo "${ERROR_COUNT} $1"
  fi
  echo
}

# define RENDER_PIPELINE_BIN, BASE_DATA_URL, exitWithErrorAndUsage(), ensureDirectoryExists(), getRunDirectory(), createLogDirectory()
. /groups/flyTEM/flyTEM/render/pipeline/bin/pipeline_common.sh 

ABSOLUTE_SCRIPT=`readlink -m $0`
USAGE_MESSAGE="${ABSOLUTE_SCRIPT} <run directory>"

if (( $# < 1 )); then
  exitWithErrorAndUsage "missing parameters"
fi

ABSOLUTE_RUN_DIR=`readlink -m ${1}`
LOG_DIR="${ABSOLUTE_RUN_DIR}/logs"
ensureDirectoryExists "${LOG_DIR}" "log"

cd ${LOG_DIR}

ERROR_FILES=`grep -il error log*`

COMPLETE_COUNT=0
INCOMPLETE_COUNT=0
unset INCOMPLETE_FILES
for LOG_FILE in log*; do
  COMPLETE_COUNT=`tail -n1 ${LOG_FILE} | grep -c "run: exit, processing"`
  if (( COMPLETE_COUNT == 0)); then
    (( INCOMPLETE_COUNT += 1 ))
    INCOMPLETE_FILES="${INCOMPLETE_FILES} ${LOG_FILE}"
  fi
done

if (( $# == 2 )); then
  SCHEDULED_JOB_COUNT="$2"
else
  SCHEDULED_JOB_COUNT=`wc -l ${ABSOLUTE_RUN_DIR}/job_specific_parameters.txt | cut -f1 -d' '`
fi

unset MISSING_FILES
(( ACTUAL_JOB_COUNT = COMPLETE_COUNT + INCOMPLETE_COUNT ))
if (( ACTUAL_JOB_COUNT < SCHEDULED_JOB_COUNT )); then
  for i in `seq 1 ${SCHEDULED_JOB_COUNT}`; do
    LOG_FILE="log_${i}.txt"
    if [[ ! -a ${LOG_FILE} ]]; then
      MISSING_FILES="${MISSING_FILES} ${LOG_FILE}"
    fi
  done
fi

if [[ -n ${ERROR_FILES} ]]; then

  echoMessage "contain errors"
  listLogFileErrors ${ERROR_FILES}

  if [[ -n ${INCOMPLETE_FILES} ]]; then
    echoMessage "did not complete normally"
    listLogFiles ${INCOMPLETE_FILES}
  fi

  if [[ -n ${MISSING_FILES} ]]; then
    echoMessage "are missing"
    listLogFiles ${MISSING_FILES}
  fi

  exit 1

elif [[ -n ${INCOMPLETE_FILES} ]]; then

  echoMessage "did not complete normally"
  listLogFiles ${INCOMPLETE_FILES}

  if [[ -n ${MISSING_FILES} ]]; then
    echoMessage "are missing"
    listLogFiles ${MISSING_FILES}
  fi

  exit 1

elif [[ -n ${MISSING_FILES} ]]; then

  echoMessage "are missing"
  listLogFiles ${MISSING_FILES}

  exit 1

else

  echo """
All log files in ${LOG_DIR} look okay.
""" 

  POST_CHECK_SCRIPT="${ABSOLUTE_RUN_DIR}/post_check.sh"
  if [[ -f ${POST_CHECK_SCRIPT} ]]; then
    ${POST_CHECK_SCRIPT}
  fi

fi