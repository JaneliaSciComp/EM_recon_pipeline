#!/bin/bash

# ----------------------------------------------------------------------------
# Prints a neuroglancer url for reviewing the heightfields that hot-knife
# 51_gen_cost_and_heightfields_n5_batch.sh (SparkComputeCostMultiSemBatch) wrote for one stack.
#
# The view is centered on an s0 x, y, z location (the center of the stack by default) of the
# ic3d <stack>___pixel export, and the max heightfield (the bottom surface) is drawn as a
# green line within RADIUS s0 voxels of it:
#   - in the XZ view, along the heightfield row at y, and
#   - in the YZ view, along the heightfield column at x.
# The url opens in the single XZ view (switch the layout to yz or 4panel in neuroglancer to see the
# YZ line).  It is also the cheapest view to load with --cost, whose blocks are large.
# The lines are only in those two planes, so stepping the XZ or YZ slice moves off them
# (run this again with another --x or --y to look somewhere else).
#
# Why lines instead of the heightfield datasets: neuroglancer merges the attributes.json of
# every parent directory into a dataset's attributes, so the 2D min and max datasets inherit
# the 3D downsamplingFactors of their s1 group and fail with "Rank mismatch, received 2 but
# expected 3".  A url can not override that, so this script reads the heightfield blocks
# around the location (gcloud storage cat) and decodes them with perl instead.
#
# The heightfield values are z in s0 voxels (the cost steps never downsample z), and hot-knife
# converts them the same way (FlatteningInfo: s0 z = (value + 0.5) * z factor - 0.5).
# Samples that are not finite are skipped, which leaves a gap in the line.
#
# Usage: print_heightfield_ng_url.sh <raw stack> [--x <s0 x>] [--y <s0 y>] [--z <s0 z>] [--cost]
#
# With --cost, the cost volume the heightfields were fit to (cost_v4 <stack> s1) is added as a
# colormapped layer under the line.  Its s1 dataset has its own downsamplingFactors (2, 2, 1),
# which neuroglancer applies, but no resolution, so neuroglancer would make its voxels 1 nm and
# shrink the layer 8 times.  The layer transform sets both the input and output dimensions to 8 nm
# (and has no matrix, which would apply the factors a second time).
#
# NOTE: the min heightfield (the top surface) is not drawn because it is always 0:
#       SparkComputeCostMultiSem gives the first z layer a fixed cost (--topLayerCost 105),
#       so the top surface stays on that layer.

N5_PATH="gs://janelia-spark-test/hess_wafers_60_61_export"
NG_BASE_URL="https://neuroglancer-demo.appspot.com/#!"

# keep these in sync with hot-knife RawStack (DEFAULT_IC3D_SUFFIX and the heightfields version)
IC3D_SUFFIX="_gc_bc_par_cc_aso_3d_s3i"
HEIGHTFIELDS_GROUP="heightfields_v4"
COST_GROUP="cost_v4"

# s1 is the heightfield level used for flattening
S_LEVEL="s1"

# the lines cover RADIUS s0 voxels on each side of the location with a point every STEP s0 voxels
# (about 4 * RADIUS / STEP lines in all, which is what makes the url long)
RADIUS=512
STEP=16

HF_COLOR="#00ff00"

usage() {
  printf "\nUSAGE: %s <raw stack> [--x <s0 x>] [--y <s0 y>] [--z <s0 z>] [--cost]

  raw stack  stack name, e.g. w61_s070_r00 or w61-s070-r00
  --x        s0 x to center on (default: center of the stack)
  --y        s0 y to center on (default: center of the stack)
  --z        s0 z to center on (default: center of the stack)
  --cost     also show the cost volume (low cost is where the surface fit wants to go)

The max heightfield (bottom surface) is drawn in green within %d s0 voxels of the location
in the XZ and YZ views.

Example:
  %s w61_s070_r00 --x 60000 --y 20000 --cost

" "$(basename "$0")" "${RADIUS}" "$(basename "$0")" >&2
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
SHOW_COST="false"

while [[ $# -gt 0 ]]; do
  case "${1}" in
    --x) ARG_X="${2:?'--x requires a value'}"; shift 2 ;;
    --y) ARG_Y="${2:?'--y requires a value'}"; shift 2 ;;
    --z) ARG_Z="${2:?'--z requires a value'}"; shift 2 ;;
    --cost) SHOW_COST="true"; shift ;;
    *)
      printf "\nERROR: unrecognized parameter '%s'\n" "${1}" >&2
      usage
      ;;
  esac
