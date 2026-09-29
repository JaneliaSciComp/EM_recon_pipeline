#!/bin/bash

RENDER_EXP="gs://janelia-spark-test/hess_wafers_60_61_export/render"
STACK_PATTERN="_gc_bc_par_cc_asoi_3d___pixel"

printf "\nFinding last s-directories for %s exports ...\n\n" "${STACK_PATTERN}"

OUTPUT_FILE="last-sdirs.${STACK_PATTERN}.$(date '+%Y%m%d-%H%M%S').txt"

# The listing finds all s-directories like:
#   ${RENDER_EXP}/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_asoi_3d___pixel/s0/
#   ${RENDER_EXP}/w61_serial_070_to_079/w61_s070_r00_gc_bc_par_cc_asoi_3d___pixel/s1/
#   ${RENDER_EXP}/w61_serial_070_to_079/w61_s070_r01_gc_bc_par_cc_asoi_3d___pixel/s0/
#
# The sed splits each of those into "<export> <level>" (and drops anything that is not an
# s-directory) while the awk reduces them to the highest numbered level for each export.
# The level is compared numerically (with +0) so that s10 sorts after s9 instead of before it.

gcloud storage ls "${RENDER_EXP}/*/*${STACK_PATTERN}/" |
  sed -n 's|^\(.*\)/s\([0-9][0-9]*\)/$|\1 \2|p' |
  awk '{
         if ((! ($1 in maxLevel)) || (($2 + 0) > maxLevel[$1])) {
           maxLevel[$1] = $2 + 0
         }
       }
       END {
         for (dataset in maxLevel) {
           print dataset "/s" maxLevel[dataset]
         }
       }' |
  sort > "${OUTPUT_FILE}"

printf "wrote %s line(s) to:\n  %s\n\n" \
       "$(wc -l < "${OUTPUT_FILE}" | tr -d ' ')" \
       "$(cd "$(dirname "${OUTPUT_FILE}")" && pwd)/${OUTPUT_FILE}"

# Count the exports that stopped at each level, including the levels nothing stopped at.
# The trailing /s<level> is matched explicitly because the rest of the path also contains
# s values (e.g. the w61_s070_r00 stack name).
awk '{
       if (match($0, /\/s[0-9]+$/)) {
         level = substr($0, RSTART + 2) + 0
         count[level] = count[level] + 1
         if (level > maxLevel) {
           maxLevel = level
         }
       }
     }
     END {
       for (level = 0; level <= maxLevel; level++) {
         printf "s%d count: %3d\n", level, count[level]
       }
     }' "${OUTPUT_FILE}"

echo

