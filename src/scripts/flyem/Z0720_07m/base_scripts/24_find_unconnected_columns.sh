#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

${SCRIPT_DIR}/find_unconnected_columns.sh ${ACQUIRE_TRIMMED_STACK}