done

# ----------------------------------------------------------------------------
# Validate parameters

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

for TOOL in gcloud jq perl; do
  if ! command -v "${TOOL}" > /dev/null; then
    printf "\nExiting, %s is required but was not found\n\n" "${TOOL}" >&2
    exit 1
  fi
done

PROJECT=$(printf '%s_serial_%03d_to_%03d' "${WAFER}" "${FIRST_PROJECT_SERIAL}" $(( FIRST_PROJECT_SERIAL + 9 )))
IC3D_STACK="${RAW_STACK}${IC3D_SUFFIX}"

PIXEL_DATASET="render/${PROJECT}/${IC3D_STACK}___pixel"
HF_GROUP="${HEIGHTFIELDS_GROUP}/${PROJECT}/${IC3D_STACK}/${S_LEVEL}"
HF_URL="${N5_PATH}/${HF_GROUP}"
COST_DATASET="${COST_GROUP}/${PROJECT}/${IC3D_STACK}/${S_LEVEL}"

readAttributes() {
  local DATASET="$1"
  if ! gcloud storage cat "${N5_PATH}/${DATASET}/attributes.json" 2>/dev/null; then
    printf "\nExiting, could not read %s/%s/attributes.json\n\n" "${N5_PATH}" "${DATASET}" >&2
    exit 1
  fi
}

# ----------------------------------------------------------------------------
# Read the dimensions and scale factors

PIXEL_S0_ATTRIBUTES=$(readAttributes "${PIXEL_DATASET}/s0") || exit 1
HF_ATTRIBUTES=$(readAttributes "${HF_GROUP}") || exit 1
HF_MAX_ATTRIBUTES=$(readAttributes "${HF_GROUP}/max") || exit 1

read -r S0_WIDTH S0_HEIGHT S0_DEPTH < <(printf '%s' "${PIXEL_S0_ATTRIBUTES}" | jq -r '.dimensions | map(tostring) | join(" ")')

# heightfield level factors are x, y, z (z is always 1 for multi-SEM)
read -r FACTOR_X FACTOR_Y FACTOR_Z < <(printf '%s' "${HF_ATTRIBUTES}" | jq -r '.downsamplingFactors // [] | map(tostring) | join(" ")')

if [ -z "${FACTOR_Z}" ]; then
  printf "\nExiting, %s has no x, y, z downsamplingFactors attribute\n\n" "${HF_URL}" >&2
  exit 1
fi

# the x and y factors are used for whole voxel arithmetic, so they must be integers (e.g. 2.0)
read -r INT_FACTOR_X INT_FACTOR_Y < <(printf '%s' "${HF_ATTRIBUTES}" |
                                      jq -r '.downsamplingFactors[0:2] | map(select(. == floor) | floor | tostring) | join(" ")')
if [ -z "${INT_FACTOR_Y}" ]; then
  printf "\nExiting, %s downsamplingFactors x and y must be whole numbers (not %s and %s)\n\n" \
         "${HF_URL}" "${FACTOR_X}" "${FACTOR_Y}" >&2
  exit 1
fi

HF_LAYOUT=$(printf '%s' "${HF_MAX_ATTRIBUTES}" |
            jq -r '[.dataType, .compression.type, (.dimensions | map(tostring) | join(" ")), (.blockSize | map(tostring) | join(" "))] | join(",")')

IFS=',' read -r HF_DATA_TYPE HF_COMPRESSION HF_DIMENSIONS HF_BLOCK_SIZE <<< "${HF_LAYOUT}"
read -r HF_WIDTH HF_HEIGHT <<< "${HF_DIMENSIONS}"
read -r HF_BLOCK_WIDTH HF_BLOCK_HEIGHT <<< "${HF_BLOCK_SIZE}"

if [ "${HF_DATA_TYPE}" != "float32" ] || [ "${HF_COMPRESSION}" != "gzip" ]; then
  printf "\nExiting, expected float32 gzip heightfields in %s, not %s %s\n\n" "${HF_URL}" "${HF_DATA_TYPE}" "${HF_COMPRESSION}" >&2
  exit 1
fi

