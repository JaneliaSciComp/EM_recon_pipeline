#!/bin/bash

set -e

if (( $# < 3 )); then
  echo "
Usage:    $0  <export-x>  <export-y>  <export-z>  [box-width]  [box-height]  [render-scale]

Examples:
  $0  97105 25483 18
  $0  82218 47280 28
  $0  53464 58922 11
  $0  97105 25483 18 5000 5000 0.1
  "
  exit 1
fi

EXPORT_X="$1"
EXPORT_Y="$2"
EXPORT_Z="$3"
WIDTH="${4:-8000}"
HEIGHT="${5:-8000}"
SCALE="${6:-0.15}"

BASE_URL="http://renderer.int.janelia.org:8080/render-ws/v1"
RAW_STACK="w61_s109_r00"
STACK="${RAW_STACK}_gc_par_crc_align_ic2d"
STACK_URL="${BASE_URL}/owner/hess_wafers_60_61/project/w61_serial_100_to_109/stack/${STACK}"

MIN_BOUNDS=$(curl -X GET --silent --header 'Accept: application/json' "${STACK_URL}" | jq -r '. | "\(.stats.stackBounds.minX) \(.stats.stackBounds.minY) \(.stats.stackBounds.minZ)"')
STACK_MIN_X=$(echo "${MIN_BOUNDS}" | cut -d' ' -f1 | cut -f1 -d'.')
STACK_MIN_Y=$(echo "${MIN_BOUNDS}" | cut -d' ' -f2 | cut -f1 -d'.')
STACK_MIN_Z=$(echo "${MIN_BOUNDS}" | cut -d' ' -f3 | cut -f1 -d'.')

X=$(( EXPORT_X - (WIDTH / 2) + STACK_MIN_X ))
Y=$(( EXPORT_Y - (HEIGHT / 2) + STACK_MIN_Y ))
Z=$(( EXPORT_Z + STACK_MIN_Z ))

BOX_URL="${STACK_URL}/z/${Z}/box/${X},${Y},${WIDTH},${HEIGHT},${SCALE}"
BOX_JPEG_URL="${BOX_URL}/jpeg-image"
BOX_RP_URL="${BOX_URL}/render-parameters"

NAME="${STACK}.exc_${EXPORT_X}_${EXPORT_Y}_${EXPORT_Z}.${WIDTH}x${HEIGHT}_at_${SCALE}"

echo "
translated export center location ${EXPORT_X}, ${EXPORT_Y}, ${EXPORT_Z} to stack box min location ${X}, ${Y}, ${Z}

box URL is:
  ${BOX_URL}

downloading border image ..."

curl --silent -o "${NAME}.border.jpg" "${BOX_JPEG_URL}?maxTileSpecsToRender=0"

echo "downloading pixel image ..."

curl --silent -o "${NAME}.pixel.jpg" "${BOX_JPEG_URL}?maxTileSpecsToRender=100&convertToGray=true"

echo "
combining pixel and border images into:
  ${NAME}.pwb.jpg
"

magick \
  \( ${NAME}.pixel.jpg -colorspace sRGB \) \
  \( ${NAME}.border.jpg -colorspace sRGB \) \
  \( ${NAME}.border.jpg -colorspace sRGB \
     -channel green -separate -threshold 20% \
     \( ${NAME}.border.jpg \
        -colorspace gray -black-threshold 10% -white-threshold 15% -threshold 8% \) \
     -compose Plus -composite \) \
  -composite ${NAME}.pwb.jpg

rm "${NAME}.border.jpg" "${NAME}.pixel.jpg"
