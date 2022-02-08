#!/bin/bash

# ============================================================================
# This wrapper script has access to the array job environment variables 
# and simply redirects standard-out and standard-err to a log file based 
# upon the the SGE_TASK_ID.
#
# For some reason using the -j y option with qsub array jobs does
# not merge the two output streams, so I needed this wrapper.
# Maybe user error on my part?
#
# @author Eric Trautman
# ============================================================================

RUN_DIR="$1"
LOG_FILE="${RUN_DIR}/logs/log_${LSB_JOBINDEX}.txt"

MEMORY="$2"
JAVA_CLASS="$3"

# uncomment the following lines to debug array job environment variables

#ARRAY_JOB_ENV=`env`
#echo """
#-----------------------------------------------
# Array Job Environment Variables are:
#
#${ARRAY_JOB_ENV}
#""" > ${RUN_DIR}/env_${SGE_TASK_ID}.txt

/groups/flyTEM/flyTEM/render/pipeline/bin/run_ws_client_lsf.sh ${MEMORY} ${JAVA_CLASS} ${RUN_DIR} 2>&1 1>${LOG_FILE}
exit $?
