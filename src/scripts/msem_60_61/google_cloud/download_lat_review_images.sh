#!/bin/bash

MIN_Z=1
MAX_Z=96

# ----------------------------------------------------------------------------
# Parse named parameters

ARG_REGIONS=()
ARG_STACK_PREFIXES=()
ARG_REVIEW_DIR=""

# should match renderedLayerRunTimestamp in ../pipeline_json/04_3d_align/pipe.04.w6n.layer-as-tile.json
ARG_LAT_TIMESTAMP="20260924_100500"      # previous value: 20260905_180000

# the aligned and intensity corrected stack suffix that the layer-as-tile run was derived from
ARG_STACK_SUFFIX="gc_bc_par_cc_asoi"     # previous value: gc_icc_par_asoi

usage() {
  echo "
USAGE $0 --review-dir <dir> --region <region> [...] --stack-prefix <prefix> [...]

  --review-dir    directory to download into (required), with one
                  <stack-prefix>_<region> subdirectory created per combination
  --region        one or more slab regions to review (required, e.g. r00 r01)
  --stack-prefix  one or more two digit serial slab prefixes (required, e.g. 07 08),
                  each of which covers the ten slabs ending in 0 through 9
  --lat-timestamp layer-as-tile run timestamp, which must match renderedLayerRunTimestamp
                  in the pipeline json (default: ${ARG_LAT_TIMESTAMP})
  --stack-suffix  suffix of the stacks the layer-as-tile run was derived from
                  (default: ${ARG_STACK_SUFFIX})

Examples:
  $0 --review-dir ~/Desktop/msem-2026-09/lat-review \
     --region r00 r01 --stack-prefix 07 08 09 10 11 12 13 14 15 16 17 18 19
  $0 --review-dir /tmp/lat-review --region r00 --stack-prefix 19
  $0 --review-dir /tmp/lat-review --region r00 --stack-prefix 19 \
     --lat-timestamp 20260905_180000 --stack-suffix gc_icc_par_asoi
"
  exit 1
}

if (( $# < 1 )); then
  usage
fi

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --review-dir)
      ARG_REVIEW_DIR="${2:?'--review-dir requires a value'}"
      shift 2
      ;;
    --lat-timestamp)
      ARG_LAT_TIMESTAMP="${2:?'--lat-timestamp requires a value'}"
      shift 2
      ;;
    --stack-suffix)
      ARG_STACK_SUFFIX="${2:?'--stack-suffix requires a value'}"
      shift 2
      ;;
    --region)
      shift
      while [[ $# -gt 0 && "${1}" != --* ]]; do
        ARG_REGIONS+=("${1}")
        shift
      done
      ;;
    --stack-prefix)
      shift
      while [[ $# -gt 0 && "${1}" != --* ]]; do
        ARG_STACK_PREFIXES+=("${1}")
        shift
      done
      ;;
    *)
      echo "ERROR: unrecognized parameter '${1}'"
      usage
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Validate parameters

if [ -z "${ARG_REVIEW_DIR}" ]; then
  echo "ERROR: --review-dir is required"
  usage
fi

# drop any trailing slash so that the paths built below have just one separator
ARG_REVIEW_DIR="${ARG_REVIEW_DIR%/}"

if (( ${#ARG_REGIONS[@]} == 0 )); then
  echo "ERROR: --region requires at least one value"
  usage
fi

if (( ${#ARG_STACK_PREFIXES[@]} == 0 )); then
  echo "ERROR: --stack-prefix requires at least one value"
  usage
fi

for REGION in "${ARG_REGIONS[@]}"; do
  if [[ ! "${REGION}" =~ ^r[0-9][0-9]$ ]]; then
    echo "ERROR: --region values must look like r00 (not '${REGION}')"
    exit 1
  fi
done

for SA in "${ARG_STACK_PREFIXES[@]}"; do
  if [[ ! "${SA}" =~ ^[0-9][0-9]$ ]]; then
    echo "ERROR: --stack-prefix values must be two digits (not '${SA}')"
    exit 1
  fi
done

# the timestamp is a path element, so a typo would simply match no objects
if [[ ! "${ARG_LAT_TIMESTAMP}" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
  echo "ERROR: --lat-timestamp must look like 20260924_100500 (not '${ARG_LAT_TIMESTAMP}')"
  exit 1
fi

# ----------------------------------------------------------------------------
# Download

for REGION in "${ARG_REGIONS[@]}"; do

  for SA in "${ARG_STACK_PREFIXES[@]}"; do

    REVIEW_DIR="${ARG_REVIEW_DIR}/${SA}_${REGION}"
    mkdir -p "${REVIEW_DIR}"

    for SB in $(seq 0 9); do

      PADDED_STACK_NUMBER="${SA}${SB}"
      RAW_STACK_PREFIX="w61_s${PADDED_STACK_NUMBER}"

      # w61_s079 -> w61_serial_070_to_079
      PROJECT=$(awk -F'[_s]' '{w=$1; s=$3+0; lo=int(s/10)*10; hi=lo+9; printf "%s_serial_%03d_to_%03d", w, lo, hi}' <<<"${RAW_STACK_PREFIX}")
      STACK="${RAW_STACK_PREFIX}_${REGION}_${ARG_STACK_SUFFIX}"
      LAT_STACK="${STACK}_lat"

      PREFIX="tiles_layer/${PROJECT}/${LAT_STACK}/${ARG_LAT_TIMESTAMP}/000/0/"

      echo "https://storage.googleapis.com/janelia-spark-test/${PREFIX}"

      # scan numbers are not derivable from z, so ask GCS for the actual object names
      # (object names look like <PREFIX><z>/<stack>_scan<n>_z<paddedZ>.png)
      DOWNLOAD_COUNT=0
      while read -r OBJECT_NAME; do

        # force base 10 so that any zero padded z is not treated as octal
        Z=$(( 10#$(basename "$(dirname "${OBJECT_NAME}")") ))
        if (( Z < MIN_Z || Z > MAX_Z )); then
          continue
        fi

        printf "."
        if curl -sf -o "${REVIEW_DIR}/$(basename "${OBJECT_NAME}")" \
                "https://storage.googleapis.com/janelia-spark-test/${OBJECT_NAME}"; then
          DOWNLOAD_COUNT=$(( DOWNLOAD_COUNT + 1 ))
        else
          printf "\n  FAILED to download %s\n" "${OBJECT_NAME}"
        fi

      done < <(curl -s --get "https://storage.googleapis.com/storage/v1/b/janelia-spark-test/o" \
                    --data-urlencode "prefix=${PREFIX}" \
                    --data-urlencode "maxResults=1000" \
                 | jq -r '.items[]?.name | select(endswith(".png"))')

      echo " ${DOWNLOAD_COUNT} file(s)"

    done

  done

done
