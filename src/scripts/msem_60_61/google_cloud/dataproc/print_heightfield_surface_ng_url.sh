#!/bin/bash

# ----------------------------------------------------------------------------
# Prints a neuroglancer url for reviewing the max heightfield (bottom surface) of one stack.
# The url has two layers:
#   1. the ic3d <stack>___pixel export, and
#   2. the heightfield surface volume written by hot-knife
#      52_export_heightfield_surface_batch.sh (SparkExportHeightFieldSurfaceMultiSemBatch),
#      shaded green where the surface is and transparent everywhere else.
#
# The surface volume is a normal multi-scale n5 group with neuroglancer attributes, so
# neuroglancer loads it as needed and the surface shows up in any XZ or YZ view (no points
# are encoded in the url).  The view is centered on an s0 x, y, z location, the center of the
# stack by default.
#
# Usage: print_heightfield_surface_ng_url.sh <raw stack> [--x <s0 x>] [--y <s0 y>] [--z <s0 z>]
#
# The min heightfield (top surface) is not shown because it is always 0: SparkComputeCostMultiSem
# gives the first z layer a fixed cost (--topLayerCost 105), so the top surface stays on that layer.

N5_PATH="gs://janelia-spark-test/hess_wafers_60_61_export"
NG_BASE_URL="https://neuroglancer-demo.appspot.com/#!"

# keep these in sync with hot-knife RawStack (DEFAULT_IC3D_SUFFIX and getHeightfieldsSurfaceDataset)
IC3D_SUFFIX="_gc_bc_par_cc_aso_3d_s3i"
SURFACE_GROUP="heightfields_v4_surface"
FIELD_NAME="max"

usage() {
  printf "\nUSAGE: %s <raw stack> [--x <s0 x>] [--y <s0 y>] [--z <s0 z>]

  raw stack  stack name, e.g. w61_s070_r00 or w61-s070-r00
  --x        s0 x to center on (default: center of the stack)
  --y        s0 y to center on (default: center of the stack)
  --z        s0 z to center on (default: center of the stack)

Example:
  %s w61_s070_r00 --x 60000 --y 20000

" "$(basename "$0")" "$(basename "$0")" >&2
  exit 1
}

if (( $# < 1 )); then
  usage
fi

# accept either dashed or underscored stack names
RAW_STACK="${1//-/_}"
shift

ARG_X=""
ARG_Y=""
ARG_Z=""

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --x) ARG_X="${2:?'--x requires a value'}"; shift 2 ;;
    --y) ARG_Y="${2:?'--y requires a value'}"; shift 2 ;;
    --z) ARG_Z="${2:?'--z requires a value'}"; shift 2 ;;
    *)
      printf "\nERROR: unrecognized parameter '%s'\n" "${1}" >&2
      usage
      ;;
  esac
done

if [[ ! "${RAW_STACK}" =~ ^(w[0-9]+)_s([0-9]+)_r[0-9]+$ ]]; then
  printf "\nExiting, raw stack '%s' is not <wafer>_s<serial>_r<region>\n\n" "${RAW_STACK}" >&2
  exit 1
fi

