#!/bin/bash

# ============================================================================
# This script runs a render web service client "safely" on a cluster node
# by constraining the JVM options.  It can be run by a single "standard" 
# job or be run as part of an array of jobs.
# See usage statements below for details.
#
# @author Eric Trautman
# ============================================================================

# define exitWithErrorAndUsage()
. /groups/flyTEM/flyTEM/render/pipeline/bin/pipeline_common.sh

ABSOLUTE_SCRIPT=`readlink -m $0`
USAGE_MESSAGE="""
  STANDARD:  ${ABSOLUTE_SCRIPT} <java heap size> <main class> [option 1] ... [option n]
  ARRAY JOB: ${ABSOLUTE_SCRIPT} <java heap size> <main class> <run directory>
"""

if (( $# < 2 )); then
  exitWithErrorAndUsage "missing parameters"
fi

MEMORY="$1"
MAIN_CLASS="$2"
shift 2

if [[ ${LSB_JOBINDEX} == 'undefined' || -z ${LSB_JOBINDEX} ]]; then

  COMMAND_OPTIONS="$*"

else

  if (( $# > 0 )); then

    RUN_DIR=`readlink -m $1`
    COMMON_OPTIONS_FILE="${RUN_DIR}/common_parameters.txt"
    ARRAY_OPTIONS_FILE="${RUN_DIR}/job_specific_parameters.txt"

    unset COMMON_OPTIONS
    if [[ -a ${ARRAY_OPTIONS_FILE} ]]; then
      COMMON_OPTIONS=`cat ${COMMON_OPTIONS_FILE}`
    fi

    unset ARRAY_OPTIONS
    if [[ -a ${ARRAY_OPTIONS_FILE} ]]; then
  
      LINE_COUNT=`wc -l ${ARRAY_OPTIONS_FILE} | cut -f1 -d' '`

      if (( LINE_COUNT < LSB_JOBINDEX )); then
        exitWithErrorAndUsage "options for LSB_JOBINDEX ${LSB_JOBINDEX} not availble in ${LINE_COUNT} line file ${ARRAY_OPTIONS_FILE}"
      fi
  
      ARRAY_OPTIONS=`head -n ${LSB_JOBINDEX} ${ARRAY_OPTIONS_FILE} | tail -n 1`

    else

      echo """
WARN: missing array options file ${ARRAY_OPTIONS_FILE}, running job without additional parameters
"""

    fi

    COMMAND_OPTIONS="${COMMON_OPTIONS} ${ARRAY_OPTIONS}"

  fi

fi

RENDER_WS_CLIENT_JAR="${RENDER_WS_CLIENT_JAR:-/groups/flyTEM/flyTEM/render/lib/current-ws-standalone.jar}"
#RENDER_WS_CLIENT_JAR="/groups/flyTEM/flyTEM/render/lib/safe/render-ws-java-client-0.3.0-SNAPSHOT-standalone.jar"
JAVA_HOME="${JAVA_HOME:-/misc/sc/jdks/8.0.275.fx-zulu}"
PATH="${JAVA_HOME}/bin:${PATH}"
unset DISPLAY

# request memory up-front and use serial garbage collector to keep GC threads from taking over cluster node
JAVA_OPTS="-Xms${MEMORY} -Xmx${MEMORY} -Djava.awt.headless=true -XX:+UseSerialGC"

JAVA_PATH=`type java | cut -c9-`
COMMAND="${JAVA_PATH} ${JAVA_OPTS} -cp ${RENDER_WS_CLIENT_JAR} ${MAIN_CLASS} ${COMMAND_OPTIONS}"
echo """
  On Host: ${HOSTNAME}

  Running: ${COMMAND} 

"""
${COMMAND}
exit $?
