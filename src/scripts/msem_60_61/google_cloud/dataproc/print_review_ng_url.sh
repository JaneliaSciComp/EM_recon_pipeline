#!/bin/bash

# ----------------------------------------------------------------------------
# Prints a neuroglancer url for reviewing 10 consecutive serial slab exports of one region
# appended one after another in z.
#
# Starting with the --raw stack, each following serial slab's export is translated in z
# so that it starts right after the previous one ends (based on the s0 z dimension).
# For example, --raw w61_s030_r00 appends the exports for w61_s030_r00 through w61_s039_r00:
#   ${RENDER_EXP}/render/w61_serial_030_to_039/w61_s030_r00_gc_bc_par_cc_asoi_3d___pixel
#   ...
#   ${RENDER_EXP}/render/w61_serial_030_to_039/w61_s039_r00_gc_bc_par_cc_asoi_3d___pixel
#
# Slabs whose export can't be read (e.g. not exported yet) are skipped with a warning
# and don't take up any z space. The z range of each layer is printed after the url.

RENDER_EXP="gs://janelia-spark-test/hess_wafers_60_61_export"
NG_BASE_URL="https://neuroglancer-demo.appspot.com/#!"

SLAB_COUNT=10

USAGE="
USAGE: $(basename "$0") --raw <raw stack> [--stack-suffix <suffix>] [--type pixel | mask]

  --raw           first stack to review, e.g. w61_s030_r00 or w61-s030-r00 (required)
  --stack-suffix  stack suffix (default: gc_bc_par_cc_asoi_3d)
  --type          exported dataset type, pixel or mask (default: pixel)
"

RAW_STACK=""
STACK_SUFFIX="gc_bc_par_cc_asoi_3d"
EXPORT_TYPE="pixel"

while (( $# > 0 )); do
  case "$1" in
    --raw|--stack-suffix|--type)
      if (( $# < 2 )); then
        printf "\nExiting, %s requires a value\n%s\n" "$1" "${USAGE}" >&2
        exit 1
      fi
      case "$1" in
        --raw)          RAW_STACK="$2" ;;
        --stack-suffix) STACK_SUFFIX="$2" ;;
        --type)         EXPORT_TYPE="$2" ;;
      esac
      shift 2
      ;;
    -h|--help)
      printf "%s\n" "${USAGE}"
      exit 0
      ;;
    *)
      printf "\nExiting, unknown argument '%s'\n%s\n" "$1" "${USAGE}" >&2
      exit 1
      ;;
  esac
done

if [ -z "${RAW_STACK}" ]; then
  printf "\nExiting, --raw must be specified\n%s\n" "${USAGE}" >&2
  exit 1
fi

# accept either dashed or underscored stack names
RAW_STACK="${RAW_STACK//-/_}"

if [[ ! "${RAW_STACK}" =~ ^(w[0-9]+)_s([0-9]+)_(r[0-9]+)$ ]]; then
  printf "\nExiting, raw stack '%s' is not <wafer>_s<serial>_r<region>\n\n" "${RAW_STACK}" >&2
  exit 1
fi

