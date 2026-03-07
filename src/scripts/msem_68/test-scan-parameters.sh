#!/bin/bash

OWNER="hess_sample_68_full"
IMAGE_URL="http://renderer.int.janelia.org:8080/render-ws/v1/owner/${OWNER}/jpeg-image"

TEST_DATA=(
  '53a|3.599264469009993,0.00721664344836311,-0.00530177423252999,0'
  '68a|3.695,-0.00555,0.180,0'
  '68b|3.695,0.00555,-0.180,0'
)

for TEST_LINE in "${TEST_DATA[@]}"; do
  TEST_CASE="${TEST_LINE%%|*}"
  DATA_STRING="${TEST_LINE#*|}"

  jq -n --arg dataString "${DATA_STRING}" \
    '{
      meshCellSize: 64, minMeshCellSize: 0, x: 3179, y: 401, width: 2004, height: 1748, scale: 1,
      areaOffset: false, convertToGray: true, quality: 0.85, numberOfThreads: 1,
      skipInterpolation: false, binaryMask: false, excludeMask: false, doFilter: false,
      addWarpFieldDebugOverlay: false, fillWithNoise: false,
      tileSpecs: [
        {
          tileId: "w68_magc0000_sc00009_m0032_r47_s02",
          layout: { sectionId: "1.0", imageRow: 5, imageCol: 12, stageX: 1604581, stageY: -162301 },
          z: 1, minX: 3179, minY: 401, maxX: 5183, maxY: 2149, width: 2000, height: 1748,
          minIntensity: 0, maxIntensity: 255,
          mipmapLevels: {
            "0": {
              imageUrl: "file:/nrs/hess/Hayworth/DATA_Sample68_FULL_FINAL/scan_000009/mFOVs/mFOV_0032/sfov_055.png"
            }
          },
          transforms: { type: "list", specList: [
              {
                className: "org.janelia.alignment.transform.ExponentialFunctionOffsetTransform",
                dataString: $dataString
              },
              {
                className: "mpicbg.trakem2.transform.AffineModel2D",
                dataString: "1 0 0 1 3183 401"
              }
            ]
          },
          meshCellSize: 64
        }
      ],
      minBoundsMeshCellSize: 64
    }' |
  curl -o "test.${TEST_CASE}.jpg" \
    -X PUT \
    -H 'Content-Type: application/json' \
    -H 'Accept: image/jpeg' \
    --data-binary @- \
    "${IMAGE_URL}"

done