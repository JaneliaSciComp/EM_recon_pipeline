#!/bin/bash

set -e
umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <wafer number> <slab number>     (e.g. 60 399)"
    exit 1
fi

echo "
On ${HOSTNAME} at $(date), running:

$*
"

WAFER_DIR=$(printf "wafer_%02d" "${1}") # wafer_60
SLAB_DIR=$(printf "slab_%04d" "${2}")   # slab_0399

NUMBER_OF_RSYNC_PROCESSES=8

SCANS_COMMON_SUBDIR="hess/ibeammsem/system_02/wafers/${WAFER_DIR}/acquisition/scans"
FROM_SCANS_DIR="/nearline/${SCANS_COMMON_SUBDIR}"
TO_SCANS_DIR="/nrs/${SCANS_COMMON_SUBDIR}"

# /nearline/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_000/slabs/slab_0399
FIRST_SCAN_FOR_SLAB_DIR="${FROM_SCANS_DIR}/scan_000/slabs/${SLAB_DIR}"
if [ ! -d "${FIRST_SCAN_FOR_SLAB_DIR}" ]; then
    echo "ERROR: ${FIRST_SCAN_FOR_SLAB_DIR} does not exist."
    exit 1
fi

# Copy:
#   /nearline/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_000
#   ...
#   /nearline/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_057
#
# Ignore:
#   /nearline/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_-05
#   /nearline/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_-843
#   ...
for FROM_SLAB_SCAN_DIR in "${FROM_SCANS_DIR}"/scan_[0-9]*/slabs/"${SLAB_DIR}"; do

    TO_SLAB_SCAN_DIR=${FROM_SLAB_SCAN_DIR/nearline/nrs}

    mkdir -p "${TO_SLAB_SCAN_DIR}"
    echo "
$(date)
Syncing ${FROM_SLAB_SCAN_DIR}
     to ${TO_SLAB_SCAN_DIR} ...
"

    # see https://github.com/jbd/msrsync?tab=readme-ov-file#usage

    # png paths are like:
    #   /nearline/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_009/slabs/slab_0399/mfovs/mfov_0012/sfov_034.png

    /misc/local/msrsync/msrsync3 \
      --processes ${NUMBER_OF_RSYNC_PROCESSES} --progress --stats \
      --rsync "--archive --include='sfov_*.png' --include='*/' --exclude='*' --chmod=D775" \
      "${FROM_SLAB_SCAN_DIR}/" "${TO_SLAB_SCAN_DIR}/"

done