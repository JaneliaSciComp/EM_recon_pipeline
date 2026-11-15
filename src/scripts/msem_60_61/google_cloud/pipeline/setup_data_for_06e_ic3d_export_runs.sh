#!/bin/bash

# ----------------------------------------------------------------------------
# Prints (and appends to the run file) the instructions for setting up a VM with the
# 06_ic3d run's mongodb dump, so that load_data_for_06e_ic3d_export_runs.sh can then
# be run against it.
#
# Unlike load_data_for_06_ic3d_run.sh, there is no pipeline run or dump here, only the setup.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

STAGE="06e_ic3d_export_setup"
SLABS_PER_RUN=10

# shellcheck source=setup_load_data_variables.sh
source "${SCRIPT_DIR}/setup_load_data_variables.sh"

echo "
# ============================================================================
# Run $(date)

VM ${VM_LABEL}, slab group ${SLAB_GROUP}, project group ${PROJECT_GROUP}

Run file: ${RUN_FILE}

cd ${GOOGLE_CLOUD_DIR}

# -------------------------------------
# Setup VM:

# Load the 06_ic3d results and list the stacks
# - only render collections are dumped for that stage,
# - aso_3d_s3i data load typically takes 1 to 2 minutes
${RIC_CMD} './db-restore-collections.sh --pattern \"06_ic3d.*${SERIAL_PATTERN}.*${SLAB_GROUP_SUFFIX}/\"'; ${RIC_CMD} './list-stacks.sh'

" | tee -a "${RUN_FILE}"

echo "
Appended run information to:
  ${RUN_FILE}
"