WAFER="${BASH_REMATCH[1]}"
# force base 10 so that a zero padded serial (e.g. 070) is not treated as octal
SERIAL_NUMBER=$(( 10#${BASH_REMATCH[2]} ))
FIRST_PROJECT_SERIAL=$(( (SERIAL_NUMBER / 10) * 10 ))

for VALUE in "${ARG_X}" "${ARG_Y}" "${ARG_Z}"; do
  if [ -n "${VALUE}" ] && [[ ! "${VALUE}" =~ ^[0-9]+$ ]]; then
    printf "\nExiting, --x, --y, and --z must be whole numbers (not '%s')\n\n" "${VALUE}" >&2
    exit 1
  fi
done

PROJECT=$(printf '%s_serial_%03d_to_%03d' "${WAFER}" "${FIRST_PROJECT_SERIAL}" $(( FIRST_PROJECT_SERIAL + 9 )))
IC3D_STACK="${RAW_STACK}${IC3D_SUFFIX}"

PIXEL_DATASET="render/${PROJECT}/${IC3D_STACK}___pixel"
SURFACE_DATASET="${SURFACE_GROUP}/${PROJECT}/${IC3D_STACK}/${FIELD_NAME}"

# ----------------------------------------------------------------------------
# Check that both exist and find the position to center on

if ! PIXEL_S0_ATTRIBUTES=$(gcloud storage cat "${N5_PATH}/${PIXEL_DATASET}/s0/attributes.json" 2>/dev/null); then
  printf "\nExiting, could not read %s/%s/s0/attributes.json\n\n" "${N5_PATH}" "${PIXEL_DATASET}" >&2
  exit 1
fi

# the neuroglancer scales are written last, so this also catches an export that has not finished
if ! gcloud storage cat "${N5_PATH}/${SURFACE_DATASET}/attributes.json" 2>/dev/null | jq -e '.scales' > /dev/null; then
  printf "\nExiting, %s/%s has no neuroglancer scales attribute
         (run hot-knife 52_export_heightfield_surface_batch.sh for %s first, or wait for it to finish)\n\n" \
         "${N5_PATH}" "${SURFACE_DATASET}" "${RAW_STACK}" >&2
  exit 1
fi

read -r S0_WIDTH S0_HEIGHT S0_DEPTH < <(printf '%s' "${PIXEL_S0_ATTRIBUTES}" | jq -r '.dimensions | map(tostring) | join(" ")')

S0_X=$(( 10#${ARG_X:-$(( S0_WIDTH / 2 ))} ))
S0_Y=$(( 10#${ARG_Y:-$(( S0_HEIGHT / 2 ))} ))
S0_Z=$(( 10#${ARG_Z:-$(( S0_DEPTH / 2 ))} ))

if (( S0_X >= S0_WIDTH )) || (( S0_Y >= S0_HEIGHT )) || (( S0_Z >= S0_DEPTH )); then
  printf "\nExiting, --x %d, --y %d, and --z %d must be less than the s0 dimensions %d, %d, and %d\n\n" \
         "${S0_X}" "${S0_Y}" "${S0_Z}" "${S0_WIDTH}" "${S0_HEIGHT}" "${S0_DEPTH}" >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# Build and print the url

# the surface voxels are 255 and everything else is 0 (or missing)
SURFACE_SHADER='#uicontrol vec3 color color(default="#00ff00")
#uicontrol float opacity slider(min=0, max=1, default=1)
void main() {
  if (toRaw(getDataValue()) > 0u) {
    emitRGBA(vec4(color, opacity));
  } else {
    emitTransparent();
  }
}
'

NG_STATE=$(jq -c -n \
              --arg exp "${N5_PATH}" \
              --arg pixelDataset "${PIXEL_DATASET}" \
              --arg surfaceDataset "${SURFACE_DATASET}" \
              --arg surfaceShader "${SURFACE_SHADER}" \
              --argjson position "[${S0_X}, ${S0_Y}, ${S0_Z}]" '
  {
    "dimensions": { "x": [8e-9, "m"], "y": [8e-9, "m"], "z": [8e-9, "m"] },
    "position": $position,
    "crossSectionScale": 1,
    "projectionScale": 4096,
    "layers": [
      { "type": "image", "source": "\($exp)/|n5:\($pixelDataset)/", "tab": "source", "name": "pixel" },
      { "type": "image", "source": "\($exp)/|n5:\($surfaceDataset)/", "tab": "rendering", "name": "hf max",
        "shader": $surfaceShader }
    ],
    "selectedLayer": { "size": 322, "visible": true, "layer": "hf max" },
    "layout": "4panel",
    "uiControlVisibility": {}
  }')

# jq writes 8e-9 as 8E-9, so restore the lower case exponent that neuroglancer uses,
# then encode the same characters as print_inpaint_ng_url.sh (% first)
ENCODED_STATE=$(printf '%s' "${NG_STATE}" |
                sed -e 's/\([0-9]\)E\([-+]\)/\1e\2/g' \
                    -e 's/%/%25/g' -e 's/ /%20/g' -e 's/"/%22/g' -e 's/,/%2C/g' -e 's/|/%7C/g' \
                    -e 's/{/%7B/g' -e 's/}/%7D/g' -e 's/\[/%5B/g' -e 's/\]/%5D/g' \
                    -e 's/#/%23/g' -e 's/</%3C/g' -e 's/>/%3E/g' -e 's/\\/%5C/g')

printf '%s%s\n' "${NG_BASE_URL}" "${ENCODED_STATE}"
