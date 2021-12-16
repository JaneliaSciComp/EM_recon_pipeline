#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`

RUN_DIR="$1"

# define RENDER_PIPELINE_BIN, BASE_DATA_URL, exitWithErrorAndUsage(), ensureDirectoryExists(), getRunDirectory(), createLogDirectory()
. /groups/flyTEM/flyTEM/render/pipeline/bin/pipeline_common.sh 

${RENDER_PIPELINE_BIN}/check_logs.sh ${RUN_DIR}

echo """
Stage parameters loaded from `ls ${RUN_DIR}/stage_parameters.*.json`	
"""

cd ${RUN_DIR}/logs
${SCRIPT_DIR}/14_report_all_stats.sh log*.txt
