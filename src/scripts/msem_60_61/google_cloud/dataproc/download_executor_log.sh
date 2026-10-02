#!/bin/bash

set -e

# ----------------------------------------------------------------------------
# Downloads the spark executor logs for a Dataproc batch run into a directory:
#
#   <output-dir>/
#     all.log             every executor's lines in time order, with a short executor id on each line
#     summary.tsv         one row per executor (first/last time, line, error, exception, and
#                         OutOfMemoryError counts), executors with problems first
#     executors/<id>.log  the lines for one executor
#
# The executor logs are in the 'spark' log (the 'output' log has the driver log, see
# download_driver_log.sh).  Each entry's jsonPayload.executor_id is the executor's pod name,
# e.g. gdpic-rm-5a66cf14-ba40-4df9-a852-2d026264fb94-0ein9709ogcd5xp, and the part after the
# last dash (0ein9709ogcd5xp) is used as the short id.

PROJECT="janelia-ibeam"
REGION="us-east4"

ARG_BATCH_ID=""
ARG_OUTPUT_DIR=""
ARG_MIN_SEVERITY=""
ARG_AFTER=""
ARG_BEFORE=""

usage() {
  echo "
USAGE $0 --batch-id <batch-id> [options]

  --batch-id      Dataproc batch id (required, e.g. rex-20260930-091200-w61-s129-r00-gc-bc-par-cc-asoi-3d-test-a),
                  use dataproc_batches.sh to find one
  --output-dir    directory to write the logs to (default: <batch-id>.executor-logs)
  --min-severity  only download entries at or above this severity: info, warning, or error
                  (default: all entries)
  --after         only download entries at or after this UTC time
  --before        only download entries before this UTC time
                  (times are 'yyyy-mm-dd hh:mm:ss' as printed in all.log, or yyyy-mm-ddThh:mm:ssZ)
  -h, --help      show this message

Large runs can have millions of executor log lines, so use --min-severity or a time window
to keep the download manageable.

Examples:

  $0 --batch-id rex-20260930-091200-w61-s129-r00-gc-bc-par-cc-asoi-3d-test-a --min-severity warning

  $0 --batch-id rex-20260930-091200-w61-s129-r00-gc-bc-par-cc-asoi-3d-test-a \\
     --after '2026-09-30 13:20:00' --before '2026-09-30 13:35:00'
"
  exit 1
}

if (( $# < 1 )); then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --batch-id)
      ARG_BATCH_ID="${2:?'--batch-id requires a value'}"
      shift 2
      ;;
    --output-dir)
      ARG_OUTPUT_DIR="${2:?'--output-dir requires a value'}"
      shift 2
      ;;
    --min-severity)
      ARG_MIN_SEVERITY="${2:?'--min-severity requires a value'}"
      shift 2
      ;;
    --after)
      ARG_AFTER="${2:?'--after requires a value'}"
      shift 2
      ;;
    --before)
      ARG_BEFORE="${2:?'--before requires a value'}"
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

# ----------------------------------------------------------------------------
# Validate parameters

if [ -z "${ARG_BATCH_ID}" ]; then
  echo "ERROR: --batch-id is required"
  usage
fi

# Batch ids start with a submitting script's prefix followed by <yyyymmdd>-<hhmmss>-,
# e.g. rp- from 02_run_pipeline.sh and rex- from 11_run_n5_export.sh.
BATCH_ID_PATTERN='^[a-z]+-([0-9]{4})([0-9]{2})([0-9]{2})-[0-9]{6}-'

if [[ ! "${ARG_BATCH_ID}" =~ ${BATCH_ID_PATTERN} ]]; then
  echo "ERROR: --batch-id '${ARG_BATCH_ID}' does not start with <prefix>-<yyyymmdd>-<hhmmss>-"
  exit 1
fi

RUN_DATE="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"

case "${ARG_MIN_SEVERITY}" in
  "")      SEVERITY="" ;;
  info)    SEVERITY="INFO" ;;
  warning) SEVERITY="WARNING" ;;
  error)   SEVERITY="ERROR" ;;
  *)
    echo "ERROR: --min-severity must be 'info', 'warning', or 'error' (not '${ARG_MIN_SEVERITY}')"
    exit 1
    ;;
