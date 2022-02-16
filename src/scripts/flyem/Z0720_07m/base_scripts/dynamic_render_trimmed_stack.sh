#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh" "${TAB}"

/groups/flyem/data/render/bin/render-tools.sh ${RENDER_OWNER} ${RENDER_PROJECT} ${ACQUIRE_TRIMMED_STACK}