# the cost layer transform has no matrix, so neuroglancer scales it with the dataset's own
# downsamplingFactors, which have to match the heightfield level for the two to line up
if [ "${SHOW_COST}" = "true" ]; then
  COST_ATTRIBUTES=$(readAttributes "${COST_DATASET}") || exit 1
  COST_FACTORS=$(printf '%s' "${COST_ATTRIBUTES}" | jq -c '.downsamplingFactors // [] | map(. * 1.0)')
  HF_FACTORS=$(printf '%s' "${HF_ATTRIBUTES}" | jq -c '.downsamplingFactors | map(. * 1.0)')
  if [ "${COST_FACTORS}" != "${HF_FACTORS}" ]; then
    printf "\nExiting, %s/%s downsamplingFactors %s do not match the heightfield %s factors %s\n\n" \
           "${N5_PATH}" "${COST_DATASET}" "${COST_FACTORS}" "${S_LEVEL}" "${HF_FACTORS}" >&2
    exit 1
  fi
fi

# ----------------------------------------------------------------------------
# Pick the location and the heightfield area around it

S0_X=$(( 10#${ARG_X:-$(( S0_WIDTH / 2 ))} ))
S0_Y=$(( 10#${ARG_Y:-$(( S0_HEIGHT / 2 ))} ))
S0_Z=$(( 10#${ARG_Z:-$(( S0_DEPTH / 2 ))} ))

if (( S0_X >= S0_WIDTH )) || (( S0_Y >= S0_HEIGHT )) || (( S0_Z >= S0_DEPTH )); then
  printf "\nExiting, --x %d, --y %d, and --z %d must be less than the s0 dimensions %d, %d, and %d\n\n" \
         "${S0_X}" "${S0_Y}" "${S0_Z}" "${S0_WIDTH}" "${S0_HEIGHT}" "${S0_DEPTH}" >&2
  exit 1
fi

clamp() {
  local VALUE="$1" MAX="$2"
  if (( VALUE < 0 )); then echo 0; elif (( VALUE > MAX )); then echo "${MAX}"; else echo "${VALUE}"; fi
}

HF_COLUMN=$(clamp $(( S0_X / INT_FACTOR_X )) $(( HF_WIDTH - 1 )))
HF_ROW=$(clamp $(( S0_Y / INT_FACTOR_Y )) $(( HF_HEIGHT - 1 )))

HF_X_START=$(clamp $(( (S0_X - RADIUS) / INT_FACTOR_X )) $(( HF_WIDTH - 1 )))
HF_X_END=$(clamp $(( (S0_X + RADIUS) / INT_FACTOR_X )) $(( HF_WIDTH - 1 )))
HF_Y_START=$(clamp $(( (S0_Y - RADIUS) / INT_FACTOR_Y )) $(( HF_HEIGHT - 1 )))
HF_Y_END=$(clamp $(( (S0_Y + RADIUS) / INT_FACTOR_Y )) $(( HF_HEIGHT - 1 )))

# heightfield steps between line points (at least one)
HF_STEP_X=$(( STEP / INT_FACTOR_X )); if (( HF_STEP_X < 1 )); then HF_STEP_X=1; fi
HF_STEP_Y=$(( STEP / INT_FACTOR_Y )); if (( HF_STEP_Y < 1 )); then HF_STEP_Y=1; fi

# ----------------------------------------------------------------------------
# Download the blocks the row and column pass through (n5 block paths are <dataset>/<x>/<y>)

WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

BLOCK_COLUMN=$(( HF_COLUMN / HF_BLOCK_WIDTH ))
BLOCK_ROW=$(( HF_ROW / HF_BLOCK_HEIGHT ))

HF_NAME="max"
BLOCK_LIST=$(for (( BX = HF_X_START / HF_BLOCK_WIDTH; BX <= HF_X_END / HF_BLOCK_WIDTH; BX++ )); do
               echo "${HF_NAME}/${BX}/${BLOCK_ROW}"
             done
             for (( BY = HF_Y_START / HF_BLOCK_HEIGHT; BY <= HF_Y_END / HF_BLOCK_HEIGHT; BY++ )); do
               echo "${HF_NAME}/${BLOCK_COLUMN}/${BY}"
             done | sort -u)

BLOCK_COUNT=$(printf '%s\n' "${BLOCK_LIST}" | wc -l | tr -d ' ')
DOWNLOADED_COUNT=0

printf "\ndownloading %d heightfield block(s) from %s ...\n" "${BLOCK_COUNT}" "${HF_URL}" >&2

# missing blocks (never written) are simply skipped, which leaves a gap in the lines
for BLOCK in ${BLOCK_LIST}; do
  BLOCK_FILE="${WORK_DIR}/${BLOCK//\//_}"
  if gcloud storage cat "${HF_URL}/${BLOCK}" > "${BLOCK_FILE}" 2>/dev/null; then
    DOWNLOADED_COUNT=$(( DOWNLOADED_COUNT + 1 ))
  else
    rm -f "${BLOCK_FILE}"
  fi
done

printf "  downloaded %d of %d block(s)\n" "${DOWNLOADED_COUNT}" "${BLOCK_COUNT}" >&2

# ----------------------------------------------------------------------------
# Decode the blocks and build the line annotations
#
# An n5 block is: uint16 mode, uint16 number of dimensions, uint32 size of each dimension,
# (uint32 element count when mode is 1), then the compressed big endian values with x fastest.
#
# Neuroglancer puts voxel v between v and v + 1, so its center is v + 0.5:
#   x = heightfield column * x factor + x factor / 2   (the center of the s0 voxels it covers)
#   z = (value + 0.5) * z factor                       (the center of s0 voxel (value + 0.5) * z factor - 0.5)

buildLines() {
  local HF_NAME="$1"
  perl -e '
    use strict;
    use warnings;
    use IO::Uncompress::Gunzip qw(gunzip $GunzipError);

    my ($dir, $name, $fx, $fy, $fz, $blockWidth, $blockHeight, $column, $row,
        $xStart, $xEnd, $yStart, $yEnd, $stepX, $stepY) = @ARGV;

    my %blocks;

    sub readBlock {
      my ($bx, $by) = @_;
      my $key = "$bx/$by";
      return $blocks{$key} if exists $blocks{$key};
      $blocks{$key} = undef;
      my $file = "$dir/${name}_${bx}_${by}";
      return undef unless -s $file;
      open(my $fh, "<:raw", $file) or die "could not open $file: $!";
      my $bytes = do { local $/; <$fh> };
      close($fh);
      my ($mode, $rank) = unpack("n n", $bytes);
      my @size = unpack("N$rank", substr($bytes, 4, 4 * $rank));
      my $offset = 4 + 4 * $rank + ($mode == 1 ? 4 : 0);
      my $compressed = substr($bytes, $offset);
      my $values;
      gunzip(\$compressed => \$values) or die "could not decompress $file: $GunzipError";
      $blocks{$key} = { width => $size[0], values => $values };
      return $blocks{$key};
    }

    sub value {
      my ($x, $y) = @_;
      my $block = readBlock(int($x / $blockWidth), int($y / $blockHeight));
      return undef unless defined $block;
      my $index = ($x % $blockWidth) + ($y % $blockHeight) * $block->{width};
      return undef if 4 * $index + 4 > length($block->{values});
      my $v = unpack("f>", substr($block->{values}, 4 * $index, 4));
      return undef if $v != $v || abs($v) > 1e30;   # NaN or infinite
      return $v;
    }

    my @lines;
    my $samples = 0;
    my $skipped = 0;

    sub point {
      my ($x, $y, $v) = @_;
      return sprintf("[%s,%s,%.1f]", $x * $fx + $fx / 2, $y * $fy + $fy / 2, ($v + 0.5) * $fz);
    }

    # connects consecutive finite samples with lines
    sub addLines {
      my (@positions) = @_;
      my $previous;
      foreach my $position (@positions) {
        my ($x, $y) = @$position;
        $samples++;
        my $v = value($x, $y);
        if (! defined $v) {
          $skipped++;
          $previous = undef;
          next;
        }
        my $current = point($x, $y, $v);
        if (defined $previous) {
          push(@lines, sprintf("{\"type\":\"line\",\"pointA\":%s,\"pointB\":%s,\"id\":\"%x\"}",
                               $previous, $current, scalar(@lines)));
        }
        $previous = $current;
      }
    }

    # the last sample is always included so the lines reach the end of the area
    my @rowPositions;
    for (my $x = $xStart; $x <= $xEnd; $x += $stepX) { push(@rowPositions, [$x, $row]); }
    push(@rowPositions, [$xEnd, $row]) if ($xEnd - $xStart) % $stepX != 0;

    my @columnPositions;
    for (my $y = $yStart; $y <= $yEnd; $y += $stepY) { push(@columnPositions, [$column, $y]); }
    push(@columnPositions, [$column, $yEnd]) if ($yEnd - $yStart) % $stepY != 0;

    addLines(@rowPositions);
    addLines(@columnPositions);

    print "[", join(",", @lines), "]\n";
    printf STDERR "  %s: %d lines from %d samples (%d skipped because their block is missing or the value is not finite)\n",
                  $name, scalar(@lines), $samples, $skipped;
  ' "${WORK_DIR}" "${HF_NAME}" "${FACTOR_X}" "${FACTOR_Y}" "${FACTOR_Z}" \
    "${HF_BLOCK_WIDTH}" "${HF_BLOCK_HEIGHT}" "${HF_COLUMN}" "${HF_ROW}" \
    "${HF_X_START}" "${HF_X_END}" "${HF_Y_START}" "${HF_Y_END}" "${HF_STEP_X}" "${HF_STEP_Y}"
}

printf "\nbuilding lines within %d s0 voxels of x %d, y %d ...\n" "${RADIUS}" "${S0_X}" "${S0_Y}" >&2

buildLines max > "${WORK_DIR}/max_lines.json" || exit 1

# ----------------------------------------------------------------------------
# Build and print the url

# the lines are drawn through the center of the heightfield row and column, so x and y are
# moved there (by less than one heightfield pixel) to put the lines in the XZ and YZ views
LINE_X=$(( HF_COLUMN * INT_FACTOR_X + INT_FACTOR_X / 2 ))
LINE_Y=$(( HF_ROW * INT_FACTOR_Y + INT_FACTOR_Y / 2 ))
POSITION="[${LINE_X}, ${LINE_Y}, ${S0_Z}]"

# cost is uint8 (0 to 255), drawn with the jet colormap over the pixel layer
COST_SHADER='#uicontrol invlerp normalized(range=[0, 255])
#uicontrol float opacity slider(min=0, max=1, default=0.5)
void main() {
  emitRGBA(vec4(colormapJet(normalized()), opacity));
}
'

NG_STATE=$(jq -c -n \
              --arg exp "${N5_PATH}" \
              --arg pixelDataset "${PIXEL_DATASET}" \
              --arg costDataset "${COST_DATASET}" \
              --arg costShader "${COST_SHADER}" \
              --argjson showCost "${SHOW_COST}" \
              --arg color "${HF_COLOR}" \
              --slurpfile maxLines "${WORK_DIR}/max_lines.json" \
              --argjson position "${POSITION}" '
  { "x": [8e-9, "m"], "y": [8e-9, "m"], "z": [8e-9, "m"] } as $dims |
  def lineLayer($name; $lines):
    { "type": "annotation", "name": $name,
      "source": { "url": "local://annotations", "transform": { "outputDimensions": $dims } },
      "annotationColor": $color, "annotations": $lines };
  {
    "dimensions": $dims,
    "position": $position,
    "crossSectionScale": 1,
    "projectionScale": 4096,
    "layers": [
      { "type": "image", "source": "\($exp)/|n5:\($pixelDataset)/", "tab": "source", "name": "pixel" },
      (if $showCost then
         { "type": "image",
           "source": { "url": "\($exp)/|n5:\($costDataset)/", "transform": { "inputDimensions": $dims, "outputDimensions": $dims } },
           "tab": "rendering", "name": "cost",
           "shader": $costShader }
       else empty end),
      lineLayer("hf max"; $maxLines[0])
    ],
    "selectedLayer": { "size": 322, "visible": true, "layer": "hf max" },
    "layout": "xz",
    "uiControlVisibility": {}
  }') || exit 1

# jq writes 8e-9 as 8E-9, so restore the lower case exponent that neuroglancer uses,
# then encode the same characters as print_inpaint_ng_url.sh (% first)
ENCODED_STATE=$(printf '%s' "${NG_STATE}" |
                sed -e 's/\([0-9]\)E\([-+]\)/\1e\2/g' \
                    -e 's/%/%25/g' -e 's/ /%20/g' -e 's/"/%22/g' -e 's/,/%2C/g' -e 's/|/%7C/g' \
                    -e 's/{/%7B/g' -e 's/}/%7D/g' -e 's/\[/%5B/g' -e 's/\]/%5D/g' \
                    -e 's/#/%23/g' -e 's/</%3C/g' -e 's/>/%3E/g' -e 's/\\/%5C/g')

printf '%s%s\n' "${NG_BASE_URL}" "${ENCODED_STATE}"

printf "
centered on s0 x %d, y %d, z %d (stack depth %d)
%s max heightfield average (z in s0 voxels): %s

" "${LINE_X}" "${LINE_Y}" "${S0_Z}" "${S0_DEPTH}" "${S_LEVEL}" \
  "$(printf '%s' "${HF_MAX_ATTRIBUTES}" | jq '.avg')" >&2
