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

ARG_BATCH_ID="$1"
ARG_OUTPUT_FILE="$2"

if (( $# < 1 )) || (( $# > 2 )); then
  printf "\nUSAGE: %s <batch-id> [output-file]

  batch-id     Dataproc batch id (e.g. rp-20260917-214456-rough-w61-s070-to-s074)
  output-file  file to write the log to (default: <batch-id>.driver.log)

" "$(basename "$0")"
  exit 1
fi

# The batch id starts with rp-<yyyymmdd>-<hhmmss>- (see 02_run_pipeline.sh RUN_TIMESTAMP).
if [[ ! "${ARG_BATCH_ID}" =~ ^rp-([0-9]{4})([0-9]{2})([0-9]{2})-[0-9]{6}- ]]; then
  printf "\nExiting, batch id '%s' does not start with rp-<yyyymmdd>-<hhmmss>-\n\n" "${ARG_BATCH_ID}"
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

printf "\nreading driver log for batch %s (entries at or after %s) ...\n" "${ARG_BATCH_ID}" "${MIN_TIMESTAMP}"

gcloud logging read \
  "resource.type=\"cloud_dataproc_batch\"
   resource.labels.batch_id=\"${ARG_BATCH_ID}\"
   logName=\"projects/${PROJECT}/logs/dataproc.googleapis.com%2Foutput\"
   timestamp>=\"${MIN_TIMESTAMP}\"" \
  --project="${PROJECT}" \
  --order=asc \
  --format='value(jsonPayload.message)' \
  > "${OUTPUT_FILE}"

LINE_COUNT=$(wc -l < "${OUTPUT_FILE}" | tr -d ' ')

if (( LINE_COUNT == 0 )); then
  printf "
WARNING: no driver log entries were found for %s

  - check the batch id (gcloud dataproc batches list --region=us-east4 --project=%s)
  - Cloud Logging keeps entries for 30 days by default, so older runs may have expired

" "${ARG_BATCH_ID}" "${PROJECT}"
else
  # NOTE: readlink -m is a GNU extension that the BSD readlink on macOS does not support,
  #       so build the absolute path with cd and pwd instead
  ABSOLUTE_OUTPUT_FILE="$(cd "$(dirname "${OUTPUT_FILE}")" && pwd)/$(basename "${OUTPUT_FILE}")"

  printf "
wrote %s lines to:
  %s

" "${LINE_COUNT}" "${ABSOLUTE_OUTPUT_FILE}"

  printf "errors and exceptions in the log:\n"
  grep -c -E 'ERROR|Exception' "${OUTPUT_FILE}" || true
fi
