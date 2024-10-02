#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

"${SCRIPT_DIR}"/count_clusters.sh "${ACQUIRE_STACK}"

# count and generate excluded cells json
# "${SCRIPT_DIR}"/count_clusters.sh "${ACQUIRE_STACK}" y
