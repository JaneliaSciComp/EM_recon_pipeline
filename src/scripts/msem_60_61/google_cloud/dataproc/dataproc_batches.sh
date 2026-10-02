#!/bin/bash

set -e

# ----------------------------------------------------------------------------
# Lists the ids of Dataproc batch jobs, most recently created first, and can
# optionally download the driver or executor logs for each one.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

PROJECT="janelia-ibeam"
REGION="us-east4"

DRIVER_LOG_SCRIPT="${SCRIPT_DIR}/download_driver_log.sh"
EXECUTOR_LOG_SCRIPT="${SCRIPT_DIR}/download_executor_log.sh"

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_BATCH_ID_PATTERN=""
ARG_CREATED_AFTER=""
ARG_CREATED_BEFORE=""
ARG_STATUS=""
ARG_MAX_ITEMS="30"
ARG_ACTION="list"

usage() {
  echo "
USAGE $0 [--action <action>] [--batch-id-pattern <pattern>] [--created-after <yyyymmdd>]
          [--created-before <yyyymmdd>] [--status <status>] [--max-items <count>]

  --action            list to just print the matching batch ids, driver-log to
                      print them and then be prompted to download each driver log,
                      or executor-log to be prompted to download each batch's executor
                      logs into a <batch-id>.executor-logs directory
                      (default: ${ARG_ACTION})
  --batch-id-pattern  extended regular expression the batch id must match
  --created-after     only include batches created on or after this date
  --created-before    only include batches created before this date
  --status            only include batches with this status: pending, running,
                      cancelling, cancelled, succeeded, or failed
  --max-items         maximum number of ids to print (default: ${ARG_MAX_ITEMS})

Examples:

  $0
  $0 --status failed
  $0 --batch-id-pattern 'ic2d-w61-s18'
  $0 --batch-id-pattern '^rds-' --created-after 20260925 --status running
  $0 --created-after 20260920 --created-before 20260925 --max-items 100
  $0 --action driver-log --status failed --created-after 20260925
  $0 --action executor-log --batch-id-pattern 'test-a' --max-items 1
"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --action)
      ARG_ACTION="${2:?'--action requires a value'}"
      shift 2
      ;;
    --batch-id-pattern)
      ARG_BATCH_ID_PATTERN="${2:?'--batch-id-pattern requires a value'}"
      shift 2
      ;;
    --created-after)
      ARG_CREATED_AFTER="${2:?'--created-after requires a value'}"
      shift 2
      ;;
    --created-before)
      ARG_CREATED_BEFORE="${2:?'--created-before requires a value'}"
      shift 2
      ;;
    --status)
      ARG_STATUS="${2:?'--status requires a value'}"
      shift 2
      ;;
    --max-items)
      ARG_MAX_ITEMS="${2:?'--max-items requires a value'}"
      shift 2
      ;;
    *)
      echo "ERROR: unrecognized parameter '${1}'"
      usage
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Validate parameters

# Converts a yyyymmdd parameter to the RFC 3339 UTC timestamp for the start of that day.
toStartOfDayTimestamp() {
  local NAME="$1"
  local VALUE="$2"
  if [[ ! "${VALUE}" =~ ^[0-9]{8}$ ]]; then
    echo "ERROR: ${NAME} must be yyyymmdd (not '${VALUE}')" >&2
    exit 1
  fi
  echo "${VALUE:0:4}-${VALUE:4:2}-${VALUE:6:2}T00:00:00Z"
}

# These are the Batch.State enum values, see
# https://cloud.google.com/dataproc-serverless/docs/reference/rest/v1/projects.locations.batches
# STATE_UNSPECIFIED is left out because no batch should ever be in it.
# CANCELLED, SUCCEEDED, and FAILED are the terminal states.
case "${ARG_STATUS}" in
  "")           BATCH_STATE="" ;;
  pending)      BATCH_STATE="PENDING" ;;
  running)      BATCH_STATE="RUNNING" ;;
  cancelling)   BATCH_STATE="CANCELLING" ;;
  cancelled)    BATCH_STATE="CANCELLED" ;;
  succeeded)    BATCH_STATE="SUCCEEDED" ;;
  failed)       BATCH_STATE="FAILED" ;;
  *)
    echo "ERROR: --status must be 'pending', 'running', 'cancelling', 'cancelled'," \
         "'succeeded', or 'failed' (not '${ARG_STATUS}')"
    exit 1
    ;;
