#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

# skip scan_000 based on Thomas's doc, skip scan_047+ because scan_046 is last one referenced
for SCAN_INDEX in $(seq 1 46); do
  # each job should take roughly 15 minutes to run, limit to 59 minutes for short queue
  bsub -P hess -J "hayworth_ic[1-403]%1000" -n 1 -W 59 -o /dev/null "${SCRIPT_DIR}"/11_hayworth_ic_slab.sh job "${SCAN_INDEX}"
done