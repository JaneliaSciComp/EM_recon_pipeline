#!/bin/bash

set -e

# ----------------------------------------------------------------------------
# Downloads the spark driver log for a Dataproc batch run to a local text file.
#
# The driver log is in the 'output' log (the 'spark' log has the executor logs).
#
# NOTE: runtime 3.0 batches do not use Cloud Storage staging buckets, so the driver output
#       is only available from Cloud Logging (runtimeInfo.outputUri is empty for those runs).

PROJECT="janelia-ibeam"
REGION="us-east4"

ARG_BATCH_ID=""
ARG_OUTPUT_FILE=""
ARG_RECENT_BATCH_COUNT=20

usage() {
  echo "
USAGE $0 [--batch-id <batch-id|pattern>] [--output-file <file>] [--recent-batch-count <n>]

  --batch-id     Dataproc batch id (e.g. rp-20260917-214456-rough-w61-s070-to-s074
                 or rex-20260906-084102-w61-s199-r00-gc-icc-par-asoi-3d-pixel)
                 or a pattern to match against the ids of existing batches
                 (e.g. ic2d-w61-s180-to-s189), in which case the most recent
                 matching batch is used
                 (default: choose from the --recent-batch-count most recent batches)
  --output-file  file to write the log to (default: <batch-id>.driver.log)
  --recent-batch-count
                 number of recent batches to choose from when --batch-id is not
                 specified (default: ${ARG_RECENT_BATCH_COUNT})
  -h, --help     show this message

Examples:

  $0

  $0 --batch-id rp-20260917-214456-rough-w61-s070-to-s074

  $0 --batch-id 'w61-s199-r00-.*-pixel' --output-file s199.driver.log
"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --batch-id)
      ARG_BATCH_ID="${2:?'--batch-id requires a value'}"
      shift 2
      ;;
    --output-file)
      ARG_OUTPUT_FILE="${2:?'--output-file requires a value'}"
      shift 2
      ;;
    --recent-batch-count)
      ARG_RECENT_BATCH_COUNT="${2:?'--recent-batch-count requires a value'}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: unrecognized parameter '${1}'"
      usage
      ;;
  esac
done