esac

if [[ ! "${ARG_MAX_ITEMS}" =~ ^[0-9]+$ ]] || (( ARG_MAX_ITEMS < 1 )); then
  echo "ERROR: --max-items must be a positive integer (not '${ARG_MAX_ITEMS}')"
  exit 1
fi

LOG_SCRIPT=""
case "${ARG_ACTION}" in
  list)
    ;;
  driver-log)
    LOG_SCRIPT="${DRIVER_LOG_SCRIPT}"
    LOG_DESCRIPTION="driver log"
    ;;
  executor-log)
    LOG_SCRIPT="${EXECUTOR_LOG_SCRIPT}"
    LOG_DESCRIPTION="executor logs"
    ;;
  *)
    echo "ERROR: --action must be 'list', 'driver-log', or 'executor-log' (not '${ARG_ACTION}')"
    exit 1
    ;;
esac

if [ -n "${LOG_SCRIPT}" ] && [ ! -x "${LOG_SCRIPT}" ]; then
  echo "ERROR: ${LOG_SCRIPT} does not exist or is not executable"
  exit 1
fi

# ----------------------------------------------------------------------------
# Build the server side filter
#
# The ListBatches API only supports filtering on batch_id, batch_uuid, state, and create_time
# (and silently returns nothing for an unsupported field), so state and create_time are
# filtered here while the batch id pattern is matched locally below.

FILTER=""

appendFilterClause() {
  if [ -n "${FILTER}" ]; then
    FILTER="${FILTER} AND $1"
  else
    FILTER="$1"
  fi
}

if [ -n "${BATCH_STATE}" ]; then
  appendFilterClause "state = ${BATCH_STATE}"
fi

if [ -n "${ARG_CREATED_AFTER}" ]; then
  appendFilterClause "create_time >= \"$(toStartOfDayTimestamp --created-after "${ARG_CREATED_AFTER}")\""
fi

if [ -n "${ARG_CREATED_BEFORE}" ]; then
  appendFilterClause "create_time < \"$(toStartOfDayTimestamp --created-before "${ARG_CREATED_BEFORE}")\""
fi

# ----------------------------------------------------------------------------
# List the batch ids
#
# The pattern is applied after the listing rather than with --limit so that the requested
# number of matching ids is printed instead of the matches within the first few batches.

LIST_ARGS=(--region="${REGION}" --project="${PROJECT}")

if [ -n "${FILTER}" ]; then
  LIST_ARGS+=(--filter="${FILTER}")
fi

# name is projects/<project>/locations/<region>/batches/<batch id>
LIST_ARGS+=(--sort-by=~createTime --format='value(name.basename())')

BATCH_IDS=()
while IFS= read -r BATCH_ID; do
  if [ -n "${BATCH_ID}" ]; then
    BATCH_IDS+=("${BATCH_ID}")
  fi
done < <(gcloud dataproc batches list "${LIST_ARGS[@]}" |
           grep -E "${ARG_BATCH_ID_PATTERN:-.}" |
           head -n "${ARG_MAX_ITEMS}")

if (( ${#BATCH_IDS[@]} == 0 )); then
  printf "\nno matching batches were found\n\n"
  exit 1
fi

printf '%s\n' "${BATCH_IDS[@]}"

# ----------------------------------------------------------------------------
# Optionally download each driver or executor log
#
# The output location is left unspecified so that the download scripts use their
# <batch-id>.driver.log and <batch-id>.executor-logs defaults in the current directory.

if [ -n "${LOG_SCRIPT}" ]; then

  printf "\n%d batch(es) matched\n" "${#BATCH_IDS[@]}"

  for BATCH_ID in "${BATCH_IDS[@]}"; do
    echo
    read -rp "Download the ${LOG_DESCRIPTION} for ${BATCH_ID}? (y/n): " DOWNLOAD_CONFIRM
    if [[ ${DOWNLOAD_CONFIRM} =~ ^[Yy]$ ]]; then
      "${LOG_SCRIPT}" --batch-id "${BATCH_ID}"
    fi
  done

fi
