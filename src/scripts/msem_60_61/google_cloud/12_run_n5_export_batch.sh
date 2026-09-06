#!/bin/bash

# Utility script to simplify submission of multiple n5 export jobs.
#
# Copy this script locally (e.g. to go.20260905-export-batch.sh) so that STACK_NAMES can be filled in
# and MAX_EXECUTORS, IP, PIXEL_OR_MASK, and LAUNCH_JOBS values can be set.

set -e

MAX_EXECUTORS=5        #  5 executors for w61_s083_r00 pixel with 80 z layers took 8 hours, 43 minutes
                       #  5 executors for w61_s097_r00 pixel with 75 z layers took 6 hours, 52 minutes
                       #  5 executors for w61_s083_r01 pixel with 80 z layers took 3 hours, 11 minutes
                       #  5 executors for w61_s097_r01 pixel with 75 z layers took 2 hours, 38 minutes
                       # 10 executors for w61_s099_r00 pixel with 82 z layers took 4 hours, 15 minutes
                       # 40 executors for w61_s081_r00 pixel with 82 z layers took 2 hours,  1 minute
                       # 10 executors for w61_s122_r00 mask  with 89 z layers took 1 hour,  30 minutes
                       # 40 executors for w61_s076_r00 mask  with 89 z layers took 0 hours, 42 minutes

IP="10.150.0.8"        # A=10.150.0.2  B=10.150.0.3  C=10.150.0.4   D=10.150.0.5   E=10.150.0.6   F=10.150.0.7
                       # G=10.150.0.8  H=10.150.0.9  I=10.150.0.10  J=10.150.0.11  K=10.150.0.12  L=10.150.0.13

STACK_PREFIX="13"      # A=07,         B=08,         C=09,          D=10,          E=11,          F=12,
                       # G=13,         H=14,         I=15,          J=16,          K=17,          L=18 and 19

PIXEL_OR_MASK="pixel"  # mask
LAUNCH_JOBS="n"        # set to "y" to launch jobs, anything else to just print commands

# STACK_NAMES examples:
#   w61_s070_r00_gc_icc_par_asoi_3d
#   w61_s129_r01_gc_icc_par_asoi_3d

STACK_NAMES="
w61_s${STACK_PREFIX}0_r00_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}0_r01_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}1_r00_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}1_r01_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}2_r00_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}2_r01_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}3_r00_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}3_r01_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}4_r00_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}4_r01_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}5_r00_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}5_r01_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}6_r00_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}6_r01_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}7_r00_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}7_r01_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}8_r00_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}8_r01_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}9_r00_gc_icc_par_asoi_3d
w61_s${STACK_PREFIX}9_r01_gc_icc_par_asoi_3d
"

while read -r LINE; do
    [[ -z "${LINE}" ]] && continue

    if [[ ${LINE} =~ ^[[:space:]]*([a-zA-Z0-9]+)_s([0-9]{3})_([^ ]+) ]]; then

        WAFER=${BASH_REMATCH[1]}                                            # w61
        SERIAL_STRING=${BASH_REMATCH[2]}                                    # 080
        STACK="${BASH_REMATCH[1]}_s${BASH_REMATCH[2]}_${BASH_REMATCH[3]}"

        # ensure decimal math
        SERIAL_NUM=$((10#${SERIAL_STRING}))

        # compute 10-range
        START=$(( (SERIAL_NUM / 10) * 10 ))
        END=$(( START + 9 ))

        # zero-pad
        START=$(printf "%03d" "${START}")
        END=$(printf "%03d" "${END}")

        PROJECT="${WAFER}_serial_${START}_to_${END}"

        CMD="./11_run_n5_export.sh ${IP} ${PROJECT} ${STACK} ${MAX_EXECUTORS} ${PIXEL_OR_MASK}"

        if [[ "${LAUNCH_JOBS}" == "y" ]]; then
          echo
          echo "Running the following in 10 seconds:"
          echo "  ${CMD}"
          echo
          sleep 10
          ${CMD}
        else
          echo "${CMD}"
        fi
    fi

done <<< "${STACK_NAMES}"