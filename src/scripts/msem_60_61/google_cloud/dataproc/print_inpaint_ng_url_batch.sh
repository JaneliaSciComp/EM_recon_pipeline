#!/bin/bash

# ----------------------------------------------------------------------------
# Runs print_inpaint_ng_url.sh for each region of each serial number in a range and appends
# the results to one file per render project:
#
#   inpaint_urls_<yyyymmdd_HHMMSS>/inpaint_urls.<project>.txt
#
# e.g. inpaint_urls_20261116_093012/inpaint_urls.w61_serial_070_to_079.txt
#
# The output directory is created in the current directory.  Stacks whose export can not be
# read (e.g. r01 for serials 180 and up, or stacks that were not exported) are skipped and
# listed at the end instead of being written to the files.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PRINT_URL_SCRIPT="${SCRIPT_DIR}/print_inpaint_ng_url.sh"

WAFER="61"
REGIONS=(r00 r01)

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_FIRST_SERIAL=""
ARG_LAST_SERIAL=""

usage() {
  echo "
USAGE $(basename "$0") --first-serial-number <number> --last-serial-number <number>

  --first-serial-number  first serial number to print urls for (required)
  --last-serial-number   last serial number to print urls for (required)

Runs print_inpaint_ng_url.sh for each w${WAFER}_s<serial>_<region> stack (regions: ${REGIONS[*]})
and appends the results to inpaint_urls_<yyyymmdd_HHMMSS>/inpaint_urls.<project>.txt

Example:
  $(basename "$0") --first-serial-number 70 --last-serial-number 108
"
  exit 1
}

if (( $# < 1 )); then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --first-serial-number)
      ARG_FIRST_SERIAL="${2:?'--first-serial-number requires a value'}"
      shift 2
      ;;
    --last-serial-number)
      ARG_LAST_SERIAL="${2:?'--last-serial-number requires a value'}"
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

if [ -z "${ARG_FIRST_SERIAL}" ] || [ -z "${ARG_LAST_SERIAL}" ]; then
  echo "ERROR: --first-serial-number and --last-serial-number are both required"
  usage
fi

for SERIAL_ARG in "${ARG_FIRST_SERIAL}" "${ARG_LAST_SERIAL}"; do
  if [[ ! "${SERIAL_ARG}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --first-serial-number and --last-serial-number must be numbers (not '${SERIAL_ARG}')"
    exit 1
  fi
done

# force base 10 so that zero padded values (e.g. 070) are not treated as octal
FIRST_SERIAL=$(( 10#${ARG_FIRST_SERIAL} ))
LAST_SERIAL=$(( 10#${ARG_LAST_SERIAL} ))

if (( FIRST_SERIAL > LAST_SERIAL )); then
  echo "ERROR: --first-serial-number ${FIRST_SERIAL} is greater than --last-serial-number ${LAST_SERIAL}"
  exit 1
fi

if (( LAST_SERIAL > 999 )); then
  echo "ERROR: --last-serial-number must be less than 1000 (not ${LAST_SERIAL})"
  exit 1
fi

if [ ! -x "${PRINT_URL_SCRIPT}" ]; then
  echo "ERROR: ${PRINT_URL_SCRIPT} is missing or not executable"
  exit 1
fi

# ----------------------------------------------------------------------------
# Create the output directory

OUTPUT_DIR="inpaint_urls_$(date '+%Y%m%d_%H%M%S')"

if ! mkdir "${OUTPUT_DIR}"; then
  echo "ERROR: could not create ${OUTPUT_DIR}"
  exit 1
fi

printf "\nwriting urls for w%s serials %03d to %03d to %s ...\n" \
       "${WAFER}" "${FIRST_SERIAL}" "${LAST_SERIAL}" "${OUTPUT_DIR}"

# ----------------------------------------------------------------------------
# Print the urls for each stack

WRITTEN_COUNT=0
SKIPPED=()
OUTPUT_FILES=()

for (( SERIAL = FIRST_SERIAL; SERIAL <= LAST_SERIAL; SERIAL++ )); do

  # e.g. serial 77 is in project w61_serial_070_to_079
  FIRST_PROJECT_SERIAL=$(( (SERIAL / 10) * 10 ))
  PROJECT=$(printf "w%s_serial_%03d_to_%03d" "${WAFER}" "${FIRST_PROJECT_SERIAL}" $(( FIRST_PROJECT_SERIAL + 9 )))
  OUTPUT_FILE="${OUTPUT_DIR}/inpaint_urls.${PROJECT}.txt"

  for REGION in "${REGIONS[@]}"; do

    STACK=$(printf "w%s_s%03d_%s" "${WAFER}" "${SERIAL}" "${REGION}")

    # stderr is kept too, since it has notes like "no recorded inpainted locations"
    if STACK_OUTPUT=$("${PRINT_URL_SCRIPT}" "${STACK}" 2>&1); then

      if [ ! -f "${OUTPUT_FILE}" ]; then
        OUTPUT_FILES+=("${OUTPUT_FILE}")
      fi

      printf "# ============================================================================\n# %s\n\n%s\n\n" \
             "${STACK}" "${STACK_OUTPUT}" >> "${OUTPUT_FILE}"

      printf "  %s\n" "${STACK}"
      WRITTEN_COUNT=$(( WRITTEN_COUNT + 1 ))

    else

      # keep the last non-blank line of the error (e.g. "Exiting, could not read ...")
      REASON=$(printf '%s\n' "${STACK_OUTPUT}" | grep -v '^[[:space:]]*$' | tail -1)
      printf "  %s skipped: %s\n" "${STACK}" "${REASON}"
      SKIPPED+=("${STACK}")

    fi

  done
done

# ----------------------------------------------------------------------------
# Summarize

printf "\nwrote urls for %d stack(s), skipped %d\n" "${WRITTEN_COUNT}" "${#SKIPPED[@]}"

if (( ${#OUTPUT_FILES[@]} > 0 )); then
  printf "\noutput files:\n"
  printf "  %s\n" "${OUTPUT_FILES[@]}"
fi

if (( ${#SKIPPED[@]} > 0 )); then
  printf "\nskipped stacks:\n"
  printf "  %s\n" "${SKIPPED[@]}"
fi

printf "\n"
