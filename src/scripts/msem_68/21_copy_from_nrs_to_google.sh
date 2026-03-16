#!/bin/bash

# ----------------------------------------------------------------------------
# Copy the surface zarr volumes from /nrs to Google cloud storage.
#
# Launch with nohup like this:
#     nohup ./21_copy_from_nrs_to_google.sh 2>&1 1>logs/2026-03-16-copy-nrs-to-google.log &
#
# The w68_s000_r00_bgc_par_align_c_ic2d_norm-layer-v2b/s0 data with 85,000 blocks took 73 minutes to rsync
# when run on trautmane-dev with 64 cores.

set -e

echo "
running $0 at $(date)
"

NRS_ROOT="/nrs/hess/data/hess_sample_68_full/export/hess_sample_68_full.n5/render/w68_serial_000_to_009"
GOOGLE_ROOT="gs://janelia-spark-test/hess_sample_68_export"

EXPORT_S0="w68_s000_r00_bgc_par_align_c_ic2d_norm-layer-v2b/s0"

FULL_NRS="${NRS_ROOT}/${EXPORT_S0}"
FULL_GOOGLE="${GOOGLE_ROOT}/${EXPORT_S0}"

gcloud storage rsync ${FULL_NRS} ${FULL_GOOGLE} --recursive