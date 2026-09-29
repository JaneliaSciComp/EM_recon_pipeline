#!/bin/bash

# ----------------------------------------------------------------------------
# Writes the downsampled dataset paths (s1, s2, ...) of each stack that has at least one
# failed batch job and no succeeded ones, so that the partial pyramids left behind by the
# failures can be removed before those stacks are downsampled again.
#
# s0 is never listed because the full scale export is what the reruns start from.
#
# The inputs are lists of batch ids, one per line, e.g.
#   rex-20260925-211038-w61-s199-r00-gc-bc-par-cc-asoi-3d-pixel
#   rds-20260925-185224-w61-s129-r01-gc-bc-par-cc-asoi-3d-pixel
#
# The stack names pulled from those are w61-s199-r00 and w61-s129-r01, and the paths
# written for w61-s199-r00 are whichever of these exist:
#   ${RENDER_EXP}/w61_serial_190_to_199/w61_s199_r00${STACK_SUFFIX}/s1
#   ${RENDER_EXP}/w61_serial_190_to_199/w61_s199_r00${STACK_SUFFIX}/s2
#   ...
#
# Only rex (export) and rds (downsample) jobs are considered.  Other jobs, like the
# rp-<time>-ic2d-w61-s180-to-s189 pipeline runs, name a slab range instead of one stack.
#
# The paths go to ${RESULT_FILE} while notes and warnings go to stderr.

SUCCEEDED_FILE="dataproc-jobs.succeeded.txt"
FAILED_FILE="dataproc-jobs.failed.txt"
RESULT_FILE="dataproc-jobs.failed-only.txt"

RENDER_EXP="gs://janelia-spark-test/hess_wafers_60_61_export/render"

# note that the exported dataset name uses three underscores before pixel
STACK_SUFFIX="_gc_bc_par_cc_asoi_3d___pixel"

# batch ids embed the raw stack name with dashes instead of underscores
STACK_NAME_PATTERN='w[0-9]+-s[0-9]+-r[0-9]+'

# rex ids come from 11_run_n5_export.sh exports, rds ids from its downsample only runs
BATCH_ID_PREFIX_PATTERN='^(rex|rds)-'

for FILE in "${SUCCEEDED_FILE}" "${FAILED_FILE}"; do
  if [ ! -f "${FILE}" ]; then
    echo "ERROR: ${FILE} does not exist" >&2
    exit 1
  fi
done

# Prints the exported dataset url for the dashed stack name in $1, e.g. w61-s071-r00 becomes
# ${RENDER_EXP}/w61_serial_070_to_079/w61_s071_r00${STACK_SUFFIX}.
#
# The project is derived from the serial number the same way 11_run_n5_export.sh does.
toDatasetUrl() {

  local DASHED_STACK_NAME="$1"

  if [[ ! "${DASHED_STACK_NAME}" =~ ^(w[0-9]+)-s([0-9]+)-r[0-9]+$ ]]; then
    echo "ERROR: cannot derive a dataset url from stack name '${DASHED_STACK_NAME}'" >&2
    return 1
  fi

  local WAFER="${BASH_REMATCH[1]}"
  # force base 10 so that a zero padded serial (e.g. 071) is not treated as octal
  local SERIAL_NUMBER=$(( 10#${BASH_REMATCH[2]} ))
  local FIRST_PROJECT_SERIAL=$(( (SERIAL_NUMBER / 10) * 10 ))

  printf '%s/%s_serial_%03d_to_%03d/%s%s\n' \
         "${RENDER_EXP}" \
         "${WAFER}" "${FIRST_PROJECT_SERIAL}" $(( FIRST_PROJECT_SERIAL + 9 )) \
         "${DASHED_STACK_NAME//-/_}" "${STACK_SUFFIX}"
}

# Prints the downsampled (s1 and higher) dataset paths that exist for the dashed stack
# name in $1, ordered by level so that s2 comes before s10.
#
# Each dataset is listed on its own instead of with one wildcard listing of the project
# group, which would also return every other export in it.
downsampledPathsForStack() {

  local DATASET_URL
  DATASET_URL=$(toDatasetUrl "$1") || return 1

  gcloud storage ls "${DATASET_URL}/" 2>/dev/null |
    sed -n 's|^\(.*\)/s\([0-9][0-9]*\)/$|\2 \1/s\2|p' |
    awk '$1 > 0' |
    sort -n |
    cut -d' ' -f2-
}

# Prints the sorted unique stack names found in the rex and rds batch ids of $1.
stackNamesInFile() {
  grep -E "${BATCH_ID_PREFIX_PATTERN}" "$1" | grep -oE "${STACK_NAME_PATTERN}" | sort -u
}

# Report what is being left out so that nothing is silently dropped from the comparison.
for FILE in "${SUCCEEDED_FILE}" "${FAILED_FILE}"; do

  OTHER_JOB_COUNT=$(grep -v '^[[:space:]]*$' "${FILE}" |
                      grep -cvE "${BATCH_ID_PREFIX_PATTERN}" || true)
  if (( OTHER_JOB_COUNT > 0 )); then
    printf "NOTE: ignoring %s non rex/rds line(s) in %s\n" "${OTHER_JOB_COUNT}" "${FILE}" >&2
  fi

  NO_STACK_NAME_COUNT=$(grep -E "${BATCH_ID_PREFIX_PATTERN}" "${FILE}" |
                          grep -cvE "${STACK_NAME_PATTERN}" || true)
  if (( NO_STACK_NAME_COUNT > 0 )); then
    printf "WARNING: %s rex/rds line(s) in %s have no stack name\n" \
           "${NO_STACK_NAME_COUNT}" "${FILE}" >&2
  fi

done

# comm -23 prints the names that appear only in the first (failed) list
FAILED_ONLY_STACKS=$(comm -23 \
  <(stackNamesInFile "${FAILED_FILE}") \
  <(stackNamesInFile "${SUCCEEDED_FILE}"))

if [ -z "${FAILED_ONLY_STACKS}" ]; then
  printf "\nno stacks failed without also succeeding\n\n" >&2
  exit 0
fi

STACK_COUNT=$(printf '%s\n' "${FAILED_ONLY_STACKS}" | wc -l | tr -d ' ')

printf "\n%s stack(s) have failures and no successes, listing their downsampled levels ...\n\n" \
       "${STACK_COUNT}" >&2

: > "${RESULT_FILE}"

while IFS= read -r DASHED_STACK_NAME; do
  DOWNSAMPLED_PATHS=$(downsampledPathsForStack "${DASHED_STACK_NAME}")
  if [ -z "${DOWNSAMPLED_PATHS}" ]; then
    printf "NOTE: %s has no downsampled levels to remove\n" "${DASHED_STACK_NAME}" >&2
  else
    printf '%s\n' "${DOWNSAMPLED_PATHS}" >> "${RESULT_FILE}"
  fi
done <<< "${FAILED_ONLY_STACKS}"

printf "\nsaved %s path(s) for %s stack(s) to %s\n\n" \
       "$(wc -l < "${RESULT_FILE}" | tr -d ' ')" "${STACK_COUNT}" "${RESULT_FILE}" >&2
