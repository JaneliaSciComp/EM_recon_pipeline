#!/bin/bash

set -e
umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <wafer number>     (e.g. 60)"
    exit 1
fi

WAFER_DIR=$(printf "wafer_%02d" "${1}") # wafer_60

SCANS_COMMON_SUBDIR="hess/ibeammsem/system_02/wafers/${WAFER_DIR}/acquisition/scans"
FROM_SCANS_DIR="/nearline/${SCANS_COMMON_SUBDIR}"
TO_SCANS_DIR="/nrs/${SCANS_COMMON_SUBDIR}"

# /nearline/hess/ibeammsem/system_02/wafers/wafer_60/acquisition/scans/scan_010/sfov_correction/results/fit_parameters.txt
for FROM_SFOV_CORR_RESULTS_DIR in "${FROM_SCANS_DIR}"/scan_[0-9]*/sfov_correction/results; do

    TO_SFOV_CORR_RESULTS_DIR=${FROM_SFOV_CORR_RESULTS_DIR/nearline/nrs}
    FIT_PARAMETERS_FILE="${FROM_SFOV_CORR_RESULTS_DIR}/fit_parameters.txt"

    mkdir -p "${TO_SFOV_CORR_RESULTS_DIR}"
    echo "Copying ${FIT_PARAMETERS_FILE} ..."
    cp "${FIT_PARAMETERS_FILE}" "${TO_SFOV_CORR_RESULTS_DIR}"

done