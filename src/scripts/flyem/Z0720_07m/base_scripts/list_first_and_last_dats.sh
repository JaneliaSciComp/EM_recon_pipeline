#!/bin/bash
set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

DAT_DIR="/nearline/flyem2/data/${FLY_REGION_TAB}/dat"

echo """
checking ${DAT_DIR}
"""

ls -alh ${DAT_DIR} | head

echo 

ls -alh ${DAT_DIR} | tail