esac

# Converts a 'yyyy-mm-dd hh:mm:ss' or yyyy-mm-ddThh:mm:ssZ UTC time to RFC 3339.
toTimestamp() {
  local NAME="$1"
  local VALUE="$2"
  if [[ ! "${VALUE}" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})[\ T]([0-9]{2}:[0-9]{2}:[0-9]{2})Z?$ ]]; then
    echo "ERROR: ${NAME} must be 'yyyy-mm-dd hh:mm:ss' or yyyy-mm-ddThh:mm:ssZ (not '${VALUE}')" >&2
    exit 1
  fi
  echo "${BASH_REMATCH[1]}T${BASH_REMATCH[2]}Z"
}

# gcloud logging read defaults to --freshness=1d when the filter has no timestamp, which silently
# returns nothing for older runs, so without --after the lower bound is derived from the batch id.
# The batch id timestamp is local (US Eastern) time, so its date at UTC midnight is always early enough.
if [ -n "${ARG_AFTER}" ]; then
  MIN_TIMESTAMP=$(toTimestamp --after "${ARG_AFTER}")
else
  MIN_TIMESTAMP="${RUN_DATE}T00:00:00Z"
fi

MAX_TIMESTAMP=""
if [ -n "${ARG_BEFORE}" ]; then
  MAX_TIMESTAMP=$(toTimestamp --before "${ARG_BEFORE}")
fi

OUTPUT_DIR="${ARG_OUTPUT_DIR:-${ARG_BATCH_ID}.executor-logs}"

if [ -e "${OUTPUT_DIR}" ]; then
  echo "ERROR: ${OUTPUT_DIR} already exists, remove it or specify a different --output-dir"
  exit 1
fi

# ----------------------------------------------------------------------------
# Download

LOG_FILTER="resource.type=\"cloud_dataproc_batch\"
 resource.labels.batch_id=\"${ARG_BATCH_ID}\"
 logName=\"projects/${PROJECT}/logs/dataproc.googleapis.com%2Fspark\"
 jsonPayload.component=\"executor\"
 timestamp>=\"${MIN_TIMESTAMP}\""

if [ -n "${MAX_TIMESTAMP}" ]; then
  LOG_FILTER="${LOG_FILTER}
 timestamp<\"${MAX_TIMESTAMP}\""
fi

if [ -n "${SEVERITY}" ]; then
  LOG_FILTER="${LOG_FILTER}
 severity>=${SEVERITY}"
fi

# Tab separated so that the message (the last field) can contain spaces.
# The date transform drops the nanoseconds from the raw 2026-09-18T00:22:50.278894893Z value.
LOG_FORMAT='value(timestamp.date(format="%Y-%m-%d %H:%M:%S"), jsonPayload.executor_id, severity, jsonPayload.message)'

mkdir -p "${OUTPUT_DIR}/executors"
RAW_FILE="${OUTPUT_DIR}/raw.tsv"
TAGGED_FILE="${OUTPUT_DIR}/tagged.tsv"

printf "\nreading executor logs for batch %s (entries at or after %s%s%s) ...\n" \
       "${ARG_BATCH_ID}" "${MIN_TIMESTAMP}" \
       "${MAX_TIMESTAMP:+, before ${MAX_TIMESTAMP}}" "${SEVERITY:+, severity ${SEVERITY} or higher}"

gcloud logging read "${LOG_FILTER}" \
  --project="${PROJECT}" \
  --order=asc \
  --format="${LOG_FORMAT}" \
  > "${RAW_FILE}"

# ----------------------------------------------------------------------------
# Organize
#
# A multi-line message (e.g. a stack trace) continues on lines that do not start with a
# timestamp, so those lines are assigned to the executor of the entry they follow.
#
# The first pass writes all.log and a copy of each line tagged with its short executor id.
# The tagged lines are then stably sorted by id (keeping each executor's lines in time order)
# so the second pass can write one executor file at a time.  That avoids having an open file
# for every executor at once, which the BSD awk on macOS has a low limit for.
#
# NOTE: awk interval expressions like [0-9]{4} are not supported by older BSD awks,
#       so the timestamp pattern is spelled out.