WAFER="${BASH_REMATCH[1]}"
# force base 10 so that a zero padded serial (e.g. 030) is not treated as octal
FIRST_SERIAL=$(( 10#${BASH_REMATCH[2]} ))
REGION="${BASH_REMATCH[3]}"

if [[ "${EXPORT_TYPE}" != "pixel" ]] && [[ "${EXPORT_TYPE}" != "mask" ]]; then
  printf "\nExiting, --type must be pixel or mask (not '%s')\n%s\n" "${EXPORT_TYPE}" "${USAGE}" >&2
  exit 1
fi

# allow the suffix to be given with or without its leading underscore
STACK_SUFFIX="${STACK_SUFFIX#_}"

# ----------------------------------------------------------------------------
# Read each slab's s0 dimensions and build its layer
# (layers are named by raw stack and first z, e.g. "w61_s031_r00 z82", to keep the tabs short)

LAYERS="[]"
POSITION=""
Z_OFFSET=0
SUMMARY=""

for (( SERIAL = FIRST_SERIAL; SERIAL < FIRST_SERIAL + SLAB_COUNT; SERIAL++ )); do

  FIRST_PROJECT_SERIAL=$(( (SERIAL / 10) * 10 ))

  RAW_NAME=$(printf "%s_s%03d_%s" "${WAFER}" "${SERIAL}" "${REGION}")

  # note that the exported dataset name uses three underscores before pixel or mask
  EXPORT_NAME="${RAW_NAME}_${STACK_SUFFIX}___${EXPORT_TYPE}"
  DATASET=$(printf 'render/%s_serial_%03d_to_%03d/%s' \
                   "${WAFER}" "${FIRST_PROJECT_SERIAL}" $(( FIRST_PROJECT_SERIAL + 9 )) "${EXPORT_NAME}")

  if ! S0_ATTRIBUTES=$(gcloud storage cat "${RENDER_EXP}/${DATASET}/s0/attributes.json" 2>/dev/null); then
    printf "WARNING: skipping %s because %s/%s/s0/attributes.json could not be read\n" \
           "${EXPORT_NAME}" "${RENDER_EXP}" "${DATASET}" >&2
    continue
  fi

  DIMENSIONS=$(printf '%s' "${S0_ATTRIBUTES}" | jq -c '.dimensions')
  Z_SIZE=$(printf '%s' "${DIMENSIONS}" | jq '.[2]')

  # open the view on z 0 (the first slab that exists), centered in x and y on that slab
  # (0.5 is the center of z 0, which neuroglancer shows as z 0)
  if [ -z "${POSITION}" ]; then
    POSITION=$(printf '%s' "${DIMENSIONS}" | jq -c '[.[0] / 2, .[1] / 2, 0.5]')
  fi

  LAYERS=$(printf '%s' "${LAYERS}" |
           jq -c --arg exp "${RENDER_EXP}" --arg dataset "${DATASET}" --arg name "${RAW_NAME} z${Z_OFFSET}" \
                 --argjson zOffset "${Z_OFFSET}" '
    . + [{
      "type": "image",
      "source": {
        "url": "\($exp)/|n5:\($dataset)/",
        "transform": {
          "outputDimensions": { "x": [8e-9, "m"], "y": [8e-9, "m"], "z": [8e-9, "m"] },
          "matrix": [ [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, $zOffset] ]
        }
      },
      "tab": "source",
      "name": $name
    }]')

  SUMMARY="${SUMMARY}$(printf '  %s: z %d to %d' "${EXPORT_NAME}" "${Z_OFFSET}" $(( Z_OFFSET + Z_SIZE - 1 )))"$'\n'
  Z_OFFSET=$(( Z_OFFSET + Z_SIZE ))

done

if [ -z "${POSITION}" ]; then
  printf "\nExiting, none of the %d exports starting with %s could be read\n\n" "${SLAB_COUNT}" "${RAW_STACK}" >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# Build and print the url

NG_STATE=$(jq -c -n --argjson layers "${LAYERS}" --argjson position "${POSITION}" '
  {
    "dimensions": { "x": [8e-9, "m"], "y": [8e-9, "m"], "z": [8e-9, "m"] },
    "position": $position,
    "crossSectionScale": 128,
    "projectionScale": 262144,
    "layers": $layers,
    "selectedLayer": { "size": 290, "visible": true, "layer": $layers[0].name },
    "layout": "xy",
    "uiControlVisibility": {}
  }')

# jq writes 8e-9 as 8E-9, so restore the lower case exponent that neuroglancer uses,
# then encode the same characters that neuroglancer encodes in its own urls (% first)
ENCODED_STATE=$(printf '%s' "${NG_STATE}" |
                sed -e 's/\([0-9]\)E\([-+]\)/\1e\2/g' \
                    -e 's/%/%25/g' -e 's/ /%20/g' -e 's/"/%22/g' -e 's/,/%2C/g' -e 's/|/%7C/g' \
                    -e 's/{/%7B/g' -e 's/}/%7D/g' -e 's/\[/%5B/g' -e 's/\]/%5D/g')

printf '\n%s%s\n\nlayer z ranges:\n%s\n' "${NG_BASE_URL}" "${ENCODED_STATE}" "${SUMMARY}"
