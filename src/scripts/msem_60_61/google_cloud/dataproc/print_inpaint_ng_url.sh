#!/bin/bash

# ----------------------------------------------------------------------------
# Prints a neuroglancer url for reviewing the inpainting of one render n5 export.
# The url has two layers:
#   1. the inpainted <pixel group>, and
#   2. the <stack>___mask group (selected), shaded so the pixels that were inpainted
#      (mask != 255) are tinted red over the image.
#
# The view is centered on one of the inpainted locations recorded in the pixel group's
# inpaint attribute. Locations are sorted by changed pixels (largest first), so by default
# the url shows the largest one. If the stack has no recorded locations, the view is
# centered on the s0 volume instead.
#
# Usage: print_inpaint_ng_url.sh <raw stack> [location index]
#
# For example, w61_s077_r00 (or w61-s077-r00) reviews
#   ${RENDER_EXP}/render/w61_serial_070_to_079/w61_s077_r00${STACK_SUFFIX}
#
# After the url, the actual number of inpainted locations is printed along with the centers
# of up to 10 other recorded locations, so their indexes can be passed to get more urls.

RENDER_EXP="gs://janelia-spark-test/hess_wafers_60_61_export"
NG_BASE_URL="https://neuroglancer-demo.appspot.com/#!"

# note that the exported dataset name uses three underscores before pixel
STACK_SUFFIX="_gc_bc_par_cc_aso_3d_s3i___pixel"

# keep these in sync with InpaintParameters (pixel and mask dataset suffixes)
# and Wafer6061Inpainter.INPAINT_ATTRIBUTE
PIXEL_SUFFIX="___pixel"
MASK_SUFFIX="___mask"
INPAINT_ATTRIBUTE="inpaint"

