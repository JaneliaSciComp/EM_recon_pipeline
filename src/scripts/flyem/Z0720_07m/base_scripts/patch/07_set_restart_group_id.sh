#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

Z_VALUES="$*"

${SCRIPT_DIR}/set_group_id.py restart ${RENDER_OWNER} ${RENDER_PROJECT} ${ACQUIRE_TRIMMED_STACK} ${Z_VALUES}
