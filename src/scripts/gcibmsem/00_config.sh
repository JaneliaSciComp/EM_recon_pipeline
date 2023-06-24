#!/bin/bash

set -e

ABSOLUTE_CONFIG=$(readlink -m $0)
CONFIG_DIR=$(dirname ${ABSOLUTE_CONFIG})

RENDER_OWNER="hess_wafer_53"
WAFER_BASE_PATH="/nrs/hess/render/raw/wafer_53"

# group name to which all cluster jobs should be billed
export BILL_TO="hess"

# ============================================================================
# The following parameters are either derived from ones above or have static
# standard values.  There is no need to modify these unless you want to
# specify non-standard values.

# IP address and port for the render web services
RENDER_HOST="10.40.3.113" # e06u08
RENDER_PORT="8080"
SERVICE_HOST="${RENDER_HOST}:${RENDER_PORT}"
RENDER_CLIENT_SCRIPTS="/groups/flyTEM/flyTEM/render/bin"
RENDER_CLIENT_SCRIPT="$RENDER_CLIENT_SCRIPTS/run_ws_client.sh"
RENDER_CLIENT_HEAP="1G"