if [[ ! "${ARG_RECENT_BATCH_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: --recent-batch-count must be a positive integer, not '${ARG_RECENT_BATCH_COUNT}'"
  usage
fi

# Batch ids start with a submitting script's prefix followed by <yyyymmdd>-<hhmmss>-,
# e.g. rp- from 02_run_pipeline.sh and rex- from 11_run_n5_export.sh.
BATCH_ID_PATTERN='^[a-z]+-([0-9]{4})([0-9]{2})([0-9]{2})-[0-9]{6}-'

# Lists the batches in the "<batch-id><tab><state>" lines passed as $1 and sets
# SELECTED_BATCH_ID to the one the user picks (exits if the user quits).
#
# The lines are passed as an argument instead of on stdin because select reads the
# user's answer from stdin.
select_batch_id() {
  local BATCH_LINES="$1"
  local BATCH_ID BATCH_STATE BATCH_LABEL

  # NOTE: mapfile is not in the bash 3.2 that ships with macOS, so the arrays are built with read
  local BATCH_IDS=()
  local BATCH_LABELS=()
  while IFS=$'\t' read -r BATCH_ID BATCH_STATE; do
    BATCH_IDS+=("${BATCH_ID}")
    BATCH_LABELS+=("$(printf '%-75s %s' "${BATCH_ID}" "${BATCH_STATE}")")
  done <<< "${BATCH_LINES}"

  SELECTED_BATCH_ID=""

  echo
  PS3=$'\nselect a batch by number (or q to quit): '
  select BATCH_LABEL in "${BATCH_LABELS[@]}"; do
    if [ "${REPLY}" = "q" ]; then
      exit 1
    elif [ -n "${BATCH_LABEL}" ]; then
      SELECTED_BATCH_ID="${BATCH_IDS[$(( REPLY - 1 ))]}"
      break
    fi
    echo "'${REPLY}' is not one of the listed numbers"
  done

  # select also ends when stdin is closed (e.g. ctrl-d) without a selection
  if [ -z "${SELECTED_BATCH_ID}" ]; then
    printf "\nExiting, no batch was selected\n\n"
    exit 1
  fi
}

# Without --batch-id, list the most recent batches and let the user pick one.
if [ -z "${ARG_BATCH_ID}" ]; then

  if [ ! -t 0 ]; then
    echo "ERROR: --batch-id is required when the script is not run interactively"
    usage
  fi

  printf "\nlooking for the %s most recent batches ...\n" "${ARG_RECENT_BATCH_COUNT}"

  RECENT_BATCHES=$(gcloud dataproc batches list \
                     --region="${REGION}" \
                     --project="${PROJECT}" \
                     --sort-by=~createTime \
                     --limit="${ARG_RECENT_BATCH_COUNT}" \
                     --format='value(name.basename(), state)')

  if [ -z "${RECENT_BATCHES}" ]; then
    printf "\nExiting, no batches were found in project %s region %s\n\n" "${PROJECT}" "${REGION}"
    exit 1
  fi

  select_batch_id "${RECENT_BATCHES}"
  ARG_BATCH_ID="${SELECTED_BATCH_ID}"

# Anything that is not a full batch id is treated as a pattern and resolved against the
# batches that still exist.
#
# The ListBatches API only supports filtering on batch_id, batch_uuid, state, and create_time
# (and silently returns nothing for an unsupported field), so the pattern is matched here
# instead of being passed to gcloud.
elif [[ ! "${ARG_BATCH_ID}" =~ ${BATCH_ID_PATTERN} ]]; then

  printf "\nlooking for batches matching '%s' ...\n" "${ARG_BATCH_ID}"

  # The pattern is only matched against the id column so that anchors like 'pixel$' still work
  # (it is read from the environment because awk -v would interpret backslashes in it).
  # Sort on the <yyyymmdd> and <hhmmss> fields (2 and 3 of the dash delimited id) so that the
  # most recent match is first even when the matches have different prefixes (rp- and rex-).
  MATCHING_BATCHES=$(gcloud dataproc batches list \
                       --region="${REGION}" \
                       --project="${PROJECT}" \
                       --format='value(name.basename(), state)' |
                     PATTERN="${ARG_BATCH_ID}" awk -F'\t' '$1 ~ ENVIRON["PATTERN"]' |
                     sort -t'-' -k2,2r -k3,3r) || true

  if [ -z "${MATCHING_BATCHES}" ]; then
    printf "\nExiting, no batch id matches '%s'\n\n" "${ARG_BATCH_ID}"
    exit 1
  fi

  MATCHING_BATCH_COUNT=$(printf '%s\n' "${MATCHING_BATCHES}" | wc -l | tr -d ' ')

  if (( MATCHING_BATCH_COUNT == 1 )); then
    ARG_BATCH_ID=$(printf '%s\n' "${MATCHING_BATCHES}" | cut -f1)
  elif [ -t 0 ]; then
    printf "\n%s batches match:\n" "${MATCHING_BATCH_COUNT}"
    select_batch_id "${MATCHING_BATCHES}"
    ARG_BATCH_ID="${SELECTED_BATCH_ID}"
  else
    # callers that are not interactive get the most recent match
    printf "\n%s batches match, using the most recent one:\n\n" "${MATCHING_BATCH_COUNT}"
    printf '%s\n' "${MATCHING_BATCHES}" | cut -f1 | sed 's/^/  /'
    ARG_BATCH_ID=$(printf '%s\n' "${MATCHING_BATCHES}" | head -1 | cut -f1)
  fi

  printf "\nusing batch id %s\n" "${ARG_BATCH_ID}"

fi

if [[ ! "${ARG_BATCH_ID}" =~ ${BATCH_ID_PATTERN} ]]; then
  printf "\nExiting, batch id '%s' does not start with <prefix>-<yyyymmdd>-<hhmmss>-\n\n" "${ARG_BATCH_ID}"
  exit 1
fi

RUN_DATE="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"

# gcloud logging read defaults to --freshness=1d when the filter has no timestamp, which silently
# returns nothing for older runs, so derive a lower bound from the batch id instead.
#
# The batch id timestamp is local time while log timestamps are UTC.  Local midnight is always
# later than the same date's UTC midnight for timezones behind UTC (the launch box is US Eastern),
# so using the batch date at UTC midnight is a safe lower bound without any timezone conversion.
MIN_TIMESTAMP="${RUN_DATE}T00:00:00Z"

OUTPUT_FILE="${ARG_OUTPUT_FILE:-${ARG_BATCH_ID}.driver.log}"

# Each line is prefixed with the entry's UTC timestamp so that log lines can be correlated with
# wall clock time (log timestamps are UTC while the batch id timestamp is local time).
# The date transform drops the nanoseconds from the raw 2026-09-18T00:22:50.278894893Z value.
# To see local times instead, add a tz to the transform, e.g.
#   timestamp.date(format="%Y-%m-%d %H:%M:%S", tz="EST5EDT")
# To go back to messages without timestamps, use:
#   --format='value(jsonPayload.message)'
LOG_FORMAT='value(timestamp.date(format="%Y-%m-%d %H:%M:%S"), jsonPayload.message)'

# Spark logs one of these lines for every executor as it comes and goes, which buries the
# pipeline's own messages in runs with hundreds of executors.  They are dropped after the
# download (instead of being filtered in the logging query) so that whole multi-line entries
# like stack traces are never removed because of one noisy line.
EXCLUDE_LINE_PATTERN='No executor found for|Registered executor NettyRpcEndpointRef'

printf "\nreading driver log for batch %s (entries at or after %s) ...\n" "${ARG_BATCH_ID}" "${MIN_TIMESTAMP}"

gcloud logging read \
  "resource.type=\"cloud_dataproc_batch\"
   resource.labels.batch_id=\"${ARG_BATCH_ID}\"
   logName=\"projects/${PROJECT}/logs/dataproc.googleapis.com%2Foutput\"
   timestamp>=\"${MIN_TIMESTAMP}\"" \
  --project="${PROJECT}" \
  --order=asc \
  --format="${LOG_FORMAT}" \
  > "${OUTPUT_FILE}"

DOWNLOADED_LINE_COUNT=$(wc -l < "${OUTPUT_FILE}" | tr -d ' ')

# grep exits 1 when nothing survives the filter, which is not an error here
grep -E -v "${EXCLUDE_LINE_PATTERN}" "${OUTPUT_FILE}" > "${OUTPUT_FILE}.tmp" || true
mv "${OUTPUT_FILE}.tmp" "${OUTPUT_FILE}"

LINE_COUNT=$(wc -l < "${OUTPUT_FILE}" | tr -d ' ')
EXCLUDED_LINE_COUNT=$(( DOWNLOADED_LINE_COUNT - LINE_COUNT ))

if (( LINE_COUNT == 0 )); then
  printf "
WARNING: no driver log entries were found for %s

  - check the batch id (gcloud dataproc batches list --region=%s --project=%s)
  - Cloud Logging keeps entries for 30 days by default, so older runs may have expired

" "${ARG_BATCH_ID}" "${REGION}" "${PROJECT}"
else
  # NOTE: readlink -m is a GNU extension that the BSD readlink on macOS does not support,
  #       so build the absolute path with cd and pwd instead
  ABSOLUTE_OUTPUT_FILE="$(cd "$(dirname "${OUTPUT_FILE}")" && pwd)/$(basename "${OUTPUT_FILE}")"

  printf "
wrote %s lines to:
  %s

(excluded %s executor registration line(s) from the %s downloaded)

" "${LINE_COUNT}" "${ABSOLUTE_OUTPUT_FILE}" "${EXCLUDED_LINE_COUNT}" "${DOWNLOADED_LINE_COUNT}"

  printf "errors and exceptions in the log:\n"
  grep -c -E 'ERROR|Exception' "${OUTPUT_FILE}" || true
fi