if (( $# < 1 )) || (( $# > 2 )); then
  printf "\nUSAGE: %s <raw stack> [location index]

  raw stack       stack name, e.g. w61_s077_r00 or w61-s077-r00
  location index  index of the inpainted location to center on (default 0 = most changed pixels)

" "$(basename "$0")" >&2
  exit 1
fi

# accept either dashed or underscored stack names
RAW_STACK="${1//-/_}"
LOCATION_INDEX="${2:-0}"

if [[ ! "${RAW_STACK}" =~ ^(w[0-9]+)_s([0-9]+)_r[0-9]+$ ]]; then
  printf "\nExiting, raw stack '%s' is not <wafer>_s<serial>_r<region>\n\n" "$1" >&2
  exit 1
fi

# read the stack match before the next =~ test replaces BASH_REMATCH
WAFER="${BASH_REMATCH[1]}"
# force base 10 so that a zero padded serial (e.g. 077) is not treated as octal
SERIAL_NUMBER=$(( 10#${BASH_REMATCH[2]} ))
FIRST_PROJECT_SERIAL=$(( (SERIAL_NUMBER / 10) * 10 ))

if [[ ! "${LOCATION_INDEX}" =~ ^[0-9]+$ ]]; then
  printf "\nExiting, location index '%s' is not a non-negative integer\n\n" "${LOCATION_INDEX}" >&2
  exit 1
fi

PIXEL_DATASET=$(printf 'render/%s_serial_%03d_to_%03d/%s%s' \
                       "${WAFER}" "${FIRST_PROJECT_SERIAL}" $(( FIRST_PROJECT_SERIAL + 9 )) \
                       "${RAW_STACK}" "${STACK_SUFFIX}")
MASK_DATASET="${PIXEL_DATASET%"${PIXEL_SUFFIX}"}${MASK_SUFFIX}"

PIXEL_URL="${RENDER_EXP}/${PIXEL_DATASET}"

# ----------------------------------------------------------------------------
# Find the position to center on

if ! PIXEL_ATTRIBUTES=$(gcloud storage cat "${PIXEL_URL}/attributes.json" 2>/dev/null); then
  printf "\nExiting, could not read %s/attributes.json\n\n" "${PIXEL_URL}" >&2
  exit 1
fi

# The recorded voxel coordinates are s0 voxels, which is also the neuroglancer coordinate
# space for these exports (the level transforms only add the half voxel offsets of the
# downsampled levels). Positions are whole voxels.
CENTER_FUNCTION='def center: [range(3) as $d | ((.voxelMin[$d] + .voxelMax[$d]) / 2 | floor)];'

POSITION=$(printf '%s' "${PIXEL_ATTRIBUTES}" |
           jq -c --arg a "${INPAINT_ATTRIBUTE}" --argjson i "${LOCATION_INDEX}" "${CENTER_FUNCTION}"'
             .[$a].inpaintedLocations[$i] // empty | center')

if [ -z "${POSITION}" ]; then

  RECORDED_COUNT=$(printf '%s' "${PIXEL_ATTRIBUTES}" |
                   jq --arg a "${INPAINT_ATTRIBUTE}" '.[$a].inpaintedLocations // [] | length')

  if (( RECORDED_COUNT > 0 )); then
    printf "\nExiting, location index %d is out of range (%d locations are recorded)\n\n" \
           "${LOCATION_INDEX}" "${RECORDED_COUNT}" >&2
    exit 1
  fi

  printf "\n%s has no recorded inpainted locations, centering on the s0 volume\n\n" "${PIXEL_URL}" >&2

  if ! S0_ATTRIBUTES=$(gcloud storage cat "${PIXEL_URL}/s0/attributes.json" 2>/dev/null); then
    printf "\nExiting, could not read %s/s0/attributes.json\n\n" "${PIXEL_URL}" >&2
    exit 1
  fi

  POSITION=$(printf '%s' "${S0_ATTRIBUTES}" | jq -c '[.dimensions[] | . / 2 | floor]')

fi

# ----------------------------------------------------------------------------
# Build and print the url

PIXEL_LAYER="${PIXEL_DATASET##*/}"
MASK_LAYER="${MASK_DATASET##*/}"

# The inpainter fills every pixel where the mask is not 255, so the mask layer tints exactly
# those pixels and leaves the rest transparent. Missing mask chunks read as 0, so areas with
# no image data at all (e.g. outside the tissue) are tinted too. The color and opacity can
# be changed with the layer's shader controls, and the layer can be hidden to see the
# image underneath.
MASK_SHADER='#uicontrol vec3 color color(default="red")
#uicontrol float opacity slider(min=0, max=1, default=0.4)
void main() {
  if (toRaw(getDataValue()) < 255u) {
    emitRGBA(vec4(color, opacity));
  } else {
    emitTransparent();
  }
}
'

NG_STATE=$(jq -c -n \
              --arg exp "${RENDER_EXP}" \
              --arg pixelDataset "${PIXEL_DATASET}" \
              --arg maskDataset "${MASK_DATASET}" \
              --arg pixelLayer "${PIXEL_LAYER}" \
              --arg maskLayer "${MASK_LAYER}" \
              --arg maskShader "${MASK_SHADER}" \
              --argjson position "${POSITION}" '
  {
    "dimensions": { "x": [8e-9, "m"], "y": [8e-9, "m"], "z": [8e-9, "m"] },
    "position": $position,
    "crossSectionScale": 1,
    "projectionScale": 262144,
    "layers": [
      { "type": "image", "source": "\($exp)/|n5:\($pixelDataset)/", "tab": "source", "name": $pixelLayer },
      { "type": "image", "source": "\($exp)/|n5:\($maskDataset)/",  "tab": "rendering", "name": $maskLayer,
        "shader": $maskShader }
    ],
    "selectedLayer": { "size": 322, "visible": true, "layer": $maskLayer },
    "layout": "xy",
    "uiControlVisibility": {}
  }')

# jq writes 8e-9 as 8E-9, so restore the lower case exponent that neuroglancer uses,
# then encode the same characters that neuroglancer encodes in its own urls (% first),
# plus the shader characters that can't appear unencoded in a url fragment
ENCODED_STATE=$(printf '%s' "${NG_STATE}" |
                sed -e 's/\([0-9]\)E\([-+]\)/\1e\2/g' \
                    -e 's/%/%25/g' -e 's/ /%20/g' -e 's/"/%22/g' -e 's/,/%2C/g' -e 's/|/%7C/g' \
                    -e 's/{/%7B/g' -e 's/}/%7D/g' -e 's/\[/%5B/g' -e 's/\]/%5D/g' \
                    -e 's/#/%23/g' -e 's/</%3C/g' -e 's/>/%3E/g' -e 's/\\/%5C/g')

printf '%s%s\n' "${NG_BASE_URL}" "${ENCODED_STATE}"

# ----------------------------------------------------------------------------
# Print the location count and the centers of up to 10 other locations
# (the list is cut short when the inpaint attribute only recorded some of the locations)

printf '%s' "${PIXEL_ATTRIBUTES}" |
  jq -r --arg a "${INPAINT_ATTRIBUTE}" --argjson i "${LOCATION_INDEX}" "${CENTER_FUNCTION}"'
    if has($a) | not then
      "\nno \($a) attribute (the stack has not been inpainted)\n"
    else
      .[$a] as $p |
      ($p.inpaintedLocations // []) as $locations |
      ([range($locations | length)] | map(select(. != $i))) as $others |
      "\ninpaintedLocationCount: \($p.inpaintedLocationCount // ($locations | length))",
      if ($locations | length) == 0 then
        empty
      else
        "\ncentered on location \($i): \($locations[$i] | center | tojson) " +
        "changedPixels=\($locations[$i].changedPixels)",
        if ($others | length) == 0 then
          empty
        else
          "\nadditional locations (index: center changedPixels):",
          ($others[0:10][] as $j |
           "  \($j): \($locations[$j] | center | tojson) changedPixels=\($locations[$j].changedPixels)")
        end
      end,
      ""
    end'
