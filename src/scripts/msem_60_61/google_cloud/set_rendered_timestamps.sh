#!/bin/bash

# ----------------------------------------------------------------------------
# Sets the rendered run timestamps in the pipeline json files to the current time:
#
#   mfovAsTile.renderedMfovRunTimestamp
#   layerAsTile.renderedLayerRunTimestamp
#
# Files in the old subdirectories are not changed.

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PIPELINE_JSON_DIR=$(cd "${SCRIPT_DIR}/../pipeline_json" && pwd)

RUN_TIME=$(date +"%Y%m%d_%H%M%S")

TIMESTAMP_KEY_PATTERN='"rendered(Mfov|Layer)RunTimestamp"'

# shellcheck disable=SC2207
JSON_FILES=($(find "${PIPELINE_JSON_DIR}" -name '*.json' -not -path '*/old/*' \
                -exec grep -l -E "${TIMESTAMP_KEY_PATTERN}" {} + | sort))

if (( ${#JSON_FILES[@]} == 0 )); then
  echo "
ERROR: no json files under ${PIPELINE_JSON_DIR} contain a rendered run timestamp
"
  exit 1
fi

echo "
Setting rendered run timestamps to ${RUN_TIME} in ${PIPELINE_JSON_DIR}:
"

for JSON_FILE in "${JSON_FILES[@]}"; do
  # -i.bak works with both GNU (Linux) and BSD (macOS) sed, the backup is removed right after
  sed -i.bak -E "s/(${TIMESTAMP_KEY_PATTERN}[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"${RUN_TIME}\"/" "${JSON_FILE}"
  rm "${JSON_FILE}.bak"

  RELATIVE_PATH="${JSON_FILE#"${PIPELINE_JSON_DIR}"/}"
  grep -E "${TIMESTAMP_KEY_PATTERN}" "${JSON_FILE}" | sed -E "s|^[[:space:]]*|  ${RELATIVE_PATH}: |"
done

echo