TIMESTAMP_LINE='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\t'

awk -F'\t' -v all_file="${OUTPUT_DIR}/all.log" -v timestamp_line="${TIMESTAMP_LINE}" '
  $0 ~ timestamp_line {
    executor = $2
    sub(/.*-/, "", executor)
    message = $4
    for (i = 5; i <= NF; i++) message = message "\t" $i
    line = $1 "  " executor "  " $3 "  " message
  }
  $0 !~ timestamp_line {
    # a continuation line of the previous entry (executor stays the same)
    line = $0
  }
  executor != "" {
    print line > all_file
    print executor "\t" line
  }
' "${RAW_FILE}" > "${TAGGED_FILE}"

SUMMARY_FILE="${OUTPUT_DIR}/summary.tsv"
SUMMARY_ROWS_FILE="${OUTPUT_DIR}/summary.rows"

sort -s -t$'\t' -k1,1 "${TAGGED_FILE}" |
awk -F'\t' -v executors_dir="${OUTPUT_DIR}/executors" -v timestamp_prefix='^[0-9][0-9][0-9][0-9]-' '
  function finish() {
    if (executor == "") return
    close(file)
    printf "%s\t%s\t%s\t%d\t%d\t%d\t%d\n", executor, first, last, lines, errors, exceptions, ooms
  }
  $1 != executor {
    finish()
    executor = $1
    file = executors_dir "/" executor ".log"
    first = ""; last = ""; lines = 0; errors = 0; exceptions = 0; ooms = 0
  }
  {
    line = substr($0, length($1) + 2)
    print line > file
    lines++
    if (line ~ timestamp_prefix) {
      # line is "<yyyy-mm-dd> <hh:mm:ss>  <executor>  <severity>  <message>"
      split(line, part, "  ")
      if (first == "") first = part[1]
      last = part[1]
      if (part[3] == "ERROR" || part[3] == "CRITICAL" || part[3] == "ALERT" || part[3] == "EMERGENCY") errors++
    }
    if (line ~ /Exception/) exceptions++
    if (line ~ /OutOfMemoryError/) ooms++
  }
  END { finish() }
' > "${SUMMARY_ROWS_FILE}"

# executors with OutOfMemoryErrors, then exceptions, then errors first
{
  printf "executor\tfirst\tlast\tlines\terrors\texceptions\tout_of_memory\n"
  sort -t$'\t' -k7,7nr -k6,6nr -k5,5nr -k1,1 "${SUMMARY_ROWS_FILE}"
} > "${SUMMARY_FILE}"

DOWNLOADED_LINE_COUNT=$(wc -l < "${RAW_FILE}" | tr -d ' ')
EXECUTOR_COUNT=$(wc -l < "${SUMMARY_ROWS_FILE}" | tr -d ' ')

rm "${RAW_FILE}" "${TAGGED_FILE}" "${SUMMARY_ROWS_FILE}"

# ----------------------------------------------------------------------------
# Report

if (( DOWNLOADED_LINE_COUNT == 0 )); then
  rm -r "${OUTPUT_DIR}"
  printf "
WARNING: no executor log entries were found for %s

  - check the batch id (gcloud dataproc batches list --region=%s --project=%s)
  - check --min-severity, --after, and --before
  - Cloud Logging keeps entries for 30 days by default, so older runs may have expired

" "${ARG_BATCH_ID}" "${REGION}" "${PROJECT}"
  exit 1
fi

# NOTE: readlink -m is a GNU extension that the BSD readlink on macOS does not support,
#       so build the absolute path with cd and pwd instead
ABSOLUTE_OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"

printf "
wrote %s lines from %s executors to:
  %s

executors with the most problems (see summary.tsv for all of them):

" "${DOWNLOADED_LINE_COUNT}" "${EXECUTOR_COUNT}" "${ABSOLUTE_OUTPUT_DIR}"

head -6 "${SUMMARY_FILE}" | column -t -s$'\t'
echo
